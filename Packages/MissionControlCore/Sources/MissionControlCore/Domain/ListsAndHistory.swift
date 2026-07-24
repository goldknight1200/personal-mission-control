import Foundation

public struct ChecklistItem: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var title: String
    public var isCompleted: Bool
    public var dueDate: Date?
    public var missionID: EntityID?
    public var quantity: String?

    public init(
        id: EntityID = EntityID(),
        title: String,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        missionID: EntityID? = nil,
        quantity: String? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.missionID = missionID
        self.quantity = quantity
    }
}

public struct Checklist: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var title: String
    public var kind: ChecklistKind
    public var items: [ChecklistItem]

    public init(
        id: EntityID = EntityID(),
        title: String,
        kind: ChecklistKind,
        items: [ChecklistItem] = []
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.items = items
    }
}

public struct CompletionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var missionID: EntityID
    public var scheduleBlockID: EntityID?
    public var status: MissionOutcomeStatus
    public var completedAt: Date
    public var actualStart: Date?
    public var actualEnd: Date?
    public var plannedDurationMinutes: Int
    public var actualDurationMinutes: Int
    public var reason: String?
    public var missCause: MissionMissCause?
    public var note: String?

    public init(
        id: EntityID = EntityID(),
        missionID: EntityID,
        scheduleBlockID: EntityID? = nil,
        status: MissionOutcomeStatus = .completed,
        completedAt: Date,
        actualStart: Date? = nil,
        actualEnd: Date? = nil,
        plannedDurationMinutes: Int,
        actualDurationMinutes: Int,
        reason: String? = nil,
        missCause: MissionMissCause? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.missionID = missionID
        self.scheduleBlockID = scheduleBlockID
        self.status = status
        self.completedAt = completedAt
        self.actualStart = actualStart
        self.actualEnd = actualEnd ?? completedAt
        self.plannedDurationMinutes = plannedDurationMinutes
        self.actualDurationMinutes = actualDurationMinutes
        self.reason = reason
        self.missCause = missCause
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case missionID
        case scheduleBlockID
        case status
        case completedAt
        case actualStart
        case actualEnd
        case plannedDurationMinutes
        case actualDurationMinutes
        case reason
        case missCause
        case note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(EntityID.self, forKey: .id)
        missionID = try container.decode(EntityID.self, forKey: .missionID)
        scheduleBlockID = try container.decodeIfPresent(
            EntityID.self,
            forKey: .scheduleBlockID
        )
        status = try container.decodeIfPresent(
            MissionOutcomeStatus.self,
            forKey: .status
        ) ?? .completed
        completedAt = try container.decode(Date.self, forKey: .completedAt)
        plannedDurationMinutes = try container.decode(
            Int.self,
            forKey: .plannedDurationMinutes
        )
        actualDurationMinutes = try container.decode(
            Int.self,
            forKey: .actualDurationMinutes
        )
        actualEnd = try container.decodeIfPresent(Date.self, forKey: .actualEnd)
            ?? completedAt
        actualStart = try container.decodeIfPresent(Date.self, forKey: .actualStart)
            ?? actualEnd?.addingTimeInterval(
                -TimeInterval(actualDurationMinutes * 60)
            )
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        missCause = try container.decodeIfPresent(
            MissionMissCause.self,
            forKey: .missCause
        )
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(missionID, forKey: .missionID)
        try container.encodeIfPresent(scheduleBlockID, forKey: .scheduleBlockID)
        try container.encode(status, forKey: .status)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(actualStart, forKey: .actualStart)
        try container.encodeIfPresent(actualEnd, forKey: .actualEnd)
        try container.encode(plannedDurationMinutes, forKey: .plannedDurationMinutes)
        try container.encode(actualDurationMinutes, forKey: .actualDurationMinutes)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(missCause, forKey: .missCause)
        try container.encodeIfPresent(note, forKey: .note)
    }
}
