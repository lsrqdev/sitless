import SwiftUI
import SitlessKit
import UserNotifications

@main
struct SitlessApp: App {
    private let healthData: HealthDataProviding = HealthKitManager()
    private let settingsStore = SettingsStore()
    private let connectivity: WatchConnectivityService
    private let motionManager = MotionManager()
    private let notificationManager = NotificationManager()
    private let notificationDelegate: ReminderNotificationDelegate

    init() {
        let healthData = healthData
        let settingsStore = settingsStore
        let motionManager = motionManager
        let notificationManager = notificationManager

        // Records every actual delivery of the reminder notification so NotificationManager's
        // repeat-window suppression (R32) has a real lastFiredAt to compare against — without
        // this, recordFired(at:) is never called and that safeguard can never engage.
        let notificationDelegate = ReminderNotificationDelegate(notificationManager: notificationManager)
        UNUserNotificationCenter.current().delegate = notificationDelegate
        self.notificationDelegate = notificationDelegate

        let connectivity = WatchConnectivityService(settingsStore: settingsStore)
        settingsStore.onStandingGoalChanged = { [connectivity] goal in
            connectivity.pushStandingGoal(goal)
        }
        connectivity.activate()
        self.connectivity = connectivity

        // The optional inactivity reminder (R31-R32): every time HealthKit reports new standing
        // activity, or the reminder setting itself changes, reschedule the single pending
        // notification against a freshly-built suppression snapshot.
        settingsStore.onReminderIntervalChanged = { [healthData, motionManager, notificationManager] _ in
            Task {
                await Self.rescheduleReminder(
                    healthData: healthData, settingsStore: settingsStore,
                    motionManager: motionManager, notificationManager: notificationManager
                )
            }
        }

        motionManager.startUpdates { _ in }

        healthData.observeChanges { [healthData, settingsStore, motionManager, notificationManager] in
            Task {
                await Self.rescheduleReminder(
                    healthData: healthData, settingsStore: settingsStore,
                    motionManager: motionManager, notificationManager: notificationManager
                )
            }
        }

        Task {
            try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(healthData: healthData, settingsStore: settingsStore)
        }
    }

    /// Live off-wrist threshold (R53): the reminder is suppressed when the most recent heart-rate
    /// sample the phone holds is older than this, which is the best available evidence that the
    /// watch is not on the wrist right now. Deliberately longer than the retrospective
    /// `HealthKitManager.offWristHeartRateGap` used when building the daily summary: that one runs
    /// over data that has already settled, while this one runs against whatever has reached the
    /// phone so far, and Watch-to-iPhone HealthKit sync latency can leave recent samples absent for
    /// many minutes while the watch is still being worn. Erring short would swallow reminders the
    /// user should have received; erring long only delays the point at which an off-wrist stretch
    /// starts suppressing, and a skipped reminder is the preferred failure over a spurious one.
    private static let liveOffWristHeartRateGap: TimeInterval = 45 * 60

    /// How far back the live off-wrist check looks for a heart-rate sample. Wide enough to cover a
    /// night on the charger, so a watch left off since the previous evening still reads as
    /// off-wrist rather than as no-watch-at-all.
    private static let liveOffWristLookback: TimeInterval = 12 * 3600

    /// Rebuilds the current suppression snapshot (R32, R52) from HealthKit sleep/workout data,
    /// heart-rate recency and `MotionManager`'s driving signal, then reschedules the pending
    /// reminder against it.
    private static func rescheduleReminder(
        healthData: HealthDataProviding,
        settingsStore: SettingsStore,
        motionManager: MotionManager,
        notificationManager: NotificationManager
    ) async {
        let now = Date()
        let interval = settingsStore.reminderInterval
        guard interval != .off else {
            notificationManager.reschedule(interval: .off, now: now)
            return
        }

        let today = DateInterval(start: Calendar.current.startOfDay(for: now), end: now)
        let isAsleep = (try? await healthData.sleepIntervals(in: today))?
            .contains { $0.start <= now && now <= $0.end } ?? false
        let isInWorkout = (try? await healthData.isInActiveWorkout(asOf: now)) ?? false
        let isLikelyDriving = await withCheckedContinuation { continuation in
            motionManager.isLikelyDriving(now: now) { continuation.resume(returning: $0) }
        }

        // R53: no heart-rate sample at all means no evidence a wearable was ever on the body, so
        // an iPhone-only user is never suppressed by this. `try?` flattens a failed query into the
        // same `nil`, and both fall back to `false` — matching the `?? false` treatment above.
        let heartRateWindow = DateInterval(start: now.addingTimeInterval(-liveOffWristLookback), end: now)
        let lastHeartRate = try? await healthData.lastHeartRateSampleDate(in: heartRateWindow)
        let isOffWrist = lastHeartRate.map { now.timeIntervalSince($0) > liveOffWristHeartRateGap } ?? false

        let snapshot = SuppressionSnapshot(
            isAsleep: isAsleep,
            isInWorkout: isInWorkout,
            isLikelyDriving: isLikelyDriving,
            isOffWrist: isOffWrist
        )
        notificationManager.reschedule(interval: interval, now: now, snapshot: snapshot)
    }
}

/// Gates the app behind the 3-screen onboarding flow (R33) on first launch, then shows the
/// app's three main sections — Today, Trends, Settings — kept deliberately simple (no nested
/// tab navigation beyond this).
private struct RootTabView: View {
    let healthData: HealthDataProviding
    let settingsStore: SettingsStore
    /// `nil` while the Health request-status check is still resolving. The check is asynchronous,
    /// so neither branch may be assumed up front: defaulting to onboarding would flash the
    /// permission explainer at someone who has already answered the prompt, and defaulting to the
    /// tabs would skip onboarding entirely on a genuine first launch.
    @State private var needsOnboarding: Bool?

    var body: some View {
        switch needsOnboarding {
        case nil:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { needsOnboarding = await healthData.authorizationState == .notDetermined }
        case true?:
            OnboardingView(viewModel: OnboardingViewModel(healthData: healthData)) {
                needsOnboarding = false
            }
        case false?:
            TabView {
                TodayView(viewModel: TodayViewModel(healthData: healthData, settingsStore: settingsStore))
                    .tabItem { Label("Today", systemImage: "figure.stand") }

                TrendsView(viewModel: TrendsViewModel(healthData: healthData))
                    .tabItem { Label("Trends", systemImage: "chart.bar") }

                SettingsView(viewModel: SettingsViewModel(store: settingsStore, healthData: healthData))
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        }
    }
}

/// Forwards actual notification deliveries back to `NotificationManager.recordFired(at:)` so the
/// R32 repeat-window safeguard has a real baseline. Covers the two cases the OS gives apps a hook
/// for — foreground delivery (`willPresent`) and the user later tapping it (`didReceive`); a
/// notification delivered while the app is suspended in the background has no delegate callback at
/// all, which is the same best-effort limitation already documented in README.md.
final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let notificationManager: NotificationManager

    init(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }

    private func recordIfReminder(_ notification: UNNotification) {
        guard notification.request.identifier == NotificationManager.requestIdentifier else { return }
        notificationManager.recordFired(at: Date())
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        recordIfReminder(notification)
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        recordIfReminder(response.notification)
        completionHandler()
    }
}
