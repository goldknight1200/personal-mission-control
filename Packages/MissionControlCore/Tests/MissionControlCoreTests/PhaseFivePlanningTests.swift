import Foundation
import XCTest
@testable import MissionControlCore

final class PhaseFivePlanningTests: XCTestCase {
    func testBatchShiftParserReadsSeveralFlexibleRanges() throws {
        let reference = try date(2026, 7, 25, 12, 0)
        let result = WorkShiftBatchParser().parse(
            "3 Aug 9-5; 5 Aug 10:00-18:00\n8 August 12pm–8pm",
            title: "Supermarket shift",
            location: "Lidl",
            referenceDate: reference,
            timeZoneIdentifier: "Europe/Berlin"
        )

        XCTAssertEqual(result.entries.count, 3)
        XCTAssertNil(result.unparsedInput)
        XCTAssertEqual(hour(result.entries[0].payload.start), 9)
        XCTAssertEqual(hour(result.entries[0].payload.end), 17)
        XCTAssertEqual(hour(result.entries[1].payload.end), 18)
        XCTAssertEqual(hour(result.entries[2].payload.start), 12)
        XCTAssertEqual(hour(result.entries[2].payload.end), 20)
        XCTAssertEqual(result.entries[0].payload.location, "Lidl")
    }

    func testBatchShiftParserMarksChangeAndConflicts() throws {
        let reference = try date(2026, 7, 25, 12, 0)
        let existing = FixedCommitment(
            title: "Work shift",
            category: .work,
            start: try date(2026, 8, 3, 9, 0),
            end: try date(2026, 8, 3, 17, 0)
        )
        let result = WorkShiftBatchParser().parse(
            "3 Aug 09:00-18:00; 3 Aug 17:30-20:00",
            referenceDate: reference,
            timeZoneIdentifier: "Europe/Berlin",
            existingCommitments: [existing]
        )

        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(
            result.entries.first?.existingCommitmentID,
            existing.id
        )
        XCTAssertTrue(result.entries.first?.isChange == true)
        XCTAssertTrue(
            result.entries.allSatisfy { !$0.warnings.isEmpty }
        )
    }

    func testShoppingItemsBecomeGroceriesMissionChecklist() throws {
        let reference = try date(2026, 7, 27, 8, 0)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: reference)
        let pending = try XCTUnwrap(
            snapshot.checklist(ofKind: .shopping)?.items.filter {
                !$0.isCompleted
            }
        )
        let result = SchedulingEngine().makePlan(
            input: PlanningInput(snapshot: snapshot, currentTime: reference)
        )
        snapshot.applySchedulingResult(result)

        let groceries = try XCTUnwrap(
            snapshot.missions.first(where: { $0.title == "Groceries" })
        )
        XCTAssertEqual(
            Set(groceries.miniGoals.map(\.id)),
            Set(pending.map(\.id))
        )

        let first = try XCTUnwrap(groceries.miniGoals.first)
        snapshot.toggleMissionStep(
            missionID: groceries.id,
            stepID: first.id
        )
        XCTAssertEqual(
            snapshot.checklist(ofKind: .shopping)?
                .items.first(where: { $0.id == first.id })?
                .isCompleted,
            true
        )
    }

    func testGroceriesCanFollowSupermarketShiftWithoutSeparateReturnTrip() throws {
        let reference = try date(2026, 7, 27, 8, 0)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: reference)
        let shift = FixedCommitment(
            title: "Supermarket shift",
            category: .work,
            start: try date(2026, 7, 27, 9, 0),
            end: try date(2026, 7, 27, 15, 0),
            location: "Lidl",
            contextTags: ["supermarket"]
        )
        snapshot.fixedCommitments.append(shift)

        let result = SchedulingEngine().makePlan(
            input: PlanningInput(snapshot: snapshot, currentTime: reference)
        )
        let groceries = try XCTUnwrap(
            result.blocks.first(where: {
                $0.title == "Groceries" && $0.kind == .mission
            })
        )

        XCTAssertEqual(groceries.start, shift.end)
        XCTAssertFalse(
            result.blocks.contains(where: {
                $0.title == "Travel after Supermarket shift"
            })
        )
        XCTAssertTrue(
            result.decisions.contains(where: {
                $0.scheduleBlockID == groceries.id
                    && $0.explanation.contains("supermarket work shift")
            })
        )
    }

    func testProjectWeeklyProgressAndRepeatedSkipReassessment() throws {
        let reference = try date(2026, 7, 29, 12, 0)
        var snapshot = MissionControlSeed.makeDemo(referenceDate: reference)
        let project = try XCTUnwrap(snapshot.projects.first)
        let mission = try XCTUnwrap(
            snapshot.missions.first(where: { $0.projectID == project.id })
        )
        snapshot.scheduleBlocks = [
            ScheduleBlock(
                missionID: mission.id,
                title: mission.title,
                category: .project,
                kind: .mission,
                rigidity: .flexible,
                start: try date(2026, 7, 29, 13, 0),
                end: try date(2026, 7, 29, 14, 30)
            )
        ]
        snapshot.completions = [
            CompletionRecord(
                missionID: mission.id,
                completedAt: try date(2026, 7, 27, 12, 0),
                plannedDurationMinutes: 60,
                actualDurationMinutes: 45
            ),
            skipped(mission.id, at: try date(2026, 7, 28, 12, 0)),
            skipped(mission.id, at: try date(2026, 7, 29, 9, 0)),
            skipped(mission.id, at: try date(2026, 7, 29, 10, 0))
        ]

        let progress = try XCTUnwrap(
            ProjectPlanningAnalytics.weeklyProgress(
                projectID: project.id,
                snapshot: snapshot,
                containing: reference
            )
        )
        XCTAssertEqual(progress.targetMinutes, 360)
        XCTAssertEqual(progress.scheduledMinutes, 90)
        XCTAssertEqual(progress.actualMinutes, 45)

        let reassessment = try XCTUnwrap(
            ProjectPlanningAnalytics.reassessment(
                projectID: project.id,
                snapshot: snapshot,
                at: reference
            )
        )
        XCTAssertEqual(reassessment.recentSkipCount, 3)
    }

    func testWeeklyProjectTargetCreatesDeliberateExposureWithoutDailyRule() throws {
        let reference = try date(2026, 7, 27, 8, 0)
        let seed = MissionControlSeed.makeDemo(referenceDate: reference)
        let project = Project(
            title: "Maintained writing",
            status: .maintained,
            weeklyPlannedMinutes: 3 * 60
        )
        let mission = Mission(
            projectID: project.id,
            category: .project,
            title: "Write",
            rigidity: .flexible,
            estimatedDurationMinutes: 60,
            minimumUsefulBlockMinutes: 30
        )
        let input = PlanningInput(
            currentTime: reference,
            profile: seed.profile,
            fixedCommitments: [],
            goals: [],
            projects: [project],
            missions: [mission],
            routines: []
        )
        let result = SchedulingEngine().makePlan(input: input)
        let blocks = result.blocks.filter {
            $0.missionID == mission.id && $0.kind == .mission
        }

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks.map(\.durationMinutes).reduce(0, +), 180)
        XCTAssertLessThanOrEqual(
            Set(blocks.map { Calendar.current.startOfDay(for: $0.start) }).count,
            3
        )
    }

    func testBacklogProjectHasNoAutomaticExposure() throws {
        let reference = try date(2026, 7, 27, 8, 0)
        let seed = MissionControlSeed.makeDemo(referenceDate: reference)
        let project = Project(
            title: "Someday",
            status: .backlog,
            weeklyPlannedMinutes: 120
        )
        let mission = Mission(
            projectID: project.id,
            category: .project,
            title: "Backlog work",
            rigidity: .flexible,
            estimatedDurationMinutes: 60
        )
        let result = SchedulingEngine().makePlan(
            input: PlanningInput(
                currentTime: reference,
                profile: seed.profile,
                fixedCommitments: [],
                goals: [],
                projects: [project],
                missions: [mission],
                routines: []
            )
        )

        XCTAssertFalse(
            result.blocks.contains(where: { $0.missionID == mission.id })
        )
        XCTAssertTrue(result.unscheduledMissionIDs.contains(mission.id))
    }

    func testManualOccurrenceAdjustmentRemainsLockedDuringPlanning() throws {
        let reference = try date(2026, 7, 27, 8, 0)
        let profile = MissionControlSeed.makeDemo(
            referenceDate: reference
        ).profile
        let mission = Mission(
            category: .personal,
            title: "Call family",
            rigidity: .flexible,
            estimatedDurationMinutes: 30
        )
        let adjusted = ScheduleBlock(
            missionID: mission.id,
            title: mission.title,
            category: mission.category,
            kind: .mission,
            rigidity: mission.rigidity,
            start: try date(2026, 7, 28, 14, 0),
            end: try date(2026, 7, 28, 14, 30)
        )
        let snapshot = MissionControlSnapshot(
            profile: profile,
            missions: [mission],
            manualScheduleAdjustments: [
                ManualScheduleAdjustment(
                    block: adjusted,
                    createdAt: reference
                )
            ]
        )

        let result = SchedulingEngine().makePlan(
            input: PlanningInput(snapshot: snapshot, currentTime: reference)
        )

        XCTAssertEqual(
            result.blocks.first(where: { $0.id == adjusted.id }),
            adjusted
        )
        XCTAssertEqual(
            result.blocks.filter {
                $0.missionID == mission.id && $0.kind == .mission
            }.count,
            1
        )
    }

    private func skipped(
        _ missionID: EntityID,
        at date: Date
    ) -> CompletionRecord {
        CompletionRecord(
            missionID: missionID,
            status: .skipped,
            completedAt: date,
            plannedDurationMinutes: 60,
            actualDurationMinutes: 0
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                )
            )
        )
    }

    private func hour(_ date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar.component(.hour, from: date)
    }
}
