import Foundation

public enum ActivityState: String, Codable, CaseIterable, Sendable {
    case standing, active, sedentary, unknown, sleep
    // "sedentary" is always a computed estimate — never a directly measured HealthKit state.
}
