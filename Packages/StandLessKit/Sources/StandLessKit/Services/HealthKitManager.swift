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
        let readTypes: Set<HKObjectType> = [Self.standTimeType, Self.standHourType]
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

    public func rawDiagnostics(in range: DateInterval) async throws -> HealthDiagnosticsSnapshot {
        let samples = try await quantitySamples(for: Self.standTimeType, in: range)
        let entries = samples.map { sample in
            HealthDiagnosticsSnapshot.SampleEntry(
                start: sample.startDate,
                end: sample.endDate,
                value: sample.quantity.doubleValue(for: .minute()),
                sourceName: sample.sourceRevision.source.name
            )
        }
        return HealthDiagnosticsSnapshot(queryRange: range, standTimeSamples: entries)
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
