import Foundation

public enum HealthAuthorizationState: Equatable, Sendable {
    case notDetermined, authorized, denied, unavailable
}
