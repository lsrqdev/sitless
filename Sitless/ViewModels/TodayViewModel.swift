import Foundation
import Observation
import SitlessKit

@MainActor
@Observable
final class TodayViewModel {
    enum LoadState: Equatable {
        case loading
        case unavailable
        case denied
        case noData
        case loaded
        /// Confidence is too low to trust a percentage or sedentary figure (R24); standing time
        /// is still shown, since that part is genuinely measured.
        case partialData
        case queryFailure
    }

    struct DailyStanding: Equatable, Identifiable {
        let date: Date
        let duration: TimeInterval
        var id: Date { date }
    }

    private(set) var state: LoadState = .loading
    private(set) var todayStandingDuration: TimeInterval = 0
    private(set) var sevenDaySeries: [DailyStanding] = []
    private(set) var comparison: StandingComparison?
    private(set) var standingGoal: TimeInterval
    private(set) var estimatedSedentaryDuration: TimeInterval?
    private(set) var activeDuration: TimeInterval?
    private(set) var standingPercentage: Int?
    private(set) var timeline: [ActivityInterval] = []
    private(set) var confidence: DataConfidence = .low
    private(set) var longestInactiveDuration: TimeInterval?
    private(set) var todayWindow: DateInterval = DateInterval(start: .distantPast, end: .distantPast)

    let healthData: HealthDataProviding
    private let settingsStore: SettingsStore
    private let activityCalculator: ActivityCalculating
    private let calendar: Calendar

    init(
        healthData: HealthDataProviding,
        settingsStore: SettingsStore = SettingsStore(),
        activityCalculator: ActivityCalculating = ActivityCalculator(),
        calendar: Calendar = .current
    ) {
        self.healthData = healthData
        self.settingsStore = settingsStore
        self.activityCalculator = activityCalculator
        self.calendar = calendar
        self.standingGoal = settingsStore.standingGoal.duration
    }

    /// Re-reads the persisted standing goal without touching HealthKit. Call this whenever
    /// the Today screen reappears, so a goal changed in Settings shows up immediately.
    func reloadGoal() {
        standingGoal = settingsStore.standingGoal.duration
    }

    /// Requests HealthKit authorization if it hasn't been decided yet, then loads today's data.
    func start() async {
        guard healthData.authorizationState != .unavailable else {
            state = .unavailable
            return
        }
        if healthData.authorizationState == .notDetermined {
            do {
                try await healthData.requestAuthorization()
            } catch {
                state = .queryFailure
                return
            }
        }
        guard healthData.authorizationState == .authorized else {
            state = .denied
            return
        }
        await refresh()
    }

    func refresh() async {
        state = .loading
        reloadGoal()
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
            sevenDaySeries = Self.dailyTotals(of: intervals, from: sevenDaysAgo, to: startOfToday, calendar: calendar)

            guard !intervals.isEmpty else {
                todayStandingDuration = 0
                comparison = nil
                resetTodaySummary()
                state = .noData
                return
            }

            todayStandingDuration = Self.totalDuration(of: intervals, in: DateInterval(start: startOfToday, end: now))
            comparison = ActivityCalculator.sameTimeOfDayComparison(
                todayStandingDuration: todayStandingDuration,
                intervals: intervals,
                // sevenDaySeries spans sevenDaysAgo...today; drop today itself to average the prior days.
                priorDaySeries: sevenDaySeries.dropLast().map { ActivityCalculator.DailyStanding(date: $0.date, duration: $0.duration) },
                startOfYesterday: startOfYesterday,
                yesterdaySameTime: yesterdaySameTime,
                calendar: calendar
            )

            let window = DateInterval(start: startOfToday, end: now)
            todayWindow = window
            let todayStanding = intervals.filter { calendar.isDate($0.start, inSameDayAs: startOfToday) }
            async let activity = healthData.activityIntervals(in: window)
            async let sleep = healthData.sleepIntervals(in: window)
            async let steps = healthData.steps(in: window)
            async let standHours = healthData.standHours(in: window)

            let summary = activityCalculator.summarize(
                standing: todayStanding,
                activity: try await activity,
                sleep: try await sleep,
                steps: try await steps,
                standHours: try await standHours,
                observationWindow: window,
                calendar: calendar
            )
            estimatedSedentaryDuration = summary.estimatedSedentaryDuration
            activeDuration = summary.activeDuration
            standingPercentage = summary.standingPercentage
            timeline = summary.timeline
            confidence = summary.confidence
            longestInactiveDuration = summary.longestInactiveDuration

            state = confidence == .low ? .partialData : .loaded
        } catch {
            state = .queryFailure
        }
    }

    private func resetTodaySummary() {
        estimatedSedentaryDuration = nil
        activeDuration = nil
        standingPercentage = nil
        timeline = []
        confidence = .low
        longestInactiveDuration = nil
    }

    /// Sums interval duration for intervals starting on `day`'s calendar day.
    static func totalDuration(of intervals: [ActivityInterval], on day: Date, calendar: Calendar) -> TimeInterval {
        ActivityCalculator.totalDuration(of: intervals, on: day, calendar: calendar)
    }

    /// Sums interval duration clipped to an arbitrary date range — used for partial-day
    /// comparisons like "today so far" or "yesterday at this same time".
    static func totalDuration(of intervals: [ActivityInterval], in range: DateInterval) -> TimeInterval {
        ActivityCalculator.totalDuration(of: intervals, in: range)
    }

    static func dailyTotals(
        of intervals: [ActivityInterval],
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> [DailyStanding] {
        ActivityCalculator.dailyTotals(of: intervals, from: start, to: end, calendar: calendar)
            .map { DailyStanding(date: $0.date, duration: $0.duration) }
    }
}
