import Foundation
import UserNotifications

/// Testability seam over `UNUserNotificationCenter` — its real implementation already matches
/// this signature exactly, so no adapter type is needed for production use.
public protocol NotificationCenterScheduling {
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable ((any Error)?) -> Void)?)
}

extension UNUserNotificationCenter: NotificationCenterScheduling {}

/// Snapshot of the conditions `NotificationManager` consults before allowing a reminder to fire
/// (R32). Built by the app layer from HealthKit sleep/workout data and `MotionManager`'s driving
/// signal; kept as plain data here so the suppression logic below is unit-testable without
/// HealthKit or CoreMotion.
public struct SuppressionSnapshot: Sendable {
    public var isAsleep: Bool
    public var isInWorkout: Bool
    public var isLikelyDriving: Bool

    public init(isAsleep: Bool = false, isInWorkout: Bool = false, isLikelyDriving: Bool = false) {
        self.isAsleep = isAsleep
        self.isInWorkout = isInWorkout
        self.isLikelyDriving = isLikelyDriving
    }
}

/// Owns exactly one pending inactivity-reminder notification, identified by `requestIdentifier`
/// (R31). `reschedule(interval:now:snapshot:)` is called on every detected meaningful movement:
/// it always cancels any existing pending request first, then schedules a new one `interval`
/// minutes out unless `interval` is `.off` or a safeguard applies (R32).
///
/// Safeguards are re-evaluated every time this is called, not at the moment the notification is
/// about to fire — iOS/watchOS give apps no supported way to re-check conditions in the final
/// seconds before a background-scheduled local notification is delivered (see README for the
/// resulting limitation). This fails closed: any suppressing condition, or too little time since
/// the last reminder actually fired, blocks scheduling.
public final class NotificationManager: @unchecked Sendable {
    public static let requestIdentifier = "sitless.inactivity"
    /// Pre-rename identifier, cancel-only: a reminder scheduled before the StandLess → Sitless
    /// rename may still be pending under it, so every `reschedule` clears both names and the user
    /// is never left with a duplicate reminder or a stale one after turning reminders off.
    public static let legacyRequestIdentifier = "standless.inactivity"
    /// Minimum gap enforced between two reminders, regardless of intervening movement (R32).
    public static let minimumRepeatGap: TimeInterval = 30 * 60

    private let center: NotificationCenterScheduling
    private var lastFiredAt: Date?

    public init(center: NotificationCenterScheduling = UNUserNotificationCenter.current(), lastFiredAt: Date? = nil) {
        self.center = center
        self.lastFiredAt = lastFiredAt
    }

    /// Records that the reminder actually fired, for the repeat-window check. The app layer calls
    /// this from its `UNUserNotificationCenterDelegate` callback when the notification is
    /// delivered.
    public func recordFired(at date: Date) {
        lastFiredAt = date
    }

    /// Whether scheduling is currently blocked.
    public func shouldSuppress(now: Date, snapshot: SuppressionSnapshot) -> Bool {
        if snapshot.isAsleep || snapshot.isInWorkout || snapshot.isLikelyDriving {
            return true
        }
        if let lastFiredAt, now.timeIntervalSince(lastFiredAt) < Self.minimumRepeatGap {
            return true
        }
        return false
    }

    /// Cancels any pending reminder and, unless suppressed, schedules a new one `interval`
    /// minutes from `now`. Returns the scheduled fire date, or `nil` if nothing was scheduled.
    @discardableResult
    public func reschedule(
        interval: ReminderInterval,
        now: Date = Date(),
        snapshot: SuppressionSnapshot = SuppressionSnapshot()
    ) -> Date? {
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier, Self.legacyRequestIdentifier])

        guard let seconds = interval.duration, !shouldSuppress(now: now, snapshot: snapshot) else {
            return nil
        }

        let content = UNMutableNotificationContent()
        content.title = "Time for a change of position?"
        content.body = "You've been inactive for a while. A few minutes standing or walking may be useful."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: Self.requestIdentifier, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)

        return now.addingTimeInterval(seconds)
    }
}
