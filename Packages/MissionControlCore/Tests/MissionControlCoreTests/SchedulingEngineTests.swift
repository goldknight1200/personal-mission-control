import Foundation
import XCTest
@testable import MissionControlCore

final class SchedulingEngineTests: XCTestCase {
    private var current: Date {
        localDate(2026, 7, 27, 8, 0) // Monday
    }

    func testSevenDayPlanHasNoOverlapsPreservesExactFixedTimeAndUsesGrid() throws {
        let fixed = FixedCommitment(
            title: "Exact imported shift",
            category: .work,
            start: localDate(2026, 7, 27, 10, 7),
            end: localDate(2026, 7, 27, 11, 13),
            externalIdentifier: "fixture-1",
            isExternallyManaged: true
        )
        let mission = Mission(
            category: .personal,
            title: "Flexible admin",
            rigidity: .flexible,
            estimatedDurationMinutes: 40
        )

        let result = SchedulingEngine().makePlan(
            input: makeInput(
                missions: [mission],
                fixedCommitments: [fixed]
            )
        )

        XCTAssertEqual(
            result.metadata.horizonEnd.timeIntervalSince(
                result.metadata.horizonStart
            ),
            7 * 24 * 60 * 60,
            accuracy: 60 * 60
        )
        let fixedBlock = try XCTUnwrap(
            result.blocks.first(where: {
                $0.fixedCommitmentID == fixed.id
            })
        )
        XCTAssertEqual(fixedBlock.start, fixed.start)
        XCTAssertEqual(fixedBlock.end, fixed.end)
        XCTAssertTrue(fixedBlock.isImmutable)

        let flexible = try XCTUnwrap(
            result.blocks.first(where: { $0.missionID == mission.id })
        )
        let components = calendar.dateComponents(
            [.minute],
            from: flexible.start
        )
        XCTAssertEqual((components.minute ?? -1) % 5, 0)
        assertNoOverlaps(result.blocks)
    }

    func testIdenticalStructuredInputProducesIdenticalPlanAndTrace() {
        let mission = Mission(
            category: .project,
            title: "Deterministic focus",
            rigidity: .protected,
            estimatedDurationMinutes: 60
        )
        let input = makeInput(missions: [mission])

        let first = SchedulingEngine().makePlan(input: input)
        let second = SchedulingEngine().makePlan(input: input)

        XCTAssertEqual(first, second)
    }

    func testMissionPreparationTravelAndRecoveryAreContiguous() throws {
        let mission = Mission(
            category: .gym,
            title: "Approved lower session",
            rigidity: .protected,
            estimatedDurationMinutes: 60,
            physicalLoad: .moderate,
            preparationMinutes: 8,
            travelBeforeMinutes: 16,
            travelAfterMinutes: 16
        )

        let result = SchedulingEngine().makePlan(
            input: makeInput(missions: [mission])
        )
        let missionBlock = try XCTUnwrap(
            result.blocks.first(where: { $0.missionID == mission.id })
        )
        let related = result.blocks.filter {
            $0.start >= missionBlock.start.addingTimeInterval(-24 * 60)
                && $0.end <= missionBlock.end.addingTimeInterval(46 * 60)
        }

        XCTAssertTrue(related.contains(where: { $0.kind == .preparation }))
        XCTAssertEqual(related.filter { $0.kind == .travel }.count, 2)
        XCTAssertTrue(
            related.contains(where: {
                $0.category == .recovery && $0.kind == .preparation
            })
        )
        assertNoOverlaps(result.blocks)
    }

    func testOverlappingFixedEventsAreKeptExactAndReported() {
        let first = FixedCommitment(
            title: "First",
            category: .work,
            start: localDate(2026, 7, 27, 10, 0),
            end: localDate(2026, 7, 27, 12, 0)
        )
        let second = FixedCommitment(
            title: "Second",
            category: .personal,
            start: localDate(2026, 7, 27, 11, 0),
            end: localDate(2026, 7, 27, 13, 0)
        )

        let result = SchedulingEngine().makePlan(
            input: makeInput(fixedCommitments: [first, second])
        )

        XCTAssertTrue(
            result.conflicts.contains(where: {
                $0.kind == .fixedOverlap && $0.severity == .blocking
            })
        )
        XCTAssertEqual(
            result.blocks.first(where: {
                $0.fixedCommitmentID == first.id
            })?.start,
            first.start
        )
        XCTAssertEqual(
            result.blocks.first(where: {
                $0.fixedCommitmentID == second.id
            })?.start,
            second.start
        )
    }

    func testFocusedProjectBlockIsNeverShorterThanThirtyMinutes() throws {
        let project = Project(
            title: "Priority",
            status: .activePriority
        )
        let mission = Mission(
            projectID: project.id,
            category: .project,
            title: "Small project step",
            rigidity: .flexible,
            estimatedDurationMinutes: 20,
            minimumUsefulBlockMinutes: 10
        )

        let result = SchedulingEngine().makePlan(
            input: makeInput(
                projects: [project],
                missions: [mission]
            )
        )

        let block = try XCTUnwrap(
            result.blocks.first(where: { $0.missionID == mission.id })
        )
        XCTAssertGreaterThanOrEqual(block.durationMinutes, 30)
    }

    func testOptionalWorkDoesNotConsumePreservedFreeTime() {
        let optional = Mission(
            category: .personal,
            title: "Optional organizing",
            rigidity: .droppable,
            importance: .low,
            urgency: .low,
            estimatedDurationMinutes: 90,
            consistencyCost: .low,
            backlogCost: .low
        )

        let result = SchedulingEngine().makePlan(
            input: makeInput(missions: [optional])
        )

        XCTAssertFalse(
            result.blocks.contains(where: { $0.missionID == optional.id })
        )
        XCTAssertTrue(result.blocks.contains(where: { $0.kind == .freeTime }))
        XCTAssertTrue(
            result.decisions.contains(where: {
                $0.missionID == optional.id
                    && $0.kind == .omitted
                    && $0.rule == .freeTime
            })
        )
    }

    func testWeeklyRoutineStaysInsideFlexibleDueWindow() throws {
        let routine = Routine(
            title: "Sunday trash",
            category: .household,
            rigidity: .flexible,
            recurrence: RecurrencePattern(
                frequency: .weekly,
                weekdays: [.sunday],
                preferredStartMinute: 20 * 60
            ),
            estimatedDurationMinutes: 10,
            dueWindowMinutes: 180
        )

        let result = SchedulingEngine().makePlan(
            input: makeInput(routines: [routine])
        )

        let block = try XCTUnwrap(
            result.blocks.first(where: {
                $0.title == routine.title && $0.kind == .mission
            })
        )
        XCTAssertEqual(calendar.component(.weekday, from: block.start), 1)
        let minute = calendar.component(.hour, from: block.start) * 60
            + calendar.component(.minute, from: block.start)
        XCTAssertTrue((18 * 60 + 30...21 * 60 + 30).contains(minute))
    }

    func testCompatibleGroceriesAndMealPreparationAreBundled() throws {
        let groceries = Routine(
            title: "Groceries",
            category: .household,
            rigidity: .flexible,
            recurrence: RecurrencePattern(frequency: .daily),
            estimatedDurationMinutes: 35,
            dueWindowMinutes: 12 * 60
        )
        let mealPreparation = Routine(
            title: "Meal preparation",
            category: .household,
            rigidity: .flexible,
            recurrence: RecurrencePattern(frequency: .daily),
            estimatedDurationMinutes: 75,
            dueWindowMinutes: 12 * 60
        )

        let result = SchedulingEngine().makePlan(
            input: makeInput(routines: [mealPreparation, groceries])
        )
        let groceryBlock = try XCTUnwrap(
            result.blocks.first(where: {
                $0.title == groceries.title && $0.kind == .mission
            })
        )
        let mealBlock = try XCTUnwrap(
            result.blocks.first(where: {
                $0.title == mealPreparation.title && $0.kind == .mission
            })
        )

        XCTAssertEqual(
            mealBlock.start.timeIntervalSince(groceryBlock.end),
            TimeInterval(
                MissionControlSeed.makeDemo(
                    referenceDate: current
                ).profile.transitions.shoppingTravelMinutes * 60
            ),
            accuracy: 1
        )
        XCTAssertTrue(
            result.decisions.contains(where: {
                $0.routineID == groceries.id
                    && $0.rule == .compatibleBundling
            })
        )
    }

    func testMonthlyRoutineReportsMissingAnchorAssumption() {
        let routine = Routine(
            title: "Monthly maintenance",
            category: .household,
            rigidity: .deferrable,
            recurrence: RecurrencePattern(frequency: .monthly),
            estimatedDurationMinutes: 20,
            dueWindowMinutes: 24 * 60
        )

        let result = SchedulingEngine().makePlan(
            input: makeInput(routines: [routine])
        )

        XCTAssertTrue(
            result.conflicts.contains(where: {
                $0.kind == .recurrenceAnchorMissing
                    && $0.severity == .warning
            })
        )
    }

    func testMultiDayCadenceDoesNotResetWhenHorizonRollsForward() {
        let routine = Routine(
            title: "Every third day",
            category: .household,
            rigidity: .flexible,
            recurrence: RecurrencePattern(
                frequency: .daily,
                interval: 3
            ),
            estimatedDurationMinutes: 20,
            dueWindowMinutes: 12 * 60
        )
        let first = SchedulingEngine().makePlan(
            input: makeInput(routines: [routine])
        )
        let secondCurrent = localDate(2026, 7, 28, 8, 0)
        let second = SchedulingEngine().makePlan(
            input: makeInput(
                currentTime: secondCurrent,
                routines: [routine]
            )
        )
        let overlapStart = calendar.startOfDay(for: secondCurrent)
        let overlapEnd = localDate(2026, 8, 3, 0, 0)
        let firstDays = Set(
            first.blocks.filter {
                $0.title == routine.title
                    && $0.kind == .mission
                    && $0.start >= overlapStart
                    && $0.start < overlapEnd
            }.map { calendar.startOfDay(for: $0.start) }
        )
        let secondDays = Set(
            second.blocks.filter {
                $0.title == routine.title
                    && $0.kind == .mission
                    && $0.start >= overlapStart
                    && $0.start < overlapEnd
            }.map { calendar.startOfDay(for: $0.start) }
        )

        XCTAssertEqual(firstDays, secondDays)
    }

    func testHeavyLowerBodyWorkAvoidsTwentyFourHoursBeforeMatch() throws {
        let match = FixedCommitment(
            title: "Football match",
            category: .football,
            start: localDate(2026, 7, 28, 12, 0),
            end: localDate(2026, 7, 28, 14, 0),
            isFootballMatch: true
        )
        let workout = Mission(
            category: .gym,
            title: "Heavy lower-body session",
            rigidity: .protected,
            estimatedDurationMinutes: 60,
            energyDemand: .high,
            physicalLoad: .heavy,
            bodyAreaTags: ["lower body"]
        )
        var input = makeInput(
            currentTime: localDate(2026, 7, 27, 13, 0),
            missions: [workout],
            fixedCommitments: [match]
        )
        input.approvedWorkouts = [
            ApprovedWorkout(
                missionID: workout.id,
                preferredWeekdays: [.monday],
                weeklySessionTarget: 1,
                preferredStartMinute: 16 * 60
            )
        ]

        let result = SchedulingEngine().makePlan(input: input)
        let block = try XCTUnwrap(
            result.blocks.first(where: { $0.missionID == workout.id })
        )
        let restrictedStart = match.start.addingTimeInterval(-24 * 60 * 60)
        XCTAssertFalse(
            overlaps(
                block.start,
                block.end,
                restrictedStart,
                match.start
            )
        )
        XCTAssertGreaterThanOrEqual(block.start, match.end)
    }

    func testUnderSixHoursSleepMovesDemandingPhysicalWorkOutOfToday() throws {
        let workout = Mission(
            category: .gym,
            title: "Demanding workout",
            rigidity: .protected,
            estimatedDurationMinutes: 60,
            energyDemand: .high,
            physicalLoad: .heavy
        )
        let recovery = RecoveryContext(
            recordedAt: current,
            sleepDurationMinutes: 5 * 60 + 30
        )

        let result = SchedulingEngine().makePlan(
            input: makeInput(
                missions: [workout],
                recoveryContext: recovery
            )
        )

        let block = try XCTUnwrap(
            result.blocks.first(where: { $0.missionID == workout.id })
        )
        XCTAssertFalse(calendar.isDate(block.start, inSameDayAs: current))
        XCTAssertTrue(
            result.decisions.contains(where: {
                $0.missionID == workout.id
                    && $0.kind == .recoveryAdjusted
            })
        )
    }

    func testExactNightCommitmentUsesPracticalSleepMinimumAndReportsShortfall() throws {
        let nightCommitment = FixedCommitment(
            title: "Late fixed commitment",
            category: .personal,
            start: localDate(2026, 7, 27, 0, 0),
            end: localDate(2026, 7, 27, 1, 0)
        )

        let result = SchedulingEngine().makePlan(
            input: makeInput(fixedCommitments: [nightCommitment])
        )
        let sleep = try XCTUnwrap(
            result.blocks.first(where: {
                $0.kind == .sleep
                    && calendar.isDate($0.end, inSameDayAs: current)
            })
        )

        XCTAssertEqual(sleep.durationMinutes, 6 * 60 + 30)
        XCTAssertTrue(
            result.conflicts.contains(where: {
                $0.kind == .sleepConflict
                    && $0.severity == .warning
            })
        )
    }

    func testPainFlagBlocksMateriallyAffectedMission() {
        let workout = Mission(
            category: .gym,
            title: "Hamstring loading",
            rigidity: .protected,
            estimatedDurationMinutes: 60,
            physicalLoad: .heavy,
            bodyAreaTags: ["hamstring"]
        )
        let pain = PainFlag(
            bodyArea: "hamstring",
            reportedAt: current,
            note: "Pain"
        )

        let result = SchedulingEngine().makePlan(
            input: makeInput(
                missions: [workout],
                painFlags: [pain]
            )
        )

        XCTAssertFalse(
            result.blocks.contains(where: { $0.missionID == workout.id })
        )
        XCTAssertTrue(
            result.decisions.contains(where: {
                $0.missionID == workout.id
                    && $0.rule == .painRestriction
            })
        )
    }

    func testClearFoodDeficitInsertsPracticalEatingBlock() {
        let need = NutritionPlanningNeed(
            localDay: calendar.startOfDay(for: current),
            substantialMealsRequired: 1,
            substantialMealsCovered: 1,
            clearDeficit: true,
            suggestedMealDurationMinutes: 30
        )

        let result = SchedulingEngine().makePlan(
            input: makeInput(nutritionNeeds: [need])
        )

        XCTAssertTrue(
            result.blocks.contains(where: {
                $0.kind == .meal && $0.title.contains("food deficit")
            })
        )
        XCTAssertTrue(
            result.decisions.contains(where: {
                $0.rule == .nutritionCoverage
            })
        )
    }

    func testAfterEventRoutineUsesNextViableWindow() throws {
        let training = FixedCommitment(
            title: "Football training",
            category: .football,
            start: localDate(2026, 7, 28, 18, 30),
            end: localDate(2026, 7, 28, 20, 30)
        )
        let laundry = Routine(
            title: "Football laundry",
            category: .household,
            rigidity: .protected,
            recurrence: RecurrencePattern(
                frequency: .afterEvent,
                triggerCategory: .football
            ),
            estimatedDurationMinutes: 15,
            dueWindowMinutes: 24 * 60
        )

        let result = SchedulingEngine().makePlan(
            input: makeInput(
                fixedCommitments: [training],
                routines: [laundry]
            )
        )
        let block = try XCTUnwrap(
            result.blocks.first(where: {
                $0.title == laundry.title && $0.kind == .mission
            })
        )

        XCTAssertGreaterThanOrEqual(block.start, training.end)
        XCTAssertLessThanOrEqual(
            block.end,
            training.end.addingTimeInterval(24 * 60 * 60)
        )
    }

    func testAfterEventRoutineCanUseNextMorningWithinDueWindow() throws {
        let training = FixedCommitment(
            title: "Football training",
            category: .football,
            start: localDate(2026, 7, 28, 18, 30),
            end: localDate(2026, 7, 28, 20, 30)
        )
        let occupiedEvening = FixedCommitment(
            title: "Protected evening",
            category: .personal,
            start: localDate(2026, 7, 28, 21, 10),
            end: localDate(2026, 7, 29, 0, 0)
        )
        let laundry = Routine(
            title: "Football laundry",
            category: .household,
            rigidity: .protected,
            recurrence: RecurrencePattern(
                frequency: .afterEvent,
                triggerCategory: .football
            ),
            estimatedDurationMinutes: 15,
            dueWindowMinutes: 24 * 60
        )

        let result = SchedulingEngine().makePlan(
            input: makeInput(
                fixedCommitments: [training, occupiedEvening],
                routines: [laundry]
            )
        )
        let block = try XCTUnwrap(
            result.blocks.first(where: {
                $0.title == laundry.title && $0.kind == .mission
            })
        )

        XCTAssertTrue(
            calendar.isDate(
                block.start,
                inSameDayAs: localDate(2026, 7, 29, 8, 0)
            )
        )
        XCTAssertEqual(calendar.component(.hour, from: block.start), 7)
        XCTAssertEqual(calendar.component(.minute, from: block.start), 30)
        XCTAssertLessThanOrEqual(
            block.end,
            training.end.addingTimeInterval(24 * 60 * 60)
        )
    }

    func testDependenciesPlacePrerequisiteFirst() throws {
        let prerequisite = Mission(
            category: .project,
            title: "A prerequisite",
            rigidity: .protected,
            estimatedDurationMinutes: 30
        )
        let dependent = Mission(
            category: .project,
            title: "Dependent",
            rigidity: .protected,
            estimatedDurationMinutes: 30,
            dependencyIDs: [prerequisite.id]
        )

        let result = SchedulingEngine().makePlan(
            input: makeInput(missions: [dependent, prerequisite])
        )
        let first = try XCTUnwrap(
            result.blocks.first(where: {
                $0.missionID == prerequisite.id
            })
        )
        let second = try XCTUnwrap(
            result.blocks.first(where: {
                $0.missionID == dependent.id
            })
        )

        XCTAssertLessThanOrEqual(first.end, second.start)
    }

    func testResolvedRoutineOccurrenceDoesNotReappearOnRecalculation() throws {
        let routine = Routine(
            title: "Daily resolved routine",
            category: .household,
            rigidity: .flexible,
            recurrence: RecurrencePattern(frequency: .daily),
            estimatedDurationMinutes: 20,
            dueWindowMinutes: 12 * 60
        )
        let input = makeInput(routines: [routine])
        var snapshot = MissionControlSnapshot(
            profile: input.profile,
            routines: [routine]
        )
        snapshot.applySchedulingResult(
            SchedulingEngine().makePlan(input: input)
        )
        let source = try XCTUnwrap(
            snapshot.scheduleBlocks.first(where: {
                $0.kind == .mission
                    && snapshot.mission(
                        withID: $0.missionID
                    )?.sourceRoutineID == routine.id
            })
        )
        let missionID = try XCTUnwrap(source.missionID)
        _ = MissionExecution.resolve(
            snapshot: &snapshot,
            missionID: missionID,
            scheduleBlockID: source.id,
            status: .completed,
            at: source.end
        )

        let recalculated = SchedulingEngine().makePlan(
            input: PlanningInput(
                snapshot: snapshot,
                currentTime: current
            )
        )
        snapshot.applySchedulingResult(recalculated)

        XCTAssertFalse(
            snapshot.scheduleBlocks.contains(where: {
                $0.missionID == missionID
            })
        )
        XCTAssertEqual(
            snapshot.mission(withID: missionID)?.status,
            .completed
        )
    }

    func testSkippedWorkoutDayPreservesOtherOccurrencesAndFindsAnotherDay() throws {
        let gym = Mission(
            category: .gym,
            title: "Approved workout",
            rigidity: .protected,
            estimatedDurationMinutes: 60
        )
        let workout = ApprovedWorkout(
            missionID: gym.id,
            preferredWeekdays: [
                .monday,
                .wednesday,
                .friday,
                .sunday
            ],
            weeklySessionTarget: 4,
            preferredStartMinute: 16 * 60
        )
        var input = makeInput(missions: [gym])
        input.approvedWorkouts = [workout]
        let first = SchedulingEngine().makePlan(input: input)
        let gymBlocks = first.blocks.filter {
            $0.missionID == gym.id && $0.kind == .mission
        }
        let monday = try XCTUnwrap(
            gymBlocks.first(where: {
                calendar.isDate(
                    $0.start,
                    inSameDayAs: current
                )
            })
        )
        let preservedIDs = Set(
            gymBlocks.filter { $0.id != monday.id }.map(\.id)
        )
        input.completionHistory = [
            CompletionRecord(
                missionID: gym.id,
                scheduleBlockID: monday.id,
                status: .skipped,
                completedAt: monday.start,
                plannedDurationMinutes: monday.durationMinutes,
                actualDurationMinutes: 0
            )
        ]
        input.existingPlan = first.blocks

        let recalculated = SchedulingEngine().makePlan(input: input)
        let updatedGymBlocks = recalculated.blocks.filter {
            $0.missionID == gym.id && $0.kind == .mission
        }

        XCTAssertEqual(updatedGymBlocks.count, 4)
        XCTAssertTrue(
            updatedGymBlocks.allSatisfy {
                !calendar.isDate($0.start, inSameDayAs: current)
            }
        )
        XCTAssertTrue(
            preservedIDs.isSubset(
                of: Set(updatedGymBlocks.map(\.id))
            )
        )
        assertNoOverlaps(recalculated.blocks)
    }

    func testWorkoutTomorrowRecoveryMovesOnlyTheSkippedOccurrence() throws {
        let gym = Mission(
            category: .gym,
            title: "Approved workout",
            rigidity: .protected,
            estimatedDurationMinutes: 60
        )
        let workout = ApprovedWorkout(
            missionID: gym.id,
            preferredWeekdays: [.monday, .wednesday, .friday, .sunday],
            weeklySessionTarget: 4,
            preferredStartMinute: 16 * 60
        )
        var input = makeInput(missions: [gym])
        input.approvedWorkouts = [workout]
        let first = SchedulingEngine().makePlan(input: input)
        let source = try XCTUnwrap(
            first.blocks.first(where: {
                $0.missionID == gym.id
                    && calendar.isDate($0.start, inSameDayAs: current)
            })
        )
        let preservedIDs = Set(
            first.blocks.filter {
                $0.missionID == gym.id && $0.id != source.id
            }.map(\.id)
        )
        let completion = CompletionRecord(
            missionID: gym.id,
            scheduleBlockID: source.id,
            status: .skipped,
            completedAt: source.start,
            plannedDurationMinutes: source.durationMinutes,
            actualDurationMinutes: 0
        )
        let snapshot = MissionControlSnapshot(
            profile: input.profile,
            missions: [gym],
            scheduleBlocks: first.blocks,
            completions: [completion],
            unresolvedDispositions: [
                UnresolvedDispositionRecord(
                    missionID: gym.id,
                    scheduleBlockID: source.id,
                    disposition: .moveToTomorrow,
                    decidedAt: source.start
                )
            ],
            approvedWorkouts: [workout]
        )

        let recalculated = SchedulingEngine().makePlan(
            input: PlanningInput(
                snapshot: snapshot,
                currentTime: current
            )
        )
        let gymBlocks = recalculated.blocks.filter {
            $0.missionID == gym.id && $0.kind == .mission
        }

        XCTAssertEqual(gymBlocks.count, 4)
        XCTAssertTrue(
            preservedIDs.isSubset(of: Set(gymBlocks.map(\.id)))
        )
        XCTAssertTrue(gymBlocks.contains(where: {
            calendar.isDate(
                $0.start,
                inSameDayAs: localDate(2026, 7, 28, 12, 0)
            )
        }))
        assertNoOverlaps(recalculated.blocks)
    }

    func testWorkoutBacklogDefersOneOccurrenceWithoutDroppingTheSeries() throws {
        let gym = Mission(
            category: .gym,
            title: "Approved workout",
            rigidity: .protected,
            estimatedDurationMinutes: 60
        )
        let workout = ApprovedWorkout(
            missionID: gym.id,
            preferredWeekdays: [.monday, .wednesday, .friday, .sunday],
            weeklySessionTarget: 4,
            preferredStartMinute: 16 * 60
        )
        var input = makeInput(missions: [gym])
        input.approvedWorkouts = [workout]
        let first = SchedulingEngine().makePlan(input: input)
        let source = try XCTUnwrap(
            first.blocks.first(where: {
                $0.missionID == gym.id
                    && calendar.isDate($0.start, inSameDayAs: current)
            })
        )
        let preservedIDs = Set(
            first.blocks.filter {
                $0.missionID == gym.id && $0.id != source.id
            }.map(\.id)
        )
        let completion = CompletionRecord(
            missionID: gym.id,
            scheduleBlockID: source.id,
            status: .skipped,
            completedAt: source.start,
            plannedDurationMinutes: source.durationMinutes,
            actualDurationMinutes: 0
        )
        let snapshot = MissionControlSnapshot(
            profile: input.profile,
            missions: [gym],
            scheduleBlocks: first.blocks,
            completions: [completion],
            unresolvedDispositions: [
                UnresolvedDispositionRecord(
                    missionID: gym.id,
                    scheduleBlockID: source.id,
                    disposition: .weeklyBacklog,
                    decidedAt: source.start
                )
            ],
            approvedWorkouts: [workout]
        )

        let recalculated = SchedulingEngine().makePlan(
            input: PlanningInput(
                snapshot: snapshot,
                currentTime: current
            )
        )
        let gymBlocks = recalculated.blocks.filter {
            $0.missionID == gym.id && $0.kind == .mission
        }

        XCTAssertEqual(gymBlocks.count, 3)
        XCTAssertEqual(Set(gymBlocks.map(\.id)), preservedIDs)
        assertNoOverlaps(recalculated.blocks)
    }

    func testSimultaneousWorkoutRecoveryDispositionsRemainOccurrenceScoped() throws {
        let gym = Mission(
            category: .gym,
            title: "Approved workout",
            rigidity: .protected,
            estimatedDurationMinutes: 60
        )
        let workout = ApprovedWorkout(
            missionID: gym.id,
            preferredWeekdays: [
                .monday,
                .wednesday,
                .friday,
                .sunday
            ],
            weeklySessionTarget: 4,
            preferredStartMinute: 16 * 60
        )
        var input = makeInput(missions: [gym])
        input.approvedWorkouts = [workout]
        let first = SchedulingEngine().makePlan(input: input)
        let sourceBlocks = first.blocks.filter {
            $0.missionID == gym.id && $0.kind == .mission
        }
        .sorted(by: { $0.start < $1.start })
        let moved = try XCTUnwrap(sourceBlocks.first)
        let backlogged = try XCTUnwrap(sourceBlocks.dropFirst().first)
        let completions = [moved, backlogged].map {
            CompletionRecord(
                missionID: gym.id,
                scheduleBlockID: $0.id,
                status: .skipped,
                completedAt: $0.start,
                plannedDurationMinutes: $0.durationMinutes,
                actualDurationMinutes: 0
            )
        }
        let snapshot = MissionControlSnapshot(
            profile: input.profile,
            missions: [gym],
            scheduleBlocks: first.blocks,
            completions: completions,
            unresolvedDispositions: [
                UnresolvedDispositionRecord(
                    missionID: gym.id,
                    scheduleBlockID: moved.id,
                    disposition: .moveToTomorrow,
                    decidedAt: moved.start
                ),
                UnresolvedDispositionRecord(
                    missionID: gym.id,
                    scheduleBlockID: backlogged.id,
                    disposition: .weeklyBacklog,
                    decidedAt: backlogged.start
                )
            ],
            approvedWorkouts: [workout]
        )
        let collisionInput = PlanningInput(
            snapshot: snapshot,
            currentTime: current
        )

        XCTAssertEqual(
            collisionInput.recoveryDueWindows[gym.id]?.count,
            1
        )
        XCTAssertEqual(
            collisionInput.deferredOccurrenceCounts[gym.id],
            1
        )

        let recalculated = SchedulingEngine().makePlan(
            input: collisionInput
        )
        let updated = recalculated.blocks.filter {
            $0.missionID == gym.id && $0.kind == .mission
        }

        XCTAssertEqual(updated.count, 3)
        XCTAssertEqual(Set(updated.map(\.id)).count, updated.count)
        XCTAssertFalse(updated.contains(where: { $0.id == moved.id }))
        XCTAssertFalse(updated.contains(where: { $0.id == backlogged.id }))
        assertNoOverlaps(recalculated.blocks)
    }

    private func makeInput(
        currentTime: Date? = nil,
        projects: [Project] = [],
        missions: [Mission] = [],
        fixedCommitments: [FixedCommitment] = [],
        routines: [Routine] = [],
        nutritionNeeds: [NutritionPlanningNeed] = [],
        recoveryContext: RecoveryContext? = nil,
        painFlags: [PainFlag] = []
    ) -> PlanningInput {
        var profile = MissionControlSeed.makeDemo(
            referenceDate: self.current
        ).profile
        profile.nutritionTargets.substantialMeals = 0
        return PlanningInput(
            currentTime: currentTime ?? self.current,
            profile: profile,
            fixedCommitments: fixedCommitments,
            goals: [],
            projects: projects,
            missions: missions,
            routines: routines,
            nutritionNeeds: nutritionNeeds,
            recoveryContext: recoveryContext,
            painFlags: painFlags
        )
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
        let blocks = source.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.end < $1.end
        }
        for pair in zip(blocks, blocks.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                pair.1.start,
                pair.0.end,
                "\(pair.0.title) overlaps \(pair.1.title)",
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
