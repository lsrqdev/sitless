import XCTest
@testable import SitlessKit

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

    func testOffWristSpansDefaultToEmpty() async throws {
        let mock = MockHealthDataProvider()
        let result = try await mock.offWristSpans(in: DateInterval(start: .distantPast, end: .distantPast))
        XCTAssertTrue(result.isEmpty)
    }

    func testOffWristSpansReturnsConfiguredResult() async throws {
        let span = DateInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600))
        let mock = MockHealthDataProvider(offWristSpansResult: .success([span]))
        let result = try await mock.offWristSpans(in: DateInterval(start: .distantPast, end: .distantPast))
        XCTAssertEqual(result, [span])
    }

    func testLastHeartRateSampleDateDefaultsToNil() async throws {
        let mock = MockHealthDataProvider()
        let result = try await mock.lastHeartRateSampleDate(in: DateInterval(start: .distantPast, end: .distantPast))
        XCTAssertNil(result)
    }

    func testLastHeartRateSampleDateReturnsConfiguredResult() async throws {
        let sampleDate = Date(timeIntervalSince1970: 3600)
        let mock = MockHealthDataProvider(lastHeartRateSampleDateResult: .success(sampleDate))
        let result = try await mock.lastHeartRateSampleDate(in: DateInterval(start: .distantPast, end: .distantPast))
        XCTAssertEqual(result, sampleDate)
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
