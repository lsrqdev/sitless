import Foundation
import Observation
import SitlessKit

@MainActor
@Observable
final class SettingsViewModel {
    private let store: SettingsStore
    private let healthData: HealthDataProviding

    var standingGoal: StandingGoal {
        didSet {
            guard standingGoal != oldValue else { return }
            store.standingGoal = standingGoal
        }
    }

    var reminderInterval: ReminderInterval {
        didSet {
            guard reminderInterval != oldValue else { return }
            store.reminderInterval = reminderInterval
        }
    }

    var isHealthConnected: Bool {
        healthData.authorizationState == .authorized
    }

    var isMotionConnected: Bool {
        MotionManager.isAuthorized
    }

    init(store: SettingsStore, healthData: HealthDataProviding) {
        self.store = store
        self.healthData = healthData
        self.standingGoal = store.standingGoal
        self.reminderInterval = store.reminderInterval
    }
}
