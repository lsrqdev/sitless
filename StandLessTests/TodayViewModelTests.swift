import XCTest
import StandLessKit
@testable import StandLess

@MainActor
final class TodayViewModelTests: XCTestCase {
    func testStartReflectsDeniedAuthorizationWithoutTouchingRealHealthKit() async {
        let mock = MockHealthDataProvider(authorizationState: .denied)
        let viewModel = TodayViewModel(healthData: mock)

        await viewModel.start()

        XCTAssertEqual(viewModel.state, .authorizationRequired)
        XCTAssertEqual(mock.requestAuthorizationCallCount, 0)
    }

    func testStartReflectsUnavailableAuthorization() async {
        let mock = MockHealthDataProvider(authorizationState: .unavailable)
        let viewModel = TodayViewModel(healthData: mock)

        await viewModel.start()

        XCTAssertEqual(viewModel.state, .unavailable)
    }

    func testStartWithNoStandingDataYetLoadsZeroDuration() async {
        let mock = MockHealthDataProvider(authorizationState: .authorized, standingIntervalsResult: .success([]))
        let viewModel = TodayViewModel(healthData: mock)

        await viewModel.start()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.todayStandingDuration, 0)
    }

    func testRefreshLoadsTodayStandingFromMock() async {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let interval = ActivityInterval(
            start: startOfToday.addingTimeInterval(3600),
            end: startOfToday.addingTimeInterval(3600 + 1800),
            state: .standing
        )
        let mock = MockHealthDataProvider(authorizationState: .authorized, standingIntervalsResult: .success([interval]))
        let viewModel = TodayViewModel(healthData: mock, calendar: calendar)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.todayStandingDuration, 1800, accuracy: 0.001)
    }
}
