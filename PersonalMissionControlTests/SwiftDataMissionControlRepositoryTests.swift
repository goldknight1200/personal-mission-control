import Foundation
import MissionControlCore
import SwiftData
import XCTest
@testable import PersonalMissionControl

final class SwiftDataMissionControlRepositoryTests: XCTestCase {
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
        XCTAssertTrue(loaded.commandHistory.isEmpty)
        XCTAssertTrue(loaded.dailyCheckIns.isEmpty)
        XCTAssertTrue(loaded.unresolvedDispositions.isEmpty)
        XCTAssertTrue(loaded.missDiagnostics.isEmpty)
        XCTAssertTrue(loaded.approvedWorkouts.isEmpty)
        XCTAssertTrue(loaded.nutritionPlanningNeeds.isEmpty)
        XCTAssertNil(loaded.recoveryContext)
        XCTAssertTrue(loaded.schedulingDecisions.isEmpty)
        XCTAssertTrue(loaded.schedulingConflicts.isEmpty)
        XCTAssertNil(loaded.schedulingPlanMetadata)

        let verifier = ModelContext(container)
        let records = try verifier.fetch(FetchDescriptor<MissionControlStateRecord>())
        XCTAssertEqual(records.first?.schemaVersion, MissionControlSnapshot.currentSchemaVersion)
    }
}
