import Foundation
import HealthKit

public enum HealthKitManagerError: Error {
    case unavailable
}

/// The sole `HKHealthStore`-backed implementation of `HealthDataProviding` (R6).
/// All queries are bounded to the caller's `DateInterval` (R9) — never an unbounded full-database query.
public final class HealthKitManager: HealthDataProviding, @unchecked Sendable {
    private let healthStore = HKHealthStore()

    // Apple system-defined identifiers — always resolvable on supported OS versions.
    private static let standTimeType = HKObjectType.quantityType(forIdentifier: .appleStandTime)!
    private static let standHourType = HKObjectType.categoryType(forIdentifier: .appleStandHour)!
    private static let exerciseTimeType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!
    private static let moveTimeType = HKObjectType.quantityType(forIdentifier: .appleMoveTime)!
    private static let stepCountType = HKObjectType.quantityType(forIdentifier: .stepCount)!
    private static let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    private static let workoutType = HKObjectType.workoutType()
    /// A workout sample is treated as "active" for this long after its recorded end, since
    /// HealthKit only commits the sample once the session finishes (see README).
    private static let workoutGracePeriod: TimeInterval = 5 * 60

    public init() {}

    public var authorizationState: HealthAuthorizationState {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        switch healthStore.authorizationStatus(for: Self.standTimeType) {
        case .notDetermined:
            return .notDetermined
        case .sharingDenied:
            return .denied
        case .sharingAuthorized:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitManagerError.unavailable
        }
        let readTypes: Set<HKObjectType> = [
            Self.standTimeType, Self.standHourType,
            Self.exerciseTimeType, Self.moveTimeType, Self.stepCountType, Self.sleepType,
            Self.workoutType
        ]
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    public func standingIntervals(in range: DateInterval) async throws -> [ActivityInterval] {
        let samples = try await quantitySamples(for: Self.standTimeType, in: range)
        return samples.map { ActivityInterval(start: $0.startDate, end: $0.endDate, state: .standing) }
    }

    public func standHours(in range: DateInterval) async throws -> Int {
        let samples = try await categorySamples(for: Self.standHourType, in: range)
        return samples.filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }.count
    }

    public func activityIntervals(in range: DateInterval) async throws -> [ActivityInterval] {
        async let exercise = quantitySamples(for: Self.exerciseTimeType, in: range)
        async let move = quantitySamples(for: Self.moveTimeType, in: range)
        let exerciseIntervals = try await exercise.map { ActivityInterval(start: $0.startDate, end: $0.endDate, state: .active) }
        let moveIntervals = try await move.map { ActivityInterval(start: $0.startDate, end: $0.endDate, state: .active) }
        return exerciseIntervals + moveIntervals
    }

    public func sleepIntervals(in range: DateInterval) async throws -> [ActivityInterval] {
        let samples = try await categorySamples(for: Self.sleepType, in: range)
        return samples.compactMap { sample in
            guard Self.isAsleepValue(sample.value) else { return nil }
            return ActivityInterval(start: sample.startDate, end: sample.endDate, state: .sleep)
        }
    }

    public func steps(in range: DateInterval) async throws -> Int {
        let samples = try await quantitySamples(for: Self.stepCountType, in: range)
        let total = samples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .count()) }
        return Int(total.rounded())
    }

    public func rawDiagnostics(in range: DateInterval) async throws -> HealthDiagnosticsSnapshot {
        async let standSamples = quantitySamples(for: Self.standTimeType, in: range)
        async let exerciseSamples = quantitySamples(for: Self.exerciseTimeType, in: range)
        async let moveSamples = quantitySamples(for: Self.moveTimeType, in: range)
        async let sleepSamples = categorySamples(for: Self.sleepType, in: range)
        async let stepSamples = quantitySamples(for: Self.stepCountType, in: range)

        let standEntries = try await standSamples.map { Self.entry($0, unit: .minute()) }
        let exerciseEntries = try await exerciseSamples.map { Self.entry($0, unit: .minute()) }
        let moveEntries = try await moveSamples.map { Self.entry($0, unit: .kilocalorie()) }
        let sleepEntries = try await sleepSamples.map { sample in
            HealthDiagnosticsSnapshot.SampleEntry(
                start: sample.startDate,
                end: sample.endDate,
                value: Double(sample.value),
                sourceName: sample.sourceRevision.source.name
            )
        }
        let totalSteps = try await stepSamples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .count()) }

        return HealthDiagnosticsSnapshot(
            queryRange: range,
            standTimeSamples: standEntries,
            exerciseTimeSamples: exerciseEntries,
            moveTimeSamples: moveEntries,
            sleepSamples: sleepEntries,
            steps: Int(totalSteps.rounded())
        )
    }

    public func observeChanges(_ handler: @escaping @Sendable () -> Void) {
        let query = HKObserverQuery(sampleType: Self.standTimeType, predicate: nil) { _, completionHandler, _ in
            handler()
            completionHandler()
        }
        healthStore.execute(query)
        healthStore.enableBackgroundDelivery(for: Self.standTimeType, frequency: .immediate) { _, _ in }
    }

    public func isInActiveWorkout(asOf now: Date) async throws -> Bool {
        let lookback = DateInterval(start: now.addingTimeInterval(-4 * 3600), end: now)
        let workouts = try await workoutSamples(in: lookback)
        return workouts.contains { now >= $0.startDate && now <= $0.endDate.addingTimeInterval(Self.workoutGracePeriod) }
    }

    private func workoutSamples(in range: DateInterval) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: Self.workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    private static func entry(_ sample: HKQuantitySample, unit: HKUnit) -> HealthDiagnosticsSnapshot.SampleEntry {
        HealthDiagnosticsSnapshot.SampleEntry(
            start: sample.startDate,
            end: sample.endDate,
            value: sample.quantity.doubleValue(for: unit),
            sourceName: sample.sourceRevision.source.name
        )
    }

    /// `stationary`/motion states are never consulted here — sleep is classified purely from
    /// HealthKit's own sleep-analysis categories (R13), never inferred from Core Motion.
    private static func isAsleepValue(_ value: Int) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
            return true
        case .inBed, .awake, .none:
            return false
        @unknown default:
            return false
        }
    }

    private func quantitySamples(for type: HKQuantityType, in range: DateInterval) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func categorySamples(for type: HKCategoryType, in range: DateInterval) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }
}
