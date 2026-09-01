import XCTest
@testable import SitlessKit

final class SettingsStoreTests: XCTestCase {
    private let legacyStandingGoalKey = "standless.settings.standingGoalDuration"
    private let legacyReminderIntervalKey = "standless.settings.reminderInterval"
    private let newStandingGoalKey = "sitless.settings.standingGoalDuration"
    private let newReminderIntervalKey = "sitless.settings.reminderInterval"

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
        defaults.set(99_999.0, forKey: "sitless.settings.standingGoalDuration")
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

    func testSettingStandingGoalInvokesOnStandingGoalChanged() {
        let (store, _) = makeStore()
        var received: StandingGoal?
        store.onStandingGoalChanged = { received = $0 }

        store.standingGoal = StandingGoal(duration: 4.5 * 3600)

        XCTAssertEqual(received?.duration, 4.5 * 3600)
    }

    func testValuesSavedUnderTheOldKeysAreMigratedOnFirstRead() {
        let (_, defaults) = makeStore()
        defaults.set(4 * 3600 as Double, forKey: legacyStandingGoalKey)
        defaults.set(ReminderInterval.sixty.rawValue, forKey: legacyReminderIntervalKey)

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.standingGoal.duration, 4 * 3600)
        XCTAssertEqual(store.reminderInterval, .sixty)
        XCTAssertEqual(defaults.double(forKey: newStandingGoalKey), 4 * 3600)
        XCTAssertEqual(defaults.object(forKey: newReminderIntervalKey) as? Int, ReminderInterval.sixty.rawValue)
    }

    func testNoOldValuesLeavesDefaultsAndWritesNothing() {
        let (_, defaults) = makeStore()

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.standingGoal, StandingGoal.defaultGoal)
        XCTAssertEqual(store.reminderInterval, ReminderInterval.defaultInterval)
        XCTAssertNil(defaults.object(forKey: newStandingGoalKey))
        XCTAssertNil(defaults.object(forKey: newReminderIntervalKey))
    }

    func testMigrationDoesNotOverwriteAValueAlreadySavedUnderTheNewKey() {
        let (_, defaults) = makeStore()
        defaults.set(4 * 3600 as Double, forKey: legacyStandingGoalKey)
        defaults.set(ReminderInterval.sixty.rawValue, forKey: legacyReminderIntervalKey)
        defaults.set(5 * 3600 as Double, forKey: newStandingGoalKey)
        defaults.set(ReminderInterval.thirty.rawValue, forKey: newReminderIntervalKey)

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.standingGoal.duration, 5 * 3600)
        XCTAssertEqual(store.reminderInterval, .thirty)
    }

    func testMigrationIsIdempotentAcrossStores() {
        let (_, defaults) = makeStore()
        defaults.set(4 * 3600 as Double, forKey: legacyStandingGoalKey)

        _ = SettingsStore(defaults: defaults)
        let store = SettingsStore(defaults: defaults)
        store.standingGoal = StandingGoal(duration: 5 * 3600)
        let reopened = SettingsStore(defaults: defaults)

        XCTAssertEqual(reopened.standingGoal.duration, 5 * 3600)
    }

    func testMigratedInvalidValueStillFallsBackToTheDefault() {
        let (_, defaults) = makeStore()
        defaults.set(99_999.0, forKey: legacyStandingGoalKey)
        defaults.set(7, forKey: legacyReminderIntervalKey)

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.standingGoal, StandingGoal.defaultGoal)
        XCTAssertEqual(store.reminderInterval, ReminderInterval.defaultInterval)
    }
}
