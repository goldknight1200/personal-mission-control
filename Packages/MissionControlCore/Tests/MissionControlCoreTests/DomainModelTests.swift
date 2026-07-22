import Foundation
import XCTest
@testable import MissionControlCore

final class DomainModelTests: XCTestCase {
    func testCompletingMissionCreatesOneCompletionAndTracksActualDuration() throws {
        let completedAt = Date(timeIntervalSince1970: 2_000)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: completedAt)
        let missionID = try XCTUnwrap(snapshot.missions.first?.id)

        snapshot.completeMission(id: missionID, at: completedAt, actualDurationMinutes: 47)
        snapshot.completeMission(id: missionID, at: completedAt.addingTimeInterval(60), actualDurationMinutes: 52)

        XCTAssertEqual(snapshot.mission(withID: missionID)?.status, .completed)
        XCTAssertEqual(snapshot.mission(withID: missionID)?.actualDurationMinutes, 52)
        XCTAssertEqual(snapshot.completions.count, 1)
        XCTAssertEqual(snapshot.completions.first?.actualDurationMinutes, 52)
    }

    func testChecklistAndMissionStepTogglesAreScopedByIdentifiers() throws {
        var snapshot = MissionControlSeed.makeDemo(referenceDate: Date(timeIntervalSince1970: 3_000))
        let mission = try XCTUnwrap(snapshot.missions.first)
        let step = try XCTUnwrap(mission.miniGoals.first)
        let checklist = try XCTUnwrap(snapshot.checklist(ofKind: .today))
        let item = try XCTUnwrap(checklist.items.first)

        snapshot.toggleMissionStep(missionID: mission.id, stepID: step.id)
        snapshot.toggleChecklistItem(checklistID: checklist.id, itemID: item.id)

        XCTAssertEqual(snapshot.mission(withID: mission.id)?.miniGoals.first?.isCompleted, true)
        XCTAssertEqual(snapshot.checklist(ofKind: .today)?.items.first?.isCompleted, true)
    }

    func testSnapshotCodableRoundTripPreservesDomainData() throws {
        let snapshot = MissionControlSeed.makeDemo(referenceDate: Date(timeIntervalSince1970: 4_000))

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(MissionControlSnapshot.self, from: encoded)

        XCTAssertEqual(decoded, snapshot)
    }

    func testProjectAndRoutineEditsReplaceOnlyMatchingRecords() throws {
        var snapshot = MissionControlSeed.makeDemo(referenceDate: Date(timeIntervalSince1970: 4_500))
        var project = try XCTUnwrap(snapshot.projects.first)
        var routine = try XCTUnwrap(snapshot.routines.first)
        project.title = "Edited priority project"
        routine.recurrence.interval = 2

        snapshot.updateProject(project)
        snapshot.updateRoutine(routine)

        XCTAssertEqual(snapshot.projects.first?.title, "Edited priority project")
        XCTAssertEqual(snapshot.routines.first?.recurrence.interval, 2)
    }
}
