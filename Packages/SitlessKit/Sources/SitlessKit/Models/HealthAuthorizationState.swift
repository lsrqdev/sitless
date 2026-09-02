import Foundation

/// Whether the person has been through the Health permission prompt for every type Sitless reads.
///
/// Apple deliberately does not expose *read* permission to apps — knowing that a type was denied
/// would itself be a disclosure — so no case here may be read as "the user granted access".
/// `determined` means only that the system no longer needs to ask. Whether anything was actually
/// granted is unknowable, and an empty query result is the only signal the app ever gets.
public enum HealthAuthorizationState: Equatable, Sendable {
    /// The system still needs to ask about at least one type Sitless reads.
    case notDetermined
    /// The prompt has been answered for every type Sitless reads.
    case determined
    /// The device has no Health data store at all.
    case unavailable
}
