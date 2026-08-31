import Foundation

/// `UserDefaults`-backed persistence for user-configurable settings.
///
/// One instance per device — the iPhone and Watch each hold their own `SettingsStore`;
/// `WatchConnectivityService` (Phase 4) is what keeps their `StandingGoal` in sync.
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let standingGoalKey = "standless.settings.standingGoalDuration"
    private static let reminderIntervalKey = "standless.settings.reminderInterval"

    /// Invoked whenever `standingGoal` is set to a new value. The iPhone target wires this to
    /// `WatchConnectivityService.pushStandingGoal(_:)` so a goal change reaches the paired Watch
    /// (Phase 4). The Watch's own `SettingsStore` instance never sets this — the Watch has no
    /// goal-setting UI, it only ever receives (R34).
    public var onStandingGoalChanged: (@Sendable (StandingGoal) -> Void)?

    /// Invoked whenever `reminderInterval` is set to a new value. The iPhone target wires this to
    /// immediately reschedule (or cancel) the pending inactivity notification, rather than
    /// waiting for the next detected movement (Phase 5).
    public var onReminderIntervalChanged: (@Sendable (ReminderInterval) -> Void)?

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

    public var reminderInterval: ReminderInterval {
        get {
            guard let stored = defaults.object(forKey: Self.reminderIntervalKey) as? Int,
                  let interval = ReminderInterval(rawValue: stored) else {
                return .defaultInterval
            }
            return interval
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.reminderIntervalKey)
            onReminderIntervalChanged?(newValue)
        }
    }
}
