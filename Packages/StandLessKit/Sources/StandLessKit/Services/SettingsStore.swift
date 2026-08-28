import Foundation

/// `UserDefaults`-backed persistence for user-configurable settings.
///
/// One instance per device — the iPhone and Watch each hold their own `SettingsStore`;
/// `WatchConnectivityService` (Phase 4) is what keeps their `StandingGoal` in sync.
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let standingGoalKey = "standless.settings.standingGoalDuration"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var standingGoal: StandingGoal {
        get {
            let stored = defaults.double(forKey: Self.standingGoalKey)
            guard StandingGoal.options.contains(stored) else { return .defaultGoal }
            return StandingGoal(duration: stored)
        }
        set {
            defaults.set(newValue.duration, forKey: Self.standingGoalKey)
        }
    }
}
