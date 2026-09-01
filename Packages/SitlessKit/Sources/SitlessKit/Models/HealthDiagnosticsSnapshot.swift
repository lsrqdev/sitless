import Foundation

/// Raw, unprocessed HealthKit query results backing the DEBUG-only diagnostics screen (R35).
public struct HealthDiagnosticsSnapshot: Equatable, Sendable {
    public struct SampleEntry: Equatable, Sendable {
        public let start: Date
        public let end: Date
        public let value: Double
        public let sourceName: String

        public init(start: Date, end: Date, value: Double, sourceName: String) {
            self.start = start
            self.end = end
            self.value = value
            self.sourceName = sourceName
        }
    }

    public let queryRange: DateInterval
    public let standTimeSamples: [SampleEntry]
    public let exerciseTimeSamples: [SampleEntry]
    public let moveTimeSamples: [SampleEntry]
    public let sleepSamples: [SampleEntry]
    public let steps: Int

    public init(
        queryRange: DateInterval,
        standTimeSamples: [SampleEntry],
        exerciseTimeSamples: [SampleEntry] = [],
        moveTimeSamples: [SampleEntry] = [],
        sleepSamples: [SampleEntry] = [],
        steps: Int = 0
    ) {
        self.queryRange = queryRange
        self.standTimeSamples = standTimeSamples
        self.exerciseTimeSamples = exerciseTimeSamples
        self.moveTimeSamples = moveTimeSamples
        self.sleepSamples = sleepSamples
        self.steps = steps
    }
}
