import Foundation

/// HealthKit-independent activity classification (R11) — turns raw interval data into a
/// `DailyActivitySummary`, unit-testable with mock intervals alone (no HealthKit dependency).
public protocol ActivityCalculating: Sendable {
    /// Merges `standing`, `activity`, and `sleep` intervals (R12), excludes sleep from the
    /// sedentary estimate (R13), computes Estimated Sedentary Time as the remainder of
    /// `observationWindow` after removing standing/activity/sleep/unknown (R14), marks
    /// periods with insufficient evidence as `.unknown` rather than guessing (R15), and
    /// derives `DataConfidence` (R16), the standing percentage (R17), and the longest
    /// inactive interval (R18).
    ///
    /// `offWrist` carries the spans the watch was not being worn (R47). They never displace
    /// measured data — classification only ever runs over the gaps left in the merged timeline
    /// (R49) — but any gap time they cover becomes `.unknown` rather than `.sedentary`, which
    /// keeps it out of the standing-percentage denominator (R50). Pass an empty array to get
    /// exactly the classification this calculator produced before off-wrist detection existed.
    func summarize(
        standing: [ActivityInterval],
        activity: [ActivityInterval],
        sleep: [ActivityInterval],
        offWrist: [DateInterval],
        steps: Int?,
        standHours: Int?,
        observationWindow: DateInterval,
        calendar: Calendar
    ) -> DailyActivitySummary
}
