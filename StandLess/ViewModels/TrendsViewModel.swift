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

    private(set) var state: LoadState = .loading
    private(set) var series: [TodayViewModel.DailyStanding] = []
    private(set) var periodAverage: TimeInterval = 0
    private(set) var priorPeriodAverage: TimeInterval = 0

    var period: Period = .sevenDays {
        didSet {
            guard oldValue != period else { return }
            Task { await refresh() }
        }
    }

    private let healthData: HealthDataProviding
    private let calendar: Calendar

    init(healthData: HealthDataProviding, calendar: Calendar = .current) {
        self.healthData = healthData
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
            let intervals = try await healthData.standingIntervals(in: range)

            series = TodayViewModel.dailyTotals(of: intervals, from: periodStart, to: startOfToday, calendar: calendar)
            periodAverage = Self.average(of: series)

            let priorSeries = TodayViewModel.dailyTotals(of: intervals, from: priorPeriodStart, to: priorPeriodEnd, calendar: calendar)
            priorPeriodAverage = Self.average(of: priorSeries)

            state = .loaded
        } catch {
            state = .queryFailure
        }
    }

    private static func average(of series: [TodayViewModel.DailyStanding]) -> TimeInterval {
        guard !series.isEmpty else { return 0 }
        return series.reduce(0) { $0 + $1.duration } / Double(series.count)
    }
}
