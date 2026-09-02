import Foundation
import Observation
import SitlessKit

/// Backs the Watch's single primary screen (R34). Owns its own `HealthDataProviding` +
/// `ActivityCalculating` instance so the Watch keeps showing correct numbers on its own even out
/// of range of the phone — it never waits for the iPhone to send it standing data.
@MainActor
@Observable
final class WatchHomeViewModel {
    enum LoadState: Equatable {
        case loading
        case unavailable
        case noData
        case loaded
        /// Confidence is too low to trust the yesterday comparison (R24-style honesty, mirrored
        /// from the iPhone's Today screen); standing time and Stand Hours are still shown, since
        /// those are genuinely measured.
        case partialData
        case queryFailure
    }

    private(set) var state: LoadState = .loading
    private(set) var standingDuration: TimeInterval = 0
    private(set) var standingGoal: TimeInterval
    private(set) var comparison: StandingComparison?
    private(set) var standHours: Int?
    private(set) var lastStandElapsed: TimeInterval?

    /// Apple's own Stand Hours goal is a fixed 12-hour target, distinct from this app's
    /// user-configurable standing-duration goal (R29's `StandingGoal`).
    static let appleStandHoursGoal = 12

    let healthData: HealthDataProviding
    private let settingsStore: SettingsStore
    private let activityCalculator: ActivityCalculating
    private let calendar: Calendar

    init(
        healthData: HealthDataProviding,
        settingsStore: SettingsStore,
        activityCalculator: ActivityCalculating = ActivityCalculator(),
        calendar: Calendar = .current
    ) {
        self.healthData = healthData
        self.settingsStore = settingsStore
        self.activityCalculator = activityCalculator
        self.calendar = calendar
        self.standingGoal = settingsStore.standingGoal.duration
    }

    /// Requests HealthKit authorization if it hasn't been decided yet, then loads today's data.
    /// The Watch has its own authorization flow, independent of the iPhone's onboarding (R34) —
    /// there's no room on a single glanceable screen for an explanation step, so the system
    /// permission sheet is requested directly.
    func start() async {
        let authorization = await healthData.authorizationState
        guard authorization != .unavailable else {
            state = .unavailable
            return
        }
        if authorization == .notDetermined {
            do {
                try await healthData.requestAuthorization()
            } catch {
                state = .queryFailure
                return
            }
        }
        // An answered prompt is as much as the platform will say — read permission is never
        // exposed — so the screen loads and lets an empty result speak for itself.
        await refresh()
    }

    func refresh() async {
        state = .loading
        standingGoal = settingsStore.standingGoal.duration
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: startOfToday),
            let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday),
            let yesterdaySameTime = calendar.date(byAdding: .day, value: -1, to: now)
        else {
            state = .queryFailure
            return
        }

        do {
            let range = DateInterval(start: sevenDaysAgo, end: now)
            let intervals = try await healthData.standingIntervals(in: range)
            guard !intervals.isEmpty else {
                standingDuration = 0
                comparison = nil
                standHours = nil
                lastStandElapsed = nil
                state = .noData
                return
            }

            standingDuration = ActivityCalculator.totalDuration(of: intervals, in: DateInterval(start: startOfToday, end: now))
            let sevenDaySeries = ActivityCalculator.dailyTotals(of: intervals, from: sevenDaysAgo, to: startOfToday, calendar: calendar)
            comparison = ActivityCalculator.sameTimeOfDayComparison(
                todayStandingDuration: standingDuration,
                intervals: intervals,
                priorDaySeries: Array(sevenDaySeries.dropLast()),
                startOfYesterday: startOfYesterday,
                yesterdaySameTime: yesterdaySameTime,
                calendar: calendar
            )

            let window = DateInterval(start: startOfToday, end: now)
            let todayStanding = intervals.filter { calendar.isDate($0.start, inSameDayAs: startOfToday) }
            async let activity = healthData.activityIntervals(in: window)
            async let sleep = healthData.sleepIntervals(in: window)
            // R51: spans the watch wasn't worn, so charging breaks land in unknown time rather
            // than being counted as estimated sitting time. R45: a failure here degrades to no
            // spans at all, leaving the day's summary exactly as it would have been.
            async let offWrist = healthData.offWristSpans(in: window)
            async let hours = healthData.standHours(in: window)

            let summary = activityCalculator.summarize(
                standing: todayStanding,
                activity: try await activity,
                sleep: try await sleep,
                offWrist: (try? await offWrist) ?? [],
                steps: nil,
                standHours: try await hours,
                observationWindow: window,
                calendar: calendar
            )
            standHours = summary.standHours
            lastStandElapsed = Self.lastStandElapsed(in: summary.timeline, asOf: now)

            state = summary.confidence == .low ? .partialData : .loaded
        } catch {
            state = .queryFailure
        }
    }

    /// Time elapsed since the end of the most recent `.standing` interval on today's timeline —
    /// backs the "Last stand" context row (R34). `nil` when there's no standing interval yet today.
    private static func lastStandElapsed(in timeline: [ActivityInterval], asOf now: Date) -> TimeInterval? {
        guard let lastStandEnd = timeline.filter({ $0.state == .standing }).map(\.end).max() else { return nil }
        return now.timeIntervalSince(lastStandEnd)
    }
}
