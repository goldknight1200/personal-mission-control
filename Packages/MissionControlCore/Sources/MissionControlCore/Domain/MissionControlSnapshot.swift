import Foundation

public struct MissionControlSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 5

    public var schemaVersion: Int
    public var profile: UserProfile
    public var goals: [Goal]
    public var projects: [Project]
    public var missions: [Mission]
    public var scheduleBlocks: [ScheduleBlock]
    public var fixedCommitments: [FixedCommitment]
    public var routines: [Routine]
    public var checklists: [Checklist]
    public var completions: [CompletionRecord]
    public var inventoryItems: [InventoryItem]
    public var painFlags: [PainFlag]
    public var missionStartRecords: [MissionStartRecord]
    public var replanRequests: [ReplanRequest]
    public var commandHistory: [StructuredCommand]
    public var dailyCheckIns: [DailyCheckIn]
    public var unresolvedDispositions: [UnresolvedDispositionRecord]
    public var missDiagnostics: [MissionMissDiagnosticRecord]
    public var approvedWorkouts: [ApprovedWorkout]
    public var nutritionPlanningNeeds: [NutritionPlanningNeed]
    public var recoveryContext: RecoveryContext?
    public var schedulingDecisions: [SchedulingDecision]
    public var schedulingConflicts: [SchedulingConflict]
    public var schedulingPlanMetadata: SchedulingPlanMetadata?

    public init(
        schemaVersion: Int = MissionControlSnapshot.currentSchemaVersion,
        profile: UserProfile,
        goals: [Goal] = [],
        projects: [Project] = [],
        missions: [Mission] = [],
        scheduleBlocks: [ScheduleBlock] = [],
        fixedCommitments: [FixedCommitment] = [],
        routines: [Routine] = [],
        checklists: [Checklist] = [],
        completions: [CompletionRecord] = [],
        inventoryItems: [InventoryItem] = [],
        painFlags: [PainFlag] = [],
        missionStartRecords: [MissionStartRecord] = [],
        replanRequests: [ReplanRequest] = [],
        commandHistory: [StructuredCommand] = [],
        dailyCheckIns: [DailyCheckIn] = [],
        unresolvedDispositions: [UnresolvedDispositionRecord] = [],
        missDiagnostics: [MissionMissDiagnosticRecord] = [],
        approvedWorkouts: [ApprovedWorkout] = [],
        nutritionPlanningNeeds: [NutritionPlanningNeed] = [],
        recoveryContext: RecoveryContext? = nil,
        schedulingDecisions: [SchedulingDecision] = [],
        schedulingConflicts: [SchedulingConflict] = [],
        schedulingPlanMetadata: SchedulingPlanMetadata? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.profile = profile
        self.goals = goals
        self.projects = projects
        self.missions = missions
        self.scheduleBlocks = scheduleBlocks
        self.fixedCommitments = fixedCommitments
        self.routines = routines
        self.checklists = checklists
        self.completions = completions
        self.inventoryItems = inventoryItems
        self.painFlags = painFlags
        self.missionStartRecords = missionStartRecords
        self.replanRequests = replanRequests
        self.commandHistory = commandHistory
        self.dailyCheckIns = dailyCheckIns
        self.unresolvedDispositions = unresolvedDispositions
        self.missDiagnostics = missDiagnostics
        self.approvedWorkouts = approvedWorkouts
        self.nutritionPlanningNeeds = nutritionPlanningNeeds
        self.recoveryContext = recoveryContext
        self.schedulingDecisions = schedulingDecisions
        self.schedulingConflicts = schedulingConflicts
        self.schedulingPlanMetadata = schedulingPlanMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case profile
        case goals
        case projects
        case missions
        case scheduleBlocks
        case fixedCommitments
        case routines
        case checklists
        case completions
        case inventoryItems
        case painFlags
        case missionStartRecords
        case replanRequests
        case commandHistory
        case dailyCheckIns
        case unresolvedDispositions
        case missDiagnostics
        case approvedWorkouts
        case nutritionPlanningNeeds
        case recoveryContext
        case schedulingDecisions
        case schedulingConflicts
        case schedulingPlanMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        profile = try container.decode(UserProfile.self, forKey: .profile)
        goals = try container.decode([Goal].self, forKey: .goals)
        projects = try container.decode([Project].self, forKey: .projects)
        missions = try container.decode([Mission].self, forKey: .missions)
        scheduleBlocks = try container.decode([ScheduleBlock].self, forKey: .scheduleBlocks)
        fixedCommitments = try container.decode([FixedCommitment].self, forKey: .fixedCommitments)
        routines = try container.decode([Routine].self, forKey: .routines)
        checklists = try container.decode([Checklist].self, forKey: .checklists)
        completions = try container.decode([CompletionRecord].self, forKey: .completions)
        inventoryItems = try container.decodeIfPresent([InventoryItem].self, forKey: .inventoryItems) ?? []
        painFlags = try container.decodeIfPresent([PainFlag].self, forKey: .painFlags) ?? []
        missionStartRecords = try container.decodeIfPresent(
            [MissionStartRecord].self,
            forKey: .missionStartRecords
        ) ?? []
        replanRequests = try container.decodeIfPresent(
            [ReplanRequest].self,
            forKey: .replanRequests
        ) ?? []
        commandHistory = try container.decodeIfPresent(
            [StructuredCommand].self,
            forKey: .commandHistory
        ) ?? []
        dailyCheckIns = try container.decodeIfPresent(
            [DailyCheckIn].self,
            forKey: .dailyCheckIns
        ) ?? []
        unresolvedDispositions = try container.decodeIfPresent(
            [UnresolvedDispositionRecord].self,
            forKey: .unresolvedDispositions
        ) ?? []
        missDiagnostics = try container.decodeIfPresent(
            [MissionMissDiagnosticRecord].self,
            forKey: .missDiagnostics
        ) ?? []
        approvedWorkouts = try container.decodeIfPresent(
            [ApprovedWorkout].self,
            forKey: .approvedWorkouts
        ) ?? []
        nutritionPlanningNeeds = try container.decodeIfPresent(
            [NutritionPlanningNeed].self,
            forKey: .nutritionPlanningNeeds
        ) ?? []
        recoveryContext = try container.decodeIfPresent(
            RecoveryContext.self,
            forKey: .recoveryContext
        )
        schedulingDecisions = try container.decodeIfPresent(
            [SchedulingDecision].self,
            forKey: .schedulingDecisions
        ) ?? []
        schedulingConflicts = try container.decodeIfPresent(
            [SchedulingConflict].self,
            forKey: .schedulingConflicts
        ) ?? []
        schedulingPlanMetadata = try container.decodeIfPresent(
            SchedulingPlanMetadata.self,
            forKey: .schedulingPlanMetadata
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(profile, forKey: .profile)
        try container.encode(goals, forKey: .goals)
        try container.encode(projects, forKey: .projects)
        try container.encode(missions, forKey: .missions)
        try container.encode(scheduleBlocks, forKey: .scheduleBlocks)
        try container.encode(fixedCommitments, forKey: .fixedCommitments)
        try container.encode(routines, forKey: .routines)
        try container.encode(checklists, forKey: .checklists)
        try container.encode(completions, forKey: .completions)
        try container.encode(inventoryItems, forKey: .inventoryItems)
        try container.encode(painFlags, forKey: .painFlags)
        try container.encode(missionStartRecords, forKey: .missionStartRecords)
        try container.encode(replanRequests, forKey: .replanRequests)
        try container.encode(commandHistory, forKey: .commandHistory)
        try container.encode(dailyCheckIns, forKey: .dailyCheckIns)
        try container.encode(unresolvedDispositions, forKey: .unresolvedDispositions)
        try container.encode(missDiagnostics, forKey: .missDiagnostics)
        try container.encode(approvedWorkouts, forKey: .approvedWorkouts)
        try container.encode(
            nutritionPlanningNeeds,
            forKey: .nutritionPlanningNeeds
        )
        try container.encodeIfPresent(recoveryContext, forKey: .recoveryContext)
        try container.encode(schedulingDecisions, forKey: .schedulingDecisions)
        try container.encode(schedulingConflicts, forKey: .schedulingConflicts)
        try container.encodeIfPresent(
            schedulingPlanMetadata,
            forKey: .schedulingPlanMetadata
        )
    }

    public func mission(withID id: EntityID?) -> Mission? {
        guard let id else { return nil }
        return missions.first(where: { $0.id == id })
    }

    public func checklist(ofKind kind: ChecklistKind) -> Checklist? {
        checklists.first(where: { $0.kind == kind })
    }

    @discardableResult
    public mutating func completeMission(
        id: EntityID,
        at date: Date,
        actualDurationMinutes: Int? = nil,
        scheduleBlockID: EntityID? = nil
    ) -> CompletionRecord? {
        MissionExecution.resolve(
            snapshot: &self,
            missionID: id,
            scheduleBlockID: scheduleBlockID,
            status: .completed,
            at: date,
            actualDurationMinutes: actualDurationMinutes
        )
    }

    public mutating func updateActualDuration(for missionID: EntityID, minutes: Int) {
        MissionExecution.updateActualDuration(
            snapshot: &self,
            missionID: missionID,
            minutes: minutes
        )
    }

    public mutating func toggleMissionStep(missionID: EntityID, stepID: EntityID) {
        guard
            let missionIndex = missions.firstIndex(where: { $0.id == missionID }),
            let stepIndex = missions[missionIndex].miniGoals.firstIndex(where: { $0.id == stepID })
        else { return }

        missions[missionIndex].miniGoals[stepIndex].isCompleted.toggle()
    }

    public mutating func toggleChecklistItem(checklistID: EntityID, itemID: EntityID) {
        guard
            let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
            let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
        else { return }

        checklists[checklistIndex].items[itemIndex].isCompleted.toggle()
    }

    public mutating func updateProject(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
    }

    public mutating func updateRoutine(_ routine: Routine) {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else { return }
        routines[index] = routine
    }
}
