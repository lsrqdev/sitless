import Foundation

/// `UserDefaults`-backed persistence for user-configurable settings.
///
/// One instance per device — the iPhone and Watch each hold their own `SettingsStore`;
/// `WatchConnectivityService` (Phase 4) is what keeps their `StandingGoal` in sync.
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let standingGoalKey = "standless.settings.standingGoalDuration"

    /// Invoked whenever `standingGoal` is set to a new value. The iPhone target wires this to
    /// `WatchConnectivityService.pushStandingGoal(_:)` so a goal change reaches the paired Watch
    /// (Phase 4). The Watch's own `SettingsStore` instance never sets this — the Watch has no
    /// goal-setting UI, it only ever receives (R34).
    public var onStandingGoalChanged: (@Sendable (StandingGoal) -> Void)?

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
            onStandingGoalChanged?(newValue)
        }
    }
}
