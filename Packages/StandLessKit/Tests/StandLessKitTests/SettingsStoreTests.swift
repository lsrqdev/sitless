import XCTest
@testable import StandLessKit

final class SettingsStoreTests: XCTestCase {
    private func makeStore(suiteSuffix: String = UUID().uuidString) -> (SettingsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests-\(suiteSuffix)")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests-\(suiteSuffix)")
        return (SettingsStore(defaults: defaults), defaults)
    }

    func testDefaultStandingGoalIsDefaultGoal() {
        let (store, _) = makeStore()
        XCTAssertEqual(store.standingGoal, StandingGoal.defaultGoal)
    }

    func testSettingStandingGoalPersists() {
        let (store, _) = makeStore()
        store.standingGoal = StandingGoal(duration: 4 * 3600)
        XCTAssertEqual(store.standingGoal.duration, 4 * 3600)
    }

    func testInvalidStoredDurationFallsBackToDefault() {
        let (_, defaults) = makeStore()
        defaults.set(99_999.0, forKey: "standless.settings.standingGoalDuration")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.standingGoal, StandingGoal.defaultGoal)
    }

    func testEachOptionRoundTripsThroughPersistence() {
        let (store, _) = makeStore()
        for option in StandingGoal.options {
            store.standingGoal = StandingGoal(duration: option)
            XCTAssertEqual(store.standingGoal.duration, option)
        }
    }
}
