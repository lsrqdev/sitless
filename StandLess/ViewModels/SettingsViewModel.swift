import Foundation
import Observation
import StandLessKit

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

    var isHealthConnected: Bool {
        healthData.authorizationState == .authorized
    }

    init(store: SettingsStore, healthData: HealthDataProviding) {
        self.store = store
        self.healthData = healthData
        self.standingGoal = store.standingGoal
    }
}
