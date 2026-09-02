import XCTest
import SitlessKit
@testable import Sitless

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
        let startOfToday = calendar.startOfDay(for: now)
        // Clamped to startOfToday so this stays correct even when the test runs within the
        // first hour after midnight — a fixed "-3600s/-1800s" offset could otherwise land
        // partly or entirely on yesterday.
        let intervalStart = max(startOfToday, now.addingTimeInterval(-3600))
        let intervalEnd = max(startOfToday, now.addingTimeInterval(-1800))
        let interval = ActivityInterval(start: intervalStart, end: intervalEnd, state: .standing)
        let expectedDuration = intervalEnd.timeIntervalSince(intervalStart)
        let mock = MockHealthDataProvider(authorizationState: .authorized, standingIntervalsResult: .success([interval]))
        let viewModel = TodayViewModel(healthData: mock, settingsStore: Self.isolatedStore(), calendar: calendar)

        await viewModel.refresh()

        // A single short standing sample against the whole elapsed day is sparse coverage,
        // so this genuinely is a low-confidence / partial-data day (R16) — but the measured
        // standing duration itself is still shown correctly (R24).
        XCTAssertEqual(viewModel.state, .partialData)
        XCTAssertEqual(viewModel.todayStandingDuration, expectedDuration, accuracy: 0.001)
    }

    func testRefreshWithComprehensiveCoverageResultsInLoadedStateWithPercentage() async {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let standingInterval = ActivityInterval(start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-300), state: .standing)
        // Spans the whole tracked window so there is no edge-of-coverage unknown time.
        let activeInterval = ActivityInterval(start: startOfToday, end: now, state: .active)
        let sleepInterval = ActivityInterval(start: startOfToday, end: startOfToday.addingTimeInterval(60), state: .sleep)
        let mock = MockHealthDataProvider(
            authorizationState: .authorized,
            standingIntervalsResult: .success([standingInterval]),
            activityIntervalsResult: .success([activeInterval]),
            sleepIntervalsResult: .success([sleepInterval])
        )
        let viewModel = TodayViewModel(healthData: mock, settingsStore: Self.isolatedStore(), calendar: calendar)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertNotNil(viewModel.standingPercentage)
        XCTAssertFalse(viewModel.timeline.isEmpty)
    }

    func testRefreshWithSparseCoverageOmitsStandingPercentage() async {
        let calendar = Calendar.current
        let now = Date()
        let interval = ActivityInterval(start: now.addingTimeInterval(-300), end: now, state: .standing)
        let mock = MockHealthDataProvider(authorizationState: .authorized, standingIntervalsResult: .success([interval]))
        let viewModel = TodayViewModel(healthData: mock, settingsStore: Self.isolatedStore(), calendar: calendar)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .partialData)
        XCTAssertEqual(viewModel.confidence, .low)
        XCTAssertNil(viewModel.standingPercentage)
    }

    func testRefreshComparesAgainstYesterdayAtTheSameTimeOfDay() async {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard let yesterdaySameTime = calendar.date(byAdding: .day, value: -1, to: now) else {
            XCTFail("failed to construct dates")
            return
        }
        let startOfYesterday = calendar.startOfDay(for: yesterdaySameTime)

        // Both intervals are clamped to their intended calendar day so a fixed offset can't
        // spill across midnight when the test happens to run in the first minutes of a day.
        let yesterdayStart = max(startOfYesterday, yesterdaySameTime.addingTimeInterval(-1800))
        let yesterdayEnd = max(startOfYesterday, yesterdaySameTime.addingTimeInterval(-600))
        let yesterdayInterval = ActivityInterval(start: yesterdayStart, end: yesterdayEnd, state: .standing)
        let yesterdaySameTimeDuration = yesterdayEnd.timeIntervalSince(yesterdayStart)

        let todayStart = max(startOfToday, now.addingTimeInterval(-2700))
        let todayEnd = max(startOfToday, now.addingTimeInterval(-300))
        let todayInterval = ActivityInterval(start: todayStart, end: todayEnd, state: .standing)
        let expectedTodayDuration = todayEnd.timeIntervalSince(todayStart)

        let mock = MockHealthDataProvider(
            authorizationState: .authorized,
            standingIntervalsResult: .success([yesterdayInterval, todayInterval])
        )
        let viewModel = TodayViewModel(healthData: mock, settingsStore: Self.isolatedStore(), calendar: calendar)

        await viewModel.refresh()

        // This test is about comparison arithmetic, not confidence — the confidence bucket
        // is sensitive to how close to midnight the suite happens to run (it changes the size
        // of "today's" tracked window), so accept either post-load state (R16).
        XCTAssertTrue(viewModel.state == .loaded || viewModel.state == .partialData)
        XCTAssertEqual(viewModel.todayStandingDuration, expectedTodayDuration, accuracy: 1)
        guard case .vsYesterday(let delta) = viewModel.comparison else {
            XCTFail("Expected vsYesterday comparison, got \(String(describing: viewModel.comparison))")
            return
        }
        XCTAssertEqual(delta, expectedTodayDuration - yesterdaySameTimeDuration, accuracy: 1)
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
        // Clamped to startOfToday so a fixed offset can't spill into yesterday.
        let todayStart = max(startOfToday, now.addingTimeInterval(-1800))
        let todayEnd = max(startOfToday, now.addingTimeInterval(-300))
        let todayInterval = ActivityInterval(start: todayStart, end: todayEnd, state: .standing)
        let mock = MockHealthDataProvider(
            authorizationState: .authorized,
            standingIntervalsResult: .success([twoDaysAgoInterval, todayInterval])
        )
        let viewModel = TodayViewModel(healthData: mock, settingsStore: Self.isolatedStore(), calendar: calendar)

        await viewModel.refresh()

        // Confidence is incidental here too — this test is about the fallback-to-average path.
        XCTAssertTrue(viewModel.state == .loaded || viewModel.state == .partialData)
        guard case .vsSevenDayAverage(let deltaPercent) = viewModel.comparison else {
            XCTFail("Expected vsSevenDayAverage comparison, got \(String(describing: viewModel.comparison))")
            return
        }
        XCTAssertGreaterThan(deltaPercent, 0)
    }

    /// R45: a failing off-wrist source must leave the day exactly as it would have been —
    /// the feature can never make the Today screen worse than it was before it existed.
    func testFailingOffWristSourceLeavesTheDaySummaryUnchanged() async {
        struct SampleError: Error {}
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let intervalStart = max(startOfToday, now.addingTimeInterval(-3600))
        let intervalEnd = max(startOfToday, now.addingTimeInterval(-1800))
        let interval = ActivityInterval(start: intervalStart, end: intervalEnd, state: .standing)

        func viewModel(offWrist: Result<[DateInterval], Error>) -> TodayViewModel {
            let mock = MockHealthDataProvider(
                authorizationState: .authorized,
                standingIntervalsResult: .success([interval]),
                offWristSpansResult: offWrist
            )
            return TodayViewModel(healthData: mock, settingsStore: Self.isolatedStore(), calendar: calendar)
        }

        let failing = viewModel(offWrist: .failure(SampleError()))
        let baseline = viewModel(offWrist: .success([]))
        await failing.refresh()
        await baseline.refresh()

        // The two refreshes each take their own `Date()`, so the observation windows differ by
        // microseconds — compare the classification and the arithmetic, not the exact boundaries.
        XCTAssertEqual(failing.state, baseline.state)
        XCTAssertEqual(failing.timeline.map(\.state), baseline.timeline.map(\.state))
        XCTAssertEqual(failing.estimatedSedentaryDuration ?? -1, baseline.estimatedSedentaryDuration ?? -1, accuracy: 1)
        XCTAssertEqual(failing.standingPercentage, baseline.standingPercentage)
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
