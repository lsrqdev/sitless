import XCTest
import StandLessKit
@testable import StandLess

@MainActor
final class TodayViewModelTests: XCTestCase {
    private static func isolatedStore() -> SettingsStore {
        let defaults = UserDefaults(suiteName: "TodayViewModelTests-\(UUID().uuidString)")!
        return SettingsStore(defaults: defaults)
    }

    func testStartReflectsDeniedAuthorizationWithoutTouchingRealHealthKit() async {
        let mock = MockHealthDataProvider(authorizationState: .denied)
        let viewModel = TodayViewModel(healthData: mock, settingsStore: Self.isolatedStore())

        await viewModel.start()

        XCTAssertEqual(viewModel.state, .denied)
        XCTAssertEqual(mock.requestAuthorizationCallCount, 0)
    }

    func testStartReflectsUnavailableAuthorization() async {
        let mock = MockHealthDataProvider(authorizationState: .unavailable)
        let viewModel = TodayViewModel(healthData: mock, settingsStore: Self.isolatedStore())

        await viewModel.start()

        XCTAssertEqual(viewModel.state, .unavailable)
    }

    func testStartWithNoStandingIntervalsShowsNoDataState() async {
        let mock = MockHealthDataProvider(authorizationState: .authorized, standingIntervalsResult: .success([]))
        let viewModel = TodayViewModel(healthData: mock, settingsStore: Self.isolatedStore())

        await viewModel.start()

        XCTAssertEqual(viewModel.state, .noData)
        XCTAssertEqual(viewModel.todayStandingDuration, 0)
    }

    func testRefreshLoadsTodayStandingFromMock() async {
        let calendar = Calendar.current
        let now = Date()
        let interval = ActivityInterval(
            start: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(-1800),
            state: .standing
        )
        let mock = MockHealthDataProvider(authorizationState: .authorized, standingIntervalsResult: .success([interval]))
        let viewModel = TodayViewModel(healthData: mock, settingsStore: Self.isolatedStore(), calendar: calendar)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.todayStandingDuration, 1800, accuracy: 0.001)
    }

    func testRefreshComparesAgainstYesterdayAtTheSameTimeOfDay() async {
        let calendar = Calendar.current
        let now = Date()
        guard let yesterdaySameTime = calendar.date(byAdding: .day, value: -1, to: now) else {
            XCTFail("failed to construct dates")
            return
        }

        // Yesterday: 20 minutes of standing, ending well before "yesterday at this same time".
        let yesterdayInterval = ActivityInterval(
            start: yesterdaySameTime.addingTimeInterval(-1800),
            end: yesterdaySameTime.addingTimeInterval(-600),
            state: .standing
        )
        // Today: 40 minutes of standing, ending well before "now".
        let todayInterval = ActivityInterval(
            start: now.addingTimeInterval(-2700),
            end: now.addingTimeInterval(-300),
            state: .standing
        )
        let mock = MockHealthDataProvider(
            authorizationState: .authorized,
            standingIntervalsResult: .success([yesterdayInterval, todayInterval])
        )
        let viewModel = TodayViewModel(healthData: mock, settingsStore: Self.isolatedStore(), calendar: calendar)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.todayStandingDuration, 2400, accuracy: 1)
        guard case .vsYesterday(let delta) = viewModel.comparison else {
            XCTFail("Expected vsYesterday comparison, got \(String(describing: viewModel.comparison))")
            return
        }
        XCTAssertEqual(delta, 1200, accuracy: 1)
    }

    func testRefreshFallsBackToSevenDayAverageWhenYesterdayHasNoData() async {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: startOfToday) else {
            XCTFail("failed to construct dates")
            return
        }

        let twoDaysAgoInterval = ActivityInterval(
            start: twoDaysAgo.addingTimeInterval(3600),
            end: twoDaysAgo.addingTimeInterval(7200),
            state: .standing
        )
        let todayInterval = ActivityInterval(
            start: now.addingTimeInterval(-1800),
            end: now.addingTimeInterval(-300),
            state: .standing
        )
        let mock = MockHealthDataProvider(
            authorizationState: .authorized,
            standingIntervalsResult: .success([twoDaysAgoInterval, todayInterval])
        )
        let viewModel = TodayViewModel(healthData: mock, settingsStore: Self.isolatedStore(), calendar: calendar)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        guard case .vsSevenDayAverage(let deltaPercent) = viewModel.comparison else {
            XCTFail("Expected vsSevenDayAverage comparison, got \(String(describing: viewModel.comparison))")
            return
        }
        XCTAssertGreaterThan(deltaPercent, 0)
    }

    func testReloadGoalReflectsPersistedSettingsStoreChange() async {
        let store = Self.isolatedStore()
        let mock = MockHealthDataProvider(authorizationState: .authorized, standingIntervalsResult: .success([]))
        let viewModel = TodayViewModel(healthData: mock, settingsStore: store)

        XCTAssertEqual(viewModel.standingGoal, StandingGoal.defaultGoal.duration)

        store.standingGoal = StandingGoal(duration: 4 * 3600)
        viewModel.reloadGoal()

        XCTAssertEqual(viewModel.standingGoal, 4 * 3600)
    }
}
