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
                ).requiresConfirmation && block.start >= date
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
            .skipped,
            "The confirmed occurrence was not recorded as skipped."
        )
        XCTAssertFalse(
            model.snapshot.scheduleBlocks.contains(where: {
                $0.id == block.id && $0.end > date
            }),
            "The skipped occurrence remained active after replanning."
        )
        XCTAssertEqual(
            model.snapshot.replanRequests.last?.reason,
            .missionSkipped,
            "The confirmed skip did not remain the terminal replan reason."
        )
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
        XCTAssertEqual(
            record.status,
            .partial,
            "The resolved occurrence was not retained as partial."
        )
        XCTAssertEqual(
            record.actualDurationMinutes,
            10,
            "Elapsed time was not measured from the corrected actual start."
        )
        XCTAssertFalse(
            model.snapshot.scheduleBlocks.contains(where: {
                $0.id == block.id && $0.end > partialAt
            }),
            "The partially completed occurrence still extends beyond its actual end."
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
private final class LoadFailingRepository: MissionControlRepository {
    private(set) var saveInvocationCount = 0

    func loadSnapshot() throws -> MissionControlSnapshot? {
        throw ExecutionTestError.loadFailed
    }

    func saveSnapshot(_ snapshot: MissionControlSnapshot) throws {
        saveInvocationCount += 1
    }
}
