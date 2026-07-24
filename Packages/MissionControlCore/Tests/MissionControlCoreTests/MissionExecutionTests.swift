import Foundation
import XCTest
@testable import MissionControlCore

final class MissionExecutionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 20_000)

    func testLatenessTransitionsAtBoundariesAndResolves() {
        let block = ScheduleBlock(
            title: "Focus",
            category: .project,
            kind: .mission,
            rigidity: .flexible,
            start: start,
            end: start.addingTimeInterval(60 * 60)
        )

        XCTAssertEqual(state(block, at: start.addingTimeInterval(-1)), .upcoming)
        XCTAssertEqual(state(block, at: start), .due)
        XCTAssertEqual(state(block, at: start.addingTimeInterval(15 * 60 - 1)), .due)
        XCTAssertEqual(state(block, at: start.addingTimeInterval(15 * 60)), .late15)
        XCTAssertEqual(state(block, at: start.addingTimeInterval(30 * 60)), .late30)
        XCTAssertEqual(
            MissionExecution.latenessState(
                block: block,
                missionStatus: .inProgress,
                hasResolution: false,
                at: start.addingTimeInterval(60 * 60)
            ),
            .inProgress
        )
        XCTAssertEqual(
            MissionExecution.latenessState(
                block: block,
                missionStatus: .planned,
                hasResolution: true,
                at: start
            ),
            .resolved
        )
    }

    func testProtectedSkipRequiresExplicitConfirmationAssessment() {
        let protected = Mission(
            category: .project,
            title: "Protected work",
            rigidity: .protected,
            estimatedDurationMinutes: 60
        )
        let lowRisk = Mission(
            category: .freeTime,
            title: "Optional walk",
            rigidity: .flexible,
            importance: .low,
            urgency: .low,
            estimatedDurationMinutes: 20,
            consistencyCost: .low,
            backlogCost: .low
        )

        XCTAssertTrue(
            MissionExecution.skipAssessment(for: protected).requiresConfirmation
        )
        XCTAssertFalse(
            MissionExecution.skipAssessment(for: lowRisk).requiresConfirmation
        )
    }

    func testActualStartEndAndDurationArePersistedAndAdjustLatestOnly() throws {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: end)
        snapshot.applySchedulingResult(
            SchedulingEngine().makePlan(
                input: PlanningInput(
                    snapshot: snapshot,
                    currentTime: end
                )
            )
        )
        let block = try XCTUnwrap(
            snapshot.scheduleBlocks.first(where: { $0.missionID != nil })
        )
        let missionID = try XCTUnwrap(block.missionID)
        let actualStart = end.addingTimeInterval(-42 * 60)

        XCTAssertTrue(
            MissionExecution.markStarted(
                snapshot: &snapshot,
                missionID: missionID,
                actualStart: actualStart,
                reportedAt: actualStart.addingTimeInterval(5 * 60)
            )
        )
        let record = try XCTUnwrap(
            MissionExecution.resolve(
                snapshot: &snapshot,
                missionID: missionID,
                scheduleBlockID: block.id,
                status: .completed,
                at: end
            )
        )

        XCTAssertEqual(record.actualStart, actualStart)
        XCTAssertEqual(record.actualEnd, end)
        XCTAssertEqual(record.actualDurationMinutes, 42)
        XCTAssertEqual(record.plannedDurationMinutes, block.durationMinutes)

        let oldRecord = CompletionRecord(
            missionID: missionID,
            completedAt: end.addingTimeInterval(-86_400),
            plannedDurationMinutes: 20,
            actualDurationMinutes: 20
        )
        snapshot.completions.insert(oldRecord, at: 0)
        MissionExecution.updateActualDuration(
            snapshot: &snapshot,
            missionID: missionID,
            minutes: 50
        )

        XCTAssertEqual(snapshot.completions.first?.actualDurationMinutes, 20)
        XCTAssertEqual(snapshot.completions.last?.actualDurationMinutes, 50)
        XCTAssertEqual(
            snapshot.completions.last?.actualStart,
            end.addingTimeInterval(-50 * 60)
        )
    }

    private func state(
        _ block: ScheduleBlock,
        at date: Date
    ) -> MissionLatenessState {
        MissionExecution.latenessState(
            block: block,
            missionStatus: .planned,
            hasResolution: false,
            at: date
        )
    }
}
