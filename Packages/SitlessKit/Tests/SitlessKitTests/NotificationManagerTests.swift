import XCTest
@testable import SitlessKit

final class NotificationManagerTests: XCTestCase {
    final class MockCenter: NotificationCenterScheduling, @unchecked Sendable {
        private(set) var addedRequests: [UNNotificationRequest] = []
        private(set) var removedIdentifiers: [[String]] = []

        func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
            removedIdentifiers.append(identifiers)
        }

        func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable ((any Error)?) -> Void)?) {
            addedRequests.append(request)
            completionHandler?(nil)
        }
    }

    func testOffIntervalSchedulesNothing() {
        let center = MockCenter()
        let manager = NotificationManager(center: center)

        let fireDate = manager.reschedule(interval: .off)

        XCTAssertNil(fireDate)
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testEachNonOffIntervalSchedulesARequestThatManyMinutesOut() {
        for interval in ReminderInterval.allCases where interval != .off {
            let center = MockCenter()
            let manager = NotificationManager(center: center)
            let now = Date()
            let expectedSeconds = TimeInterval(interval.rawValue * 60)

            let fireDate = manager.reschedule(interval: interval, now: now)

            XCTAssertEqual(center.addedRequests.count, 1, "expected a request for \(interval)")
            XCTAssertEqual(fireDate, now.addingTimeInterval(expectedSeconds))
            let trigger = center.addedRequests.first?.trigger as? UNTimeIntervalNotificationTrigger
            XCTAssertEqual(trigger?.timeInterval, expectedSeconds)
        }
    }

    func testAlwaysCancelsAnyExistingPendingRequestFirst() {
        let center = MockCenter()
        let manager = NotificationManager(center: center)

        manager.reschedule(interval: .fortyFive)

        XCTAssertEqual(center.removedIdentifiers.first, [NotificationManager.requestIdentifier])
    }

    func testSuppressesDuringSleep() {
        let center = MockCenter()
        let manager = NotificationManager(center: center)
        let snapshot = SuppressionSnapshot(isAsleep: true)

        XCTAssertTrue(manager.shouldSuppress(now: Date(), snapshot: snapshot))
        XCTAssertNil(manager.reschedule(interval: .fortyFive, snapshot: snapshot))
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testSuppressesDuringWorkout() {
        let center = MockCenter()
        let manager = NotificationManager(center: center)
        let snapshot = SuppressionSnapshot(isInWorkout: true)

        XCTAssertTrue(manager.shouldSuppress(now: Date(), snapshot: snapshot))
        XCTAssertNil(manager.reschedule(interval: .fortyFive, snapshot: snapshot))
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testSuppressesWhileLikelyDriving() {
        let center = MockCenter()
        let manager = NotificationManager(center: center)
        let snapshot = SuppressionSnapshot(isLikelyDriving: true)

        XCTAssertTrue(manager.shouldSuppress(now: Date(), snapshot: snapshot))
        XCTAssertNil(manager.reschedule(interval: .fortyFive, snapshot: snapshot))
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testSuppressesWithinRepeatWindowAfterAFiredReminder() {
        let now = Date()
        let center = MockCenter()
        let manager = NotificationManager(center: center, lastFiredAt: now.addingTimeInterval(-10 * 60))

        XCTAssertTrue(manager.shouldSuppress(now: now, snapshot: SuppressionSnapshot()))
        XCTAssertNil(manager.reschedule(interval: .fortyFive, now: now))
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testDoesNotSuppressOnceRepeatWindowHasElapsed() {
        let now = Date()
        let manager = NotificationManager(center: MockCenter(), lastFiredAt: now.addingTimeInterval(-31 * 60))

        XCTAssertFalse(manager.shouldSuppress(now: now, snapshot: SuppressionSnapshot()))
        XCTAssertNotNil(manager.reschedule(interval: .fortyFive, now: now))
    }

    func testRecordFiredUpdatesTheRepeatWindowBaseline() {
        let now = Date()
        let manager = NotificationManager(center: MockCenter())

        manager.recordFired(at: now)

        XCTAssertTrue(manager.shouldSuppress(now: now.addingTimeInterval(5 * 60), snapshot: SuppressionSnapshot()))
        XCTAssertFalse(manager.shouldSuppress(now: now.addingTimeInterval(31 * 60), snapshot: SuppressionSnapshot()))
    }
}
