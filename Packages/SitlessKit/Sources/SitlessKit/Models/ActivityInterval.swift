import Foundation

public struct ActivityInterval: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let state: ActivityState

    public init(start: Date, end: Date, state: ActivityState) {
        self.start = start
        self.end = end
        self.state = state
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}
