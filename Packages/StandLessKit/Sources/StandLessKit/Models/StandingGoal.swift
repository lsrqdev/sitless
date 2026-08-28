import Foundation

/// A user-configurable daily standing-duration goal (R29).
///
/// This is distinct from Apple's own Stand Hours goal — it represents total
/// accumulated standing duration, not a count of hours with at least one stand.
public struct StandingGoal: Codable, Equatable, Sendable {
    public var duration: TimeInterval

    public init(duration: TimeInterval) {
        self.duration = duration
    }

    public static let options: [TimeInterval] = [2, 2.5, 3, 3.5, 4, 4.5, 5].map { $0 * 3600 }
    public static let defaultGoal = StandingGoal(duration: 3.5 * 3600)
}
