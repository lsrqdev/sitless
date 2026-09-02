import Foundation
import HealthKit

public enum HealthKitManagerError: Error {
    case unavailable
}

/// The sole `HKHealthStore`-backed implementation of `HealthDataProviding` (R6).
/// All queries are bounded to the caller's `DateInterval` (R9) — never an unbounded full-database query.
public final class HealthKitManager: HealthDataProviding, @unchecked Sendable {
    private let healthStore = HKHealthStore()
    private let defaults: UserDefaults

    // Apple system-defined identifiers — always resolvable on supported OS versions.
    private static let standTimeType = HKObjectType.quantityType(forIdentifier: .appleStandTime)!
    private static let standHourType = HKObjectType.categoryType(forIdentifier: .appleStandHour)!
    private static let exerciseTimeType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!
    private static let moveTimeType = HKObjectType.quantityType(forIdentifier: .appleMoveTime)!
    private static let stepCountType = HKObjectType.quantityType(forIdentifier: .stepCount)!
    private static let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    private static let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
    private static let workoutType = HKObjectType.workoutType()
    /// A workout sample is treated as "active" for this long after its recorded end, since
    /// HealthKit only commits the sample once the session finishes (see README).
    private static let workoutGracePeriod: TimeInterval = 5 * 60

    /// Retrospective off-wrist threshold (R41): heart-rate silence longer than this between two
    /// consecutive samples is treated as the watch having been off the wrist. Deliberately
    /// conservative — a worn Apple Watch records heart rate every few minutes in the background,
    /// but widens that cadence in Low Power Mode and through long stretches of stillness. Erring
    /// long only leaves some genuinely off-wrist time counted as estimated sitting time, exactly
    /// as it is today; erring short would relabel worn-but-still time as unmeasured and silently
    /// erode the sedentary estimate the app exists to produce, which is the worse failure. The
    /// live check that suppresses the inactivity reminder uses its own, even more conservative
    /// threshold, because Watch-to-iPhone sync latency makes recent data look absent.
    public static let offWristHeartRateGap: TimeInterval = 20 * 60

    /// Detected spans shorter than this are discarded (R43), so ordinary sampling jitter never
    /// produces a stream of tiny unmeasured slivers on the timeline.
    public static let minimumOffWristSpan: TimeInterval = 10 * 60

    /// Bumped whenever a type joins `requestAuthorization`'s read set (R44). An install that last
    /// requested an earlier version has never been asked about the newly added types, so it is
    /// reported as `.notDetermined` until it has been re-prompted.
    private static let readSetVersion = 2
    private static let requestedReadSetVersionKey = "sitless.healthkit.requestedReadSetVersion"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var authorizationState: HealthAuthorizationState {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        // R44: an install authorized before heart rate joined the read set has never been asked
        // about it, and `authorizationStatus(for:)` cannot say so — it reports sharing permission,
        // not read permission. Reporting `.notDetermined` here is what makes the existing
        // `TodayViewModel.start()` / `WatchHomeViewModel.start()` gate re-run `requestAuthorization()`
        // on the next launch. Re-requesting is harmless for types the user already answered:
        // HealthKit only prompts for the ones still undecided. Without this the feature would
        // silently never activate for anyone upgrading.
        guard defaults.integer(forKey: Self.requestedReadSetVersionKey) >= Self.readSetVersion else {
            return .notDetermined
        }
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
            Self.workoutType, Self.heartRateType
        ]
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
        defaults.set(Self.readSetVersion, forKey: Self.requestedReadSetVersionKey)
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

    public func offWristSpans(in range: DateInterval) async throws -> [DateInterval] {
        // R45: heart rate being unavailable, unauthorized, or simply failing must leave every
        // downstream behaviour identical to a build without this feature, so the failure is
        // swallowed into an empty result rather than propagated to the view models.
        guard let samples = try? await quantitySamples(for: Self.heartRateType, in: range) else {
            return []
        }
        let extents = samples.map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
        return Self.offWristSpans(betweenHeartRateSamples: extents)
    }

    /// The off-wrist spans implied by a set of heart-rate sample extents (R41-R43), split out from
    /// the HealthKit query so both threshold boundaries are directly unit-testable.
    ///
    /// Only the stretches *between* two samples are considered (R42), so fewer than two samples
    /// yields nothing. A consecutive pair qualifies when its start-to-start spacing exceeds
    /// `offWristHeartRateGap`; the span itself runs from the end of everything measured so far to
    /// the start of the later sample, and is kept only when it lasts at least
    /// `minimumOffWristSpan`.
    static func offWristSpans(betweenHeartRateSamples samples: [DateInterval]) -> [DateInterval] {
        let sorted = samples.sorted { $0.start < $1.start }
        guard sorted.count >= 2 else { return [] }

        var spans: [DateInterval] = []
        var coveredUntil = sorted[0].end
        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let next = sorted[index]
            defer { coveredUntil = max(coveredUntil, next.end) }
            guard next.start.timeIntervalSince(previous.start) > offWristHeartRateGap else { continue }
            guard next.start.timeIntervalSince(coveredUntil) >= minimumOffWristSpan else { continue }
            spans.append(DateInterval(start: coveredUntil, end: next.start))
        }
        return spans
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
