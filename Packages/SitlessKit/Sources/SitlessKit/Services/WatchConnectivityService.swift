import Foundation
import WatchConnectivity

/// Thin `WCSession` wrapper — the only cross-device data flow in the app (per architecture).
/// Deliberately not an App Group, since App Groups only share storage between extensions on the
/// *same* device, not between an iPhone and a paired Watch.
///
/// iPhone side: pushes the current `StandingGoal` to the paired Watch via
/// `updateApplicationContext` whenever `SettingsStore.standingGoal` changes (wired through
/// `SettingsStore.onStandingGoalChanged` in `SitlessApp`), and again as soon as the session
/// finishes activating, so a freshly-paired Watch picks up the current goal without the user
/// having to reopen Settings.
///
/// Watch side: observes incoming application-context updates and writes them straight into its
/// own local `SettingsStore` — the Watch has no goal-setting UI of its own (R34).
public final class WatchConnectivityService: NSObject, @unchecked Sendable {
    static let standingGoalDurationKey = "standingGoalDuration"

    private let settingsStore: SettingsStore

    public init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        super.init()
    }

    /// Activates the underlying `WCSession`. Safe to call even where WatchConnectivity isn't
    /// supported (e.g. no paired counterpart device) — a no-op in that case.
    public func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// iPhone side only: sends `goal` to the paired Watch. WatchConnectivity delivery is
    /// opportunistic — there is no user-facing error surface for a failed or delayed push.
    public func pushStandingGoal(_ goal: StandingGoal) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext([Self.standingGoalDurationKey: goal.duration])
    }

    /// Applies an incoming application-context payload to the local `SettingsStore`. Split out
    /// from the `WCSessionDelegate` callback so this logic is unit-testable without requiring a
    /// real, activated `WCSession` pairing.
    func applyIncomingContext(_ context: [String: Any]) {
        guard let duration = context[Self.standingGoalDurationKey] as? TimeInterval,
              StandingGoal.options.contains(duration) else { return }
        settingsStore.standingGoal = StandingGoal(duration: duration)
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        #if os(iOS)
        guard activationState == .activated else { return }
        pushStandingGoal(settingsStore.standingGoal)
        #endif
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyIncomingContext(applicationContext)
    }
}
