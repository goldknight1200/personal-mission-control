import Foundation
import XCTest
@testable import MissionControlCore

final class PhaseEightIntegrationTests: XCTestCase {
    func testExternalEventReconciliationUpdatesWithoutDuplicating() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let interval = DateInterval(
            start: now,
            duration: 7 * 86_400
        )
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        let originalLocalCount = snapshot.fixedCommitments.count
        let first = externalEvent(
            uid: "fixture-42",
            title: "Home fixture",
            start: now.addingTimeInterval(86_400)
        )

        let inserted = ExternalScheduleReconciler.reconcile(
            batch: batch(event: first, interval: interval, at: now),
            snapshot: &snapshot
        )
        let commitmentID = try XCTUnwrap(
            inserted.insertedCommitmentIDs.first
        )
        XCTAssertEqual(
            snapshot.fixedCommitments.count,
            originalLocalCount + 1
        )
        XCTAssertTrue(
            try XCTUnwrap(snapshot.fixedCommitments.first(where: {
                $0.id == commitmentID
            })).isExternallyManaged
        )

        var changed = first
        changed.title = "Home fixture — updated"
        changed.start = changed.start.addingTimeInterval(30 * 60)
        changed.end = changed.end.addingTimeInterval(30 * 60)
        changed.lastModifiedAt = now.addingTimeInterval(300)
        let updated = ExternalScheduleReconciler.reconcile(
            batch: batch(
                event: changed,
                interval: interval,
                at: now.addingTimeInterval(300)
            ),
            snapshot: &snapshot
        )

        XCTAssertEqual(updated.updatedCommitmentIDs, [commitmentID])
        XCTAssertEqual(
            snapshot.fixedCommitments.filter(\.isExternallyManaged).count,
            1
        )
        XCTAssertEqual(
            snapshot.fixedCommitments.first(where: {
                $0.id == commitmentID
            })?.title,
            "Home fixture — updated"
        )
    }

    func testSuccessfulEmptyBatchDeletesOnlyCoveredExternalItems() throws {
        let now = Date(timeIntervalSince1970: 2_000_100_000)
        let covered = DateInterval(start: now, duration: 7 * 86_400)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        let inside = externalEvent(
            uid: "inside",
            title: "Inside",
            start: now.addingTimeInterval(86_400)
        )
        let outside = externalEvent(
            uid: "outside",
            title: "Outside",
            start: now.addingTimeInterval(20 * 86_400)
        )
        _ = ExternalScheduleReconciler.reconcile(
            batch: ExternalEventBatch(
                sourceKind: .iCal,
                sourceIdentifier: "fixtures",
                coveredInterval: DateInterval(
                    start: now,
                    duration: 30 * 86_400
                ),
                events: [inside, outside],
                fetchedAt: now
            ),
            snapshot: &snapshot
        )

        let removed = ExternalScheduleReconciler.reconcile(
            batch: ExternalEventBatch(
                sourceKind: .iCal,
                sourceIdentifier: "fixtures",
                coveredInterval: covered,
                events: [],
                fetchedAt: now.addingTimeInterval(60)
            ),
            snapshot: &snapshot
        )

        XCTAssertEqual(removed.removedCommitmentIDs.count, 1)
        XCTAssertEqual(
            snapshot.fixedCommitments.filter(\.isExternallyManaged)
                .map(\.title),
            ["Outside"]
        )
    }

    func testAppOwnedCalendarEventDoesNotBecomeExternalCommitment() {
        let now = Date(timeIntervalSince1970: 2_000_200_000)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        var event = externalEvent(
            sourceKind: .eventKit,
            sourceIdentifier: "calendar-a",
            uid: "owned",
            title: "Owned",
            start: now.addingTimeInterval(3_600)
        )
        event.isAppOwned = true

        _ = ExternalScheduleReconciler.reconcile(
            batch: ExternalEventBatch(
                sourceKind: .eventKit,
                sourceIdentifier: "calendar-a",
                coveredInterval: DateInterval(
                    start: now,
                    duration: 86_400
                ),
                events: [event],
                fetchedAt: now
            ),
            snapshot: &snapshot
        )

        XCTAssertFalse(
            snapshot.fixedCommitments.contains(where: {
                $0.externalIdentifier == event.reconciliationKey
            })
        )
    }

    func testCalendarServiceRespectsDeniedPermissionWithoutFetching()
        async throws
    {
        let now = Date(timeIntervalSince1970: 2_000_300_000)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        snapshot.calendarIntegrationSettings.mode = .importAndSync
        let provider = FakeCalendarProvider()
        provider.state = .denied

        do {
            _ = try await CalendarSyncService(provider: provider)
                .synchronize(
                    snapshot: snapshot,
                    interval: DateInterval(
                        start: now,
                        duration: 86_400
                    ),
                    at: now
                )
            XCTFail("Expected permission failure")
        } catch let error as PlatformIntegrationError {
            XCTAssertEqual(error, .permissionRequired(.denied))
        }
        XCTAssertEqual(provider.fetchCount, 0)
        XCTAssertEqual(provider.writeCount, 0)
    }

    func testCalendarExportPersistsIdentityForUpdateWithoutDuplicate()
        async throws
    {
        let now = Date(timeIntervalSince1970: 2_000_400_000)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        snapshot.calendarIntegrationSettings = CalendarIntegrationSettings(
            mode: .importAndSync,
            importsCalendarIDs: ["calendar-a"],
            exportsLocalCommitments: true
        )
        snapshot.fixedCommitments = [
            FixedCommitment(
                title: "Work shift",
                category: .work,
                start: now.addingTimeInterval(3_600),
                end: now.addingTimeInterval(7_200)
            )
        ]
        let provider = FakeCalendarProvider()
        provider.state = .authorized
        let service = CalendarSyncService(provider: provider)

        let first = try await service.synchronize(
            snapshot: snapshot,
            interval: DateInterval(start: now, duration: 86_400),
            at: now
        )
        let second = try await service.synchronize(
            snapshot: first,
            interval: DateInterval(start: now, duration: 86_400),
            at: now.addingTimeInterval(60)
        )

        XCTAssertEqual(
            second.externalCalendarItems.filter(\.isAppOwned).count,
            1
        )
        XCTAssertEqual(provider.createdIdentifiers.count, 1)
        XCTAssertEqual(provider.writeCount, 2)
    }

    func testWriteOnlyExportAddsEachLocalCommitmentOnce() async throws {
        let now = Date(timeIntervalSince1970: 2_000_450_000)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        snapshot.calendarIntegrationSettings = CalendarIntegrationSettings(
            mode: .createOnly,
            exportsLocalCommitments: true
        )
        snapshot.fixedCommitments = [
            FixedCommitment(
                title: "One-way export",
                category: .personal,
                start: now.addingTimeInterval(3_600),
                end: now.addingTimeInterval(7_200)
            )
        ]
        let provider = FakeCalendarProvider()
        provider.state = .authorized
        let service = CalendarSyncService(provider: provider)

        let first = try await service.synchronize(
            snapshot: snapshot,
            interval: DateInterval(start: now, duration: 86_400),
            at: now
        )
        _ = try await service.synchronize(
            snapshot: first,
            interval: DateInterval(start: now, duration: 86_400),
            at: now.addingTimeInterval(60)
        )

        XCTAssertEqual(provider.writeCount, 1)
        XCTAssertEqual(provider.createdIdentifiers.count, 1)
    }

    func testHealthSleepContextIsOptionalAndDerivedOnly() async throws {
        let now = Date(timeIntervalSince1970: 2_000_500_000)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        snapshot.healthIntegrationSettings.sleepReadEnabled = true
        let provider = FakeHealthProvider()
        provider.state = .requested
        provider.sample = SleepRecoverySample(
            sleepWindowStart: now.addingTimeInterval(-8 * 3_600),
            sleepWindowEnd: now.addingTimeInterval(-30 * 60),
            asleepMinutes: 425
        )

        let result = try await HealthSleepSyncService(provider: provider)
            .refresh(snapshot: snapshot, at: now)

        XCTAssertEqual(result.recoveryContext?.sleepDurationMinutes, 425)
        XCTAssertEqual(
            result.recoveryContext?.sleepSource,
            .healthKitSleep
        )
        XCTAssertEqual(
            result.recoveryContext?.note,
            "Sleep duration from HealthKit; planning context only."
        )
    }

    func testHealthNoDataLeavesLocalRecoveryContextUnchanged()
        async throws
    {
        let now = Date(timeIntervalSince1970: 2_000_600_000)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        snapshot.healthIntegrationSettings.sleepReadEnabled = true
        snapshot.recoveryContext = RecoveryContext(
            recordedAt: now,
            fatigue: .mild,
            note: "Manual"
        )
        let provider = FakeHealthProvider()
        provider.state = .requested

        let result = try await HealthSleepSyncService(provider: provider)
            .refresh(snapshot: snapshot, at: now)

        XCTAssertEqual(result.recoveryContext, snapshot.recoveryContext)
    }

    func testHealthNoDataClearsOnlyStaleHealthDerivedSleep()
        async throws
    {
        let now = Date(timeIntervalSince1970: 2_000_620_000)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        snapshot.healthIntegrationSettings.sleepReadEnabled = true
        snapshot.recoveryContext = RecoveryContext(
            recordedAt: now.addingTimeInterval(-86_400),
            sleepDurationMinutes: 420,
            fatigue: .mild,
            note: "Manual fatigue note",
            sleepSource: .healthKitSleep,
            sleepWindowStart: now.addingTimeInterval(-95_000),
            sleepWindowEnd: now.addingTimeInterval(-86_400)
        )
        let provider = FakeHealthProvider()
        provider.state = .requested

        let result = try await HealthSleepSyncService(provider: provider)
            .refresh(snapshot: snapshot, at: now)

        XCTAssertNil(result.recoveryContext?.sleepDurationMinutes)
        XCTAssertEqual(result.recoveryContext?.fatigue, .mild)
        XCTAssertEqual(
            result.recoveryContext?.note,
            "Manual fatigue note"
        )
        XCTAssertEqual(result.recoveryContext?.sleepSource, .manual)
    }

    func testICalendarParserHandlesTimeZoneFoldingAndCancellation()
        throws
    {
        let start = ISO8601DateFormatter().date(
            from: "2026-08-01T00:00:00Z"
        )!
        let subscription = ICalSubscription(
            title: "League",
            urlString: "https://example.com/fixtures.ics",
            isFootballFixtures: true
        )
        let text = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:fixture-1
        DTSTART;TZID=Europe/Berlin:20260802T150000
        DTEND;TZID=Europe/Berlin:20260802T170000
        SUMMARY:League match at the very long
         stadium name
        LOCATION:Main\\, Ground
        LAST-MODIFIED:20260731T100000Z
        END:VEVENT
        BEGIN:VEVENT
        UID:fixture-2
        DTSTART:20260803T180000Z
        DTEND:20260803T200000Z
        SUMMARY:Cancelled match
        STATUS:CANCELLED
        END:VEVENT
        END:VCALENDAR
        """

        let batch = try ICalendarParser().parse(
            text,
            subscription: subscription,
            interval: DateInterval(start: start, duration: 7 * 86_400),
            fetchedAt: start,
            defaultTimeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(batch.events.count, 2)
        XCTAssertEqual(
            batch.events.first(where: {
                $0.externalIdentifier == "fixture-1"
            })?.title,
            "League match at the very longstadium name"
        )
        XCTAssertEqual(
            batch.events.first(where: {
                $0.externalIdentifier == "fixture-1"
            })?.location,
            "Main, Ground"
        )
        XCTAssertTrue(
            batch.events.first(where: {
                $0.externalIdentifier == "fixture-2"
            })?.isCancelled == true
        )
    }

    func testICalProtocolSyncReconcilesUpdateAndDeletion() async throws {
        let now = Date(timeIntervalSince1970: 2_000_650_000)
        let interval = DateInterval(start: now, duration: 14 * 86_400)
        let subscription = ICalSubscription(
            title: "Fixtures",
            urlString: "https://example.com/fixtures.ics",
            isFootballFixtures: true
        )
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        snapshot.iCalSubscriptions = [subscription]
        let provider = FakeICalProvider()
        provider.nextEvents = [
            externalEvent(
                sourceIdentifier: subscription.id.rawValue.uuidString,
                uid: "fixture-sync",
                title: "First title",
                start: now.addingTimeInterval(86_400)
            )
        ]
        let service = ICalSyncService(provider: provider)

        let inserted = try await service.synchronize(
            subscriptionID: subscription.id,
            snapshot: snapshot,
            interval: interval,
            at: now
        )
        provider.nextEvents[0].title = "Updated title"
        let updated = try await service.synchronize(
            subscriptionID: subscription.id,
            snapshot: inserted,
            interval: interval,
            at: now.addingTimeInterval(60)
        )
        provider.nextEvents = []
        let removed = try await service.synchronize(
            subscriptionID: subscription.id,
            snapshot: updated,
            interval: interval,
            at: now.addingTimeInterval(120)
        )

        XCTAssertEqual(
            updated.fixedCommitments.first(where: {
                $0.isExternallyManaged
            })?.title,
            "Updated title"
        )
        XCTAssertFalse(
            removed.fixedCommitments.contains(where: {
                $0.isExternallyManaged
            })
        )
        XCTAssertEqual(provider.fetchCount, 3)
    }

    func testTruncatedICalendarIsRejectedBeforeReconciliation() {
        let now = Date(timeIntervalSince1970: 2_000_680_000)
        let subscription = ICalSubscription(
            title: "Fixtures",
            urlString: "https://example.com/fixtures.ics"
        )

        XCTAssertThrowsError(
            try ICalendarParser().parse(
                """
                BEGIN:VCALENDAR
                BEGIN:VEVENT
                UID:truncated
                DTSTART:20260803T180000Z
                """,
                subscription: subscription,
                interval: DateInterval(start: now, duration: 86_400),
                fetchedAt: now
            )
        )
    }

    func testVersionEightSnapshotDefaultsIntegrationState() throws {
        let snapshot = MissionControlSeed.makeDemo(
            referenceDate: Date(timeIntervalSince1970: 2_000_700_000)
        )
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["schemaVersion"] = 8
        object.removeValue(forKey: "calendarIntegrationSettings")
        object.removeValue(forKey: "healthIntegrationSettings")
        object.removeValue(forKey: "externalCalendarItems")
        object.removeValue(forKey: "iCalSubscriptions")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            MissionControlSnapshot.self,
            from: legacy
        )

        XCTAssertEqual(
            decoded.calendarIntegrationSettings.mode,
            .disabled
        )
        XCTAssertFalse(decoded.healthIntegrationSettings.sleepReadEnabled)
        XCTAssertTrue(decoded.externalCalendarItems.isEmpty)
        XCTAssertTrue(decoded.iCalSubscriptions.isEmpty)
    }

    private func externalEvent(
        sourceKind: ExternalScheduleSourceKind = .iCal,
        sourceIdentifier: String = "fixtures",
        uid: String,
        title: String,
        start: Date
    ) -> ExternalCalendarEvent {
        ExternalCalendarEvent(
            sourceKind: sourceKind,
            sourceIdentifier: sourceIdentifier,
            externalIdentifier: uid,
            title: title,
            category: .football,
            start: start,
            end: start.addingTimeInterval(2 * 3_600),
            isFootballMatch: true
        )
    }

    private func batch(
        event: ExternalCalendarEvent,
        interval: DateInterval,
        at date: Date
    ) -> ExternalEventBatch {
        ExternalEventBatch(
            sourceKind: event.sourceKind,
            sourceIdentifier: event.sourceIdentifier,
            coveredInterval: interval,
            events: [event],
            fetchedAt: date
        )
    }
}

private final class FakeCalendarProvider: CalendarProviding {
    var changeHandler: (() -> Void)?
    var state: PlatformAuthorizationState = .notDetermined
    var fetchedEvents: [ExternalCalendarEvent] = []
    var fetchCount = 0
    var writeCount = 0
    var createdIdentifiers: [String] = []

    func authorizationState(
        for accessLevel: CalendarAccessLevel
    ) async -> PlatformAuthorizationState {
        state
    }

    func requestAccess(
        _ accessLevel: CalendarAccessLevel
    ) async -> PlatformAuthorizationState {
        state
    }

    func calendars() async -> [CalendarDescriptor] {
        [
            CalendarDescriptor(
                id: "calendar-a",
                title: "Calendar",
                sourceTitle: "Local",
                allowsContentModifications: true
            )
        ]
    }

    func events(
        in interval: DateInterval,
        calendarIDs: [String]
    ) async throws -> [ExternalCalendarEvent] {
        fetchCount += 1
        return fetchedEvents
    }

    func upsertAppOwnedEvents(
        _ events: [CalendarEventWrite]
    ) async throws -> [CalendarEventWriteResult] {
        writeCount += 1
        return events.map { event in
            let identifier: String
            if let existing = event.externalIdentifier {
                identifier = existing
            } else {
                identifier =
                    "created-\(event.localFixedCommitmentID.rawValue.uuidString)"
                createdIdentifiers.append(identifier)
            }
            return CalendarEventWriteResult(
                localFixedCommitmentID: event.localFixedCommitmentID,
                sourceIdentifier: "calendar-a",
                externalIdentifier: identifier
            )
        }
    }

    func deleteAppOwnedEvent(
        externalIdentifier: String
    ) async throws {}
}

private final class FakeHealthProvider: HealthContextProviding {
    var state: PlatformAuthorizationState = .notDetermined
    var sample: SleepRecoverySample?

    func availabilityState() async -> PlatformAuthorizationState {
        state
    }

    func requestSleepReadAccess() async -> PlatformAuthorizationState {
        state
    }

    func sleepRecoverySample(
        endingAt date: Date
    ) async throws -> SleepRecoverySample? {
        sample
    }
}

private final class FakeICalProvider: ICalSubscriptionProviding {
    var nextEvents: [ExternalCalendarEvent] = []
    var fetchCount = 0

    func events(
        for subscription: ICalSubscription,
        in interval: DateInterval,
        fetchedAt: Date,
        timeZoneIdentifier: String
    ) async throws -> ExternalEventBatch {
        fetchCount += 1
        return ExternalEventBatch(
            sourceKind: .iCal,
            sourceIdentifier: subscription.id.rawValue.uuidString,
            coveredInterval: interval,
            events: nextEvents,
            fetchedAt: fetchedAt
        )
    }
}
