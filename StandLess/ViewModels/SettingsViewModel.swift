import Foundation
import Observation
import StandLessKit

@MainActor
@Observable
final class SettingsViewModel {
    private let store: SettingsStore

    var standingGoal: StandingGoal {
        didSet {
            guard standingGoal != oldValue else { return }
            store.standingGoal = standingGoal
        }
    }

    init(store: SettingsStore) {
        self.store = store
        self.standingGoal = store.standingGoal
    }
}
