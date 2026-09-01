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
    /// Wraps `HKObserverQuery` + background delivery for the primary standing type. The handler
    /// is invoked whenever HealthKit reports new standing data, used as the "meaningful movement"
    /// trigger that reschedules the inactivity reminder (R32). Delivery timing while the app is
    /// suspended is governed entirely by the OS's background-delivery scheduler — see the README
    /// for the resulting best-effort limitation; this is not a substitute for continuous polling.
    func observeChanges(_ handler: @escaping @Sendable () -> Void)
    /// Whether a workout is currently in progress, or ended within the last few minutes — used to
    /// suppress the inactivity reminder during and immediately after a workout (R32). Workout
    /// samples become queryable only once HealthKit commits them at the end of the session, so
    /// this is a best-effort signal, not a live one — documented in the README.
    func isInActiveWorkout(asOf now: Date) async throws -> Bool
}
