import Foundation

public enum InventoryState:
    String,
    CaseIterable,
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    case available
    case low
    case empty

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .available: "Available"
        case .low: "Low"
        case .empty: "Out"
        }
    }
}

public struct InventoryItem: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var name: String
    public var state: InventoryState
    public var quantityNote: String?
    public var exactQuantity: Double?
    public var quantityUnit: String?
    public var mealsRemaining: Int?
    public var lowQuantityThreshold: Double?
    public var shoppingQuantity: String?
    public var automaticallyAddToShopping: Bool
    public var updatedAt: Date

    public init(
        id: EntityID = EntityID(),
        name: String,
        state: InventoryState,
        quantityNote: String? = nil,
        exactQuantity: Double? = nil,
        quantityUnit: String? = nil,
        mealsRemaining: Int? = nil,
        lowQuantityThreshold: Double? = nil,
        shoppingQuantity: String? = nil,
        automaticallyAddToShopping: Bool = true,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.state = state
        self.quantityNote = quantityNote
        self.exactQuantity = exactQuantity
        self.quantityUnit = quantityUnit
        self.mealsRemaining = mealsRemaining
        self.lowQuantityThreshold = lowQuantityThreshold
        self.shoppingQuantity = shoppingQuantity
        self.automaticallyAddToShopping = automaticallyAddToShopping
        self.updatedAt = updatedAt
    }

    public var quantityDescription: String {
        if let mealsRemaining {
            return "\(mealsRemaining) meal\(mealsRemaining == 1 ? "" : "s") remaining"
        }
        if let exactQuantity {
            return "\(exactQuantity.formatted())\(quantityUnit.map { " \($0)" } ?? "")"
        }
        if let quantityNote, !quantityNote.isEmpty {
            return quantityNote
        }
        switch state {
        case .available: "Available"
        case .low: "Low"
        case .empty: "Out"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case state
        case quantityNote
        case exactQuantity
        case quantityUnit
        case mealsRemaining
        case lowQuantityThreshold
        case shoppingQuantity
        case automaticallyAddToShopping
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(EntityID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        state = try container.decode(InventoryState.self, forKey: .state)
        quantityNote = try container.decodeIfPresent(
            String.self,
            forKey: .quantityNote
        )
        exactQuantity = try container.decodeIfPresent(
            Double.self,
            forKey: .exactQuantity
        )
        quantityUnit = try container.decodeIfPresent(
            String.self,
            forKey: .quantityUnit
        )
        mealsRemaining = try container.decodeIfPresent(
            Int.self,
            forKey: .mealsRemaining
        )
        lowQuantityThreshold = try container.decodeIfPresent(
            Double.self,
            forKey: .lowQuantityThreshold
        )
        shoppingQuantity = try container.decodeIfPresent(
            String.self,
            forKey: .shoppingQuantity
        )
        automaticallyAddToShopping = try container.decodeIfPresent(
            Bool.self,
            forKey: .automaticallyAddToShopping
        ) ?? true
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public struct PainFlag: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var bodyArea: String
    public var reportedAt: Date
    public var note: String
    public var isActive: Bool
    public var clearedAt: Date?
    public var clearanceNote: String?

    public init(
        id: EntityID = EntityID(),
        bodyArea: String,
        reportedAt: Date,
        note: String,
        isActive: Bool = true,
        clearedAt: Date? = nil,
        clearanceNote: String? = nil
    ) {
        self.id = id
        self.bodyArea = bodyArea
        self.reportedAt = reportedAt
        self.note = note
        self.isActive = isActive
        self.clearedAt = clearedAt
        self.clearanceNote = clearanceNote
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
    case shoppingListChanged
    case inventoryChanged
    case foodDeficit
    case repeatedMiss
    case recoveryChanged
    case externalScheduleChanged
    case manualReplan
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
