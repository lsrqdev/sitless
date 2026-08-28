import Foundation
import Observation
import StandLessKit

@MainActor
@Observable
final class TodayViewModel {
    enum LoadState: Equatable {
        case loading
        case unavailable
        case denied
        case noData
        case loaded
        case queryFailure
    }

    /// How today's standing time compares to a baseline. Prefers "yesterday at this time"
    /// (a partial-day-aware comparison) and falls back to the prior-days average when
    /// yesterday has no standing data of its own.
    enum Comparison: Equatable {
        case vsYesterday(delta: TimeInterval)
        case vsSevenDayAverage(deltaPercent: Int)
    }

    struct DailyStanding: Equatable, Identifiable {
        let date: Date
        let duration: TimeInterval
        var id: Date { date }
    }

    private(set) var state: LoadState = .loading
    private(set) var todayStandingDuration: TimeInterval = 0
    private(set) var sevenDaySeries: [DailyStanding] = []
    private(set) var comparison: Comparison?
    private(set) var standingGoal: TimeInterval

    let healthData: HealthDataProviding
    private let settingsStore: SettingsStore
    private let calendar: Calendar

    init(healthData: HealthDataProviding, settingsStore: SettingsStore = SettingsStore(), calendar: Calendar = .current) {
        self.healthData = healthData
        self.settingsStore = settingsStore
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
                state = .noData
                return
            }

            todayStandingDuration = Self.totalDuration(of: intervals, in: DateInterval(start: startOfToday, end: now))
            comparison = Self.comparison(
                todayStandingDuration: todayStandingDuration,
                intervals: intervals,
                sevenDaySeries: sevenDaySeries,
                startOfYesterday: startOfYesterday,
                yesterdaySameTime: yesterdaySameTime,
                calendar: calendar
            )
            state = .loaded
        } catch {
            state = .queryFailure
        }
    }

    static func comparison(
        todayStandingDuration: TimeInterval,
        intervals: [ActivityInterval],
        sevenDaySeries: [DailyStanding],
        startOfYesterday: Date,
        yesterdaySameTime: Date,
        calendar: Calendar
    ) -> Comparison? {
        let yesterdayHasData = intervals.contains { calendar.isDate($0.start, inSameDayAs: startOfYesterday) }
        if yesterdayHasData {
            let yesterdaySameTimeDuration = totalDuration(
                of: intervals,
                in: DateInterval(start: startOfYesterday, end: yesterdaySameTime)
            )
            return .vsYesterday(delta: todayStandingDuration - yesterdaySameTimeDuration)
        }

        // sevenDaySeries spans sevenDaysAgo...today; drop today itself to average the prior days.
        let priorDays = sevenDaySeries.dropLast()
        guard !priorDays.isEmpty else { return nil }
        let priorAverage = priorDays.reduce(0) { $0 + $1.duration } / Double(priorDays.count)
        guard priorAverage > 0 else { return nil }
        let deltaPercent = Int(((todayStandingDuration - priorAverage) / priorAverage * 100).rounded())
        return .vsSevenDayAverage(deltaPercent: deltaPercent)
    }

    /// Sums interval duration for intervals starting on `day`'s calendar day.
    static func totalDuration(of intervals: [ActivityInterval], on day: Date, calendar: Calendar) -> TimeInterval {
        intervals
            .filter { calendar.isDate($0.start, inSameDayAs: day) }
            .reduce(0) { $0 + $1.duration }
    }

    /// Sums interval duration clipped to an arbitrary date range — used for partial-day
    /// comparisons like "today so far" or "yesterday at this same time".
    static func totalDuration(of intervals: [ActivityInterval], in range: DateInterval) -> TimeInterval {
        intervals.reduce(0) { total, interval in
            let start = max(interval.start, range.start)
            let end = min(interval.end, range.end)
            guard end > start else { return total }
            return total + end.timeIntervalSince(start)
        }
    }

    static func dailyTotals(
        of intervals: [ActivityInterval],
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> [DailyStanding] {
        var day = start
        var results: [DailyStanding] = []
        while day <= end {
            let total = totalDuration(of: intervals, on: day, calendar: calendar)
            results.append(DailyStanding(date: day, duration: total))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return results
    }
}
