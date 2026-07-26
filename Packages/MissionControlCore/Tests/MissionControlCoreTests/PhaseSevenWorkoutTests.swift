import Foundation
import XCTest
@testable import MissionControlCore

final class PhaseSevenWorkoutTests: XCTestCase {
    func testSessionSelectionFollowsApprovedProgramRotation() {
        let fixture = workoutFixture()
        let first = fixture.program.sessionTemplates[0]
        let second = fixture.program.sessionTemplates[1]
        let prior = WorkoutLog(
            programID: fixture.program.id,
            sessionTemplateID: first.id,
            missionID: fixture.mission.id,
            scheduleBlockID: EntityID(),
            selectedExerciseIDs: first.exercises.map(\.id),
            startedAt: fixture.now.addingTimeInterval(-3_600),
            completedAt: fixture.now.addingTimeInterval(-2_000),
            status: .completed
        )

        let selected = WorkoutPlanning.nextSessions(
            in: fixture.program,
            after: [prior],
            count: 3
        )

        XCTAssertEqual(
            selected.map(\.id),
            [second.id, first.id, second.id]
        )
    }

    func testWeeklyTargetCreatesStructuredApprovedSessions() throws {
        let fixture = workoutFixture()
        var approved = fixture.approved
        approved.weeklySessionTarget = 4

        let result = SchedulingEngine().makePlan(
            input: planningInput(
                fixture: fixture,
                approved: approved
            )
        )
        let workoutBlocks = result.blocks.filter {
            $0.missionID == fixture.mission.id && $0.kind == .mission
        }

        XCTAssertEqual(workoutBlocks.count, 4)
        XCTAssertTrue(workoutBlocks.allSatisfy {
            $0.workout?.programID == fixture.program.id
        })
        XCTAssertEqual(
            workoutBlocks.compactMap(\.workout?.sessionTemplateID),
            [
                fixture.program.sessionTemplates[0].id,
                fixture.program.sessionTemplates[1].id,
                fixture.program.sessionTemplates[0].id,
                fixture.program.sessionTemplates[1].id
            ]
        )
    }

    func testInactiveProgramDoesNotGenerateReplacementWorkout() {
        var fixture = workoutFixture()
        fixture.program.isActive = false

        let result = SchedulingEngine().makePlan(
            input: planningInput(fixture: fixture)
        )

        XCTAssertFalse(
            result.blocks.contains(where: {
                $0.missionID == fixture.mission.id
                    && $0.kind == .mission
            })
        )
        XCTAssertTrue(
            result.decisions.contains(where: {
                $0.kind == .omitted
                    && $0.explanation.contains("not both user-approved and active")
            })
        )
    }

    func testHeavyLowerBodyNeverFallsInsidePreMatchWindow() throws {
        var fixture = workoutFixture(lowerOnly: true)
        fixture.approved.preferredWeekdays = [.monday]
        fixture.approved.weeklySessionTarget = 1
        let matchStart = date(
            year: 2026,
            month: 7,
            day: 28,
            hour: 15
        )
        let match = FixedCommitment(
            title: "League match",
            category: .football,
            start: matchStart,
            end: matchStart.addingTimeInterval(2 * 3_600),
            isFootballMatch: true
        )

        let result = SchedulingEngine().makePlan(
            input: planningInput(
                fixture: fixture,
                fixedCommitments: [match]
            )
        )
        let block = try XCTUnwrap(
            result.blocks.first(where: {
                $0.missionID == fixture.mission.id
                    && $0.kind == .mission
            })
        )
        let restrictedStart = matchStart.addingTimeInterval(-24 * 3_600)

        XCTAssertFalse(
            overlaps(
                block.start,
                block.end,
                restrictedStart,
                matchStart
            )
        )
    }

    func testHeavyLowerBodyWaitsThroughPostMatchRecoveryWindow() throws {
        var fixture = workoutFixture(lowerOnly: true)
        fixture.approved.preferredWeekdays = [.tuesday]
        fixture.approved.weeklySessionTarget = 1
        let matchStart = date(
            year: 2026,
            month: 7,
            day: 27,
            hour: 18
        )
        let matchEnd = matchStart.addingTimeInterval(2 * 3_600)
        let match = FixedCommitment(
            title: "League match",
            category: .football,
            start: matchStart,
            end: matchEnd,
            isFootballMatch: true
        )

        let result = SchedulingEngine().makePlan(
            input: planningInput(
                fixture: fixture,
                fixedCommitments: [match]
            )
        )
        let block = try XCTUnwrap(
            result.blocks.first(where: {
                $0.missionID == fixture.mission.id
                    && $0.kind == .mission
            })
        )

        XCTAssertFalse(
            overlaps(
                block.start,
                block.end,
                matchEnd,
                matchEnd.addingTimeInterval(24 * 3_600)
            )
        )
    }

    func testUnderSixHoursSleepMovesDemandingSessionOffToday() throws {
        var fixture = workoutFixture(lowerOnly: true)
        fixture.approved.preferredWeekdays = [.monday]
        fixture.approved.weeklySessionTarget = 1
        let recovery = RecoveryContext(
            recordedAt: fixture.now,
            sleepDurationMinutes: 5 * 60 + 30
        )

        let result = SchedulingEngine().makePlan(
            input: planningInput(
                fixture: fixture,
                recoveryContext: recovery
            )
        )
        let block = try XCTUnwrap(
            result.blocks.first(where: {
                $0.missionID == fixture.mission.id
                    && $0.kind == .mission
            })
        )

        XCTAssertFalse(calendar.isDate(block.start, inSameDayAs: fixture.now))
    }

    func testPainFlagBlocksOnlyMateriallyAffectedExercises() throws {
        var fixture = workoutFixture()
        fixture.approved.weeklySessionTarget = 1
        fixture.approved.preferredWeekdays = [.monday]
        let session = fixture.program.sessionTemplates[0]
        let shoulderExercise = try XCTUnwrap(
            session.exercises.first(where: {
                $0.bodyAreaTags.contains("shoulder")
            })
        )
        let unaffectedExercise = try XCTUnwrap(
            session.exercises.first(where: {
                !$0.bodyAreaTags.contains("shoulder")
            })
        )
        let pain = PainFlag(
            bodyArea: "shoulder",
            reportedAt: fixture.now,
            note: "Reported during check-in."
        )

        let result = SchedulingEngine().makePlan(
            input: planningInput(
                fixture: fixture,
                painFlags: [pain]
            )
        )
        let metadata = try XCTUnwrap(
            result.blocks.first(where: {
                $0.missionID == fixture.mission.id
                    && $0.kind == .mission
            })?.workout
        )

        XCTAssertFalse(metadata.exerciseIDs.contains(shoulderExercise.id))
        XCTAssertTrue(metadata.blockedExerciseIDs.contains(shoulderExercise.id))
        XCTAssertTrue(metadata.exerciseIDs.contains(unaffectedExercise.id))
        XCTAssertTrue(
            result.decisions.contains(where: {
                $0.rule == .painRestriction
                    && $0.kind == .recoveryAdjusted
            })
        )
    }

    func testFootballTrainingLoadKeepsHeavyLowerOffTrainingDay() throws {
        var fixture = workoutFixture(lowerOnly: true)
        fixture.approved.preferredWeekdays = [.tuesday]
        fixture.approved.weeklySessionTarget = 1
        let training = Routine(
            title: "Football training",
            category: .football,
            rigidity: .protected,
            recurrence: RecurrencePattern(
                frequency: .weekly,
                weekdays: [.tuesday],
                preferredStartMinute: 18 * 60 + 30
            ),
            estimatedDurationMinutes: 120,
            dueWindowMinutes: 60
        )

        let result = SchedulingEngine().makePlan(
            input: planningInput(
                fixture: fixture,
                routines: [training]
            )
        )
        let block = try XCTUnwrap(
            result.blocks.first(where: {
                $0.missionID == fixture.mission.id
                    && $0.kind == .mission
            })
        )

        XCTAssertNotEqual(
            calendar.component(.weekday, from: block.start),
            Weekday.tuesday.rawValue
        )
    }

    func testShortenedSuggestionPreservesProgramAndOnlyAppliesBelowTarget() {
        let fixture = workoutFixture()
        let session = fixture.program.sessionTemplates[0]
        let original = fixture.program

        let suggestion = WorkoutPlanning.shortenedSuggestion(
            program: fixture.program,
            session: session,
            availableExerciseIDs: session.exercises.map(\.id),
            completedSessionsThisWeek: 2,
            weeklyTarget: 4
        )
        let atTarget = WorkoutPlanning.shortenedSuggestion(
            program: fixture.program,
            session: session,
            availableExerciseIDs: session.exercises.map(\.id),
            completedSessionsThisWeek: 4,
            weeklyTarget: 4
        )

        XCTAssertNotNil(suggestion)
        XCTAssertLessThan(
            suggestion?.exerciseIDs.count ?? .max,
            session.exercises.count
        )
        XCTAssertNil(atTarget)
        XCTAssertEqual(fixture.program, original)
    }

    func testWorkoutLogSetRestStateAndPersistenceRoundTrip() throws {
        let now = date(year: 2026, month: 7, day: 27, hour: 8)
        let set = WorkoutSetPrescription(targetRepMinimum: 8, targetRepMaximum: 10)
        let exercise = ExercisePrescription(
            title: "Row",
            sets: [set],
            restDurationSeconds: 90,
            bodyAreaTags: ["upper back"]
        )
        let session = WorkoutSessionTemplate(
            title: "Upper",
            exercises: [exercise]
        )
        let program = WorkoutProgram(
            title: "Approved",
            isApproved: true,
            isActive: true,
            sessionTemplates: [session]
        )
        let mission = gymMission()
        let block = ScheduleBlock(
            missionID: mission.id,
            title: session.title,
            category: .gym,
            kind: .mission,
            rigidity: .protected,
            start: now,
            end: now.addingTimeInterval(3_600),
            workout: ScheduledWorkoutMetadata(
                programID: program.id,
                sessionTemplateID: session.id,
                exerciseIDs: [exercise.id]
            )
        )
        var snapshot = MissionControlSnapshot(
            profile: profile(),
            missions: [mission],
            scheduleBlocks: [block],
            workoutPrograms: [program]
        )

        let logID = try XCTUnwrap(
            WorkoutExecution.start(
                snapshot: &snapshot,
                scheduleBlockID: block.id,
                at: now
            )
        )
        XCTAssertTrue(
            WorkoutExecution.recordSet(
                snapshot: &snapshot,
                workoutLogID: logID,
                weight: 70,
                reps: 9,
                at: now.addingTimeInterval(60)
            )
        )
        let logged = try XCTUnwrap(
            snapshot.workoutLogs.first(where: { $0.id == logID })
        )
        XCTAssertEqual(logged.exerciseLogs.first?.setLogs.first?.reps, 9)
        XCTAssertEqual(logged.exerciseLogs.first?.setLogs.first?.weight, 70)
        XCTAssertEqual(
            logged.restTimerEndsAt,
            now.addingTimeInterval(150)
        )
        XCTAssertNil(logged.currentExerciseID)

        XCTAssertTrue(
            WorkoutExecution.finish(
                snapshot: &snapshot,
                workoutLogID: logID,
                at: now.addingTimeInterval(1_800)
            )
        )
        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(
            MissionControlSnapshot.self,
            from: data
        )

        XCTAssertEqual(restored.workoutLogs, snapshot.workoutLogs)
        XCTAssertEqual(
            WorkoutExecution.previousExerciseLog(
                exerciseID: exercise.id,
                before: nil,
                in: restored.workoutLogs
            )?.setLogs.first?.reps,
            9
        )
    }

    func testPainClearanceIsExplicitAndPersisted() throws {
        let now = date(year: 2026, month: 7, day: 27, hour: 8)
        let flag = PainFlag(
            bodyArea: "knee",
            reportedAt: now,
            note: "Pain reported."
        )
        var snapshot = MissionControlSnapshot(
            profile: profile(),
            painFlags: [flag]
        )
        let clearedAt = now.addingTimeInterval(86_400)

        snapshot.clearPainFlag(
            id: flag.id,
            at: clearedAt,
            note: "Reassessed and cleared for planning."
        )
        let restored = try JSONDecoder().decode(
            MissionControlSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        let restoredFlag = try XCTUnwrap(restored.painFlags.first)

        XCTAssertFalse(restoredFlag.isActive)
        XCTAssertEqual(restoredFlag.clearedAt, clearedAt)
        XCTAssertEqual(
            restoredFlag.clearanceNote,
            "Reassessed and cleared for planning."
        )
    }

    private struct Fixture {
        var now: Date
        var mission: Mission
        var program: WorkoutProgram
        var approved: ApprovedWorkout
    }

    private func workoutFixture(lowerOnly: Bool = false) -> Fixture {
        let now = date(year: 2026, month: 7, day: 27, hour: 8)
        let upper = WorkoutSessionTemplate(
            title: "Upper A",
            exercises: [
                ExercisePrescription(
                    title: "Bench press",
                    sets: threeSets(6, 8),
                    restDurationSeconds: 120,
                    bodyAreaTags: ["chest", "shoulder"],
                    physicalLoad: .heavy
                ),
                ExercisePrescription(
                    title: "Row",
                    sets: threeSets(8, 12),
                    restDurationSeconds: 90,
                    bodyAreaTags: ["upper back"]
                ),
                ExercisePrescription(
                    title: "Pulldown",
                    sets: threeSets(8, 12),
                    restDurationSeconds: 90,
                    bodyAreaTags: ["upper back", "biceps"]
                ),
                ExercisePrescription(
                    title: "Curl",
                    sets: threeSets(10, 15),
                    restDurationSeconds: 60,
                    bodyAreaTags: ["biceps"],
                    physicalLoad: .light
                )
            ]
        )
        let lower = WorkoutSessionTemplate(
            title: "Lower A",
            exercises: [
                ExercisePrescription(
                    title: "Squat",
                    sets: threeSets(5, 7),
                    restDurationSeconds: 180,
                    bodyAreaTags: ["lower body", "quadriceps", "knee"],
                    physicalLoad: .heavy
                ),
                ExercisePrescription(
                    title: "Romanian deadlift",
                    sets: threeSets(6, 8),
                    restDurationSeconds: 150,
                    bodyAreaTags: ["lower body", "hamstring"],
                    physicalLoad: .heavy
                ),
                ExercisePrescription(
                    title: "Leg curl",
                    sets: threeSets(8, 12),
                    restDurationSeconds: 90,
                    bodyAreaTags: ["hamstring"]
                )
            ],
            estimatedDurationMinutes: 65
        )
        let program = WorkoutProgram(
            title: "Approved rotation",
            isApproved: true,
            isActive: true,
            sessionTemplates: lowerOnly ? [lower] : [upper, lower]
        )
        let mission = gymMission()
        let approved = ApprovedWorkout(
            missionID: mission.id,
            programID: program.id,
            preferredWeekdays: [
                .monday,
                .wednesday,
                .friday,
                .sunday
            ],
            weeklySessionTarget: 4,
            preferredStartMinute: 16 * 60
        )
        return Fixture(
            now: now,
            mission: mission,
            program: program,
            approved: approved
        )
    }

    private func planningInput(
        fixture: Fixture,
        approved: ApprovedWorkout? = nil,
        fixedCommitments: [FixedCommitment] = [],
        routines: [Routine] = [],
        recoveryContext: RecoveryContext? = nil,
        painFlags: [PainFlag] = []
    ) -> PlanningInput {
        PlanningInput(
            currentTime: fixture.now,
            profile: profile(),
            fixedCommitments: fixedCommitments,
            goals: [],
            projects: [],
            missions: [fixture.mission],
            routines: routines,
            approvedWorkouts: [approved ?? fixture.approved],
            workoutPrograms: [fixture.program],
            recoveryContext: recoveryContext,
            painFlags: painFlags
        )
    }

    private func gymMission() -> Mission {
        Mission(
            category: .gym,
            title: "Approved gym session",
            rigidity: .protected,
            importance: .high,
            estimatedDurationMinutes: 60,
            minimumUsefulBlockMinutes: 30,
            consistencyCost: .high,
            energyDemand: .high,
            physicalLoad: .moderate
        )
    }

    private func profile() -> UserProfile {
        UserProfile(
            displayName: "Test",
            timeZoneIdentifier: "Europe/Berlin",
            uses24HourTime: true,
            hasRegularUniversityLectures: false,
            planningPolicy: .baseline,
            workPattern: WorkPattern(
                typicalWeekdays: [],
                actualShiftsAreFixedCommitments: true
            ),
            footballPattern: FootballPattern(
                trainingWeekdays: [],
                historicalTrainingStartMinute: 18 * 60 + 30,
                historicalTrainingDurationMinutes: 120,
                likelyMatchWeekdays: [],
                historicalTimeIsConfigurable: true
            ),
            gymWeeklyTarget: WeeklyTarget(minimum: 4, preferred: 5),
            transitions: TransitionDefaults(
                workTravelEachWayMinutes: 0,
                footballTravelEachWayMinutes: 0,
                gymTravelEachWayMinutes: 0,
                shoppingTravelMinutes: 0,
                workPreparationMinutes: MinuteRange(minimum: 0, maximum: 0),
                footballPreparationMinutes: MinuteRange(minimum: 0, maximum: 0),
                gymPreparationMinutes: MinuteRange(minimum: 0, maximum: 0),
                gymShowerChangeMinutes: MinuteRange(minimum: 0, maximum: 0),
                footballShowerChangeMinutes: MinuteRange(minimum: 0, maximum: 0)
            ),
            nutritionTargets: NutritionTargets(
                approximateCalories: 3_400,
                approximateProteinGrams: 180,
                substantialMeals: 3
            ),
            categoryAccents: []
        )
    }

    private func threeSets(
        _ minimum: Int,
        _ maximum: Int
    ) -> [WorkoutSetPrescription] {
        (0..<3).map { _ in
            WorkoutSetPrescription(
                targetRepMinimum: minimum,
                targetRepMaximum: maximum
            )
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
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
