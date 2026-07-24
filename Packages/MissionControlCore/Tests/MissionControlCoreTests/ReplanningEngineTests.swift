import Foundation
import XCTest
@testable import MissionControlCore

final class ReplanningEngineTests: XCTestCase {
    private var morning: Date {
        localDate(2026, 7, 27, 8, 0)
    }

    func testLateWakeRemovesUnavailableMorningAndPreservesNextDayFixedEvent() throws {
        let first = mission("Priority focus", rigidity: .protected)
        let second = mission("Flexible follow-up")
        let tomorrow = FixedCommitment(
            title: "Tomorrow exact",
            category: .personal,
            start: localDate(2026, 7, 28, 15, 7),
            end: localDate(2026, 7, 28, 16, 11),
            isExternallyManaged: true
        )
        var snapshot = plannedSnapshot(
            missions: [first, second],
            fixedCommitments: [tomorrow]
        )
        let oldFixed = try XCTUnwrap(
            snapshot.scheduleBlocks.first(where: {
                $0.fixedCommitmentID == tomorrow.id
            })
        )
        let request = ReplanRequest(
            reason: .lateStart,
            requestedAt: localDate(2026, 7, 27, 8, 30),
            affectedStart: localDate(2026, 7, 27, 11, 0),
            affectedEnd: localDate(2026, 7, 28, 0, 0)
        )
        snapshot.replanRequests.append(request)

        let result = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [request]
        )

        let todayMissionBlocks = result.scheduleBlocks.filter {
            $0.kind == .mission
                && calendar.isDate($0.start, inSameDayAs: morning)
        }
        XCTAssertTrue(
            todayMissionBlocks.allSatisfy {
                $0.start >= localDate(2026, 7, 27, 11, 0)
            }
        )
        let newFixed = try XCTUnwrap(
            result.scheduleBlocks.first(where: {
                $0.fixedCommitmentID == tomorrow.id
            })
        )
        XCTAssertEqual(newFixed.id, oldFixed.id)
        XCTAssertEqual(newFixed.start, tomorrow.start)
        XCTAssertEqual(
            result.replanRequests.first(where: {
                $0.id == request.id
            })?.status,
            .applied
        )
    }

    func testLateActualStartPreservesInProgressWorkAndMovesOnlyCollision() throws {
        let active = mission("Active", rigidity: .protected)
        let later = mission("Later")
        var snapshot = plannedSnapshot(missions: [active, later])
        let activeBlock = try XCTUnwrap(block(active.id, in: snapshot))
        let laterBefore = try XCTUnwrap(block(later.id, in: snapshot))
        let actualStart = activeBlock.start.addingTimeInterval(20 * 60)
        _ = MissionExecution.markStarted(
            snapshot: &snapshot,
            missionID: active.id,
            actualStart: actualStart,
            reportedAt: actualStart
        )
        let request = ReplanRequest(
            reason: .actualStartCorrected,
            missionID: active.id,
            requestedAt: actualStart,
            affectedStart: actualStart,
            affectedEnd: localDate(2026, 7, 28, 0, 0)
        )
        snapshot.replanRequests.append(request)

        let result = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [request]
        )

        let preserved = try XCTUnwrap(block(active.id, in: result))
        let laterAfter = try XCTUnwrap(block(later.id, in: result))
        XCTAssertEqual(preserved.start, actualStart)
        XCTAssertEqual(
            result.mission(withID: active.id)?.status,
            .inProgress
        )
        XCTAssertGreaterThanOrEqual(laterAfter.start, preserved.end)
        XCTAssertNotEqual(laterAfter.start, laterBefore.start)
    }

    func testEarlyFinishFreezesActualHistoryAndAvoidsUnnecessaryMovement() throws {
        let first = mission("A first", rigidity: .protected)
        let second = mission("B second")
        var snapshot = plannedSnapshot(missions: [first, second])
        let firstBlock = try XCTUnwrap(block(first.id, in: snapshot))
        let secondBefore = try XCTUnwrap(block(second.id, in: snapshot))
        let actualEnd = firstBlock.end.addingTimeInterval(-20 * 60)
        _ = MissionExecution.markStarted(
            snapshot: &snapshot,
            missionID: first.id,
            actualStart: firstBlock.start,
            reportedAt: firstBlock.start
        )
        _ = MissionExecution.resolve(
            snapshot: &snapshot,
            missionID: first.id,
            scheduleBlockID: firstBlock.id,
            status: .completed,
            at: actualEnd
        )
        let request = ReplanRequest(
            reason: .taskFinishedEarly,
            missionID: first.id,
            requestedAt: actualEnd,
            affectedStart: actualEnd,
            affectedEnd: localDate(2026, 7, 28, 0, 0)
        )
        snapshot.replanRequests.append(request)

        let result = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [request]
        )

        let frozen = try XCTUnwrap(
            result.scheduleBlocks.first(where: { $0.id == firstBlock.id })
        )
        let secondAfter = try XCTUnwrap(block(second.id, in: result))
        XCTAssertEqual(frozen.end, actualEnd)
        XCTAssertEqual(secondAfter.start, secondBefore.start)
    }

    func testLateFinishMovesConflictingFutureBlock() throws {
        let first = mission("A first", rigidity: .protected)
        let second = mission("B second")
        var snapshot = plannedSnapshot(missions: [first, second])
        let firstBlock = try XCTUnwrap(block(first.id, in: snapshot))
        let secondBefore = try XCTUnwrap(block(second.id, in: snapshot))
        let actualEnd = firstBlock.end.addingTimeInterval(30 * 60)
        _ = MissionExecution.markStarted(
            snapshot: &snapshot,
            missionID: first.id,
            actualStart: firstBlock.start,
            reportedAt: firstBlock.start
        )
        _ = MissionExecution.resolve(
            snapshot: &snapshot,
            missionID: first.id,
            scheduleBlockID: firstBlock.id,
            status: .completed,
            at: actualEnd
        )
        let request = ReplanRequest(
            reason: .taskFinishedLate,
            missionID: first.id,
            requestedAt: actualEnd,
            affectedStart: actualEnd,
            affectedEnd: localDate(2026, 7, 28, 0, 0)
        )
        snapshot.replanRequests.append(request)

        let result = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [request]
        )

        let secondAfter = try XCTUnwrap(block(second.id, in: result))
        XCTAssertGreaterThanOrEqual(secondAfter.start, actualEnd)
        XCTAssertNotEqual(secondAfter.start, secondBefore.start)
    }

    func testUrgentTaskAddedTodayTakesPriorityWithoutOverlaps() throws {
        let existing = mission("Existing")
        var snapshot = plannedSnapshot(missions: [existing])
        let urgent = Mission(
            category: .personal,
            title: "Urgent today",
            rigidity: .protected,
            importance: .critical,
            urgency: .critical,
            deadline: localDate(2026, 7, 27, 18, 0),
            estimatedDurationMinutes: 45,
            backlogCost: .critical
        )
        snapshot.missions.append(urgent)
        let request = ReplanRequest(
            reason: .urgentTaskAdded,
            missionID: urgent.id,
            requestedAt: morning,
            affectedStart: morning,
            affectedEnd: localDate(2026, 7, 28, 0, 0)
        )
        snapshot.replanRequests.append(request)

        let result = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [request]
        )

        XCTAssertNotNil(block(urgent.id, in: result))
        assertNoOverlaps(result.scheduleBlocks)
    }

    func testUnconfirmedProtectedSkipIsRejectedAndExplained() throws {
        let protected = mission("Protected", rigidity: .protected)
        var snapshot = plannedSnapshot(missions: [protected])
        let original = try XCTUnwrap(block(protected.id, in: snapshot))
        if let index = snapshot.missions.firstIndex(where: {
            $0.id == protected.id
        }) {
            snapshot.missions[index].status = .skipped
        }
        let request = ReplanRequest(
            reason: .missionSkipped,
            missionID: protected.id,
            requestedAt: morning,
            affectedStart: morning,
            affectedEnd: localDate(2026, 7, 28, 0, 0),
            confirmationProvided: false
        )
        snapshot.replanRequests.append(request)

        let result = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [request]
        )

        XCTAssertEqual(result.mission(withID: protected.id)?.status, .planned)
        XCTAssertEqual(block(protected.id, in: result)?.id, original.id)
        XCTAssertTrue(
            result.schedulingDecisions.contains(where: {
                $0.missionID == protected.id
                    && $0.kind == .confirmationRequired
                    && $0.requiresConfirmation
            })
        )
        XCTAssertEqual(
            result.replanRequests.first(where: {
                $0.id == request.id
            })?.status,
            .pending
        )
    }

    func testConfirmedProtectedSkipRemovesMissionBlock() throws {
        let protected = mission("Protected", rigidity: .protected)
        var snapshot = plannedSnapshot(missions: [protected])
        if let index = snapshot.missions.firstIndex(where: {
            $0.id == protected.id
        }) {
            snapshot.missions[index].status = .skipped
        }
        let request = ReplanRequest(
            reason: .missionSkipped,
            missionID: protected.id,
            requestedAt: morning,
            affectedStart: morning,
            affectedEnd: localDate(2026, 7, 28, 0, 0),
            confirmationProvided: true
        )
        snapshot.replanRequests.append(request)

        let result = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [request]
        )

        XCTAssertNil(block(protected.id, in: result))
        XCTAssertEqual(result.mission(withID: protected.id)?.status, .skipped)
    }

    func testConfirmedSkipWithPhaseFourHistoryRemovesFutureBlock() throws {
        let protected = mission("Protected", rigidity: .protected)
        var snapshot = plannedSnapshot(missions: [protected])
        let original = try XCTUnwrap(block(protected.id, in: snapshot))
        let skippedAt = original.start
        _ = MissionExecution.resolve(
            snapshot: &snapshot,
            missionID: protected.id,
            scheduleBlockID: original.id,
            status: .skipped,
            at: skippedAt,
            reason: "Confirmed skip"
        )
        let request = ReplanRequest(
            reason: .missionSkipped,
            missionID: protected.id,
            requestedAt: skippedAt,
            affectedStart: skippedAt,
            affectedEnd: localDate(2026, 7, 28, 0, 0),
            confirmationProvided: true
        )
        snapshot.replanRequests.append(request)

        let result = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [request]
        )

        XCTAssertFalse(
            result.scheduleBlocks.contains(where: {
                $0.id == original.id && $0.end > skippedAt
            })
        )
        XCTAssertEqual(
            result.completions.first(where: {
                $0.scheduleBlockID == original.id
            })?.status,
            .skipped
        )
    }

    func testMoveTomorrowAndWeeklyBacklogRemainDistinct() throws {
        let tomorrowMission = mission("Tomorrow")
        let backlogMission = mission("Backlog")
        var snapshot = plannedSnapshot(
            missions: [tomorrowMission, backlogMission]
        )
        let tomorrowBlock = try XCTUnwrap(
            block(tomorrowMission.id, in: snapshot)
        )
        let backlogBlock = try XCTUnwrap(
            block(backlogMission.id, in: snapshot)
        )
        let decisionTime = min(tomorrowBlock.start, backlogBlock.start)
        for (mission, sourceBlock, disposition) in [
            (
                tomorrowMission,
                tomorrowBlock,
                UnresolvedMissionDisposition.moveToTomorrow
            ),
            (
                backlogMission,
                backlogBlock,
                UnresolvedMissionDisposition.weeklyBacklog
            )
        ] {
            _ = MissionExecution.resolve(
                snapshot: &snapshot,
                missionID: mission.id,
                scheduleBlockID: sourceBlock.id,
                status: .skipped,
                at: decisionTime,
                reason: disposition.displayName
            )
            snapshot.unresolvedDispositions.append(
                UnresolvedDispositionRecord(
                    missionID: mission.id,
                    scheduleBlockID: sourceBlock.id,
                    disposition: disposition,
                    decidedAt: decisionTime
                )
            )
            if let index = snapshot.missions.firstIndex(where: {
                $0.id == mission.id
            }) {
                snapshot.missions[index].status = .planned
            }
        }
        let requests = [
            ReplanRequest(
                reason: .movedToTomorrow,
                missionID: tomorrowMission.id,
                requestedAt: decisionTime,
                affectedStart: decisionTime,
                affectedEnd: localDate(2026, 7, 29, 0, 0)
            ),
            ReplanRequest(
                reason: .returnedToBacklog,
                missionID: backlogMission.id,
                requestedAt: decisionTime,
                affectedStart: decisionTime,
                affectedEnd: localDate(2026, 7, 29, 0, 0)
            )
        ]
        snapshot.replanRequests.append(contentsOf: requests)

        let result = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: requests
        )

        let moved = try XCTUnwrap(block(tomorrowMission.id, in: result))
        XCTAssertTrue(
            calendar.isDate(
                moved.start,
                inSameDayAs: localDate(2026, 7, 28, 12, 0)
            )
        )
        XCTAssertNil(block(backlogMission.id, in: result))
        XCTAssertEqual(
            result.mission(withID: backlogMission.id)?.status,
            .planned
        )
    }

    func testStartingOneRepeatedMissionBlockDoesNotMoveEveryOccurrence() throws {
        let repeated = mission("Repeated", rigidity: .protected)
        let first = ScheduleBlock(
            missionID: repeated.id,
            title: repeated.title,
            category: repeated.category,
            kind: .mission,
            rigidity: repeated.rigidity,
            start: localDate(2026, 7, 27, 9, 0),
            end: localDate(2026, 7, 27, 10, 0)
        )
        let future = ScheduleBlock(
            missionID: repeated.id,
            title: repeated.title,
            category: repeated.category,
            kind: .mission,
            rigidity: repeated.rigidity,
            start: localDate(2026, 7, 28, 9, 0),
            end: localDate(2026, 7, 28, 10, 0)
        )
        var snapshot = MissionControlSnapshot(
            profile: profile,
            missions: [repeated],
            scheduleBlocks: [first, future]
        )
        let actualStart = localDate(2026, 7, 27, 9, 20)
        _ = MissionExecution.markStarted(
            snapshot: &snapshot,
            missionID: repeated.id,
            scheduleBlockID: first.id,
            actualStart: actualStart,
            reportedAt: actualStart
        )
        let request = ReplanRequest(
            reason: .actualStartCorrected,
            missionID: repeated.id,
            requestedAt: actualStart,
            affectedStart: actualStart,
            affectedEnd: localDate(2026, 7, 28, 0, 0)
        )
        snapshot.replanRequests.append(request)

        let result = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [request]
        )

        XCTAssertEqual(
            result.scheduleBlocks.first(where: { $0.id == first.id })?.start,
            actualStart
        )
        XCTAssertEqual(
            result.scheduleBlocks.first(where: { $0.id == future.id })?.start,
            future.start
        )
        assertNoOverlaps(result.scheduleBlocks)
    }

    func testFixedEventAddedKeepsExactTimeAndMovesOnlyCollision() throws {
        let mission = self.mission("Flexible")
        var snapshot = plannedSnapshot(missions: [mission])
        let before = try XCTUnwrap(block(mission.id, in: snapshot))
        let fixed = FixedCommitment(
            title: "New exact event",
            category: .personal,
            start: before.start.addingTimeInterval(15 * 60),
            end: before.end.addingTimeInterval(30 * 60)
        )
        snapshot.fixedCommitments.append(fixed)
        let request = ReplanRequest(
            reason: .fixedCommitmentAdded,
            requestedAt: morning,
            affectedStart: fixed.start,
            affectedEnd: localDate(2026, 7, 28, 0, 0)
        )
        snapshot.replanRequests.append(request)

        let result = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [request]
        )

        let exact = try XCTUnwrap(
            result.scheduleBlocks.first(where: {
                $0.fixedCommitmentID == fixed.id
            })
        )
        let after = try XCTUnwrap(block(mission.id, in: result))
        XCTAssertEqual(exact.start, fixed.start)
        XCTAssertEqual(exact.end, fixed.end)
        XCTAssertFalse(
            overlaps(after.start, after.end, exact.start, exact.end)
        )
    }

    func testChangedFixedEventReplacesOldExactInterval() throws {
        var fixed = FixedCommitment(
            title: "Exact appointment",
            category: .personal,
            start: localDate(2026, 7, 27, 14, 7),
            end: localDate(2026, 7, 27, 15, 11),
            isExternallyManaged: true
        )
        var snapshot = plannedSnapshot(
            missions: [mission("Flexible")],
            fixedCommitments: [fixed]
        )
        let oldStart = fixed.start
        fixed.start = localDate(2026, 7, 27, 16, 13)
        fixed.end = localDate(2026, 7, 27, 17, 19)
        snapshot.fixedCommitments = [fixed]
        let request = ReplanRequest(
            reason: .fixedCommitmentChanged,
            requestedAt: morning,
            affectedStart: oldStart,
            affectedEnd: localDate(2026, 7, 28, 0, 0)
        )
        snapshot.replanRequests.append(request)

        let result = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [request]
        )
        let exact = try XCTUnwrap(
            result.scheduleBlocks.first(where: {
                $0.fixedCommitmentID == fixed.id
            })
        )

        XCTAssertEqual(exact.start, fixed.start)
        XCTAssertEqual(exact.end, fixed.end)
        XCTAssertNotEqual(exact.start, oldStart)
        XCTAssertTrue(exact.isImmutable)
    }

    func testRaisedProjectPriorityReordersOnlyRelevantWork() throws {
        let maintainedProject = Project(
            title: "Maintained",
            status: .maintained
        )
        var raisedProject = Project(
            title: "Raised",
            status: .backlog
        )
        let maintained = Mission(
            projectID: maintainedProject.id,
            category: .project,
            title: "A maintained",
            rigidity: .flexible,
            estimatedDurationMinutes: 60
        )
        let raised = Mission(
            projectID: raisedProject.id,
            category: .project,
            title: "Z raised",
            rigidity: .flexible,
            estimatedDurationMinutes: 60
        )
        var snapshot = plannedSnapshot(
            projects: [maintainedProject, raisedProject],
            missions: [maintained, raised]
        )
        raisedProject.status = .activePriority
        raisedProject.priorityOverride = .critical
        snapshot.updateProject(raisedProject)
        if let index = snapshot.missions.firstIndex(where: {
            $0.id == raised.id
        }) {
            snapshot.missions[index].userPriorityOverride = .critical
        }
        let request = ReplanRequest(
            reason: .projectPriorityRaised,
            missionID: raised.id,
            requestedAt: morning,
            affectedStart: morning,
            affectedEnd: localDate(2026, 7, 28, 0, 0)
        )
        snapshot.replanRequests.append(request)

        let result = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [request]
        )

        let raisedBlock = try XCTUnwrap(block(raised.id, in: result))
        let maintainedBlock = try XCTUnwrap(block(maintained.id, in: result))
        XCTAssertLessThan(raisedBlock.start, maintainedBlock.start)
    }

    func testPainAndFoodDeficitStructuredFixturesUpdatePlan() throws {
        let physical = Mission(
            category: .gym,
            title: "Hamstring session",
            rigidity: .protected,
            estimatedDurationMinutes: 60,
            physicalLoad: .heavy,
            bodyAreaTags: ["hamstring"]
        )
        var snapshot = plannedSnapshot(missions: [physical])
        snapshot.painFlags.append(
            PainFlag(
                bodyArea: "hamstring",
                reportedAt: morning,
                note: "Structured fixture"
            )
        )
        snapshot.nutritionPlanningNeeds = [
            NutritionPlanningNeed(
                localDay: calendar.startOfDay(for: morning),
                substantialMealsRequired: 1,
                substantialMealsCovered: 1,
                clearDeficit: true
            )
        ]
        let painRequest = ReplanRequest(
            reason: .painReported,
            missionID: physical.id,
            requestedAt: morning,
            affectedStart: morning,
            affectedEnd: localDate(2026, 7, 28, 0, 0)
        )
        let foodRequest = ReplanRequest(
            reason: .foodDeficit,
            requestedAt: morning,
            affectedStart: morning,
            affectedEnd: localDate(2026, 7, 28, 0, 0)
        )
        snapshot.replanRequests.append(contentsOf: [
            painRequest,
            foodRequest
        ])

        let result = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [painRequest, foodRequest]
        )

        XCTAssertNil(block(physical.id, in: result))
        XCTAssertTrue(
            result.scheduleBlocks.contains(where: {
                $0.kind == .meal && $0.title.contains("food deficit")
            })
        )
    }

    func testRepeatedMissFeedbackMovesTargetButPreservesUnaffectedBlocks() throws {
        let first = mission("A stable")
        let target = mission("B target")
        let third = mission("C stable")
        var snapshot = plannedSnapshot(missions: [first, target, third])
        let firstBefore = try XCTUnwrap(block(first.id, in: snapshot))
        let targetBefore = try XCTUnwrap(block(target.id, in: snapshot))
        let thirdBefore = try XCTUnwrap(block(third.id, in: snapshot))
        snapshot.missDiagnostics.append(
            MissionMissDiagnosticRecord(
                missionID: target.id,
                category: target.category,
                cause: .badTiming,
                recordedAt: morning
            )
        )
        let request = ReplanRequest(
            reason: .repeatedMiss,
            missionID: target.id,
            requestedAt: morning,
            affectedStart: morning,
            affectedEnd: localDate(2026, 7, 28, 0, 0)
        )
        snapshot.replanRequests.append(request)

        let result = try ReplanningEngine().replan(
            snapshot: snapshot,
            requests: [request]
        )

        XCTAssertEqual(block(first.id, in: result)?.start, firstBefore.start)
        XCTAssertEqual(block(third.id, in: result)?.start, thirdBefore.start)
        XCTAssertNotEqual(block(target.id, in: result)?.start, targetBefore.start)
        XCTAssertTrue(
            result.schedulingDecisions.contains(where: {
                $0.rule == .repeatedMissFeedback
            })
        )
    }

    private func plannedSnapshot(
        projects: [Project] = [],
        missions: [Mission],
        fixedCommitments: [FixedCommitment] = []
    ) -> MissionControlSnapshot {
        var snapshot = MissionControlSnapshot(
            profile: profile,
            projects: projects,
            missions: missions,
            fixedCommitments: fixedCommitments
        )
        let result = SchedulingEngine().makePlan(
            input: PlanningInput(
                snapshot: snapshot,
                currentTime: morning
            )
        )
        snapshot.applySchedulingResult(result)
        return snapshot
    }

    private func mission(
        _ title: String,
        rigidity: MissionRigidity = .flexible
    ) -> Mission {
        Mission(
            category: .personal,
            title: title,
            rigidity: rigidity,
            importance: rigidity == .protected ? .high : .normal,
            estimatedDurationMinutes: 60
        )
    }

    private func block(
        _ missionID: EntityID,
        in snapshot: MissionControlSnapshot
    ) -> ScheduleBlock? {
        snapshot.scheduleBlocks.first(where: {
            $0.missionID == missionID && $0.kind == .mission
        })
    }

    private var profile: UserProfile {
        var profile = MissionControlSeed.makeDemo(
            referenceDate: morning
        ).profile
        profile.nutritionTargets.substantialMeals = 0
        return profile
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func localDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private func assertNoOverlaps(
        _ source: [ScheduleBlock],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sorted = source.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.end < $1.end
        }
        for pair in zip(sorted, sorted.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                pair.1.start,
                pair.0.end,
                file: file,
                line: line
            )
        }
    }

    private func overlaps(
        _ leftStart: Date,
        _ leftEnd: Date,
        _ rightStart: Date,
        _ rightEnd: Date
    ) -> Bool {
        leftStart < rightEnd && rightStart < leftEnd
    }
}
