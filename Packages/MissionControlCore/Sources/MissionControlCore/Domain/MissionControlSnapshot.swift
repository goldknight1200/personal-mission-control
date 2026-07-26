import Foundation

public struct MissionControlSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 10

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
    public var mealTemplates: [MealTemplate]
    public var plannedMeals: [PlannedMeal]
    public var inventoryItems: [InventoryItem]
    public var painFlags: [PainFlag]
    public var missionStartRecords: [MissionStartRecord]
    public var replanRequests: [ReplanRequest]
    public var commandHistory: [StructuredCommand]
    public var dailyCheckIns: [DailyCheckIn]
    public var unresolvedDispositions: [UnresolvedDispositionRecord]
    public var missDiagnostics: [MissionMissDiagnosticRecord]
    public var approvedWorkouts: [ApprovedWorkout]
    public var workoutPrograms: [WorkoutProgram]
    public var workoutLogs: [WorkoutLog]
    public var nutritionPlanningNeeds: [NutritionPlanningNeed]
    public var recoveryContext: RecoveryContext?
    public var schedulingDecisions: [SchedulingDecision]
    public var schedulingConflicts: [SchedulingConflict]
    public var schedulingPlanMetadata: SchedulingPlanMetadata?
    public var manualScheduleAdjustments: [ManualScheduleAdjustment]
    public var calendarIntegrationSettings: CalendarIntegrationSettings
    public var healthIntegrationSettings: HealthIntegrationSettings
    public var externalCalendarItems: [ExternalCalendarItem]
    public var iCalSubscriptions: [ICalSubscription]
    public var aiIntegrationSettings: AIIntegrationSettings
    public var privacySettings: PrivacySettings

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
        mealTemplates: [MealTemplate] = [],
        plannedMeals: [PlannedMeal] = [],
        inventoryItems: [InventoryItem] = [],
        painFlags: [PainFlag] = [],
        missionStartRecords: [MissionStartRecord] = [],
        replanRequests: [ReplanRequest] = [],
        commandHistory: [StructuredCommand] = [],
        dailyCheckIns: [DailyCheckIn] = [],
        unresolvedDispositions: [UnresolvedDispositionRecord] = [],
        missDiagnostics: [MissionMissDiagnosticRecord] = [],
        approvedWorkouts: [ApprovedWorkout] = [],
        workoutPrograms: [WorkoutProgram] = [],
        workoutLogs: [WorkoutLog] = [],
        nutritionPlanningNeeds: [NutritionPlanningNeed] = [],
        recoveryContext: RecoveryContext? = nil,
        schedulingDecisions: [SchedulingDecision] = [],
        schedulingConflicts: [SchedulingConflict] = [],
        schedulingPlanMetadata: SchedulingPlanMetadata? = nil,
        manualScheduleAdjustments: [ManualScheduleAdjustment] = [],
        calendarIntegrationSettings: CalendarIntegrationSettings =
            CalendarIntegrationSettings(),
        healthIntegrationSettings: HealthIntegrationSettings =
            HealthIntegrationSettings(),
        externalCalendarItems: [ExternalCalendarItem] = [],
        iCalSubscriptions: [ICalSubscription] = [],
        aiIntegrationSettings: AIIntegrationSettings =
            AIIntegrationSettings(),
        privacySettings: PrivacySettings = PrivacySettings()
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
        self.mealTemplates = mealTemplates
        self.plannedMeals = plannedMeals
        self.inventoryItems = inventoryItems
        self.painFlags = painFlags
        self.missionStartRecords = missionStartRecords
        self.replanRequests = replanRequests
        self.commandHistory = commandHistory
        self.dailyCheckIns = dailyCheckIns
        self.unresolvedDispositions = unresolvedDispositions
        self.missDiagnostics = missDiagnostics
        self.approvedWorkouts = approvedWorkouts
        self.workoutPrograms = workoutPrograms
        self.workoutLogs = workoutLogs
        self.nutritionPlanningNeeds = nutritionPlanningNeeds
        self.recoveryContext = recoveryContext
        self.schedulingDecisions = schedulingDecisions
        self.schedulingConflicts = schedulingConflicts
        self.schedulingPlanMetadata = schedulingPlanMetadata
        self.manualScheduleAdjustments = manualScheduleAdjustments
        self.calendarIntegrationSettings = calendarIntegrationSettings
        self.healthIntegrationSettings = healthIntegrationSettings
        self.externalCalendarItems = externalCalendarItems
        self.iCalSubscriptions = iCalSubscriptions
        self.aiIntegrationSettings = aiIntegrationSettings
        self.privacySettings = privacySettings
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
        case mealTemplates
        case plannedMeals
        case inventoryItems
        case painFlags
        case missionStartRecords
        case replanRequests
        case commandHistory
        case dailyCheckIns
        case unresolvedDispositions
        case missDiagnostics
        case approvedWorkouts
        case workoutPrograms
        case workoutLogs
        case nutritionPlanningNeeds
        case recoveryContext
        case schedulingDecisions
        case schedulingConflicts
        case schedulingPlanMetadata
        case manualScheduleAdjustments
        case calendarIntegrationSettings
        case healthIntegrationSettings
        case externalCalendarItems
        case iCalSubscriptions
        case aiIntegrationSettings
        case privacySettings
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
        mealTemplates = try container.decodeIfPresent(
            [MealTemplate].self,
            forKey: .mealTemplates
        ) ?? []
        plannedMeals = try container.decodeIfPresent(
            [PlannedMeal].self,
            forKey: .plannedMeals
        ) ?? []
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
        workoutPrograms = try container.decodeIfPresent(
            [WorkoutProgram].self,
            forKey: .workoutPrograms
        ) ?? []
        workoutLogs = try container.decodeIfPresent(
            [WorkoutLog].self,
            forKey: .workoutLogs
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
        manualScheduleAdjustments = try container.decodeIfPresent(
            [ManualScheduleAdjustment].self,
            forKey: .manualScheduleAdjustments
        ) ?? []
        calendarIntegrationSettings = try container.decodeIfPresent(
            CalendarIntegrationSettings.self,
            forKey: .calendarIntegrationSettings
        ) ?? CalendarIntegrationSettings()
        healthIntegrationSettings = try container.decodeIfPresent(
            HealthIntegrationSettings.self,
            forKey: .healthIntegrationSettings
        ) ?? HealthIntegrationSettings()
        externalCalendarItems = try container.decodeIfPresent(
            [ExternalCalendarItem].self,
            forKey: .externalCalendarItems
        ) ?? []
        iCalSubscriptions = try container.decodeIfPresent(
            [ICalSubscription].self,
            forKey: .iCalSubscriptions
        ) ?? []
        aiIntegrationSettings = try container.decodeIfPresent(
            AIIntegrationSettings.self,
            forKey: .aiIntegrationSettings
        ) ?? AIIntegrationSettings()
        privacySettings = try container.decodeIfPresent(
            PrivacySettings.self,
            forKey: .privacySettings
        ) ?? PrivacySettings()
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
        try container.encode(mealTemplates, forKey: .mealTemplates)
        try container.encode(plannedMeals, forKey: .plannedMeals)
        try container.encode(inventoryItems, forKey: .inventoryItems)
        try container.encode(painFlags, forKey: .painFlags)
        try container.encode(missionStartRecords, forKey: .missionStartRecords)
        try container.encode(replanRequests, forKey: .replanRequests)
        try container.encode(commandHistory, forKey: .commandHistory)
        try container.encode(dailyCheckIns, forKey: .dailyCheckIns)
        try container.encode(unresolvedDispositions, forKey: .unresolvedDispositions)
        try container.encode(missDiagnostics, forKey: .missDiagnostics)
        try container.encode(approvedWorkouts, forKey: .approvedWorkouts)
        try container.encode(workoutPrograms, forKey: .workoutPrograms)
        try container.encode(workoutLogs, forKey: .workoutLogs)
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
        try container.encode(
            manualScheduleAdjustments,
            forKey: .manualScheduleAdjustments
        )
        try container.encode(
            calendarIntegrationSettings,
            forKey: .calendarIntegrationSettings
        )
        try container.encode(
            healthIntegrationSettings,
            forKey: .healthIntegrationSettings
        )
        try container.encode(
            externalCalendarItems,
            forKey: .externalCalendarItems
        )
        try container.encode(iCalSubscriptions, forKey: .iCalSubscriptions)
        try container.encode(
            aiIntegrationSettings,
            forKey: .aiIntegrationSettings
        )
        try container.encode(privacySettings, forKey: .privacySettings)
    }

    public func mission(withID id: EntityID?) -> Mission? {
        guard let id else { return nil }
        return missions.first(where: { $0.id == id })
    }

    public func workoutProgram(withID id: EntityID?) -> WorkoutProgram? {
        guard let id else { return nil }
        return workoutPrograms.first(where: { $0.id == id })
    }

    public func workoutSession(
        programID: EntityID?,
        sessionTemplateID: EntityID?
    ) -> WorkoutSessionTemplate? {
        guard
            let program = workoutProgram(withID: programID),
            let sessionTemplateID
        else {
            return nil
        }
        return program.sessionTemplates.first(where: {
            $0.id == sessionTemplateID
        })
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
        let alreadyResolved = completions.contains {
            $0.missionID == id
                && (
                    scheduleBlockID == nil
                        || $0.scheduleBlockID == scheduleBlockID
                )
        }
        let completion = MissionExecution.resolve(
            snapshot: &self,
            missionID: id,
            scheduleBlockID: scheduleBlockID,
            status: .completed,
            at: date,
            actualDurationMinutes: actualDurationMinutes
        )
        if completion != nil && !alreadyResolved {
            decrementInventoryForCompletedMeal(
                missionID: id,
                at: date
            )
        }
        return completion
    }

    public mutating func updateActualDuration(for missionID: EntityID, minutes: Int) {
        MissionExecution.updateActualDuration(
            snapshot: &self,
            missionID: missionID,
            minutes: minutes
        )
    }

    public mutating func toggleMissionStep(
        missionID: EntityID,
        stepID: EntityID,
        at date: Date = Date()
    ) {
        guard
            let missionIndex = missions.firstIndex(where: { $0.id == missionID }),
            let stepIndex = missions[missionIndex].miniGoals.firstIndex(where: { $0.id == stepID })
        else { return }

        missions[missionIndex].miniGoals[stepIndex].isCompleted.toggle()
        let isCompleted = missions[missionIndex].miniGoals[stepIndex].isCompleted
        for checklistIndex in checklists.indices
        where checklists[checklistIndex].kind == .shopping {
            guard let itemIndex = checklists[checklistIndex].items.firstIndex(
                where: { $0.id == stepID }
            ) else {
                continue
            }
            checklists[checklistIndex].items[itemIndex].isCompleted = isCompleted
            checklists[checklistIndex].items[itemIndex].completedAt =
                isCompleted ? date : nil
            if isCompleted {
                restockInventory(
                    from: checklists[checklistIndex].items[itemIndex],
                    at: date
                )
            }
        }
    }

    public mutating func toggleChecklistItem(
        checklistID: EntityID,
        itemID: EntityID,
        at date: Date = Date()
    ) {
        guard
            let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
            let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
        else { return }

        checklists[checklistIndex].items[itemIndex].isCompleted.toggle()
        checklists[checklistIndex].items[itemIndex].completedAt =
            checklists[checklistIndex].items[itemIndex].isCompleted
                ? date
                : nil
        if checklists[checklistIndex].kind == .shopping,
           checklists[checklistIndex].items[itemIndex].isCompleted {
            restockInventory(
                from: checklists[checklistIndex].items[itemIndex],
                at: date
            )
        }
    }

    public mutating func upsertGoal(_ goal: Goal) {
        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[index] = goal
        } else {
            goals.append(goal)
        }
    }

    public mutating func removeGoal(id: EntityID) {
        goals.removeAll(where: { $0.id == id })
        for index in projects.indices where projects[index].goalID == id {
            projects[index].goalID = nil
        }
    }

    public mutating func upsertProject(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
    }

    public mutating func removeProject(id: EntityID) {
        projects.removeAll(where: { $0.id == id })
        let missionIDs = Set(
            missions.filter { $0.projectID == id }.map(\.id)
        )
        missions.removeAll(where: { missionIDs.contains($0.id) })
        scheduleBlocks.removeAll(where: {
            $0.missionID.map(missionIDs.contains) ?? false
        })
        manualScheduleAdjustments.removeAll(where: {
            $0.block.missionID.map(missionIDs.contains) ?? false
        })
    }

    public mutating func upsertMission(_ mission: Mission) {
        if let index = missions.firstIndex(where: { $0.id == mission.id }) {
            missions[index] = mission
        } else {
            missions.append(mission)
        }
    }

    public mutating func removeMission(id: EntityID) {
        missions.removeAll(where: { $0.id == id })
        scheduleBlocks.removeAll(where: { $0.missionID == id })
        manualScheduleAdjustments.removeAll(where: {
            $0.block.missionID == id
        })
    }

    public mutating func upsertRoutine(_ routine: Routine) {
        if let index = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[index] = routine
        } else {
            routines.append(routine)
        }
    }

    public mutating func removeRoutine(id: EntityID) {
        routines.removeAll(where: { $0.id == id })
        routines = routines.map { routine in
            var updated = routine
            updated.compatibleRoutineIDs.removeAll(where: { $0 == id })
            return updated
        }
        let missionIDs = Set(
            missions.filter { $0.sourceRoutineID == id }.map(\.id)
        )
        missions.removeAll(where: { missionIDs.contains($0.id) })
        scheduleBlocks.removeAll(where: {
            $0.missionID.map(missionIDs.contains) ?? false
        })
        manualScheduleAdjustments.removeAll(where: {
            $0.block.missionID.map(missionIDs.contains) ?? false
        })
    }

    @discardableResult
    public mutating func addChecklistItem(
        kind: ChecklistKind,
        item: ChecklistItem
    ) -> EntityID {
        if let index = checklists.firstIndex(where: { $0.kind == kind }) {
            checklists[index].items.append(item)
            return checklists[index].id
        }
        let checklist = Checklist(
            title: kind.displayName,
            kind: kind,
            items: [item]
        )
        checklists.append(checklist)
        return checklist.id
    }

    public mutating func upsertChecklistItem(
        checklistID: EntityID,
        item: ChecklistItem
    ) {
        guard let checklistIndex = checklists.firstIndex(where: {
            $0.id == checklistID
        }) else {
            return
        }
        if let itemIndex = checklists[checklistIndex].items.firstIndex(where: {
            $0.id == item.id
        }) {
            checklists[checklistIndex].items[itemIndex] = item
        } else {
            checklists[checklistIndex].items.append(item)
        }
    }

    public mutating func removeChecklistItem(
        checklistID: EntityID,
        itemID: EntityID
    ) {
        guard let checklistIndex = checklists.firstIndex(where: {
            $0.id == checklistID
        }) else {
            return
        }
        checklists[checklistIndex].items.removeAll(where: { $0.id == itemID })
    }

    public mutating func updateProject(_ project: Project) {
        upsertProject(project)
    }

    public mutating func updateRoutine(_ routine: Routine) {
        upsertRoutine(routine)
    }

    public mutating func upsertMealTemplate(_ template: MealTemplate) {
        if let index = mealTemplates.firstIndex(where: {
            $0.id == template.id
        }) {
            mealTemplates[index] = template
        } else {
            mealTemplates.append(template)
        }
    }

    public mutating func removeMealTemplate(id: EntityID) {
        mealTemplates.removeAll(where: { $0.id == id })
        for index in plannedMeals.indices
        where plannedMeals[index].mealTemplateID == id {
            plannedMeals[index].mealTemplateID = nil
        }
    }

    public mutating func upsertPlannedMeal(_ plannedMeal: PlannedMeal) {
        if let index = plannedMeals.firstIndex(where: {
            $0.id == plannedMeal.id
        }) {
            plannedMeals[index] = plannedMeal
        } else {
            plannedMeals.append(plannedMeal)
        }
    }

    public mutating func removePlannedMeal(id: EntityID) {
        plannedMeals.removeAll(where: { $0.id == id })
        let missionIDs = Set(
            missions.filter { $0.plannedMealID == id }.map(\.id)
        )
        missions.removeAll(where: { missionIDs.contains($0.id) })
        scheduleBlocks.removeAll(where: {
            $0.missionID.map(missionIDs.contains) ?? false
        })
        manualScheduleAdjustments.removeAll(where: {
            $0.block.missionID.map(missionIDs.contains) ?? false
        })
    }

    public mutating func upsertInventoryItem(_ item: InventoryItem) {
        if let index = inventoryItems.firstIndex(where: { $0.id == item.id }) {
            inventoryItems[index] = item
        } else {
            inventoryItems.append(item)
        }
    }

    public mutating func removeInventoryItem(id: EntityID) {
        inventoryItems.removeAll(where: { $0.id == id })
        for templateIndex in mealTemplates.indices {
            mealTemplates[templateIndex].inventoryUsage.removeAll(where: {
                $0.inventoryItemID == id
            })
        }
        for checklistIndex in checklists.indices
        where checklists[checklistIndex].kind == .shopping {
            for itemIndex in checklists[checklistIndex].items.indices
            where checklists[checklistIndex].items[itemIndex].inventoryItemID
                == id {
                checklists[checklistIndex].items[itemIndex].inventoryItemID = nil
            }
        }
    }

    public mutating func upsertWorkoutProgram(_ program: WorkoutProgram) {
        if let index = workoutPrograms.firstIndex(where: {
            $0.id == program.id
        }) {
            workoutPrograms[index] = program
        } else {
            workoutPrograms.append(program)
        }
    }

    public mutating func removeWorkoutProgram(id: EntityID) {
        workoutPrograms.removeAll(where: { $0.id == id })
        approvedWorkouts = approvedWorkouts.map { workout in
            var updated = workout
            if updated.programID == id {
                updated.programID = nil
                updated.isEnabled = false
            }
            return updated
        }
        scheduleBlocks.removeAll(where: { $0.workout?.programID == id })
        manualScheduleAdjustments.removeAll(where: {
            $0.block.workout?.programID == id
        })
    }

    public mutating func clearPainFlag(
        id: EntityID,
        at date: Date,
        note: String
    ) {
        guard let index = painFlags.firstIndex(where: { $0.id == id }) else {
            return
        }
        painFlags[index].isActive = false
        painFlags[index].clearedAt = date
        painFlags[index].clearanceNote = note
    }

    private mutating func restockInventory(
        from shoppingItem: ChecklistItem,
        at date: Date
    ) {
        guard let inventoryID = shoppingItem.inventoryItemID,
              let index = inventoryItems.firstIndex(where: {
                  $0.id == inventoryID
              }) else {
            return
        }
        let quantity = shoppingItem.quantity?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstNumber = quantity?
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .first
            .flatMap {
                Double(
                    String($0).replacingOccurrences(of: ",", with: ".")
                )
            }
        if let quantity,
           quantity.lowercased().contains("meal"),
           let firstNumber {
            inventoryItems[index].mealsRemaining = Int(firstNumber)
            inventoryItems[index].exactQuantity = nil
            inventoryItems[index].quantityUnit = nil
            inventoryItems[index].quantityNote = nil
        } else if inventoryItems[index].exactQuantity != nil,
                  let firstNumber {
            inventoryItems[index].exactQuantity = firstNumber
            inventoryItems[index].mealsRemaining = nil
            inventoryItems[index].quantityNote = nil
        } else {
            inventoryItems[index].exactQuantity = nil
            inventoryItems[index].mealsRemaining = nil
            inventoryItems[index].quantityNote = quantity
        }
        inventoryItems[index].state = .available
        inventoryItems[index].updatedAt = date
    }
}
