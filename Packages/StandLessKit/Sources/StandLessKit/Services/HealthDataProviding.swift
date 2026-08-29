import Foundation

/// The mock boundary required by R39 — SwiftUI views never call HealthKit APIs directly,
/// only through a ViewModel that holds a `HealthDataProviding`.
public protocol HealthDataProviding: Sendable {
    var authorizationState: HealthAuthorizationState { get }
    func requestAuthorization() async throws
    func standingIntervals(in range: DateInterval) async throws -> [ActivityInterval]
    func standHours(in range: DateInterval) async throws -> Int
    /// Meaningful-activity intervals (exercise + move time), tagged `.active` (R8).
    func activityIntervals(in range: DateInterval) async throws -> [ActivityInterval]
    /// Known-sleep intervals, tagged `.sleep` — excluded from the sedentary estimate (R13).
    func sleepIntervals(in range: DateInterval) async throws -> [ActivityInterval]
    func steps(in range: DateInterval) async throws -> Int
    func rawDiagnostics(in range: DateInterval) async throws -> HealthDiagnosticsSnapshot
}
