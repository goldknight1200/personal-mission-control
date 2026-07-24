import Foundation

public enum InventoryState: String, Codable, Equatable, Sendable {
    case available
    case low
    case empty
}

public struct InventoryItem: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var name: String
    public var state: InventoryState
    public var quantityNote: String?
    public var updatedAt: Date

    public init(
        id: EntityID = EntityID(),
        name: String,
        state: InventoryState,
        quantityNote: String? = nil,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.state = state
        self.quantityNote = quantityNote
        self.updatedAt = updatedAt
    }
}

public struct PainFlag: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var bodyArea: String
    public var reportedAt: Date
    public var note: String
    public var isActive: Bool

    public init(
        id: EntityID = EntityID(),
        bodyArea: String,
        reportedAt: Date,
        note: String,
        isActive: Bool = true
    ) {
        self.id = id
        self.bodyArea = bodyArea
        self.reportedAt = reportedAt
        self.note = note
        self.isActive = isActive
    }
}

public struct MissionStartRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var missionID: EntityID
    public var scheduleBlockID: EntityID?
    public var actualStart: Date
    public var reportedAt: Date

    public init(
        id: EntityID = EntityID(),
        missionID: EntityID,
        scheduleBlockID: EntityID? = nil,
        actualStart: Date,
        reportedAt: Date
    ) {
        self.id = id
        self.missionID = missionID
        self.scheduleBlockID = scheduleBlockID
        self.actualStart = actualStart
        self.reportedAt = reportedAt
    }
}

public enum ReplanReason: String, Codable, Hashable, Sendable {
    case lateStart
    case actualStartCorrected
    case startNow
    case missionDeferredToday
    case movedToTomorrow
    case returnedToBacklog
    case missionMove
    case missionSkipped
    case taskFinishedEarly
    case taskFinishedLate
    case urgentTaskAdded
    case painReported
    case fixedCommitmentAdded
    case fixedCommitmentChanged
    case projectPriorityRaised
    case foodDeficit
    case repeatedMiss
    case recoveryChanged
}

public enum ReplanRequestStatus: String, Codable, Equatable, Sendable {
    case pending
    case applied
}

public struct ReplanRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var reason: ReplanReason
    public var missionID: EntityID?
    public var requestedAt: Date
    public var affectedStart: Date?
    public var affectedEnd: Date?
    public var status: ReplanRequestStatus
    public var confirmationProvided: Bool

    public init(
        id: EntityID = EntityID(),
        reason: ReplanReason,
        missionID: EntityID? = nil,
        requestedAt: Date,
        affectedStart: Date? = nil,
        affectedEnd: Date? = nil,
        status: ReplanRequestStatus = .pending,
        confirmationProvided: Bool = false
    ) {
        self.id = id
        self.reason = reason
        self.missionID = missionID
        self.requestedAt = requestedAt
        self.affectedStart = affectedStart
        self.affectedEnd = affectedEnd
        self.status = status
        self.confirmationProvided = confirmationProvided
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case reason
        case missionID
        case requestedAt
        case affectedStart
        case affectedEnd
        case status
        case confirmationProvided
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(EntityID.self, forKey: .id)
        reason = try container.decode(ReplanReason.self, forKey: .reason)
        missionID = try container.decodeIfPresent(
            EntityID.self,
            forKey: .missionID
        )
        requestedAt = try container.decode(Date.self, forKey: .requestedAt)
        affectedStart = try container.decodeIfPresent(
            Date.self,
            forKey: .affectedStart
        )
        affectedEnd = try container.decodeIfPresent(
            Date.self,
            forKey: .affectedEnd
        )
        status = try container.decodeIfPresent(
            ReplanRequestStatus.self,
            forKey: .status
        ) ?? .pending
        confirmationProvided = try container.decodeIfPresent(
            Bool.self,
            forKey: .confirmationProvided
        ) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(reason, forKey: .reason)
        try container.encodeIfPresent(missionID, forKey: .missionID)
        try container.encode(requestedAt, forKey: .requestedAt)
        try container.encodeIfPresent(affectedStart, forKey: .affectedStart)
        try container.encodeIfPresent(affectedEnd, forKey: .affectedEnd)
        try container.encode(status, forKey: .status)
        try container.encode(
            confirmationProvided,
            forKey: .confirmationProvided
        )
    }
}
