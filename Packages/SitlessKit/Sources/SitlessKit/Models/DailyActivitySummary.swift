import Foundation

public struct DailyActivitySummary: Equatable, Sendable {
    public let date: Date
    public let standingDuration: TimeInterval
    public let estimatedSedentaryDuration: TimeInterval?   // nil until Phase 3's calculator runs
    public let activeDuration: TimeInterval?
    public let unknownDuration: TimeInterval
    public let standHours: Int?
    public let steps: Int?
    public let longestInactiveDuration: TimeInterval?
    public let confidence: DataConfidence
    public let standingPercentage: Int?   // whole number only; nil when confidence is too low to claim precision
    public let timeline: [ActivityInterval]  // merged, ordered — backs the hourly timeline view

    public init(
        date: Date,
        standingDuration: TimeInterval,
        estimatedSedentaryDuration: TimeInterval? = nil,
        activeDuration: TimeInterval? = nil,
        unknownDuration: TimeInterval = 0,
        standHours: Int? = nil,
        steps: Int? = nil,
        longestInactiveDuration: TimeInterval? = nil,
        confidence: DataConfidence = .low,
        standingPercentage: Int? = nil,
        timeline: [ActivityInterval] = []
    ) {
        self.date = date
        self.standingDuration = standingDuration
        self.estimatedSedentaryDuration = estimatedSedentaryDuration
        self.activeDuration = activeDuration
        self.unknownDuration = unknownDuration
        self.standHours = standHours
        self.steps = steps
        self.longestInactiveDuration = longestInactiveDuration
        self.confidence = confidence
        self.standingPercentage = standingPercentage
        self.timeline = timeline
    }
}
