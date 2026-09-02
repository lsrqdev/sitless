import XCTest
@testable import SitlessKit

/// Covers the pure off-wrist derivation (R41-R43) that `HealthKitManager.offWristSpans(in:)`
/// runs over its heart-rate query results. The HealthKit query itself is not exercised — the
/// simulator's HealthKit store never holds Apple-Watch-synced samples (see README).
final class HealthKitManagerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)

    private func sample(atMinute minute: Double, lastingMinutes duration: Double = 0) -> DateInterval {
        let sampleStart = start.addingTimeInterval(minute * 60)
        return DateInterval(start: sampleStart, end: sampleStart.addingTimeInterval(duration * 60))
    }

    // MARK: - R42: only spans between two samples count

    func testNoSamplesYieldsNoOffWristSpans() {
        XCTAssertTrue(HealthKitManager.offWristSpans(betweenHeartRateSamples: []).isEmpty)
    }

    func testASingleSampleYieldsNoOffWristSpans() {
        // The iPhone-only and sparse-data cases: nothing before the first sample or after the
        // last one is ever claimed as off-wrist, so one sample can never produce a span.
        XCTAssertTrue(HealthKitManager.offWristSpans(betweenHeartRateSamples: [sample(atMinute: 120)]).isEmpty)
    }

    // MARK: - R41: the gap threshold

    func testSamplesSpacedUnderTheThresholdYieldNoSpans() {
        let spacing = HealthKitManager.offWristHeartRateGap / 60 - 1
        let samples = [sample(atMinute: 0), sample(atMinute: spacing), sample(atMinute: spacing * 2)]
        XCTAssertTrue(HealthKitManager.offWristSpans(betweenHeartRateSamples: samples).isEmpty)
    }

    func testSamplesSpacedExactlyAtTheThresholdYieldNoSpans() {
        let samples = [sample(atMinute: 0), sample(atMinute: HealthKitManager.offWristHeartRateGap / 60)]
        XCTAssertTrue(HealthKitManager.offWristSpans(betweenHeartRateSamples: samples).isEmpty)
    }

    func testASingleGapJustOverTheThresholdYieldsExactlyOneSpan() {
        let justOver = HealthKitManager.offWristHeartRateGap / 60 + 1
        let samples = [sample(atMinute: 0), sample(atMinute: justOver), sample(atMinute: justOver + 5)]
        let spans = HealthKitManager.offWristSpans(betweenHeartRateSamples: samples)
        XCTAssertEqual(spans, [DateInterval(start: sample(atMinute: 0).end, end: sample(atMinute: justOver).start)])
    }

    func testAChargingBreakBetweenTwoSamplesIsReportedInFull() {
        let samples = [sample(atMinute: 0), sample(atMinute: 60), sample(atMinute: 65)]
        let spans = HealthKitManager.offWristSpans(betweenHeartRateSamples: samples)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans.first?.duration ?? 0, 3600, accuracy: 1)
    }

    // MARK: - R43: the minimum span

    func testASpanShorterThanTheMinimumIsDiscarded() {
        // Start-to-start spacing clears the gap threshold, but the earlier sample covers almost
        // all of it, so the genuinely unmeasured stretch is a sliver and is dropped.
        let spacing = HealthKitManager.offWristHeartRateGap / 60 + 10
        let minimumMinutes = HealthKitManager.minimumOffWristSpan / 60
        let samples = [
            sample(atMinute: 0, lastingMinutes: spacing - minimumMinutes + 1),
            sample(atMinute: spacing)
        ]
        XCTAssertTrue(HealthKitManager.offWristSpans(betweenHeartRateSamples: samples).isEmpty)
    }

    func testSamplesAreSortedBeforeDerivingSpans() {
        let samples = [sample(atMinute: 60), sample(atMinute: 0)]
        let spans = HealthKitManager.offWristSpans(betweenHeartRateSamples: samples)
        XCTAssertEqual(spans, [DateInterval(start: sample(atMinute: 0).end, end: sample(atMinute: 60).start)])
    }
}
