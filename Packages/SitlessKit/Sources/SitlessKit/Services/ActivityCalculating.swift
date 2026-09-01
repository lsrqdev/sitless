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
    func summarize(
        standing: [ActivityInterval],
        activity: [ActivityInterval],
        sleep: [ActivityInterval],
        steps: Int?,
        standHours: Int?,
        observationWindow: DateInterval,
        calendar: Calendar
    ) -> DailyActivitySummary
}
