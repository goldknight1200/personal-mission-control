import Foundation
import MissionControlCore
import SwiftData
import XCTest
@testable import PersonalMissionControl

final class SwiftDataMissionControlRepositoryTests: XCTestCase {
    @MainActor
    func testDeleteSnapshotRemovesDurablePrimaryRecord() throws {
        let repository = try SwiftDataMissionControlRepository(
            isStoredInMemoryOnly: true
        )
        try repository.saveSnapshot(
            MissionControlSeed.makeDemo(
                referenceDate: Date(timeIntervalSince1970: 30_000)
            )
        )

        try repository.deleteSnapshot()

        XCTAssertNil(try repository.loadSnapshot())
    }

    @MainActor
    func testInvalidSnapshotIsRejectedBeforePersistence() throws {
        let repository = try SwiftDataMissionControlRepository(
            isStoredInMemoryOnly: true
        )
        var snapshot = MissionControlSeed.makeDemo(
            referenceDate: Date(timeIntervalSince1970: 35_000)
        )
        snapshot.goals.append(snapshot.goals[0])

        XCTAssertThrowsError(try repository.saveSnapshot(snapshot))
        XCTAssertNil(try repository.loadSnapshot())
    }

    @MainActor
    func testSemanticallyCorruptedPayloadIsRejectedWithoutOverwrite()
        throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: MissionControlStateRecord.self,
            configurations: configuration
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let snapshot = MissionControlSeed.makeDemo(
            referenceDate: Date(timeIntervalSince1970: 36_000)
        )
        let encoded = try encoder.encode(snapshot)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var missions = try XCTUnwrap(
            object["missions"] as? [[String: Any]]
        )
        missions[0]["estimatedDurationMinutes"] = -1
        object["missions"] = missions
        let corruptedPayload = try JSONSerialization.data(
            withJSONObject: object
        )
        let writer = ModelContext(container)
        writer.insert(
            MissionControlStateRecord(payload: corruptedPayload)
        )
        try writer.save()
        let repository = SwiftDataMissionControlRepository(container: container)

        XCTAssertThrowsError(try repository.loadSnapshot()) { error in
            XCTAssertEqual(
                error as? MissionControlPersistenceError,
                .invalidSnapshot
            )
        }

        let verifier = ModelContext(container)
        let record = try XCTUnwrap(
            verifier.fetch(
                FetchDescriptor<MissionControlStateRecord>()
            ).first
        )
        XCTAssertEqual(record.payload, corruptedPayload)
    }

    @MainActor
    func testMalformedPayloadIsRejectedWithoutOverwrite() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: MissionControlStateRecord.self,
            configurations: configuration
        )
        let malformedPayload = Data(#"{"schemaVersion":10"#.utf8)
        let writer = ModelContext(container)
        writer.insert(
            MissionControlStateRecord(payload: malformedPayload)
        )
        try writer.save()
        let repository = SwiftDataMissionControlRepository(container: container)

        XCTAssertThrowsError(try repository.loadSnapshot())

        let verifier = ModelContext(container)
        let record = try XCTUnwrap(
            verifier.fetch(
                FetchDescriptor<MissionControlStateRecord>()
            ).first
        )
        XCTAssertEqual(record.payload, malformedPayload)
    }

    @MainActor
    func testMismatchedRecordAndPayloadSchemaIsRejected() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: MissionControlStateRecord.self,
            configurations: configuration
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        var snapshot = MissionControlSeed.makeDemo(
            referenceDate: Date(timeIntervalSince1970: 37_000)
        )
        snapshot.schemaVersion = 9
        let writer = ModelContext(container)
        writer.insert(
            MissionControlStateRecord(
                schemaVersion: 10,
                payload: try encoder.encode(snapshot)
            )
        )
        try writer.save()
        let repository = SwiftDataMissionControlRepository(container: container)

        XCTAssertThrowsError(try repository.loadSnapshot()) { error in
            XCTAssertEqual(
                error as? MissionControlPersistenceError,
                .invalidSnapshot
            )
        }
    }

    @MainActor
    func testEveryStoredSchemaMigrationIsIdempotent() throws {
        for schemaVersion in 1..<MissionControlSnapshot.currentSchemaVersion {
            let configuration = ModelConfiguration(
                isStoredInMemoryOnly: true
            )
            let container = try ModelContainer(
                for: MissionControlStateRecord.self,
                configurations: configuration
            )
            let writer = ModelContext(container)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            var snapshot = MissionControlSeed.makeDemo(
                referenceDate: Date(
                    timeIntervalSince1970:
                        50_000 + Double(schemaVersion)
                )
            )
            snapshot.schemaVersion = schemaVersion
            writer.insert(
                MissionControlStateRecord(
                    schemaVersion: schemaVersion,
                    payload: try encoder.encode(snapshot)
                )
            )
            try writer.save()
            let repository = SwiftDataMissionControlRepository(
                container: container
            )

            let migrated = try XCTUnwrap(repository.loadSnapshot())
            let reloaded = try XCTUnwrap(repository.loadSnapshot())

            XCTAssertEqual(
                migrated.schemaVersion,
                MissionControlSnapshot.currentSchemaVersion
            )
            XCTAssertEqual(reloaded, migrated)
            let records = try ModelContext(container).fetch(
                FetchDescriptor<MissionControlStateRecord>()
            )
            XCTAssertEqual(records.count, 1)
            XCTAssertEqual(
                records.first?.schemaVersion,
                MissionControlSnapshot.currentSchemaVersion
            )
        }
    }

    @MainActor
    func testEmptyStoreReturnsNilThenRoundTripsSnapshot() throws {
        let repository = try SwiftDataMissionControlRepository(isStoredInMemoryOnly: true)
        let snapshot = MissionControlSeed.makeDemo(referenceDate: Date(timeIntervalSince1970: 20_000))

        XCTAssertNil(try repository.loadSnapshot())
        try repository.saveSnapshot(snapshot)

        XCTAssertEqual(try repository.loadSnapshot(), snapshot)
    }

    @MainActor
    func testSaveUpdatesTheExistingLocalSnapshot() throws {
        let repository = try SwiftDataMissionControlRepository(isStoredInMemoryOnly: true)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: Date(timeIntervalSince1970: 30_000))
        let checklist = try XCTUnwrap(snapshot.checklist(ofKind: .today))
        let item = try XCTUnwrap(checklist.items.first)
        let mission = try XCTUnwrap(snapshot.missions.first)

        try repository.saveSnapshot(snapshot)
        snapshot.toggleChecklistItem(checklistID: checklist.id, itemID: item.id)
        snapshot.completeMission(id: mission.id, at: Date(timeIntervalSince1970: 31_000))
        try repository.saveSnapshot(snapshot)

        let loaded = try XCTUnwrap(repository.loadSnapshot())
        XCTAssertEqual(loaded.checklist(ofKind: .today)?.items.first?.isCompleted, true)
        XCTAssertEqual(loaded.mission(withID: mission.id)?.status, .completed)
        XCTAssertEqual(loaded.completions.count, 1)
    }

    @MainActor
    func testWorkoutLogRoundTripsThroughSwiftDataSnapshot() throws {
        let repository = try SwiftDataMissionControlRepository(
            isStoredInMemoryOnly: true
        )
        let date = Date(timeIntervalSince1970: 50_000)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: date)
        let program = try XCTUnwrap(snapshot.workoutPrograms.first)
        let session = try XCTUnwrap(program.sessionTemplates.first)
        let mission = try XCTUnwrap(
            snapshot.missions.first(where: { $0.category == .gym })
        )
        let blockID = EntityID()
        snapshot.workoutLogs.append(
            WorkoutLog(
                programID: program.id,
                sessionTemplateID: session.id,
                missionID: mission.id,
                scheduleBlockID: blockID,
                selectedExerciseIDs: session.exercises.map(\.id),
                startedAt: date,
                completedAt: date.addingTimeInterval(3_600),
                status: .completed,
                exerciseLogs: [
                    WorkoutExerciseLog(
                        exerciseID: session.exercises[0].id,
                        setLogs: [
                            WorkoutSetLog(
                                prescriptionSetID:
                                    session.exercises[0].sets[0].id,
                                setNumber: 1,
                                weight: 70,
                                reps: 8,
                                completedAt:
                                    date.addingTimeInterval(300)
                            )
                        ]
                    )
                ]
            )
        )

        try repository.saveSnapshot(snapshot)
        let restored = try XCTUnwrap(repository.loadSnapshot())

        XCTAssertEqual(restored.workoutLogs, snapshot.workoutLogs)
    }

    @MainActor
    func testPhaseOnePayloadMigratesToCurrentSnapshotSchema() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: MissionControlStateRecord.self,
            configurations: configuration
        )
        let writer = ModelContext(container)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let snapshot = MissionControlSeed.makeDemo(
            referenceDate: Date(timeIntervalSince1970: 40_000)
        )
        let encoded = try encoder.encode(snapshot)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
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
        object.removeValue(forKey: "workoutPrograms")
        object.removeValue(forKey: "workoutLogs")
        object.removeValue(forKey: "nutritionPlanningNeeds")
        object.removeValue(forKey: "recoveryContext")
        object.removeValue(forKey: "schedulingDecisions")
        object.removeValue(forKey: "schedulingConflicts")
        object.removeValue(forKey: "schedulingPlanMetadata")
        object.removeValue(forKey: "manualScheduleAdjustments")
        object.removeValue(forKey: "calendarIntegrationSettings")
        object.removeValue(forKey: "healthIntegrationSettings")
        object.removeValue(forKey: "externalCalendarItems")
        object.removeValue(forKey: "iCalSubscriptions")
        object.removeValue(forKey: "aiIntegrationSettings")
        object.removeValue(forKey: "privacySettings")
        let legacyPayload = try JSONSerialization.data(withJSONObject: object)
        writer.insert(
            MissionControlStateRecord(
                schemaVersion: 1,
                payload: legacyPayload
            )
        )
        try writer.save()

        let repository = SwiftDataMissionControlRepository(container: container)
        let loaded = try XCTUnwrap(repository.loadSnapshot())

        XCTAssertEqual(
            loaded.schemaVersion,
            MissionControlSnapshot.currentSchemaVersion
        )
        XCTAssertTrue(loaded.inventoryItems.isEmpty)
        XCTAssertTrue(loaded.mealTemplates.isEmpty)
        XCTAssertTrue(loaded.plannedMeals.isEmpty)
        XCTAssertTrue(loaded.commandHistory.isEmpty)
        XCTAssertTrue(loaded.dailyCheckIns.isEmpty)
        XCTAssertTrue(loaded.unresolvedDispositions.isEmpty)
        XCTAssertTrue(loaded.missDiagnostics.isEmpty)
        XCTAssertTrue(loaded.approvedWorkouts.isEmpty)
        XCTAssertTrue(loaded.workoutPrograms.isEmpty)
        XCTAssertTrue(loaded.workoutLogs.isEmpty)
        XCTAssertTrue(loaded.nutritionPlanningNeeds.isEmpty)
        XCTAssertNil(loaded.recoveryContext)
        XCTAssertTrue(loaded.schedulingDecisions.isEmpty)
        XCTAssertTrue(loaded.schedulingConflicts.isEmpty)
        XCTAssertNil(loaded.schedulingPlanMetadata)
        XCTAssertTrue(loaded.manualScheduleAdjustments.isEmpty)
        XCTAssertEqual(loaded.calendarIntegrationSettings.mode, .disabled)
        XCTAssertFalse(loaded.healthIntegrationSettings.sleepReadEnabled)
        XCTAssertTrue(loaded.externalCalendarItems.isEmpty)
        XCTAssertTrue(loaded.iCalSubscriptions.isEmpty)
        XCTAssertFalse(loaded.aiIntegrationSettings.isEnabled)
        XCTAssertTrue(loaded.privacySettings.retainsCommandTranscripts)

        let verifier = ModelContext(container)
        let records = try verifier.fetch(FetchDescriptor<MissionControlStateRecord>())
        XCTAssertEqual(records.first?.schemaVersion, MissionControlSnapshot.currentSchemaVersion)
    }
}
