import Foundation

public enum CommandIntentKind: String, CaseIterable, Codable, Equatable, Sendable {
    case replanDay
    case markMissionStarted
    case addTodayItem
    case addShoppingItem
    case emptyInventoryItem
    case updateInventory
    case moveMission
    case skipMission
    case addWorkShift
    case reportPain
    case unknown

    public var displayName: String {
        switch self {
        case .replanDay: "Replan day"
        case .markMissionStarted: "Correct mission start"
        case .addTodayItem: "Add to Today"
        case .addShoppingItem: "Add to Shopping"
        case .emptyInventoryItem: "Update inventory"
        case .updateInventory: "Update inventory"
        case .moveMission: "Move mission"
        case .skipMission: "Skip mission"
        case .addWorkShift: "Add work shift"
        case .reportPain: "Report pain"
        case .unknown: "Unrecognized command"
        }
    }
}

public struct DetectedIntent: Codable, Equatable, Sendable {
    public var kind: CommandIntentKind
    public var confidence: Double

    public init(kind: CommandIntentKind, confidence: Double) {
        self.kind = kind
        self.confidence = min(max(confidence, 0), 1)
    }
}

public enum ExtractedEntityKind: String, Codable, Equatable, Sendable {
    case mission
    case durationMinutes
    case checklistItem
    case inventoryItem
    case inventoryQuantity
    case date
    case timeRange
    case bodyArea
}

public struct ExtractedEntity: Codable, Equatable, Sendable {
    public var kind: ExtractedEntityKind
    public var value: String
    public var normalizedValue: String
    public var dateValue: Date?
    public var integerValue: Int?

    public init(
        kind: ExtractedEntityKind,
        value: String,
        normalizedValue: String? = nil,
        dateValue: Date? = nil,
        integerValue: Int? = nil
    ) {
        self.kind = kind
        self.value = value
        self.normalizedValue = normalizedValue ?? value.lowercased()
        self.dateValue = dateValue
        self.integerValue = integerValue
    }
}

public struct AffectedScheduleRange: Codable, Equatable, Sendable {
    public var start: Date?
    public var end: Date?

    public init(start: Date? = nil, end: Date? = nil) {
        self.start = start
        self.end = end
    }
}

public enum CommandWarningSeverity: String, Codable, Equatable, Sendable {
    case information
    case caution
    case consequence
}

public struct CommandWarning: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var severity: CommandWarningSeverity
    public var message: String

    public init(
        id: EntityID = EntityID(),
        severity: CommandWarningSeverity,
        message: String
    ) {
        self.id = id
        self.severity = severity
        self.message = message
    }
}

public struct WorkShiftPayload: Codable, Equatable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    public var location: String?

    public init(
        title: String = "Work shift",
        start: Date,
        end: Date,
        location: String? = nil
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.location = location
    }
}

public struct InventoryUpdatePayload: Codable, Equatable, Sendable {
    public var name: String
    public var state: InventoryState?
    public var exactQuantity: Double?
    public var quantityUnit: String?
    public var mealsRemaining: Int?
    public var quantityNote: String?

    public init(
        name: String,
        state: InventoryState? = nil,
        exactQuantity: Double? = nil,
        quantityUnit: String? = nil,
        mealsRemaining: Int? = nil,
        quantityNote: String? = nil
    ) {
        self.name = name
        self.state = state
        self.exactQuantity = exactQuantity
        self.quantityUnit = quantityUnit
        self.mealsRemaining = mealsRemaining
        self.quantityNote = quantityNote
    }
}

public enum ProposedMutation: Codable, Equatable, Sendable {
    case requestDayReplan(availableFrom: Date)
    case markMissionStarted(missionID: EntityID?, missionName: String, minutesAgo: Int)
    case addChecklistItem(kind: ChecklistKind, title: String)
    case markInventoryEmpty(name: String)
    case updateInventory(InventoryUpdatePayload)
    case requestMissionMove(missionID: EntityID?, missionName: String)
    case skipMission(missionID: EntityID?, missionName: String)
    case addWorkShift(WorkShiftPayload)
    case addPainFlag(bodyArea: String)

    public var summary: String {
        switch self {
        case .requestDayReplan:
            "Request a replan of the remaining day"
        case let .markMissionStarted(_, missionName, minutesAgo):
            "Mark \(missionName) as started \(minutesAgo) minutes ago"
        case let .addChecklistItem(kind, title):
            "Add “\(title)” to \(kind.displayName)"
        case let .markInventoryEmpty(name):
            "Mark \(name) as empty"
        case let .updateInventory(update):
            if let meals = update.mealsRemaining {
                "Set \(update.name) to \(meals) meals remaining"
            } else if let quantity = update.exactQuantity {
                "Set \(update.name) to \(quantity.formatted())\(update.quantityUnit.map { " \($0)" } ?? "")"
            } else if let state = update.state {
                "Mark \(update.name) as \(state == .empty ? "out" : state.rawValue)"
            } else {
                "Update \(update.name)"
            }
        case let .requestMissionMove(_, missionName):
            "Request a new time for \(missionName)"
        case let .skipMission(_, missionName):
            "Skip \(missionName)"
        case let .addWorkShift(shift):
            "Add \(shift.title)"
        case let .addPainFlag(bodyArea):
            "Add an active pain flag for \(bodyArea)"
        }
    }
}

public enum ConfirmationRequirement: Codable, Equatable, Sendable {
    case none
    case explicit(reasons: [String])

    public var isRequired: Bool {
        if case .explicit = self { return true }
        return false
    }

    public var reasons: [String] {
        if case let .explicit(reasons) = self { return reasons }
        return []
    }
}

public struct StructuredCommand: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var rawTranscript: String
    public var confirmedTranscript: String
    public var detectedIntents: [DetectedIntent]
    public var confidence: Double
    public var extractedEntities: [ExtractedEntity]
    public var proposedMutations: [ProposedMutation]
    public var affectedScheduleRange: AffectedScheduleRange
    public var warnings: [CommandWarning]
    public var confirmationRequirement: ConfirmationRequirement
    public var createdAt: Date
    public var interpretationSource: CommandInterpretationSource?
    public var contextRevisionToken: String?

    public init(
        id: EntityID = EntityID(),
        rawTranscript: String,
        confirmedTranscript: String,
        detectedIntents: [DetectedIntent],
        confidence: Double? = nil,
        extractedEntities: [ExtractedEntity],
        proposedMutations: [ProposedMutation],
        affectedScheduleRange: AffectedScheduleRange = AffectedScheduleRange(),
        warnings: [CommandWarning] = [],
        confirmationRequirement: ConfirmationRequirement = .none,
        createdAt: Date,
        interpretationSource: CommandInterpretationSource? = .localRule,
        contextRevisionToken: String? = nil
    ) {
        self.id = id
        self.rawTranscript = rawTranscript
        self.confirmedTranscript = confirmedTranscript
        self.detectedIntents = detectedIntents
        let inferredConfidence = detectedIntents.isEmpty
            ? 0
            : detectedIntents.map(\.confidence).reduce(0, +) / Double(detectedIntents.count)
        self.confidence = min(max(confidence ?? inferredConfidence, 0), 1)
        self.extractedEntities = extractedEntities
        self.proposedMutations = proposedMutations
        self.affectedScheduleRange = affectedScheduleRange
        self.warnings = warnings
        self.confirmationRequirement = confirmationRequirement
        self.createdAt = createdAt
        self.interpretationSource = interpretationSource
        self.contextRevisionToken = contextRevisionToken
    }

    public mutating func removeTranscriptContent() {
        rawTranscript = "[Not retained]"
        confirmedTranscript = "[Not retained]"
    }
}

public struct CommandMissionReference: Codable, Equatable, Sendable {
    public var id: EntityID
    public var title: String
    public var category: MissionCategory
    public var rigidity: MissionRigidity
    public var scheduledStart: Date?
    public var scheduledEnd: Date?

    public init(
        id: EntityID,
        title: String,
        category: MissionCategory,
        rigidity: MissionRigidity,
        scheduledStart: Date? = nil,
        scheduledEnd: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.rigidity = rigidity
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
    }
}

public struct CommandContext: Codable, Equatable, Sendable {
    public var referenceDate: Date
    public var timeZoneIdentifier: String
    public var missions: [CommandMissionReference]
    public var fixedCommitments: [FixedCommitment]
    public var revisionToken: String

    public init(
        referenceDate: Date,
        timeZoneIdentifier: String,
        missions: [CommandMissionReference],
        fixedCommitments: [FixedCommitment],
        scheduleBlocks: [ScheduleBlock] = []
    ) {
        self.referenceDate = referenceDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.missions = missions
        self.fixedCommitments = fixedCommitments
        revisionToken = Self.makeRevisionToken(
            missions: missions,
            fixedCommitments: fixedCommitments,
            scheduleBlocks: scheduleBlocks
        )
    }

    public init(snapshot: MissionControlSnapshot, referenceDate: Date) {
        self.referenceDate = referenceDate
        timeZoneIdentifier = snapshot.profile.timeZoneIdentifier
        fixedCommitments = snapshot.fixedCommitments
        missions = snapshot.missions.map { mission in
            let block = snapshot.scheduleBlocks.first(where: { $0.missionID == mission.id })
            return CommandMissionReference(
                id: mission.id,
                title: mission.title,
                category: mission.category,
                rigidity: mission.rigidity,
                scheduledStart: block?.start,
                scheduledEnd: block?.end
            )
        }
        revisionToken = Self.makeRevisionToken(
            missions: missions,
            fixedCommitments: fixedCommitments,
            scheduleBlocks: snapshot.scheduleBlocks
        )
    }

    private static func makeRevisionToken(
        missions: [CommandMissionReference],
        fixedCommitments: [FixedCommitment],
        scheduleBlocks: [ScheduleBlock]
    ) -> String {
        let missionParts = missions.sorted { $0.id < $1.id }.map {
            [
                $0.id.rawValue.uuidString.lowercased(),
                $0.title,
                $0.rigidity.rawValue,
                String($0.scheduledStart?.timeIntervalSince1970 ?? -1),
                String($0.scheduledEnd?.timeIntervalSince1970 ?? -1)
            ].joined(separator: ":")
        }
        let fixedParts = fixedCommitments.sorted { $0.id < $1.id }.map {
            [
                $0.id.rawValue.uuidString.lowercased(),
                $0.title,
                String($0.start.timeIntervalSince1970),
                String($0.end.timeIntervalSince1970),
                String($0.isExternallyManaged)
            ].joined(separator: ":")
        }
        let scheduleParts = scheduleBlocks.sorted { $0.id < $1.id }.map {
            [
                $0.id.rawValue.uuidString.lowercased(),
                $0.missionID?.rawValue.uuidString.lowercased() ?? "",
                $0.fixedCommitmentID?.rawValue.uuidString.lowercased() ?? "",
                String($0.start.timeIntervalSince1970),
                String($0.end.timeIntervalSince1970),
                String($0.isImmutable)
            ].joined(separator: ":")
        }
        let material = (
            missionParts
                + ["--fixed--"]
                + fixedParts
                + ["--schedule--"]
                + scheduleParts
        )
            .joined(separator: "|")
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in material.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

public protocol CommandInterpreting {
    func interpret(
        rawTranscript: String,
        confirmedTranscript: String,
        context: CommandContext
    ) -> StructuredCommand
}

public protocol AICommandInterpreter {
    func interpret(
        rawTranscript: String,
        confirmedTranscript: String,
        context: CommandContext
    ) async throws -> StructuredCommand
}
