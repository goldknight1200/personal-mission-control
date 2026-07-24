import Foundation
import XCTest
@testable import MissionControlCore

final class ReflectionConsistencyTests: XCTestCase {
    func testEveningSummaryRequiresDecisionsOnlyForUnresolvedPastBlocks() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        let mission = try XCTUnwrap(snapshot.missions.first)
        let unresolvedBlock = ScheduleBlock(
            missionID: mission.id,
            title: mission.title,
            category: mission.category,
            kind: .mission,
            rigidity: mission.rigidity,
            start: now.addingTimeInterval(-120 * 60),
            end: now.addingTimeInterval(-60 * 60)
        )
        snapshot.scheduleBlocks = [unresolvedBlock]
        snapshot.missions[0].status = .planned
        snapshot.completions = []

        let summary = DailyReflection.eveningSummary(
            snapshot: snapshot,
            at: now
        )

        XCTAssertEqual(summary.unresolvedBlocks.map(\.id), [unresolvedBlock.id])
        XCTAssertEqual(summary.completedCount, 0)

        _ = MissionExecution.resolve(
            snapshot: &snapshot,
            missionID: mission.id,
            scheduleBlockID: unresolvedBlock.id,
            status: .partial,
            at: now,
            actualDurationMinutes: 25
        )
        let resolved = DailyReflection.eveningSummary(
            snapshot: snapshot,
            at: now
        )
        XCTAssertTrue(resolved.unresolvedBlocks.isEmpty)
        XCTAssertEqual(resolved.partialCount, 1)
    }

    func testRepeatedMissDiagnosticTriggersAtThresholdAndRespectsClassification() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        let mission = try XCTUnwrap(snapshot.missions.first)
        snapshot.completions = (1...3).map { day in
            CompletionRecord(
                missionID: mission.id,
                status: .skipped,
                completedAt: now.addingTimeInterval(-TimeInterval(day * 86_400)),
                plannedDurationMinutes: 60,
                actualDurationMinutes: 0
            )
        }

        let diagnostic = RepeatedMissAnalyzer.diagnostic(
            snapshot: snapshot,
            missionID: mission.id,
            at: now
        )
        XCTAssertEqual(diagnostic?.recentMissCount, 3)

        snapshot.missDiagnostics.append(
            MissionMissDiagnosticRecord(
                missionID: mission.id,
                category: mission.category,
                cause: .badTiming,
                recordedAt: now
            )
        )
        XCTAssertNil(
            RepeatedMissAnalyzer.diagnostic(
                snapshot: snapshot,
                missionID: mission.id,
                at: now
            )
        )

        let block = ScheduleBlock(
            missionID: mission.id,
            title: mission.title,
            category: mission.category,
            kind: .mission,
            rigidity: mission.rigidity,
            start: now.addingTimeInterval(60 * 60),
            end: now.addingTimeInterval(120 * 60)
        )
        let proposal = MissionRecoveryPlanner.proposal(
            mission: mission,
            block: block,
            snapshot: snapshot
        )
        XCTAssertTrue(
            proposal.alternatives.contains(where: {
                $0.recommendation == MissionMissCause.badTiming.recommendation
            })
        )
    }

    func testWeeklyAggregationTracksRequiredConsistencySignals() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        let football = Mission(
            category: .football,
            title: "Football",
            rigidity: .fixed,
            estimatedDurationMinutes: 90
        )
        let gym = Mission(
            category: .gym,
            title: "Gym",
            rigidity: .flexible,
            estimatedDurationMinutes: 60
        )
        let project = Mission(
            category: .project,
            title: "Project",
            rigidity: .protected,
            estimatedDurationMinutes: 120
        )
        snapshot.missions = [football, gym, project]
        snapshot.fixedCommitments = []
        snapshot.scheduleBlocks = [
            block(football, start: now.addingTimeInterval(-3_600), minutes: 90),
            block(gym, start: now.addingTimeInterval(-1_800), minutes: 60),
            block(project, start: now, minutes: 120)
        ]
        snapshot.completions = [
            record(football, at: now, actual: 90),
            record(gym, at: now, actual: 55),
            record(project, at: now, actual: 100)
        ]
        snapshot.dailyCheckIns = [
            DailyCheckIn(
                kind: .evening,
                recordedAt: now,
                sleepDurationMinutes: 470,
                nutritionTargetMet: true
            )
        ]

        let summary = WeeklyConsistencyAggregator.summarize(
            snapshot: snapshot,
            containing: now
        )

        XCTAssertEqual(summary.footballCompleted, 1)
        XCTAssertEqual(summary.footballPlanned, 1)
        XCTAssertEqual(summary.gymCompleted, 1)
        XCTAssertEqual(summary.projectActualMinutes, 100)
        XCTAssertEqual(summary.projectPlannedMinutes, 120)
        XCTAssertEqual(summary.nutritionTargetDays, 1)
        XCTAssertEqual(summary.sleepTargetNights, 1)
    }

    private func block(
        _ mission: Mission,
        start: Date,
        minutes: Int
    ) -> ScheduleBlock {
        ScheduleBlock(
            missionID: mission.id,
            title: mission.title,
            category: mission.category,
            kind: .mission,
            rigidity: mission.rigidity,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60))
        )
    }

    private func record(
        _ mission: Mission,
        at date: Date,
        actual: Int
    ) -> CompletionRecord {
        CompletionRecord(
            missionID: mission.id,
            status: .completed,
            completedAt: date,
            actualStart: date.addingTimeInterval(-TimeInterval(actual * 60)),
            plannedDurationMinutes: mission.estimatedDurationMinutes,
            actualDurationMinutes: actual
        )
    }
}
