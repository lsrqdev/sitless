import Foundation

public enum DataConfidence: Int, Codable, Comparable, Sendable {
    case low, medium, high

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
