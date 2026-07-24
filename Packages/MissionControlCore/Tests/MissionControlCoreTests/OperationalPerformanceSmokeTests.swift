import Foundation
import XCTest
@testable import MissionControlCore

final class OperationalPerformanceSmokeTests: XCTestCase {
    func testTypicalWeekRepeatedPlanningIsStableAndBounded() {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = MissionControlSeed.makeDemo(
            referenceDate: referenceDate
        )
        let engine = SchedulingEngine()
        snapshot.applySchedulingResult(
            engine.makePlan(
                input: PlanningInput(
                    snapshot: snapshot,
                    currentTime: referenceDate
                )
            )
        )
        let expectedBlockIDs = Set(snapshot.scheduleBlocks.map(\.id))
        let startedAt = Date()

        for _ in 0..<25 {
            let result = engine.makePlan(
                input: PlanningInput(
                    snapshot: snapshot,
                    currentTime: referenceDate
                )
            )
            XCTAssertEqual(Set(result.blocks.map(\.id)), expectedBlockIDs)
            XCTAssertEqual(Set(result.blocks.map(\.id)).count, result.blocks.count)
            snapshot.applySchedulingResult(result)
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        print("PERF_METRIC typical_week_replans_25_seconds=\(elapsed)")
        XCTAssertLessThan(elapsed, 30)
    }

    func testLargeBacklogPlanningHasNoDuplicateOrOverlappingBlocks() {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = MissionControlSeed.makeDemo(
            referenceDate: referenceDate
        )
        snapshot.missions.append(
            contentsOf: (0..<200).map { index in
                Mission(
                    category: .project,
                    title: "Synthetic backlog item \(index)",
                    rigidity: .flexible,
                    importance: .normal,
                    urgency: .normal,
                    estimatedDurationMinutes: 30
                )
            }
        )
        let startedAt = Date()
        let result = SchedulingEngine().makePlan(
            input: PlanningInput(
                snapshot: snapshot,
                currentTime: referenceDate
            )
        )
        let elapsed = Date().timeIntervalSince(startedAt)
        let sorted = result.blocks.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.end < $1.end
        }

        XCTAssertEqual(Set(result.blocks.map(\.id)).count, result.blocks.count)
        for pair in zip(sorted, sorted.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1.start, pair.0.end)
        }
        print(
            "PERF_METRIC large_backlog_200_seconds=\(elapsed) "
                + "blocks=\(result.blocks.count) "
                + "unscheduled=\(result.unscheduledMissionIDs.count)"
        )
        XCTAssertLessThan(elapsed, 30)
    }

    func testRepresentativeSnapshotSerializationIsStableAndBounded() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = MissionControlSeed.makeDemo(
            referenceDate: referenceDate
        )
        snapshot.applySchedulingResult(
            SchedulingEngine().makePlan(
                input: PlanningInput(
                    snapshot: snapshot,
                    currentTime: referenceDate
                )
            )
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var decoded = snapshot
        let startedAt = Date()

        for _ in 0..<100 {
            let data = try encoder.encode(decoded)
            decoded = try decoder.decode(
                MissionControlSnapshot.self,
                from: data
            )
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        XCTAssertEqual(decoded, snapshot)
        print(
            "PERF_METRIC snapshot_round_trips_100_seconds=\(elapsed)"
        )
        XCTAssertLessThan(elapsed, 30)
    }
}
