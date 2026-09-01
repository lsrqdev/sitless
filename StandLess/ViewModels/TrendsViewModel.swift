import Foundation
import Observation
import StandLessKit

@MainActor
@Observable
final class TrendsViewModel {
    enum Period: String, CaseIterable, Identifiable {
        case sevenDays = "7D"
        case thirtyDays = "30D"
        case twelveWeeks = "12W"

        var id: String { rawValue }

        /// Number of days in the period, inclusive of today.
        var dayCount: Int {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .twelveWeeks: return 84
            }
        }

        var label: String {
            switch self {
            case .sevenDays: return "7-day"
            case .thirtyDays: return "30-day"
            case .twelveWeeks: return "12-week"
            }
        }
    }

    enum LoadState: Equatable {
        case loading
        case loaded
        case queryFailure
    }

    /// Shown only when at least half the days in each period have confidence better than
    /// `.low` (R27) — never derived from thin data.
    struct SedentaryTrend: Equatable {
        let periodAverage: TimeInterval
        let priorPeriodAverage: TimeInterval
    }

    private(set) var state: LoadState = .loading
    private(set) var series: [TodayViewModel.DailyStanding] = []
    private(set) var periodAverage: TimeInterval = 0
    private(set) var priorPeriodAverage: TimeInterval = 0
    private(set) var sedentaryTrend: SedentaryTrend?

    var period: Period = .sevenDays {
        didSet {
            guard oldValue != period else { return }
            Task { await refresh() }
        }
    }

    private let healthData: HealthDataProviding
    private let activityCalculator: ActivityCalculating
    private let calendar: Calendar

    init(healthData: HealthDataProviding, activityCalculator: ActivityCalculating = ActivityCalculator(), calendar: Calendar = .current) {
        self.healthData = healthData
        self.activityCalculator = activityCalculator
        self.calendar = calendar
    }

    func refresh() async {
        state = .loading
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let days = period.dayCount
        guard
            let periodStart = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday),
            let priorPeriodEnd = calendar.date(byAdding: .day, value: -1, to: periodStart),
            let priorPeriodStart = calendar.date(byAdding: .day, value: -(days - 1), to: priorPeriodEnd)
        else {
            state = .queryFailure
            return
        }

        do {
            // A single bounded query (R9) covers both the current and the prior period.
            let range = DateInterval(start: priorPeriodStart, end: now)
            let standing = try await healthData.standingIntervals(in: range)
            let activity = try await healthData.activityIntervals(in: range)
            let sleep = try await healthData.sleepIntervals(in: range)

            series = TodayViewModel.dailyTotals(of: standing, from: periodStart, to: startOfToday, calendar: calendar)
            periodAverage = Self.average(of: series)

            let priorSeries = TodayViewModel.dailyTotals(of: standing, from: priorPeriodStart, to: priorPeriodEnd, calendar: calendar)
            priorPeriodAverage = Self.average(of: priorSeries)

            sedentaryTrend = Self.sedentaryTrend(
                standing: standing,
                activity: activity,
                sleep: sleep,
                periodStart: periodStart,
                periodEnd: startOfToday,
                priorPeriodStart: priorPeriodStart,
                priorPeriodEnd: priorPeriodEnd,
                now: now,
                calendar: calendar,
                activityCalculator: activityCalculator
            )

            state = .loaded
        } catch {
            state = .queryFailure
        }
    }

    private static func average(of series: [TodayViewModel.DailyStanding]) -> TimeInterval {
        guard !series.isEmpty else { return 0 }
        return series.reduce(0) { $0 + $1.duration } / Double(series.count)
    }

    /// Runs `ActivityCalculator.summarize` per day and averages only the days whose confidence
    /// clears `.low`, requiring at least half of each period's days to qualify (R27).
    private static func sedentaryTrend(
        standing: [ActivityInterval],
        activity: [ActivityInterval],
        sleep: [ActivityInterval],
        periodStart: Date,
        periodEnd: Date,
        priorPeriodStart: Date,
        priorPeriodEnd: Date,
        now: Date,
        calendar: Calendar,
        activityCalculator: ActivityCalculating
    ) -> SedentaryTrend? {
        func qualifyingDailyAverage(from start: Date, to end: Date) -> TimeInterval? {
            var day = start
            var values: [TimeInterval] = []
            var totalDays = 0
            while day <= end {
                totalDays += 1
                let dayEnd = min(calendar.date(byAdding: .day, value: 1, to: day) ?? end, now)
                defer { day = calendar.date(byAdding: .day, value: 1, to: day) ?? end.addingTimeInterval(1) }
                guard dayEnd > day else { continue }

                let window = DateInterval(start: day, end: dayEnd)
                func within(_ intervals: [ActivityInterval]) -> [ActivityInterval] {
                    intervals.filter { $0.start < window.end && $0.end > window.start }
                }
                let summary = activityCalculator.summarize(
                    standing: within(standing),
                    activity: within(activity),
                    sleep: within(sleep),
                    steps: nil,
                    standHours: nil,
                    observationWindow: window,
                    calendar: calendar
                )
                if summary.confidence != .low, let sedentary = summary.estimatedSedentaryDuration {
                    values.append(sedentary)
                }
            }
            guard totalDays > 0, values.count * 2 >= totalDays, !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }

        guard
            let periodAverage = qualifyingDailyAverage(from: periodStart, to: periodEnd),
            let priorPeriodAverage = qualifyingDailyAverage(from: priorPeriodStart, to: priorPeriodEnd)
        else { return nil }

        return SedentaryTrend(periodAverage: periodAverage, priorPeriodAverage: priorPeriodAverage)
    }
}
