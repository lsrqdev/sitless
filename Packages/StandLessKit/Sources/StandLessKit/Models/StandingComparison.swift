import Foundation

/// How today's standing time compares to a baseline. Prefers "yesterday at this time"
/// (a partial-day-aware comparison, R18) and falls back to the prior-days average when
/// yesterday has no standing data of its own.
public enum StandingComparison: Equatable, Sendable {
    case vsYesterday(delta: TimeInterval)
    case vsSevenDayAverage(deltaPercent: Int)
}
