import Foundation
import MissionControlCore
import XCTest
@testable import PersonalMissionControl

final class ExecutionFlowTests: XCTestCase {
    @MainActor
    func testProtectedSkipPushesBackBeforePersistingOutcome() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let repository = InMemoryMissionControlRepository()
        let model = AppModel(repository: repository, referenceDate: date)
        let block = try XCTUnwrap(
            model.snapshot.scheduleBlocks.first(where: { block in
                guard let mission = model.snapshot.mission(withID: block.missionID) else {
                    return false
                }
                return MissionExecution.skipAssessment(
                    for: mission
                ).requiresConfirmation
            })
        )
        let missionID = try XCTUnwrap(block.missionID)

        model.requestSkip(
            missionID: missionID,
            scheduleBlockID: block.id,
            at: date
        )

        guard case .confirmSkip? = model.executionPrompt else {
            return XCTFail("Expected a consequential skip confirmation")
        }
        XCTAssertFalse(
            model.snapshot.completions.contains(where: {
                $0.scheduleBlockID == block.id
            })
        )

        model.confirmSkip(
            missionID: missionID,
            scheduleBlockID: block.id,
            at: date
        )

        XCTAssertEqual(
            model.snapshot.completions.first(where: {
                $0.scheduleBlockID == block.id
            })?.status,
            .skipped
        )
        XCTAssertFalse(
            model.snapshot.scheduleBlocks.contains(where: {
                $0.id == block.id && $0.end > date
            })
        )
        XCTAssertEqual(model.snapshot.replanRequests.last?.reason, .missionSkipped)
    }

    @MainActor
    func testFailedStartNowWriteDoesNotCorruptSchedule() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let seed = MissionControlSeed.makeDemo(referenceDate: date)
        let repository = ExecutionFailingRepository(snapshot: seed)
        let model = AppModel(repository: repository, referenceDate: date)
        let block = try XCTUnwrap(
            model.snapshot.scheduleBlocks.first(where: { $0.missionID != nil })
        )
        let missionID = try XCTUnwrap(block.missionID)
        let original = model.snapshot
        repository.shouldFailSave = true

        model.startMissionNow(
            missionID: missionID,
            scheduleBlockID: block.id,
            at: date
        )

        XCTAssertEqual(model.snapshot, original)
        XCTAssertNotNil(model.persistenceNotice)
    }

    @MainActor
    func testPartialCompletionTracksElapsedTimeAndReplansTheRemainder() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let repository = InMemoryMissionControlRepository()
        let model = AppModel(repository: repository, referenceDate: date)
        let block = try XCTUnwrap(
            model.snapshot.scheduleBlocks.first(where: {
                $0.missionID != nil && $0.start >= date
            })
        )
        let missionID = try XCTUnwrap(block.missionID)
        let startedAt = block.start.addingTimeInterval(5 * 60)
        let partialAt = startedAt.addingTimeInterval(10 * 60)

        model.confirmAlreadyStarted(
            missionID: missionID,
            scheduleBlockID: block.id,
            minutesAgo: 0,
            at: startedAt
        )

        model.recordPartialMission(
            missionID: missionID,
            scheduleBlockID: block.id,
            at: partialAt
        )

        let record = try XCTUnwrap(
            model.snapshot.completions.first(where: {
                $0.scheduleBlockID == block.id
            })
        )
        XCTAssertEqual(record.status, .partial)
        XCTAssertEqual(record.actualDurationMinutes, 10)
        XCTAssertFalse(
            model.snapshot.scheduleBlocks.contains(where: {
                $0.id == block.id && $0.end > partialAt
            })
        )
    }

    @MainActor
    func testLoadFailureCannotOverwriteCorruptedDurableState() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let repository = LoadFailingRepository()
        let model = AppModel(repository: repository, referenceDate: date)
        let checklist = try XCTUnwrap(
            model.snapshot.checklist(ofKind: .today)
        )
        let item = try XCTUnwrap(checklist.items.first)

        XCTAssertEqual(repository.saveInvocationCount, 0)
        XCTAssertNotNil(model.persistenceNotice)

        model.toggleChecklistItem(
            checklistID: checklist.id,
            itemID: item.id
        )

        XCTAssertEqual(repository.saveInvocationCount, 0)
        XCTAssertEqual(
            model.snapshot.checklist(ofKind: .today)?
                .items.first?.isCompleted,
            true
        )
        XCTAssertNotNil(model.persistenceNotice)
    }

    @MainActor
    func testRapidNotificationReconciliationsAreSerializedAndFinishCurrent() async throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let service = DelayedNotificationService()
        let model = AppModel(
            repository: InMemoryMissionControlRepository(),
            referenceDate: date,
            notificationService: service
        )
        await model.requestNotificationAuthorization()
        service.resetMeasurements()
        let block = try XCTUnwrap(
            model.snapshot.scheduleBlocks.first(where: {
                $0.missionID != nil && $0.kind == .mission
            })
        )
        let missionID = try XCTUnwrap(block.missionID)

        let first = Task { @MainActor in
            await model.reconcileNotifications(at: date)
        }
        try await Task.sleep(nanoseconds: 1_000_000)
        model.completeMission(
            missionID,
            scheduleBlockID: block.id,
            at: block.end,
            plannedDurationMinutes: block.durationMinutes
        )
        await model.reconcileNotifications(at: date)
        await first.value

        let desired = NotificationSchedulePlanner.desiredRequests(
            snapshot: model.snapshot,
            now: date
        )
        XCTAssertEqual(service.maximumConcurrentReconciliations, 1)
        XCTAssertEqual(Set(service.pending.map(\.id)), Set(desired.map(\.id)))
        XCTAssertEqual(Set(service.pending.map(\.id)).count, service.pending.count)
    }
}

@MainActor
private final class ExecutionFailingRepository: MissionControlRepository {
    var shouldFailSave = false
    private var snapshot: MissionControlSnapshot?

    init(snapshot: MissionControlSnapshot?) {
        self.snapshot = snapshot
    }

    func loadSnapshot() throws -> MissionControlSnapshot? {
        snapshot
    }

    func saveSnapshot(_ snapshot: MissionControlSnapshot) throws {
        if shouldFailSave {
            throw ExecutionTestError.saveFailed
        }
        self.snapshot = snapshot
    }
}

private enum ExecutionTestError: Error {
    case loadFailed
    case saveFailed
}

@MainActor
private final class DelayedNotificationService: NotificationService {
    var actionHandler: ((MissionNotificationAction) -> Void)?
    private(set) var pending: [MissionNotificationRequest] = []
    private(set) var maximumConcurrentReconciliations = 0
    private var activeReconciliations = 0

    func authorizationState() async -> NotificationAuthorizationState {
        .authorized
    }

    func requestAuthorization() async -> NotificationAuthorizationState {
        .authorized
    }

    func pendingMissionNotifications() async
        -> [MissionNotificationRequest] {
        pending
    }

    func reconcile(
        _ reconciliation: NotificationReconciliation
    ) async throws {
        activeReconciliations += 1
        maximumConcurrentReconciliations = max(
            maximumConcurrentReconciliations,
            activeReconciliations
        )
        defer { activeReconciliations -= 1 }
        try await Task.sleep(nanoseconds: 20_000_000)
        let cancelled = Set(reconciliation.identifiersToCancel)
        pending.removeAll(where: { cancelled.contains($0.id) })
        for request in reconciliation.requestsToSchedule {
            pending.removeAll(where: { $0.id == request.id })
            pending.append(request)
        }
    }

    func resetMeasurements() {
        maximumConcurrentReconciliations = 0
    }
}

@MainActor
private final class LoadFailingRepository: MissionControlRepository {
    private(set) var saveInvocationCount = 0

    func loadSnapshot() throws -> MissionControlSnapshot? {
        throw ExecutionTestError.loadFailed
    }

    func saveSnapshot(_ snapshot: MissionControlSnapshot) throws {
        saveInvocationCount += 1
    }
}
