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

    /// Rebuilds the current suppression snapshot (R32) from HealthKit sleep/workout data and
    /// `MotionManager`'s driving signal, then reschedules the pending reminder against it.
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

        let snapshot = SuppressionSnapshot(isAsleep: isAsleep, isInWorkout: isInWorkout, isLikelyDriving: isLikelyDriving)
        notificationManager.reschedule(interval: interval, now: now, snapshot: snapshot)
    }
}

/// Gates the app behind the 3-screen onboarding flow (R33) on first launch, then shows the
/// app's three main sections — Today, Trends, Settings — kept deliberately simple (no nested
/// tab navigation beyond this).
private struct RootTabView: View {
    let healthData: HealthDataProviding
    let settingsStore: SettingsStore
    @State private var needsOnboarding: Bool

    init(healthData: HealthDataProviding, settingsStore: SettingsStore) {
        self.healthData = healthData
        self.settingsStore = settingsStore
        _needsOnboarding = State(initialValue: healthData.authorizationState == .notDetermined)
    }

    var body: some View {
        if needsOnboarding {
            OnboardingView(viewModel: OnboardingViewModel(healthData: healthData)) {
                needsOnboarding = false
            }
        } else {
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
