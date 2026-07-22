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
}
