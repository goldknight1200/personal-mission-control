import Foundation

public protocol IdentifierGenerating {
    func identifier(namespace: String) -> EntityID
}

public protocol SchedulePlanning {
    func makePlan(input: PlanningInput) -> SchedulingResult
}

public struct PlanningInput: Equatable, Sendable {
    public var currentTime: Date
    public var profile: UserProfile
    public var fixedCommitments: [FixedCommitment]
    public var goals: [Goal]
    public var projects: [Project]
    public var missions: [Mission]
    public var routines: [Routine]
    public var shoppingItems: [ChecklistItem]
    public var mealTemplates: [MealTemplate]
    public var plannedMeals: [PlannedMeal]
    public var approvedWorkouts: [ApprovedWorkout]
    public var workoutPrograms: [WorkoutProgram]
    public var workoutLogs: [WorkoutLog]
    public var nutritionNeeds: [NutritionPlanningNeed]
    public var completionHistory: [CompletionRecord]
    public var recoveryContext: RecoveryContext?
    public var painFlags: [PainFlag]
    public var missDiagnostics: [MissionMissDiagnosticRecord]
    public var existingPlan: [ScheduleBlock]
    public var lockedBlocks: [ScheduleBlock]
    public var deferredMissionIDs: Set<EntityID>
    public var deferredOccurrenceCounts: [EntityID: Int]
    public var dueWindowOverrides: [EntityID: DueWindow]

    public init(
        currentTime: Date,
        profile: UserProfile,
        fixedCommitments: [FixedCommitment],
        goals: [Goal],
        projects: [Project],
        missions: [Mission],
        routines: [Routine],
        shoppingItems: [ChecklistItem] = [],
        mealTemplates: [MealTemplate] = [],
        plannedMeals: [PlannedMeal] = [],
        approvedWorkouts: [ApprovedWorkout] = [],
        workoutPrograms: [WorkoutProgram] = [],
        workoutLogs: [WorkoutLog] = [],
        nutritionNeeds: [NutritionPlanningNeed] = [],
        completionHistory: [CompletionRecord] = [],
        recoveryContext: RecoveryContext? = nil,
        painFlags: [PainFlag] = [],
        missDiagnostics: [MissionMissDiagnosticRecord] = [],
        existingPlan: [ScheduleBlock] = [],
        lockedBlocks: [ScheduleBlock] = [],
        deferredMissionIDs: Set<EntityID> = [],
        deferredOccurrenceCounts: [EntityID: Int] = [:],
        dueWindowOverrides: [EntityID: DueWindow] = [:]
    ) {
        self.currentTime = currentTime
        self.profile = profile
        self.fixedCommitments = fixedCommitments
        self.goals = goals
        self.projects = projects
        self.missions = missions
        self.routines = routines
        self.shoppingItems = shoppingItems
        self.mealTemplates = mealTemplates
        self.plannedMeals = plannedMeals
        self.approvedWorkouts = approvedWorkouts
        self.workoutPrograms = workoutPrograms
        self.workoutLogs = workoutLogs
        self.nutritionNeeds = nutritionNeeds
        self.completionHistory = completionHistory
        self.recoveryContext = recoveryContext
        self.painFlags = painFlags
        self.missDiagnostics = missDiagnostics
        self.existingPlan = existingPlan
        self.lockedBlocks = lockedBlocks
        self.deferredMissionIDs = deferredMissionIDs
        self.deferredOccurrenceCounts = deferredOccurrenceCounts
        self.dueWindowOverrides = dueWindowOverrides
    }

    public init(
        snapshot: MissionControlSnapshot,
        currentTime: Date,
        lockedBlocks: [ScheduleBlock] = []
    ) {
        var latestDispositionByMission: [
            EntityID: UnresolvedDispositionRecord
        ] = [:]
        for disposition in snapshot.unresolvedDispositions.sorted(by: {
            $0.decidedAt < $1.decidedAt
        }) {
            latestDispositionByMission[disposition.missionID] = disposition
        }
        var deferredMissionIDs = Set<EntityID>()
        var deferredOccurrenceCounts: [EntityID: Int] = [:]
        var dueWindowOverrides: [EntityID: DueWindow] = [:]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(
            identifier: snapshot.profile.timeZoneIdentifier
        ) ?? .current
        for (missionID, disposition) in latestDispositionByMission {
            let isRepeatedWorkout = snapshot.approvedWorkouts.contains {
                $0.isEnabled && $0.missionID == missionID
            }
            let resolvedAfterDisposition = snapshot.completions.contains {
                $0.missionID == missionID
                    && ($0.status == .completed || $0.status == .partial)
                    && $0.completedAt >= disposition.decidedAt
            }
            if resolvedAfterDisposition {
                continue
            }
            switch disposition.disposition {
            case .laterToday:
                let end = calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: calendar.startOfDay(for: disposition.decidedAt)
                ) ?? disposition.decidedAt.addingTimeInterval(86_400)
                dueWindowOverrides[missionID] = DueWindow(
                    earliest: disposition.decidedAt,
                    latest: end
                )
            case .moveToTomorrow:
                let tomorrow = calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: calendar.startOfDay(for: disposition.decidedAt)
                ) ?? disposition.decidedAt.addingTimeInterval(86_400)
                let dayAfter = calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: tomorrow
                ) ?? tomorrow.addingTimeInterval(86_400)
                dueWindowOverrides[missionID] = DueWindow(
                    earliest: tomorrow,
                    latest: dayAfter
                )
            case .weeklyBacklog, .drop:
                if isRepeatedWorkout {
                    deferredOccurrenceCounts[missionID, default: 0] += 1
                } else {
                    deferredMissionIDs.insert(missionID)
                }
            }
        }
        let pendingShoppingItems = snapshot.checklist(ofKind: .shopping)?
            .items.filter { !$0.isCompleted } ?? []
        let manualBlocks = snapshot.manualScheduleAdjustments.map(\.block)
        self.init(
            currentTime: currentTime,
            profile: snapshot.profile,
            fixedCommitments: snapshot.fixedCommitments,
            goals: snapshot.goals,
            projects: snapshot.projects,
            missions: snapshot.missions.filter {
                $0.sourceRoutineID == nil
                    && $0.plannedMealID == nil
                    && $0.nutritionPlanningNeedID == nil
            },
            routines: snapshot.routines,
            shoppingItems: pendingShoppingItems,
            mealTemplates: snapshot.mealTemplates,
            plannedMeals: snapshot.plannedMeals,
            approvedWorkouts: snapshot.approvedWorkouts,
            workoutPrograms: snapshot.workoutPrograms,
            workoutLogs: snapshot.workoutLogs,
            nutritionNeeds: snapshot.nutritionPlanningNeeds,
            completionHistory: snapshot.completions,
            recoveryContext: snapshot.recoveryContext,
            painFlags: snapshot.painFlags,
            missDiagnostics: snapshot.missDiagnostics,
            existingPlan: snapshot.scheduleBlocks,
            lockedBlocks: lockedBlocks + manualBlocks.filter { manual in
                !lockedBlocks.contains(where: { $0.id == manual.id })
            },
            deferredMissionIDs: deferredMissionIDs,
            deferredOccurrenceCounts: deferredOccurrenceCounts,
            dueWindowOverrides: dueWindowOverrides
        )
    }
}

public struct SchedulingResult: Equatable, Sendable {
    public var metadata: SchedulingPlanMetadata
    public var blocks: [ScheduleBlock]
    public var generatedMissions: [Mission]
    public var decisions: [SchedulingDecision]
    public var conflicts: [SchedulingConflict]
    public var unscheduledMissionIDs: [EntityID]

    public init(
        metadata: SchedulingPlanMetadata,
        blocks: [ScheduleBlock],
        generatedMissions: [Mission] = [],
        decisions: [SchedulingDecision] = [],
        conflicts: [SchedulingConflict] = [],
        unscheduledMissionIDs: [EntityID] = []
    ) {
        self.metadata = metadata
        self.blocks = blocks
        self.generatedMissions = generatedMissions
        self.decisions = decisions
        self.conflicts = conflicts
        self.unscheduledMissionIDs = unscheduledMissionIDs
    }
}

public extension MissionControlSnapshot {
    mutating func applySchedulingResult(_ result: SchedulingResult) {
        let historicalGenerated = missions.filter { mission in
            (
                mission.sourceRoutineID != nil
                    || mission.plannedMealID != nil
                    || mission.nutritionPlanningNeedID != nil
            )
                && completions.contains(where: { $0.missionID == mission.id })
                && !result.generatedMissions.contains(where: {
                    $0.id == mission.id
                })
        }
        missions.removeAll(where: {
            $0.sourceRoutineID != nil
                || $0.plannedMealID != nil
                || $0.nutritionPlanningNeedID != nil
        })
        missions.append(contentsOf: historicalGenerated)
        for generated in result.generatedMissions
        where !missions.contains(where: { $0.id == generated.id }) {
            missions.append(generated)
        }
        scheduleBlocks = result.blocks
        schedulingDecisions = result.decisions
        schedulingConflicts = result.conflicts
        schedulingPlanMetadata = result.metadata
        schemaVersion = MissionControlSnapshot.currentSchemaVersion
    }
}
