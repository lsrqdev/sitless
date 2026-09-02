import Foundation

/// The mock boundary required by R39 — SwiftUI views never call HealthKit APIs directly,
/// only through a ViewModel that holds a `HealthDataProviding`.
public protocol HealthDataProviding: Sendable {
    /// Whether the Health prompt has been answered for every type Sitless reads. Asynchronous
    /// because the only API that can answer it — `HKHealthStore.getRequestStatusForAuthorization` —
    /// is completion-based.
    var authorizationState: HealthAuthorizationState { get async }
    func requestAuthorization() async throws
    func standingIntervals(in range: DateInterval) async throws -> [ActivityInterval]
    func standHours(in range: DateInterval) async throws -> Int
    /// Meaningful-activity intervals (exercise + move time), tagged `.active` (R8).
    func activityIntervals(in range: DateInterval) async throws -> [ActivityInterval]
    /// Known-sleep intervals, tagged `.sleep` — excluded from the sedentary estimate (R13).
    func sleepIntervals(in range: DateInterval) async throws -> [ActivityInterval]
    /// Spans within `range` during which the Apple Watch was not being worn (R40), inferred from
    /// gaps between consecutive heart-rate samples — the only continuously-recorded HealthKit
    /// signal that stops entirely when the watch leaves the wrist.
    ///
    /// Deliberately plain `DateInterval` values rather than `ActivityInterval`s: off-wrist time
    /// surfaces as the existing `.unknown` state, so no fifth `ActivityState` case is introduced
    /// and `ActivityCalculator` stays free of any notion of *why* a span is unmeasured.
    ///
    /// Only stretches *between* two heart-rate samples are reported — never the span before the
    /// first sample or after the last one in `range` (R42) — so a range with zero or one sample
    /// yields nothing at all. That is what makes this a no-op for someone using Sitless without
    /// an Apple Watch. Returns an empty result rather than throwing when heart-rate data is
    /// unavailable, unauthorized, or the query fails (R45).
    func offWristSpans(in range: DateInterval) async throws -> [DateInterval]
    /// The start date of the most recent heart-rate sample within `range`, or `nil` when the range
    /// holds none (R53). Used by the app layer for the *live* off-wrist check that suppresses the
    /// inactivity reminder, which `offWristSpans(in:)` cannot answer: that method only reports
    /// stretches *between* two samples (R42), so an ongoing off-wrist stretch — silence running all
    /// the way to now, with no later sample to close it — is never one of its spans.
    ///
    /// `nil` means "no evidence a wearable was on the body at all", not "off the wrist": someone
    /// using Sitless without an Apple Watch must never have a reminder suppressed by this.
    func lastHeartRateSampleDate(in range: DateInterval) async throws -> Date?
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
