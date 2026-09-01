import Foundation

/// Protocol-conforming mock for permission-denied / no-data paths (R39).
///
/// Lives in the main `StandLessKit` library (not a test-only target) so that both
/// `StandLessKitTests` (Swift Package tests) and the app's own `StandLessTests`
/// (which needs `@testable import StandLess` for `TodayViewModel`) can use the same
/// mock without a `HealthKit`-dependent test double duplicated in two places.
public final class MockHealthDataProvider: HealthDataProviding, @unchecked Sendable {
    public var authorizationState: HealthAuthorizationState
    public var standingIntervalsResult: Result<[ActivityInterval], Error>
    public var standHoursResult: Result<Int, Error>
    public var activityIntervalsResult: Result<[ActivityInterval], Error>
    public var sleepIntervalsResult: Result<[ActivityInterval], Error>
    public var stepsResult: Result<Int, Error>
    public var rawDiagnosticsResult: Result<HealthDiagnosticsSnapshot, Error>
    public var isInActiveWorkoutResult: Result<Bool, Error>
    public private(set) var requestAuthorizationCallCount = 0
    /// The handler most recently passed to `observeChanges(_:)`, if any. Tests use
    /// `simulateChange()` to invoke it rather than reaching into this directly.
    public private(set) var observeChangesHandler: (@Sendable () -> Void)?

    public init(
        authorizationState: HealthAuthorizationState = .notDetermined,
        standingIntervalsResult: Result<[ActivityInterval], Error> = .success([]),
        standHoursResult: Result<Int, Error> = .success(0),
        activityIntervalsResult: Result<[ActivityInterval], Error> = .success([]),
        sleepIntervalsResult: Result<[ActivityInterval], Error> = .success([]),
        stepsResult: Result<Int, Error> = .success(0),
        rawDiagnosticsResult: Result<HealthDiagnosticsSnapshot, Error>? = nil,
        isInActiveWorkoutResult: Result<Bool, Error> = .success(false)
    ) {
        self.authorizationState = authorizationState
        self.standingIntervalsResult = standingIntervalsResult
        self.standHoursResult = standHoursResult
        self.activityIntervalsResult = activityIntervalsResult
        self.sleepIntervalsResult = sleepIntervalsResult
        self.stepsResult = stepsResult
        self.rawDiagnosticsResult = rawDiagnosticsResult ?? .success(
            HealthDiagnosticsSnapshot(
                queryRange: DateInterval(start: .distantPast, end: .distantPast),
                standTimeSamples: []
            )
        )
        self.isInActiveWorkoutResult = isInActiveWorkoutResult
    }

    public func requestAuthorization() async throws {
        requestAuthorizationCallCount += 1
        authorizationState = .authorized
    }

    public func standingIntervals(in range: DateInterval) async throws -> [ActivityInterval] {
        try standingIntervalsResult.get()
    }

    public func standHours(in range: DateInterval) async throws -> Int {
        try standHoursResult.get()
    }

    public func activityIntervals(in range: DateInterval) async throws -> [ActivityInterval] {
        try activityIntervalsResult.get()
    }

    public func sleepIntervals(in range: DateInterval) async throws -> [ActivityInterval] {
        try sleepIntervalsResult.get()
    }

    public func steps(in range: DateInterval) async throws -> Int {
        try stepsResult.get()
    }

    public func rawDiagnostics(in range: DateInterval) async throws -> HealthDiagnosticsSnapshot {
        try rawDiagnosticsResult.get()
    }

    public func observeChanges(_ handler: @escaping @Sendable () -> Void) {
        observeChangesHandler = handler
    }

    public func isInActiveWorkout(asOf now: Date) async throws -> Bool {
        try isInActiveWorkoutResult.get()
    }

    /// Test helper: simulates HealthKit reporting new standing data, invoking the handler passed
    /// to `observeChanges(_:)` if one was registered.
    public func simulateChange() {
        observeChangesHandler?()
    }
}
