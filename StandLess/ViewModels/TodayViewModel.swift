import Foundation
import Observation
import StandLessKit

@MainActor
@Observable
final class TodayViewModel {
    enum LoadState: Equatable {
        case loading
        case unavailable
        case authorizationRequired
        case loaded
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

    let healthData: HealthDataProviding
    private let calendar: Calendar

    init(healthData: HealthDataProviding, calendar: Calendar = .current) {
        self.healthData = healthData
        self.calendar = calendar
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
            state = .authorizationRequired
            return
        }
        await refresh()
    }

    func refresh() async {
        state = .loading
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: startOfToday) else {
            state = .queryFailure
            return
        }
        do {
            let range = DateInterval(start: sevenDaysAgo, end: now)
            let intervals = try await healthData.standingIntervals(in: range)
            todayStandingDuration = Self.totalDuration(of: intervals, on: startOfToday, calendar: calendar)
            sevenDaySeries = Self.dailyTotals(of: intervals, from: sevenDaysAgo, to: startOfToday, calendar: calendar)
            state = .loaded
        } catch {
            state = .queryFailure
        }
    }

    static func totalDuration(of intervals: [ActivityInterval], on day: Date, calendar: Calendar) -> TimeInterval {
        intervals
            .filter { calendar.isDate($0.start, inSameDayAs: day) }
            .reduce(0) { $0 + $1.duration }
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
