import XCTest
@testable import SitlessKit

final class ActivityCalculatorTests: XCTestCase {
    private let calculator = ActivityCalculator()
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 1, timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = timeZone
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - Standing duration

    func testStandingDurationSumsNonOverlappingIntervals() {
        let window = DateInterval(start: date(6), end: date(22))
        let standing = [
            ActivityInterval(start: date(7), end: date(8), state: .standing),
            ActivityInterval(start: date(10), end: date(10, 30), state: .standing)
        ]
        let summary = calculator.summarize(standing: standing, activity: [], sleep: [], offWrist: [], steps: nil, standHours: nil, observationWindow: window, calendar: calendar)
        XCTAssertEqual(summary.standingDuration, 5400, accuracy: 1)
    }

    // MARK: - Overlapping / adjacent merging

    func testOverlappingStandingIntervalsAreNotDoubleCounted() {
        let window = DateInterval(start: date(6), end: date(22))
        let standing = [
            ActivityInterval(start: date(7), end: date(8), state: .standing),
            ActivityInterval(start: date(7, 30), end: date(8, 30), state: .standing)
        ]
        let summary = calculator.summarize(standing: standing, activity: [], sleep: [], offWrist: [], steps: nil, standHours: nil, observationWindow: window, calendar: calendar)
        XCTAssertEqual(summary.standingDuration, 5400, accuracy: 1) // 7:00-8:30, not 7200+3600
    }

    func testAdjacentStandingIntervalsMergeIntoOne() {
        let window = DateInterval(start: date(6), end: date(22))
        let standing = [
            ActivityInterval(start: date(7), end: date(8), state: .standing),
            ActivityInterval(start: date(8), end: date(9), state: .standing)
        ]
        let summary = calculator.summarize(standing: standing, activity: [], sleep: [], offWrist: [], steps: nil, standHours: nil, observationWindow: window, calendar: calendar)
        XCTAssertEqual(summary.standingDuration, 7200, accuracy: 1)
    }

    // MARK: - Active + standing overlap

    func testActiveOverlappingStandingIsNotDoubleCounted() {
        let window = DateInterval(start: date(6), end: date(22))
        let standing = [ActivityInterval(start: date(7), end: date(8), state: .standing)]
        let activity = [ActivityInterval(start: date(7, 30), end: date(8, 30), state: .active)]
        let summary = calculator.summarize(standing: standing, activity: activity, sleep: [], offWrist: [], steps: nil, standHours: nil, observationWindow: window, calendar: calendar)
        XCTAssertEqual(summary.standingDuration, 3600, accuracy: 1) // standing wins 7:00-8:00
        XCTAssertEqual(summary.activeDuration ?? 0, 1800, accuracy: 1) // active keeps only 8:00-8:30
    }

    // MARK: - Sleep exclusion

    func testSleepIsNeverClassifiedAsSedentary() {
        let window = DateInterval(start: date(0), end: date(8))
        let sleep = [ActivityInterval(start: date(0), end: date(6), state: .sleep)]
        let summary = calculator.summarize(standing: [], activity: [], sleep: sleep, offWrist: [], steps: nil, standHours: nil, observationWindow: window, calendar: calendar)
        XCTAssertEqual(summary.estimatedSedentaryDuration ?? -1, 0, accuracy: 1)
        XCTAssertTrue(summary.timeline.allSatisfy { $0.state != .sedentary || $0.start >= date(6) })
    }

    func testSleepOverlappingStandingWinsThePriorityContest() {
        // A standing sample reported during a known-sleep window (e.g. device artifact) must not
        // leak standing time into what HealthKit's own sleep analysis says is sleep.
        let window = DateInterval(start: date(0), end: date(8))
        let sleep = [ActivityInterval(start: date(0), end: date(6), state: .sleep)]
        let standing = [ActivityInterval(start: date(2), end: date(2, 30), state: .standing)]
        let summary = calculator.summarize(standing: standing, activity: [], sleep: sleep, offWrist: [], steps: nil, standHours: nil, observationWindow: window, calendar: calendar)
        XCTAssertEqual(summary.standingDuration, 0, accuracy: 1)
    }

    // MARK: - Sedentary estimate

    func testGapBetweenTwoKnownSamplesIsEstimatedSedentary() {
        let window = DateInterval(start: date(6), end: date(12))
        let standing = [
            ActivityInterval(start: date(6), end: date(7), state: .standing),
            ActivityInterval(start: date(8), end: date(9), state: .standing)
        ]
        let summary = calculator.summarize(standing: standing, activity: [], sleep: [], offWrist: [], steps: nil, standHours: nil, observationWindow: window, calendar: calendar)
        // 7:00-8:00 gap (1h) is a short gap between two known samples -> sedentary.
        XCTAssertEqual(summary.estimatedSedentaryDuration ?? 0, 3600, accuracy: 1)
    }

    // MARK: - Unknown periods

    func testGapBeforeFirstAndAfterLastSampleIsUnknownNotSedentary() {
        let window = DateInterval(start: date(6), end: date(22))
        let standing = [ActivityInterval(start: date(10), end: date(11), state: .standing)]
        let summary = calculator.summarize(standing: standing, activity: [], sleep: [], offWrist: [], steps: nil, standHours: nil, observationWindow: window, calendar: calendar)
        // Everything outside 10:00-11:00 is edge-of-coverage -> unknown, never guessed as sedentary.
        XCTAssertEqual(summary.unknownDuration, window.duration - 3600, accuracy: 1)
        XCTAssertEqual(summary.estimatedSedentaryDuration ?? -1, 0, accuracy: 1)
    }

    func testLongSilentGapBetweenSamplesIsUnknownNotSedentary() {
        let window = DateInterval(start: date(0), end: date(23, 59))
        let standing = [
            ActivityInterval(start: date(6), end: date(6, 30), state: .standing),
            ActivityInterval(start: date(20), end: date(20, 30), state: .standing)
        ]
        let summary = calculator.summarize(standing: standing, activity: [], sleep: [], offWrist: [], steps: nil, standHours: nil, observationWindow: window, calendar: calendar)
        // The 6:30-20:00 gap exceeds maxInferredSedentaryGap -> unknown, not a 13.5-hour sedentary claim.
        XCTAssertGreaterThan(summary.unknownDuration, ActivityCalculator.maxInferredSedentaryGap)
        XCTAssertEqual(summary.estimatedSedentaryDuration ?? -1, 0, accuracy: 1)
    }

    // MARK: - Midnight / day boundary

    func testDailyTotalsCrossingMidnightAttributesToCorrectDay() {
        let day1 = date(0, day: 1)
        let day2 = date(0, day: 2)
        let intervals = [
            ActivityInterval(start: date(23, day: 1), end: date(23, 30, day: 1), state: .standing),
            ActivityInterval(start: date(0, 30, day: 2), end: date(1, day: 2), state: .standing)
        ]
        let series = ActivityCalculator.dailyTotals(of: intervals, from: day1, to: day2, calendar: calendar)
        XCTAssertEqual(series.first { calendar.isDate($0.date, inSameDayAs: day1) }?.duration ?? 0, 1800, accuracy: 1)
        XCTAssertEqual(series.first { calendar.isDate($0.date, inSameDayAs: day2) }?.duration ?? 0, 1800, accuracy: 1)
    }

    // MARK: - DST transitions

    func testDurationAcrossSpringForwardDSTTransitionIsCorrect() {
        // US spring-forward in 2026 is March 8th; clocks jump 02:00 -> 03:00 local.
        let newYork = TimeZone(identifier: "America/New_York")!
        var start = DateComponents()
        start.year = 2026; start.month = 3; start.day = 8; start.hour = 1; start.minute = 30; start.timeZone = newYork
        var end = DateComponents()
        end.year = 2026; end.month = 3; end.day = 8; end.hour = 3; end.minute = 30; end.timeZone = newYork
        let calendarNY = Calendar(identifier: .gregorian)
        let interval = ActivityInterval(
            start: calendarNY.date(from: start)!,
            end: calendarNY.date(from: end)!,
            state: .standing
        )
        // Wall-clock reads as 2 hours, but only 1 hour of absolute time actually elapsed.
        let window = DateInterval(start: interval.start, end: interval.end)
        let summary = calculator.summarize(standing: [interval], activity: [], sleep: [], offWrist: [], steps: nil, standHours: nil, observationWindow: window, calendar: calendarNY)
        XCTAssertEqual(summary.standingDuration, 3600, accuracy: 1)
    }

    // MARK: - Timezone changes

    func testDailyTotalsRespectTheSuppliedCalendarsTimeZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        var tokyoCalendar = Calendar(identifier: .gregorian)
        tokyoCalendar.timeZone = tokyo
        let day = date(0, day: 1, timeZone: tokyo)
        let interval = ActivityInterval(start: date(10, day: 1, timeZone: tokyo), end: date(11, day: 1, timeZone: tokyo), state: .standing)
        let series = ActivityCalculator.dailyTotals(of: [interval], from: day, to: day, calendar: tokyoCalendar)
        XCTAssertEqual(series.first?.duration ?? 0, 3600, accuracy: 1)
    }

    // MARK: - Historical averages

    func testDailyTotalsProduceAnAveragableSeries() {
        let day1 = date(0, day: 1)
        let day2 = date(0, day: 2)
        let day3 = date(0, day: 3)
        let intervals = [
            ActivityInterval(start: date(8, day: 1), end: date(9, day: 1), state: .standing),
            ActivityInterval(start: date(8, day: 2), end: date(10, day: 2), state: .standing),
            ActivityInterval(start: date(8, day: 3), end: date(11, day: 3), state: .standing)
        ]
        let series = ActivityCalculator.dailyTotals(of: intervals, from: day1, to: day3, calendar: calendar)
        let average = series.reduce(0) { $0 + $1.duration } / Double(series.count)
        XCTAssertEqual(average, 2 * 3600, accuracy: 1) // (1h + 2h + 3h) / 3
    }

    // MARK: - Same-time-of-day comparisons

    func testSameTimeOfDayComparisonPrefersYesterdayOverAverage() {
        let startOfYesterday = date(0, day: 1)
        let yesterdaySameTime = date(9, day: 1)
        let intervals = [
            ActivityInterval(start: date(7, day: 1), end: date(8, day: 1), state: .standing), // yesterday, before "same time"
            ActivityInterval(start: date(7, day: 2), end: date(9, day: 2), state: .standing)  // today, 2h so far
        ]
        let comparison = ActivityCalculator.sameTimeOfDayComparison(
            todayStandingDuration: 7200,
            intervals: intervals,
            priorDaySeries: [ActivityCalculator.DailyStanding(date: startOfYesterday, duration: 3600)],
            startOfYesterday: startOfYesterday,
            yesterdaySameTime: yesterdaySameTime,
            calendar: calendar
        )
        guard case .vsYesterday(let delta) = comparison else {
            XCTFail("Expected vsYesterday, got \(String(describing: comparison))")
            return
        }
        XCTAssertEqual(delta, 3600, accuracy: 1) // today's 2h vs yesterday's 1h-by-this-time
    }

    func testSameTimeOfDayComparisonFallsBackToAverageWhenYesterdayHasNoData() {
        let startOfYesterday = date(0, day: 2)
        let yesterdaySameTime = date(9, day: 2)
        let intervals = [ActivityInterval(start: date(7, day: 3), end: date(9, day: 3), state: .standing)]
        let comparison = ActivityCalculator.sameTimeOfDayComparison(
            todayStandingDuration: 7200,
            intervals: intervals,
            priorDaySeries: [ActivityCalculator.DailyStanding(date: date(0, day: 1), duration: 3600)],
            startOfYesterday: startOfYesterday,
            yesterdaySameTime: yesterdaySameTime,
            calendar: calendar
        )
        guard case .vsSevenDayAverage(let deltaPercent) = comparison else {
            XCTFail("Expected vsSevenDayAverage, got \(String(describing: comparison))")
            return
        }
        XCTAssertEqual(deltaPercent, 100) // 2h vs a 1h average is +100%
    }

    // MARK: - Longest inactive interval

    func testLongestInactiveIntervalPicksTheLargestSedentaryGap() {
        let window = DateInterval(start: date(6), end: date(20))
        let standing = [
            ActivityInterval(start: date(6), end: date(6, 30), state: .standing),
            ActivityInterval(start: date(8), end: date(8, 10), state: .standing), // 1.5h gap before
            ActivityInterval(start: date(10), end: date(10, 10), state: .standing) // ~1h50m gap before
        ]
        let summary = calculator.summarize(standing: standing, activity: [], sleep: [], offWrist: [], steps: nil, standHours: nil, observationWindow: window, calendar: calendar)
        XCTAssertEqual(summary.longestInactiveDuration ?? 0, 6600, accuracy: 1) // 8:10-10:00 is the largest of the two sedentary gaps
    }

    // MARK: - Standing percentage

    func testStandingPercentageIsWholeNumberAndMatchesFormula() {
        // Window matches the sample coverage bounds exactly (6:00-9:00), so there is no
        // edge-of-coverage unknown time and confidence clears the .low bar.
        let window = DateInterval(start: date(6), end: date(9))
        let standing = [
            ActivityInterval(start: date(6), end: date(7), state: .standing),
            ActivityInterval(start: date(8), end: date(9), state: .standing)
        ]
        let summary = calculator.summarize(standing: standing, activity: [], sleep: [], offWrist: [], steps: nil, standHours: nil, observationWindow: window, calendar: calendar)
        XCTAssertNotEqual(summary.confidence, .low)
        let expected = Int((summary.standingDuration / (summary.standingDuration + (summary.estimatedSedentaryDuration ?? 0)) * 100).rounded())
        XCTAssertEqual(summary.standingPercentage, expected)
    }

    func testStandingPercentageIsNilWhenConfidenceIsLow() {
        let window = DateInterval(start: date(0), end: date(23, 59))
        let standing = [ActivityInterval(start: date(10), end: date(10, 5), state: .standing)]
        let summary = calculator.summarize(standing: standing, activity: [], sleep: [], offWrist: [], steps: nil, standHours: nil, observationWindow: window, calendar: calendar)
        XCTAssertEqual(summary.confidence, .low)
        XCTAssertNil(summary.standingPercentage)
    }

    // MARK: - Data confidence

    func testHighConfidenceRequiresStandingActivitySleepAndLowUnknownRatio() {
        let window = DateInterval(start: date(6), end: date(10)) // 4h window
        let standing = [ActivityInterval(start: date(6), end: date(7), state: .standing)]
        let activity = [ActivityInterval(start: date(7), end: date(8), state: .active)]
        let sleep = [ActivityInterval(start: date(8), end: date(10), state: .sleep)]
        let summary = calculator.summarize(standing: standing, activity: activity, sleep: sleep, offWrist: [], steps: nil, standHours: nil, observationWindow: window, calendar: calendar)
        XCTAssertEqual(summary.confidence, .high)
    }

    // MARK: - Off-wrist spans (R47-R50)

    /// A 4-hour window with standing at 08:00-08:30 and 11:00-11:30, and the watch on the
    /// charger from 09:00-10:00. Shared by the classification and arithmetic tests below.
    private var chargingDayWindow: DateInterval { DateInterval(start: date(8), end: date(12)) }
    private var chargingDayStanding: [ActivityInterval] {
        [
            ActivityInterval(start: date(8), end: date(8, 30), state: .standing),
            ActivityInterval(start: date(11), end: date(11, 30), state: .standing)
        ]
    }
    private var chargingHour: DateInterval { DateInterval(start: date(9), end: date(10)) }

    private func chargingDaySummary(offWrist: [DateInterval]) -> DailyActivitySummary {
        calculator.summarize(
            standing: chargingDayStanding,
            activity: [],
            sleep: [],
            offWrist: offWrist,
            steps: nil,
            standHours: nil,
            observationWindow: chargingDayWindow,
            calendar: calendar
        )
    }

    func testMidMorningChargingHourIsUnknownRatherThanEstimatedSitting() {
        let summary = chargingDaySummary(offWrist: [chargingHour])

        // 08:30-09:00 and 10:00-11:00 remain sedentary; the charging hour and the 11:30-12:00
        // edge gap are unknown.
        XCTAssertEqual(summary.estimatedSedentaryDuration ?? 0, 5400, accuracy: 1)
        XCTAssertEqual(summary.unknownDuration, 5400, accuracy: 1)
        XCTAssertTrue(summary.timeline.contains(ActivityInterval(start: date(9), end: date(10), state: .unknown)))
    }

    func testChargingHourRaisesStandingPercentageVersusNoOffWristBaseline() {
        let baseline = chargingDaySummary(offWrist: [])
        let withOffWrist = chargingDaySummary(offWrist: [chargingHour])

        guard let baselinePercentage = baseline.standingPercentage,
              let offWristPercentage = withOffWrist.standingPercentage else {
            XCTFail("Expected both summaries to produce a standing percentage")
            return
        }
        XCTAssertGreaterThan(offWristPercentage, baselinePercentage)
    }

    func testEmptyOffWristInputReproducesTheUnchangedClassification() {
        let summary = chargingDaySummary(offWrist: [])

        XCTAssertEqual(summary.standingDuration, 3600, accuracy: 1)
        XCTAssertEqual(summary.estimatedSedentaryDuration ?? 0, 9000, accuracy: 1) // the whole 08:30-11:00 gap
        XCTAssertEqual(summary.unknownDuration, 1800, accuracy: 1) // only the 11:30-12:00 edge gap
        XCTAssertEqual(summary.standingPercentage, 29) // 3600 / 12600
    }

    func testPartiallyOverlappingOffWristSpanSplitsTheGap() {
        // 10:30-11:30 overlaps the 08:30-11:00 sedentary gap only from 10:30.
        let summary = chargingDaySummary(offWrist: [DateInterval(start: date(10, 30), end: date(11, 30))])

        XCTAssertTrue(summary.timeline.contains(ActivityInterval(start: date(8, 30), end: date(10, 30), state: .sedentary)))
        XCTAssertTrue(summary.timeline.contains(ActivityInterval(start: date(10, 30), end: date(11), state: .unknown)))
        XCTAssertEqual(summary.estimatedSedentaryDuration ?? 0, 7200, accuracy: 1)
    }

    func testMeasuredIntervalsSurviveAnOverlappingOffWristSpan() {
        // The span swallows the 11:00-11:30 standing sample whole; measured data always wins (R49).
        let summary = chargingDaySummary(offWrist: [DateInterval(start: date(10, 30), end: date(11, 30))])

        XCTAssertTrue(summary.timeline.contains(ActivityInterval(start: date(11), end: date(11, 30), state: .standing)))
        XCTAssertEqual(summary.standingDuration, 3600, accuracy: 1)
    }

    func testOffWristSpanInsideASleepIntervalLeavesItClassifiedAsSleep() {
        let window = DateInterval(start: date(0), end: date(8))
        let sleep = [ActivityInterval(start: date(0), end: date(6), state: .sleep)]
        let standing = [ActivityInterval(start: date(6), end: date(6, 30), state: .standing)]
        let summary = calculator.summarize(
            standing: standing,
            activity: [],
            sleep: sleep,
            offWrist: [DateInterval(start: date(1), end: date(2))],
            steps: nil,
            standHours: nil,
            observationWindow: window,
            calendar: calendar
        )

        XCTAssertTrue(summary.timeline.contains(ActivityInterval(start: date(0), end: date(6), state: .sleep)))
        XCTAssertFalse(summary.timeline.contains { $0.state == .unknown && $0.start < date(6) })
    }

    func testEnoughOffWristTimeDropsConfidenceThroughTheExistingUnknownRatioRule() {
        let window = DateInterval(start: date(6), end: date(12)) // 6h
        let standing = [
            ActivityInterval(start: date(6), end: date(7), state: .standing),
            ActivityInterval(start: date(11), end: date(12), state: .standing)
        ]
        let activity = [ActivityInterval(start: date(7), end: date(8), state: .active)]
        let sleep = [ActivityInterval(start: date(8), end: date(9), state: .sleep)]

        func summary(offWrist: [DateInterval]) -> DailyActivitySummary {
            calculator.summarize(
                standing: standing, activity: activity, sleep: sleep, offWrist: offWrist,
                steps: nil, standHours: nil, observationWindow: window, calendar: calendar
            )
        }

        XCTAssertEqual(summary(offWrist: []).confidence, .high)
        // 2h of the 6h window unmeasured is a 0.33 unknown ratio, past the 0.25 high-confidence
        // bar — no confidence threshold changed, the ratio simply moved.
        XCTAssertEqual(summary(offWrist: [DateInterval(start: date(9), end: date(11))]).confidence, .medium)
    }

    func testOffWristSpansAreClippedToTheObservationWindow() {
        // A charge running from midnight to 07:00, against a window that only opens at 06:00 —
        // only the in-window portion is ever classified.
        let summary = calculator.summarize(
            standing: [ActivityInterval(start: date(8), end: date(9), state: .standing)],
            activity: [],
            sleep: [],
            offWrist: [DateInterval(start: date(0), end: date(7))],
            steps: nil,
            standHours: nil,
            observationWindow: DateInterval(start: date(6), end: date(9)),
            calendar: calendar
        )

        XCTAssertTrue(summary.timeline.contains(ActivityInterval(start: date(6), end: date(7), state: .unknown)))
        XCTAssertEqual(summary.unknownDuration, 7200, accuracy: 1) // 06:00-07:00 off-wrist + 07:00-08:00 edge gap
    }
}
