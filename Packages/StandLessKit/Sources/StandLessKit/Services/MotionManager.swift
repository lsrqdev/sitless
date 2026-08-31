import Foundation
import CoreMotion

/// Wraps `CMMotionActivityManager` — adopted only for driving-based reminder suppression (R32),
/// not for the sedentary estimate. `stationary` is never read as sitting, standing-still, or
/// lying down anywhere in this type or its callers — the only signal this type surfaces is
/// `automotive` (R19).
public final class MotionManager: @unchecked Sendable {
    private let activityManager = CMMotionActivityManager()

    public init() {}

    public static var isAvailable: Bool {
        CMMotionActivityManager.isActivityAvailable()
    }

    /// Whether the user has granted motion access, for display in Settings (R30) without
    /// exposing `CoreMotion` types to the view layer.
    public static var isAuthorized: Bool {
        CMMotionActivityManager.authorizationStatus() == .authorized
    }

    /// Starts continuous motion-activity updates. Continuous updates do not themselves survive
    /// app suspension — `isLikelyDriving(now:completion:)` is used at reschedule time instead of
    /// relying solely on this (documented background limitation, see README).
    public func startUpdates(handler: @escaping @Sendable (_ isAutomotive: Bool) -> Void) {
        guard Self.isAvailable else { return }
        activityManager.startActivityUpdates(to: .main) { activity in
            guard let activity else { return }
            handler(activity.automotive)
        }
    }

    public func stopUpdates() {
        activityManager.stopActivityUpdates()
    }

    /// One-shot lookback query for whether the most recent motion sample indicates driving. Used
    /// at reschedule time, since a suspended app may not have received a live `startUpdates`
    /// callback recently.
    public func isLikelyDriving(
        lookback: TimeInterval = 5 * 60,
        now: Date = Date(),
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        guard Self.isAvailable else {
            completion(false)
            return
        }
        let start = now.addingTimeInterval(-lookback)
        activityManager.queryActivityStarting(from: start, to: now, to: .main) { activities, _ in
            completion(activities?.last?.automotive ?? false)
        }
    }
}
