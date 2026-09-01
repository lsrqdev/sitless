import Foundation

/// The user-configurable inactivity reminder interval (R31). `.off` disables the reminder
/// entirely; every other case is the number of minutes of inactivity before a reminder fires.
public enum ReminderInterval: Int, Codable, CaseIterable, Sendable {
    case off = 0, thirty = 30, fortyFive = 45, sixty = 60, ninety = 90

    public static let defaultInterval: ReminderInterval = .fortyFive

    /// `nil` for `.off` — no reminder should ever be scheduled.
    public var duration: TimeInterval? {
        self == .off ? nil : TimeInterval(rawValue * 60)
    }

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .thirty: return "30 min"
        case .fortyFive: return "45 min"
        case .sixty: return "60 min"
        case .ninety: return "90 min"
        }
    }
}
