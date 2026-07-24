import Foundation
import XCTest
@testable import MissionControlCore

final class NotificationSchedulePlannerTests: XCTestCase {
    func testPlannerProducesFourStableOffsetsForUnresolvedMission() throws {
        var snapshot = plannedSeed(
            referenceDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let block = try XCTUnwrap(
            snapshot.scheduleBlocks.first(where: { $0.missionID != nil })
        )
        let missionID = try XCTUnwrap(block.missionID)
        snapshot.missions = snapshot.missions.map { mission in
            var mission = mission
            mission.status = mission.id == missionID ? .planned : .completed
            return mission
        }
        snapshot.scheduleBlocks = [block]
        let now = block.start.addingTimeInterval(-60 * 60)

        let requests = NotificationSchedulePlanner.desiredRequests(
            snapshot: snapshot,
            now: now
        )

        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(Set(requests.map(\.stage)), Set(MissionNotificationStage.allCases))
        XCTAssertEqual(
            requests.first(where: { $0.stage == .preStart })?.fireDate,
            block.start.addingTimeInterval(-15 * 60)
        )
        XCTAssertEqual(
            requests.first(where: { $0.stage == .start })?.fireDate,
            block.start
        )
        XCTAssertEqual(
            requests.first(where: { $0.stage == .late15 })?.fireDate,
            block.start.addingTimeInterval(15 * 60)
        )
        XCTAssertEqual(
            requests.first(where: { $0.stage == .late30 })?.fireDate,
            block.start.addingTimeInterval(30 * 60)
        )
        XCTAssertEqual(
            requests.map(\.id),
            NotificationSchedulePlanner.desiredRequests(
                snapshot: snapshot,
                now: now
            ).map(\.id)
        )
    }

    func testReconciliationCancelsStaleRequestsAfterResolution() throws {
        var snapshot = plannedSeed(
            referenceDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let block = try XCTUnwrap(
            snapshot.scheduleBlocks.first(where: { $0.missionID != nil })
        )
        let missionID = try XCTUnwrap(block.missionID)
        snapshot.missions = snapshot.missions.map { mission in
            var mission = mission
            mission.status = mission.id == missionID ? .planned : .completed
            return mission
        }
        snapshot.scheduleBlocks = [block]
        let now = block.start.addingTimeInterval(-60 * 60)
        let existing = NotificationSchedulePlanner.desiredRequests(
            snapshot: snapshot,
            now: now
        )

        _ = MissionExecution.resolve(
            snapshot: &snapshot,
            missionID: missionID,
            scheduleBlockID: block.id,
            status: .completed,
            at: block.end
        )
        let reconciliation = NotificationSchedulePlanner.reconciliation(
            snapshot: snapshot,
            existing: existing,
            now: now
        )

        XCTAssertEqual(
            reconciliation.identifiersToCancel,
            existing.map(\.id).sorted()
        )
        XCTAssertTrue(reconciliation.requestsToSchedule.isEmpty)
    }

    func testReconciliationReplacesChangedFireDate() throws {
        var snapshot = plannedSeed(
            referenceDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let source = try XCTUnwrap(
            snapshot.scheduleBlocks.first(where: { $0.missionID != nil })
        )
        let missionID = try XCTUnwrap(source.missionID)
        snapshot.missions = snapshot.missions.map { mission in
            var mission = mission
            mission.status = mission.id == missionID ? .planned : .completed
            return mission
        }
        snapshot.scheduleBlocks = [source]
        let now = source.start.addingTimeInterval(-60 * 60)
        let existing = NotificationSchedulePlanner.desiredRequests(
            snapshot: snapshot,
            now: now
        )
        snapshot.scheduleBlocks[0].start.addTimeInterval(10 * 60)
        snapshot.scheduleBlocks[0].end.addTimeInterval(10 * 60)

        let reconciliation = NotificationSchedulePlanner.reconciliation(
            snapshot: snapshot,
            existing: existing,
            now: now
        )

        XCTAssertEqual(reconciliation.identifiersToCancel.count, 4)
        XCTAssertEqual(reconciliation.requestsToSchedule.count, 4)
        XCTAssertEqual(
            reconciliation.requestsToSchedule.first(where: {
                $0.stage == .start
            })?.fireDate,
            source.start.addingTimeInterval(10 * 60)
        )
    }

    func testInProgressOccurrenceDoesNotSuppressLaterOccurrenceReminders() {
        let mission = Mission(
            category: .gym,
            title: "Repeated gym session",
            rigidity: .protected,
            estimatedDurationMinutes: 60,
            status: .inProgress
        )
        let active = ScheduleBlock(
            missionID: mission.id,
            title: mission.title,
            category: mission.category,
            kind: .mission,
            rigidity: mission.rigidity,
            start: Date(timeIntervalSince1970: 1_800_003_600),
            end: Date(timeIntervalSince1970: 1_800_007_200)
        )
        let future = ScheduleBlock(
            missionID: mission.id,
            title: mission.title,
            category: mission.category,
            kind: .mission,
            rigidity: mission.rigidity,
            start: Date(timeIntervalSince1970: 1_800_090_000),
            end: Date(timeIntervalSince1970: 1_800_093_600)
        )
        let snapshot = MissionControlSnapshot(
            profile: MissionControlSeed.makeDemo(
                referenceDate: active.start
            ).profile,
            missions: [mission],
            scheduleBlocks: [active, future],
            missionStartRecords: [
                MissionStartRecord(
                    missionID: mission.id,
                    scheduleBlockID: active.id,
                    actualStart: active.start,
                    reportedAt: active.start
                )
            ]
        )

        let requests = NotificationSchedulePlanner.desiredRequests(
            snapshot: snapshot,
            now: active.start
        )

        XCTAssertEqual(requests.count, 4)
        XCTAssertTrue(
            requests.allSatisfy {
                $0.scheduleBlockID == future.id
            }
        )
    }

    private func plannedSeed(referenceDate: Date) -> MissionControlSnapshot {
        var snapshot = MissionControlSeed.makeDemo(
            referenceDate: referenceDate
        )
        let result = SchedulingEngine().makePlan(
            input: PlanningInput(
                snapshot: snapshot,
                currentTime: referenceDate
            )
        )
        snapshot.applySchedulingResult(result)
        return snapshot
    }
}
