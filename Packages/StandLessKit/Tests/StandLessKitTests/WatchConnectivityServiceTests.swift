import XCTest
@testable import StandLessKit

final class WatchConnectivityServiceTests: XCTestCase {
    private func makeStore() -> SettingsStore {
        let suiteName = "WatchConnectivityServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(defaults: defaults)
    }

    func testApplyingIncomingContextUpdatesLocalSettingsStore() {
        let store = makeStore()
        let service = WatchConnectivityService(settingsStore: store)
        let goal = StandingGoal.options[2]

        service.applyIncomingContext([WatchConnectivityService.standingGoalDurationKey: goal])

        XCTAssertEqual(store.standingGoal.duration, goal)
    }

    func testApplyingContextWithUnrecognizedDurationIsIgnored() {
        let store = makeStore()
        let service = WatchConnectivityService(settingsStore: store)
        let before = store.standingGoal

        service.applyIncomingContext([WatchConnectivityService.standingGoalDurationKey: 99_999.0])

        XCTAssertEqual(store.standingGoal, before)
    }

    func testApplyingContextMissingTheExpectedKeyIsIgnored() {
        let store = makeStore()
        let service = WatchConnectivityService(settingsStore: store)
        let before = store.standingGoal

        service.applyIncomingContext(["unexpected": "value"])

        XCTAssertEqual(store.standingGoal, before)
    }

    func testApplyingContextWithWrongValueTypeIsIgnored() {
        let store = makeStore()
        let service = WatchConnectivityService(settingsStore: store)
        let before = store.standingGoal

        service.applyIncomingContext([WatchConnectivityService.standingGoalDurationKey: "not a number"])

        XCTAssertEqual(store.standingGoal, before)
    }
}
