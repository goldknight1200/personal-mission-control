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

    func testRemovingMissionClearsActiveWorkoutProjection() {
        let mission = Mission(
            category: .gym,
            title: "Approved session",
            rigidity: .protected,
            estimatedDurationMinutes: 60
        )
        var snapshot = MissionControlSeed.makeFresh(
            referenceDate: Date(timeIntervalSince1970: 4_600)
        )
        snapshot.missions = [mission]
        snapshot.approvedWorkouts = [
            ApprovedWorkout(missionID: mission.id)
        ]

        snapshot.removeMission(id: mission.id)

        XCTAssertTrue(snapshot.missions.isEmpty)
        XCTAssertTrue(snapshot.approvedWorkouts.isEmpty)
    }

    func testRemovingMealTemplateClearsMissionReference() throws {
        var snapshot = MissionControlSeed.makeDemo(
            referenceDate: Date(timeIntervalSince1970: 4_650)
        )
        let template = try XCTUnwrap(snapshot.mealTemplates.first)
        snapshot.missions[0].mealTemplateID = template.id

        snapshot.removeMealTemplate(id: template.id)

        XCTAssertNil(snapshot.missions[0].mealTemplateID)
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
        object.removeValue(forKey: "clearCalorieDeficitThreshold")
        object.removeValue(forKey: "clearProteinDeficitThreshold")
        object.removeValue(forKey: "clearSubstantialMealDeficitThreshold")
        object.removeValue(forKey: "additionalEatingBlockMinutes")
        object.removeValue(forKey: "inventoryShoppingLeadHours")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            NutritionTargets.self,
            from: legacyData
        )

        XCTAssertEqual(
            decoded.preferredMealStartMinutes,
            [8 * 60, 13 * 60, 19 * 60]
        )
        XCTAssertEqual(decoded.clearCalorieDeficitThreshold, 400)
        XCTAssertEqual(decoded.clearProteinDeficitThreshold, 25)
        XCTAssertEqual(decoded.clearSubstantialMealDeficitThreshold, 1)
        XCTAssertEqual(decoded.additionalEatingBlockMinutes, 20)
        XCTAssertEqual(decoded.inventoryShoppingLeadHours, 24)
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
        object.removeValue(forKey: "mealTemplates")
        object.removeValue(forKey: "plannedMeals")
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
        object.removeValue(forKey: "manualScheduleAdjustments")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            MissionControlSnapshot.self,
            from: legacyData
        )

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertTrue(decoded.inventoryItems.isEmpty)
        XCTAssertTrue(decoded.mealTemplates.isEmpty)
        XCTAssertTrue(decoded.plannedMeals.isEmpty)
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
        XCTAssertTrue(decoded.manualScheduleAdjustments.isEmpty)
    }

    func testLegacyProjectsAndRoutinesReceivePhaseFiveDefaults() throws {
        let snapshot = MissionControlSeed.makeDemo(
            referenceDate: Date(timeIntervalSince1970: 4_750)
        )
        let projectData = try JSONEncoder().encode(
            try XCTUnwrap(snapshot.projects.first)
        )
        var projectObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: projectData)
                as? [String: Any]
        )
        projectObject.removeValue(forKey: "weeklyPlannedMinutes")
        projectObject.removeValue(forKey: "lastActiveReviewAt")
        let legacyProject = try JSONDecoder().decode(
            Project.self,
            from: JSONSerialization.data(withJSONObject: projectObject)
        )
        XCTAssertEqual(legacyProject.weeklyPlannedMinutes, 0)
        XCTAssertNil(legacyProject.lastActiveReviewAt)

        let routineData = try JSONEncoder().encode(
            try XCTUnwrap(snapshot.routines.first)
        )
        var routineObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: routineData)
                as? [String: Any]
        )
        routineObject.removeValue(forKey: "anchorDate")
        routineObject.removeValue(forKey: "flexibleCadence")
        routineObject.removeValue(forKey: "compatibleRoutineIDs")
        routineObject.removeValue(forKey: "allowsCompatibleOverlap")
        routineObject.removeValue(forKey: "bundlingNote")
        let legacyRoutine = try JSONDecoder().decode(
            Routine.self,
            from: JSONSerialization.data(withJSONObject: routineObject)
        )
        XCTAssertNil(legacyRoutine.anchorDate)
        XCTAssertNil(legacyRoutine.flexibleCadence)
        XCTAssertTrue(legacyRoutine.compatibleRoutineIDs.isEmpty)
        XCTAssertFalse(legacyRoutine.allowsCompatibleOverlap)
        XCTAssertTrue(legacyRoutine.bundlingNote.isEmpty)
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
