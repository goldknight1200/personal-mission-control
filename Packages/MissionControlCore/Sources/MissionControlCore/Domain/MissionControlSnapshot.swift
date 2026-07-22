import Foundation

public struct MissionControlSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

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
        completions: [CompletionRecord] = []
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
        actualDurationMinutes: Int? = nil
    ) -> CompletionRecord? {
        guard let missionIndex = missions.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let plannedDuration = missions[missionIndex].estimatedDurationMinutes
        let actualDuration = actualDurationMinutes ?? plannedDuration
        missions[missionIndex].status = .completed
        missions[missionIndex].actualDurationMinutes = actualDuration

        if let completionIndex = completions.firstIndex(where: { $0.missionID == id }) {
            completions[completionIndex].completedAt = date
            completions[completionIndex].actualDurationMinutes = actualDuration
            return completions[completionIndex]
        }

        let completion = CompletionRecord(
            missionID: id,
            completedAt: date,
            plannedDurationMinutes: plannedDuration,
            actualDurationMinutes: actualDuration
        )
        completions.append(completion)
        return completion
    }

    public mutating func updateActualDuration(for missionID: EntityID, minutes: Int) {
        guard minutes > 0 else { return }
        if let missionIndex = missions.firstIndex(where: { $0.id == missionID }) {
            missions[missionIndex].actualDurationMinutes = minutes
        }
        if let completionIndex = completions.firstIndex(where: { $0.missionID == missionID }) {
            completions[completionIndex].actualDurationMinutes = minutes
        }
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
