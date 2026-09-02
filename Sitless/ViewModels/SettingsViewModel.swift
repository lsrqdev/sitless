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

    /// What the Apple Health row reports. `connected` means the Health prompt has been answered —
    /// Apple never tells an app whether a read was granted, so that is as much as can honestly be
    /// claimed.
    enum HealthConnection: Equatable {
        case connected
        case notConnected
        case unavailable
    }

    /// `nil` until the asynchronous Health request-status check resolves, so the row never flashes
    /// "Not Connected" at someone who has in fact been through the prompt.
    private(set) var healthConnection: HealthConnection?

    var isMotionConnected: Bool {
        MotionManager.isAuthorized
    }

    init(store: SettingsStore, healthData: HealthDataProviding) {
        self.store = store
        self.healthData = healthData
        self.standingGoal = store.standingGoal
        self.reminderInterval = store.reminderInterval
    }

    func loadHealthConnection() async {
        switch await healthData.authorizationState {
        case .determined:
            healthConnection = .connected
        case .notDetermined:
            healthConnection = .notConnected
        case .unavailable:
            healthConnection = .unavailable
        }
    }
}
