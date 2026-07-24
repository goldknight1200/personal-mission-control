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

    func testLegacyPlanningPolicyReceivesEditableSleepDefaults() throws {
        let encoded = try JSONEncoder().encode(PlanningPolicy.baseline)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "sleepTargetMinutes")
        object.removeValue(forKey: "practicalSleepMinimumMinutes")
        object.removeValue(forKey: "reconsiderDemandingWorkBelowMinutes")
        object.removeValue(forKey: "preferredWakeMinute")
        object.removeValue(forKey: "generatedGridMinutes")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            PlanningPolicy.self,
            from: legacyData
        )

        XCTAssertEqual(decoded.sleepTargetMinutes, 450)
        XCTAssertEqual(decoded.practicalSleepMinimumMinutes, 390)
        XCTAssertEqual(decoded.reconsiderDemandingWorkBelowMinutes, 360)
        XCTAssertEqual(decoded.preferredWakeMinute, 7 * 60 + 30)
        XCTAssertEqual(decoded.generatedGridMinutes, 5)
    }

    func testLegacyNutritionTargetsReceiveEditableMealTimes() throws {
        let encoded = try JSONEncoder().encode(
            NutritionTargets(
                approximateCalories: 3_400,
                approximateProteinGrams: 180,
                substantialMeals: 3
            )
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "preferredMealStartMinutes")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            NutritionTargets.self,
            from: legacyData
        )

        XCTAssertEqual(
            decoded.preferredMealStartMinutes,
            [8 * 60, 13 * 60, 19 * 60]
        )
    }

    func testPhaseOneSnapshotPayloadDecodesWithLaterCollectionsEmpty() throws {
        let snapshot = MissionControlSeed.makeDemo(
            referenceDate: Date(timeIntervalSince1970: 4_700)
        )
        let data = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["schemaVersion"] = 1
        object.removeValue(forKey: "inventoryItems")
        object.removeValue(forKey: "painFlags")
        object.removeValue(forKey: "missionStartRecords")
        object.removeValue(forKey: "replanRequests")
        object.removeValue(forKey: "commandHistory")
        object.removeValue(forKey: "dailyCheckIns")
        object.removeValue(forKey: "unresolvedDispositions")
        object.removeValue(forKey: "missDiagnostics")
        object.removeValue(forKey: "approvedWorkouts")
        object.removeValue(forKey: "nutritionPlanningNeeds")
        object.removeValue(forKey: "recoveryContext")
        object.removeValue(forKey: "schedulingDecisions")
        object.removeValue(forKey: "schedulingConflicts")
        object.removeValue(forKey: "schedulingPlanMetadata")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            MissionControlSnapshot.self,
            from: legacyData
        )

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertTrue(decoded.inventoryItems.isEmpty)
        XCTAssertTrue(decoded.painFlags.isEmpty)
        XCTAssertTrue(decoded.missionStartRecords.isEmpty)
        XCTAssertTrue(decoded.replanRequests.isEmpty)
        XCTAssertTrue(decoded.commandHistory.isEmpty)
        XCTAssertTrue(decoded.dailyCheckIns.isEmpty)
        XCTAssertTrue(decoded.unresolvedDispositions.isEmpty)
        XCTAssertTrue(decoded.missDiagnostics.isEmpty)
        XCTAssertTrue(decoded.approvedWorkouts.isEmpty)
        XCTAssertTrue(decoded.nutritionPlanningNeeds.isEmpty)
        XCTAssertNil(decoded.recoveryContext)
        XCTAssertTrue(decoded.schedulingDecisions.isEmpty)
        XCTAssertTrue(decoded.schedulingConflicts.isEmpty)
        XCTAssertNil(decoded.schedulingPlanMetadata)
    }

    func testLegacyMissionStartRecordDecodesWithoutBlockIdentity() throws {
        let record = MissionStartRecord(
            missionID: EntityID(),
            scheduleBlockID: EntityID(),
            actualStart: Date(timeIntervalSince1970: 5_000),
            reportedAt: Date(timeIntervalSince1970: 5_060)
        )
        let data = try JSONEncoder().encode(record)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "scheduleBlockID")
        let legacyData = try JSONSerialization.data(
            withJSONObject: object
        )

        let decoded = try JSONDecoder().decode(
            MissionStartRecord.self,
            from: legacyData
        )

        XCTAssertEqual(decoded.missionID, record.missionID)
        XCTAssertNil(decoded.scheduleBlockID)
        XCTAssertEqual(decoded.actualStart, record.actualStart)
    }
}
