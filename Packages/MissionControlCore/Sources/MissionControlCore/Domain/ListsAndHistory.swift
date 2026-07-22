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
    public var completedAt: Date
    public var plannedDurationMinutes: Int
    public var actualDurationMinutes: Int
    public var note: String?

    public init(
        id: EntityID = EntityID(),
        missionID: EntityID,
        completedAt: Date,
        plannedDurationMinutes: Int,
        actualDurationMinutes: Int,
        note: String? = nil
    ) {
        self.id = id
        self.missionID = missionID
        self.completedAt = completedAt
        self.plannedDurationMinutes = plannedDurationMinutes
        self.actualDurationMinutes = actualDurationMinutes
        self.note = note
    }
}
