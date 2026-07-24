import Foundation

public struct DueWindow: Codable, Equatable, Sendable {
    public var earliest: Date?
    public var latest: Date?

    public init(earliest: Date? = nil, latest: Date? = nil) {
        if let earliest, let latest {
            precondition(earliest <= latest)
        }
        self.earliest = earliest
        self.latest = latest
    }
}

public struct Goal: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var title: String
    public var detail: String
    public var category: MissionCategory
    public var targetDate: Date?
    public var isActive: Bool

    public init(
        id: EntityID = EntityID(),
        title: String,
        detail: String = "",
        category: MissionCategory,
        targetDate: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.category = category
        self.targetDate = targetDate
        self.isActive = isActive
    }
}

public struct Project: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var goalID: EntityID?
    public var title: String
    public var detail: String
    public var status: ProjectStatus
    public var targetDate: Date?
    public var priorityOverride: PriorityLevel?

    public init(
        id: EntityID = EntityID(),
        goalID: EntityID? = nil,
        title: String,
        detail: String = "",
        status: ProjectStatus,
        targetDate: Date? = nil,
        priorityOverride: PriorityLevel? = nil
    ) {
        self.id = id
        self.goalID = goalID
        self.title = title
        self.detail = detail
        self.status = status
        self.targetDate = targetDate
        self.priorityOverride = priorityOverride
    }
}

public struct MissionStep: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var title: String
    public var isCompleted: Bool

    public init(id: EntityID = EntityID(), title: String, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }
}

public struct Mission: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var projectID: EntityID?
    public var category: MissionCategory
    public var title: String
    public var miniGoals: [MissionStep]
    public var rigidity: MissionRigidity
    public var importance: PriorityLevel
    public var urgency: PriorityLevel
    public var deadline: Date?
    public var dueWindow: DueWindow?
    public var estimatedDurationMinutes: Int
    public var minimumUsefulBlockMinutes: Int
    public var actualDurationMinutes: Int?
    public var sourceRoutineID: EntityID?
    public var consistencyCost: PriorityLevel
    public var backlogCost: PriorityLevel
    public var energyDemand: EnergyDemand
    public var physicalLoad: PhysicalLoad
    public var bodyAreaTags: [String]
    public var preparationMinutes: Int
    public var travelBeforeMinutes: Int
    public var travelAfterMinutes: Int
    public var location: String?
    public var dependencyIDs: [EntityID]
    public var allowsSplitting: Bool
    public var isExternallyManaged: Bool
    public var userPriorityOverride: PriorityLevel?
    public var status: MissionStatus

    public init(
        id: EntityID = EntityID(),
        projectID: EntityID? = nil,
        category: MissionCategory,
        title: String,
        miniGoals: [MissionStep] = [],
        rigidity: MissionRigidity,
        importance: PriorityLevel = .normal,
        urgency: PriorityLevel = .normal,
        deadline: Date? = nil,
        dueWindow: DueWindow? = nil,
        estimatedDurationMinutes: Int,
        minimumUsefulBlockMinutes: Int = 10,
        actualDurationMinutes: Int? = nil,
        sourceRoutineID: EntityID? = nil,
        consistencyCost: PriorityLevel = .normal,
        backlogCost: PriorityLevel = .normal,
        energyDemand: EnergyDemand = .moderate,
        physicalLoad: PhysicalLoad = .none,
        bodyAreaTags: [String] = [],
        preparationMinutes: Int = 0,
        travelBeforeMinutes: Int = 0,
        travelAfterMinutes: Int = 0,
        location: String? = nil,
        dependencyIDs: [EntityID] = [],
        allowsSplitting: Bool = false,
        isExternallyManaged: Bool = false,
        userPriorityOverride: PriorityLevel? = nil,
        status: MissionStatus = .planned
    ) {
        precondition(estimatedDurationMinutes > 0)
        precondition(minimumUsefulBlockMinutes > 0)
        self.id = id
        self.projectID = projectID
        self.category = category
        self.title = title
        self.miniGoals = miniGoals
        self.rigidity = rigidity
        self.importance = importance
        self.urgency = urgency
        self.deadline = deadline
        self.dueWindow = dueWindow
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.minimumUsefulBlockMinutes = minimumUsefulBlockMinutes
        self.actualDurationMinutes = actualDurationMinutes
        self.sourceRoutineID = sourceRoutineID
        self.consistencyCost = consistencyCost
        self.backlogCost = backlogCost
        self.energyDemand = energyDemand
        self.physicalLoad = physicalLoad
        self.bodyAreaTags = bodyAreaTags
        self.preparationMinutes = preparationMinutes
        self.travelBeforeMinutes = travelBeforeMinutes
        self.travelAfterMinutes = travelAfterMinutes
        self.location = location
        self.dependencyIDs = dependencyIDs
        self.allowsSplitting = allowsSplitting
        self.isExternallyManaged = isExternallyManaged
        self.userPriorityOverride = userPriorityOverride
        self.status = status
    }
}

public struct ScheduleBlock: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var missionID: EntityID?
    public var fixedCommitmentID: EntityID?
    public var title: String
    public var category: MissionCategory
    public var kind: ScheduleBlockKind
    public var rigidity: MissionRigidity
    public var start: Date
    public var end: Date
    public var isImmutable: Bool

    public init(
        id: EntityID = EntityID(),
        missionID: EntityID? = nil,
        fixedCommitmentID: EntityID? = nil,
        title: String,
        category: MissionCategory,
        kind: ScheduleBlockKind,
        rigidity: MissionRigidity,
        start: Date,
        end: Date,
        isImmutable: Bool = false
    ) {
        precondition(end > start)
        self.id = id
        self.missionID = missionID
        self.fixedCommitmentID = fixedCommitmentID
        self.title = title
        self.category = category
        self.kind = kind
        self.rigidity = rigidity
        self.start = start
        self.end = end
        self.isImmutable = isImmutable
    }

    public var durationMinutes: Int {
        Int(end.timeIntervalSince(start) / 60)
    }
}

public struct FixedCommitment: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var title: String
    public var category: MissionCategory
    public var start: Date
    public var end: Date
    public var location: String?
    public var externalIdentifier: String?
    public var isExternallyManaged: Bool
    public var isFootballMatch: Bool

    public init(
        id: EntityID = EntityID(),
        title: String,
        category: MissionCategory,
        start: Date,
        end: Date,
        location: String? = nil,
        externalIdentifier: String? = nil,
        isExternallyManaged: Bool = false,
        isFootballMatch: Bool = false
    ) {
        precondition(end > start)
        self.id = id
        self.title = title
        self.category = category
        self.start = start
        self.end = end
        self.location = location
        self.externalIdentifier = externalIdentifier
        self.isExternallyManaged = isExternallyManaged
        self.isFootballMatch = isFootballMatch
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case start
        case end
        case location
        case externalIdentifier
        case isExternallyManaged
        case isFootballMatch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(EntityID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(MissionCategory.self, forKey: .category)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        externalIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .externalIdentifier
        )
        isExternallyManaged = try container.decodeIfPresent(
            Bool.self,
            forKey: .isExternallyManaged
        ) ?? false
        isFootballMatch = try container.decodeIfPresent(
            Bool.self,
            forKey: .isFootballMatch
        ) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(
            externalIdentifier,
            forKey: .externalIdentifier
        )
        try container.encode(
            isExternallyManaged,
            forKey: .isExternallyManaged
        )
        try container.encode(isFootballMatch, forKey: .isFootballMatch)
    }
}

public struct RecurrencePattern: Codable, Equatable, Sendable {
    public var frequency: RecurrenceFrequency
    public var interval: Int
    public var weekdays: [Weekday]
    public var preferredStartMinute: Int?
    public var triggerCategory: MissionCategory?

    public init(
        frequency: RecurrenceFrequency,
        interval: Int = 1,
        weekdays: [Weekday] = [],
        preferredStartMinute: Int? = nil,
        triggerCategory: MissionCategory? = nil
    ) {
        precondition(interval > 0)
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.preferredStartMinute = preferredStartMinute
        self.triggerCategory = triggerCategory
    }
}

public struct Routine: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var title: String
    public var category: MissionCategory
    public var rigidity: MissionRigidity
    public var recurrence: RecurrencePattern
    public var estimatedDurationMinutes: Int
    public var dueWindowMinutes: Int
    public var isEnabled: Bool
    public var note: String

    public init(
        id: EntityID = EntityID(),
        title: String,
        category: MissionCategory,
        rigidity: MissionRigidity,
        recurrence: RecurrencePattern,
        estimatedDurationMinutes: Int,
        dueWindowMinutes: Int,
        isEnabled: Bool = true,
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.rigidity = rigidity
        self.recurrence = recurrence
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.dueWindowMinutes = dueWindowMinutes
        self.isEnabled = isEnabled
        self.note = note
    }
}
