import Foundation

/// HealthKit-independent implementation of `ActivityCalculating` (R11).
///
/// `summarize` never trusts a single source in isolation: it merges standing, activity, and
/// sleep samples on a shared timeline, resolves any overlap by priority (sleep > standing >
/// active, since sleep is the most authoritative "not sedentary" signal and standing/active
/// are both directly measured), and only then treats the remaining gaps in `observationWindow`
/// as sedentary or unknown. This is what R14 means by "never a naive subtraction of cumulative
/// HealthKit totals" — durations always come from a de-duplicated timeline, not raw sums.
public struct ActivityCalculator: ActivityCalculating {
    /// A gap between two known samples longer than this is treated as `.unknown` rather than
    /// `.sedentary` (R15) — a multi-hour silence is insufficient evidence to confidently call
    /// sedentary, distinct from a short gap between two nearby measurements.
    public static let maxInferredSedentaryGap: TimeInterval = 3 * 3600

    /// Below this fraction of `observationWindow` covered by `.unknown` time, confidence can be
    /// `.high` when standing/activity/sleep are all present (R16).
    private static let highConfidenceMaxUnknownRatio: Double = 0.25
    /// Below this fraction of `observationWindow` covered by `.unknown` time, confidence is at
    /// least `.medium` when standing data is present (R16).
    private static let mediumConfidenceMaxUnknownRatio: Double = 0.5

    public init() {}

    public func summarize(
        standing: [ActivityInterval],
        activity: [ActivityInterval],
        sleep: [ActivityInterval],
        offWrist: [DateInterval],
        steps: Int?,
        standHours: Int?,
        observationWindow: DateInterval,
        calendar: Calendar
    ) -> DailyActivitySummary {
        let clippedStanding = clip(standing, to: observationWindow)
        let clippedActivity = clip(activity, to: observationWindow)
        let clippedSleep = clip(sleep, to: observationWindow)
        let clippedOffWrist = clipSpans(offWrist, to: observationWindow)

        let known = Self.mergeIntervals(clippedStanding + clippedActivity + clippedSleep)
        let gaps = Self.gaps(in: known, within: observationWindow)
        let classifiedGaps = Self.classify(gaps: gaps, knownSamples: known, offWrist: clippedOffWrist)
        let timeline = (known + classifiedGaps).sorted { $0.start < $1.start }

        let standingDuration = duration(of: timeline, state: .standing)
        let activeDuration = duration(of: timeline, state: .active)
        let sedentaryDuration = duration(of: timeline, state: .sedentary)
        let unknownDuration = duration(of: timeline, state: .unknown)

        let windowDuration = observationWindow.duration
        let unknownRatio = windowDuration > 0 ? unknownDuration / windowDuration : 1
        let confidence = Self.confidence(
            hasStanding: !clippedStanding.isEmpty,
            hasActivity: !clippedActivity.isEmpty,
            hasSleep: !clippedSleep.isEmpty,
            unknownRatio: unknownRatio
        )

        let denominator = standingDuration + sedentaryDuration
        let standingPercentage: Int? = (confidence == .low || denominator <= 0)
            ? nil
            : Int((standingDuration / denominator * 100).rounded())

        let longestInactive = Self.longestInactiveInterval(in: timeline)

        return DailyActivitySummary(
            date: calendar.startOfDay(for: observationWindow.start),
            standingDuration: standingDuration,
            estimatedSedentaryDuration: sedentaryDuration,
            activeDuration: activeDuration,
            unknownDuration: unknownDuration,
            standHours: standHours,
            steps: steps,
            longestInactiveDuration: longestInactive,
            confidence: confidence,
            standingPercentage: standingPercentage,
            timeline: timeline
        )
    }

    // MARK: - Timeline construction

    private func clip(_ intervals: [ActivityInterval], to window: DateInterval) -> [ActivityInterval] {
        intervals.compactMap { interval in
            let start = max(interval.start, window.start)
            let end = min(interval.end, window.end)
            guard end > start else { return nil }
            return ActivityInterval(start: start, end: end, state: interval.state)
        }
    }

    /// Clips off-wrist spans to the observation window and merges any overlap, mirroring how
    /// every other input is clipped (R47). An overnight charge that straddles midnight therefore
    /// contributes only its own day's portion to each day's summary.
    private func clipSpans(_ spans: [DateInterval], to window: DateInterval) -> [DateInterval] {
        let clipped = spans.compactMap { span -> DateInterval? in
            let start = max(span.start, window.start)
            let end = min(span.end, window.end)
            guard end > start else { return nil }
            return DateInterval(start: start, end: end)
        }.sorted { $0.start < $1.start }

        guard var current = clipped.first else { return [] }
        var merged: [DateInterval] = []
        for span in clipped.dropFirst() {
            if span.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, span.end))
            } else {
                merged.append(current)
                current = span
            }
        }
        merged.append(current)
        return merged
    }

    /// Higher wins when two different states overlap in time.
    private static func priority(for state: ActivityState) -> Int {
        switch state {
        case .sleep: return 3
        case .standing: return 2
        case .active: return 1
        case .sedentary, .unknown: return 0
        }
    }

    /// Merges same-state overlapping/adjacent intervals (R12's "adjacent interval merging"),
    /// then resolves cross-state overlap by priority so overlapping activity and standing
    /// samples are never double-counted (R12's "active+standing overlap").
    static func mergeIntervals(_ intervals: [ActivityInterval]) -> [ActivityInterval] {
        let valid = intervals.filter { $0.end > $0.start }
        guard !valid.isEmpty else { return [] }

        let grouped = Dictionary(grouping: valid, by: \.state)
        var perStateMerged: [ActivityInterval] = []
        for (state, group) in grouped {
            let sorted = group.sorted { $0.start < $1.start }
            var current = sorted[0]
            for next in sorted.dropFirst() {
                if next.start <= current.end {
                    current = ActivityInterval(start: current.start, end: max(current.end, next.end), state: state)
                } else {
                    perStateMerged.append(current)
                    current = next
                }
            }
            perStateMerged.append(current)
        }

        // Process strictly highest-priority-first (not by start time): a lower-priority interval
        // placed into `result` before a higher-priority one arrives would never get carved back,
        // since this loop only subtracts the *incoming* interval against what's already placed.
        let byPriorityThenStart = perStateMerged.sorted {
            let lhs = priority(for: $0.state), rhs = priority(for: $1.state)
            return lhs != rhs ? lhs > rhs : $0.start < $1.start
        }

        var result: [ActivityInterval] = []
        for interval in byPriorityThenStart {
            var remaining = [interval]
            for existing in result where priority(for: existing.state) > priority(for: interval.state) {
                remaining = remaining.flatMap { subtract($0, existing) }
                if remaining.isEmpty { break }
            }
            result.append(contentsOf: remaining)
        }
        return result.sorted { $0.start < $1.start }
    }

    private static func subtract(_ interval: ActivityInterval, _ other: ActivityInterval) -> [ActivityInterval] {
        guard interval.end > other.start, interval.start < other.end else { return [interval] }
        var pieces: [ActivityInterval] = []
        if interval.start < other.start {
            pieces.append(ActivityInterval(start: interval.start, end: other.start, state: interval.state))
        }
        if interval.end > other.end {
            pieces.append(ActivityInterval(start: other.end, end: interval.end, state: interval.state))
        }
        return pieces
    }

    /// The uncovered spans of `window` once every known (standing/active/sleep) interval is
    /// placed on the timeline.
    private static func gaps(in known: [ActivityInterval], within window: DateInterval) -> [DateInterval] {
        var gaps: [DateInterval] = []
        var cursor = window.start
        for interval in known.sorted(by: { $0.start < $1.start }) {
            if interval.start > cursor {
                gaps.append(DateInterval(start: cursor, end: interval.start))
            }
            cursor = max(cursor, interval.end)
        }
        if cursor < window.end {
            gaps.append(DateInterval(start: cursor, end: window.end))
        }
        return gaps
    }

    /// A gap before the first sample, after the last sample, or longer than
    /// `maxInferredSedentaryGap` is `.unknown` (R15) — there isn't enough evidence around it to
    /// call it confidently sedentary. Shorter gaps between two known samples are `.sedentary`,
    /// the estimated-remainder rule from R14.
    ///
    /// Each gap is then split at `offWrist` boundaries (R48): the portions the watch was not being
    /// worn become `.unknown`, and every remaining portion keeps whichever state the rule above
    /// gave the gap as a whole. The rule is deliberately evaluated on the undivided gap, never on
    /// the pieces, so splitting can never turn part of a long `.unknown` gap into `.sedentary`.
    private static func classify(
        gaps: [DateInterval],
        knownSamples: [ActivityInterval],
        offWrist: [DateInterval]
    ) -> [ActivityInterval] {
        let firstStart = knownSamples.map(\.start).min()
        let lastEnd = knownSamples.map(\.end).max()
        return gaps.flatMap { gap -> [ActivityInterval] in
            let state: ActivityState
            if let firstStart, let lastEnd {
                let isEdgeGap = gap.start < firstStart || gap.end > lastEnd
                state = (isEdgeGap || gap.duration > maxInferredSedentaryGap) ? .unknown : .sedentary
            } else {
                state = .unknown
            }
            return split(gap: gap, at: offWrist, otherwise: state)
        }
    }

    /// Splits one gap into `.unknown` pieces wherever it overlaps an off-wrist span and `state`
    /// pieces everywhere else (R48). `offWrist` is expected already clipped, sorted and merged.
    private static func split(
        gap: DateInterval,
        at offWrist: [DateInterval],
        otherwise state: ActivityState
    ) -> [ActivityInterval] {
        let overlaps = offWrist.compactMap { span -> DateInterval? in
            let start = max(span.start, gap.start)
            let end = min(span.end, gap.end)
            guard end > start else { return nil }
            return DateInterval(start: start, end: end)
        }
        guard !overlaps.isEmpty else {
            return [ActivityInterval(start: gap.start, end: gap.end, state: state)]
        }

        var pieces: [ActivityInterval] = []
        var cursor = gap.start
        for span in overlaps {
            if span.start > cursor {
                pieces.append(ActivityInterval(start: cursor, end: span.start, state: state))
            }
            pieces.append(ActivityInterval(start: span.start, end: span.end, state: .unknown))
            cursor = span.end
        }
        if cursor < gap.end {
            pieces.append(ActivityInterval(start: cursor, end: gap.end, state: state))
        }
        return pieces
    }

    private func duration(of timeline: [ActivityInterval], state: ActivityState) -> TimeInterval {
        timeline.filter { $0.state == state }.reduce(0) { $0 + $1.duration }
    }

    private static func confidence(hasStanding: Bool, hasActivity: Bool, hasSleep: Bool, unknownRatio: Double) -> DataConfidence {
        if hasStanding, hasActivity, hasSleep, unknownRatio < highConfidenceMaxUnknownRatio {
            return .high
        }
        if hasStanding, unknownRatio < mediumConfidenceMaxUnknownRatio {
            return .medium
        }
        return .low
    }

    /// The longest single `.sedentary` (estimated-inactive) interval on the timeline (R18).
    static func longestInactiveInterval(in timeline: [ActivityInterval]) -> TimeInterval? {
        timeline.filter { $0.state == .sedentary }.map(\.duration).max()
    }

    // MARK: - Cross-day utilities (R18: historical averages, same-time-of-day comparisons)

    public struct DailyStanding: Equatable, Sendable {
        public let date: Date
        public let duration: TimeInterval
        public init(date: Date, duration: TimeInterval) {
            self.date = date
            self.duration = duration
        }
    }

    /// Sums interval duration for intervals starting on `day`'s calendar day.
    public static func totalDuration(of intervals: [ActivityInterval], on day: Date, calendar: Calendar) -> TimeInterval {
        intervals
            .filter { calendar.isDate($0.start, inSameDayAs: day) }
            .reduce(0) { $0 + $1.duration }
    }

    /// Sums interval duration clipped to an arbitrary date range — used for partial-day
    /// comparisons like "today so far" or "yesterday at this same time".
    public static func totalDuration(of intervals: [ActivityInterval], in range: DateInterval) -> TimeInterval {
        intervals.reduce(0) { total, interval in
            let start = max(interval.start, range.start)
            let end = min(interval.end, range.end)
            guard end > start else { return total }
            return total + end.timeIntervalSince(start)
        }
    }

    /// A day-by-day standing-duration series from `start` to `end`, inclusive — the input to
    /// historical averages and trend charts.
    public static func dailyTotals(
        of intervals: [ActivityInterval],
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> [DailyStanding] {
        var day = start
        var results: [DailyStanding] = []
        while day <= end {
            let total = totalDuration(of: intervals, on: day, calendar: calendar)
            results.append(DailyStanding(date: day, duration: total))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return results
    }

    /// Prefers "yesterday at this same time" (partial-day-aware, R18) and falls back to the
    /// prior-days average when yesterday has no standing data of its own.
    public static func sameTimeOfDayComparison(
        todayStandingDuration: TimeInterval,
        intervals: [ActivityInterval],
        priorDaySeries: [DailyStanding],
        startOfYesterday: Date,
        yesterdaySameTime: Date,
        calendar: Calendar
    ) -> StandingComparison? {
        let yesterdayHasData = intervals.contains { calendar.isDate($0.start, inSameDayAs: startOfYesterday) }
        if yesterdayHasData {
            let yesterdaySameTimeDuration = totalDuration(
                of: intervals,
                in: DateInterval(start: startOfYesterday, end: yesterdaySameTime)
            )
            return .vsYesterday(delta: todayStandingDuration - yesterdaySameTimeDuration)
        }

        guard !priorDaySeries.isEmpty else { return nil }
        let priorAverage = priorDaySeries.reduce(0) { $0 + $1.duration } / Double(priorDaySeries.count)
        guard priorAverage > 0 else { return nil }
        let deltaPercent = Int(((todayStandingDuration - priorAverage) / priorAverage * 100).rounded())
        return .vsSevenDayAverage(deltaPercent: deltaPercent)
    }
}
