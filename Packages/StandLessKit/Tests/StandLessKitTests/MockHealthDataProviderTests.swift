import XCTest
@testable import StandLessKit

final class MockHealthDataProviderTests: XCTestCase {
    func testDefaultAuthorizationStateIsNotDetermined() {
        let mock = MockHealthDataProvider()
        XCTAssertEqual(mock.authorizationState, .notDetermined)
    }

    func testRequestAuthorizationMarksAuthorized() async throws {
        let mock = MockHealthDataProvider()
        try await mock.requestAuthorization()
        XCTAssertEqual(mock.authorizationState, .authorized)
        XCTAssertEqual(mock.requestAuthorizationCallCount, 1)
    }

    func testStandingIntervalsReturnsConfiguredResult() async throws {
        let interval = ActivityInterval(start: .distantPast, end: .distantPast, state: .standing)
        let mock = MockHealthDataProvider(standingIntervalsResult: .success([interval]))
        let result = try await mock.standingIntervals(in: DateInterval(start: .distantPast, end: .distantPast))
        XCTAssertEqual(result, [interval])
    }

    func testStandingIntervalsPropagatesFailure() async {
        struct SampleError: Error {}
        let mock = MockHealthDataProvider(standingIntervalsResult: .failure(SampleError()))
        do {
            _ = try await mock.standingIntervals(in: DateInterval(start: .distantPast, end: .distantPast))
            XCTFail("Expected error to propagate")
        } catch {
            XCTAssertTrue(error is SampleError)
        }
    }
}
