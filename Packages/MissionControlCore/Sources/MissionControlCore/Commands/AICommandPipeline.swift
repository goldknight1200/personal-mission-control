import Foundation

public struct AIContextMission: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var category: MissionCategory
    public var rigidity: MissionRigidity
    public var scheduledStart: Date?
    public var scheduledEnd: Date?

    public init(
        id: String,
        title: String,
        category: MissionCategory,
        rigidity: MissionRigidity,
        scheduledStart: Date?,
        scheduledEnd: Date?
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.rigidity = rigidity
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
    }
}

public struct AIContextWorkShift: Codable, Equatable, Sendable {
    public var id: String
    public var start: Date
    public var end: Date

    public init(id: String, start: Date, end: Date) {
        self.id = id
        self.start = start
        self.end = end
    }
}

public struct AIProviderRequest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var confirmedText: String
    public var referenceDate: Date
    public var timeZoneIdentifier: String
    public var relevantMissions: [AIContextMission]
    public var relevantWorkShifts: [AIContextWorkShift]
    public var allowedMutationKinds: [AIProviderMutationKind]

    public init(
        schemaVersion: Int = AIProviderRequest.currentSchemaVersion,
        confirmedText: String,
        referenceDate: Date,
        timeZoneIdentifier: String,
        relevantMissions: [AIContextMission],
        relevantWorkShifts: [AIContextWorkShift],
        allowedMutationKinds: [AIProviderMutationKind] =
            AIProviderMutationKind.allCases
    ) {
        self.schemaVersion = schemaVersion
        self.confirmedText = confirmedText
        self.referenceDate = referenceDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.relevantMissions = relevantMissions
        self.relevantWorkShifts = relevantWorkShifts
        self.allowedMutationKinds = allowedMutationKinds
    }
}

public enum AIProviderMutationKind:
    String,
    CaseIterable,
    Codable,
    Equatable,
    Sendable
{
    case requestDayReplan
    case markMissionStarted
    case addChecklistItem
    case markInventoryEmpty
    case updateInventory
    case requestMissionMove
    case skipMission
    case addWorkShift
    case addPainFlag
}

public struct AIProviderMutation: Codable, Equatable, Sendable {
    public var kind: AIProviderMutationKind
    public var availableFrom: Date?
    public var missionID: String?
    public var missionName: String?
    public var minutesAgo: Int?
    public var checklistKind: ChecklistKind?
    public var title: String?
    public var inventoryUpdate: InventoryUpdatePayload?
    public var shift: WorkShiftPayload?
    public var bodyArea: String?

    public init(
        kind: AIProviderMutationKind,
        availableFrom: Date? = nil,
        missionID: String? = nil,
        missionName: String? = nil,
        minutesAgo: Int? = nil,
        checklistKind: ChecklistKind? = nil,
        title: String? = nil,
        inventoryUpdate: InventoryUpdatePayload? = nil,
        shift: WorkShiftPayload? = nil,
        bodyArea: String? = nil
    ) {
        self.kind = kind
        self.availableFrom = availableFrom
        self.missionID = missionID
        self.missionName = missionName
        self.minutesAgo = minutesAgo
        self.checklistKind = checklistKind
        self.title = title
        self.inventoryUpdate = inventoryUpdate
        self.shift = shift
        self.bodyArea = bodyArea
    }
}

public struct AIProviderResponse: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var detectedIntents: [DetectedIntent]
    public var confidence: Double
    public var extractedEntities: [ExtractedEntity]
    public var mutations: [AIProviderMutation]
    public var affectedScheduleRange: AffectedScheduleRange
    public var warnings: [String]

    public init(
        schemaVersion: Int = AIProviderResponse.currentSchemaVersion,
        detectedIntents: [DetectedIntent],
        confidence: Double,
        extractedEntities: [ExtractedEntity] = [],
        mutations: [AIProviderMutation],
        affectedScheduleRange: AffectedScheduleRange =
            AffectedScheduleRange(),
        warnings: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.detectedIntents = detectedIntents
        self.confidence = confidence
        self.extractedEntities = extractedEntities
        self.mutations = mutations
        self.affectedScheduleRange = affectedScheduleRange
        self.warnings = warnings
    }
}

public enum AICommandPipelineError:
    Error,
    Equatable,
    Sendable
{
    case providerUnavailable
    case invalidSchema
    case invalidConfidence
    case tooManyValues
    case unsupportedOrIncompleteMutation(String)
    case invalidMissionReference
    case invalidDateRange
    case responseTooLarge
    case invalidJSONStructure
}

public enum AICommandContextMinimizer {
    public static func request(
        confirmedText: String,
        context: CommandContext,
        settings: AIIntegrationSettings
    ) -> AIProviderRequest {
        let normalized = confirmedText.lowercased()
        let tokens = Set(
            normalized
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count >= 3 }
        )
        let upcomingBoundary = context.referenceDate.addingTimeInterval(
            18 * 60 * 60
        )
        let candidates = context.missions.filter { mission in
            let titleTokens = Set(
                mission.title.lowercased().split(
                    whereSeparator: { !$0.isLetter && !$0.isNumber }
                ).map(String.init)
            )
            let nameMatch = !tokens.isDisjoint(with: titleTokens)
            let isCurrentOrSoon = mission.scheduledStart.map {
                $0 <= upcomingBoundary
                    && (mission.scheduledEnd ?? $0) >= context.referenceDate
            } ?? false
            return nameMatch || isCurrentOrSoon
        }
        let relevantMissions = candidates
            .sorted {
                ($0.scheduledStart ?? .distantFuture)
                    < ($1.scheduledStart ?? .distantFuture)
            }
            .prefix(6)
            .enumerated()
            .map { offset, mission in
                AIContextMission(
                    id: mission.id.rawValue.uuidString.lowercased(),
                    title: settings.sharesRelevantMissionTitles
                        ? mission.title
                        : "Mission \(offset + 1)",
                    category: mission.category,
                    rigidity: mission.rigidity,
                    scheduledStart: mission.scheduledStart,
                    scheduledEnd: mission.scheduledEnd
                )
            }

        let asksAboutWorkShifts = [
            "shift", "rota", "work schedule", "working"
        ].contains(where: normalized.contains)
        let relevantWorkShifts: [AIContextWorkShift]
        if asksAboutWorkShifts
            && settings.sharesWorkShiftTimesWhenRelevant {
            let earliest = context.referenceDate.addingTimeInterval(
                -31 * 86_400
            )
            let latest = context.referenceDate.addingTimeInterval(
                62 * 86_400
            )
            relevantWorkShifts = context.fixedCommitments
                .filter {
                    $0.category == .work
                        && $0.end >= earliest
                        && $0.start <= latest
                }
                .sorted(by: { $0.start < $1.start })
                .prefix(20)
                .map {
                    AIContextWorkShift(
                        id: $0.id.rawValue.uuidString.lowercased(),
                        start: $0.start,
                        end: $0.end
                    )
                }
        } else {
            relevantWorkShifts = []
        }

        return AIProviderRequest(
            confirmedText: String(confirmedText.prefix(2_000)),
            referenceDate: context.referenceDate,
            timeZoneIdentifier: context.timeZoneIdentifier,
            relevantMissions: relevantMissions,
            relevantWorkShifts: relevantWorkShifts
        )
    }
}

public struct ProviderBackedAICommandInterpreter: AICommandInterpreter {
    private let provider: any AICommandProvider
    private let settings: AIIntegrationSettings
    private let fallback: LocalCommandParser

    public init(
        provider: any AICommandProvider,
        settings: AIIntegrationSettings,
        fallback: LocalCommandParser = LocalCommandParser()
    ) {
        self.provider = provider
        self.settings = settings
        self.fallback = fallback
    }

    public func interpret(
        rawTranscript: String,
        confirmedTranscript: String,
        context: CommandContext
    ) async throws -> StructuredCommand {
        let request = AICommandContextMinimizer.request(
            confirmedText: confirmedTranscript,
            context: context,
            settings: settings
        )
        do {
            let response = try await provider.requestCommand(request)
            return try AICommandOutputValidator.command(
                response: response,
                rawTranscript: rawTranscript,
                confirmedTranscript: confirmedTranscript,
                context: context
            )
        } catch {
            var local = fallback.interpret(
                rawTranscript: rawTranscript,
                confirmedTranscript: confirmedTranscript,
                context: context
            )
            guard !local.proposedMutations.isEmpty else {
                throw error
            }
            local.interpretationSource = .aiFallback
            local.warnings.append(
                CommandWarning(
                    severity: .information,
                    message:
                        "The AI provider was unavailable or returned an invalid proposal. This supported command was interpreted locally."
                )
            )
            return local
        }
    }
}

public enum AICommandOutputValidator {
    public static func command(
        response: AIProviderResponse,
        rawTranscript: String,
        confirmedTranscript: String,
        context: CommandContext
    ) throws -> StructuredCommand {
        guard
            response.schemaVersion == AIProviderResponse.currentSchemaVersion
        else {
            throw AICommandPipelineError.invalidSchema
        }
        guard
            response.confidence.isFinite,
            (0...1).contains(response.confidence),
            !response.detectedIntents.isEmpty,
            response.detectedIntents.allSatisfy({
                $0.confidence.isFinite && (0...1).contains($0.confidence)
            })
        else {
            throw AICommandPipelineError.invalidConfidence
        }
        guard
            !response.mutations.isEmpty,
            response.mutations.count <= 8,
            response.detectedIntents.count <= 8,
            response.extractedEntities.count <= 24,
            response.warnings.count <= 8
        else {
            throw AICommandPipelineError.tooManyValues
        }
        guard response.warnings.allSatisfy({ $0.count <= 240 }) else {
            throw AICommandPipelineError.tooManyValues
        }
        guard
            response.affectedScheduleRange.start.map({
                $0.timeIntervalSinceReferenceDate.isFinite
            }) ?? true,
            response.affectedScheduleRange.end.map({
                $0.timeIntervalSinceReferenceDate.isFinite
            }) ?? true,
            response.extractedEntities.allSatisfy({
                $0.dateValue.map {
                    $0.timeIntervalSinceReferenceDate.isFinite
                } ?? true
            })
        else {
            throw AICommandPipelineError.invalidDateRange
        }
        if let start = response.affectedScheduleRange.start,
           let end = response.affectedScheduleRange.end,
           end < start {
            throw AICommandPipelineError.invalidDateRange
        }

        let mutations = try response.mutations.map {
            try validatedMutation(
                $0,
                context: context
            )
        }
        var reasons = [
            "This proposal came from the configured AI provider and must be reviewed before local application."
        ]
        if response.confidence < 0.85 {
            reasons.append("The provider reported less than 85% confidence.")
        }
        if mutations.contains(where: isHighImpact) {
            reasons.append(
                "The proposal changes a fixed commitment, recovery safeguard, or existing scheduled work."
            )
        }
        var warnings = response.warnings.map {
            CommandWarning(severity: .caution, message: $0)
        }
        if response.confidence < 0.65 {
            warnings.append(
                CommandWarning(
                    severity: .caution,
                    message:
                        "Low-confidence provider output needs especially careful review."
                )
            )
        }
        return StructuredCommand(
            rawTranscript: rawTranscript,
            confirmedTranscript: confirmedTranscript,
            detectedIntents: response.detectedIntents,
            confidence: response.confidence,
            extractedEntities: response.extractedEntities,
            proposedMutations: mutations,
            affectedScheduleRange: response.affectedScheduleRange,
            warnings: warnings,
            confirmationRequirement: .explicit(reasons: reasons),
            createdAt: context.referenceDate,
            interpretationSource: .aiProvider,
            contextRevisionToken: context.revisionToken
        )
    }

    private static func validatedMutation(
        _ mutation: AIProviderMutation,
        context: CommandContext
    ) throws -> ProposedMutation {
        switch mutation.kind {
        case .requestDayReplan:
            guard let date = mutation.availableFrom,
                  abs(date.timeIntervalSince(context.referenceDate))
                    <= 31 * 86_400 else {
                throw AICommandPipelineError.unsupportedOrIncompleteMutation(
                    mutation.kind.rawValue
                )
            }
            return .requestDayReplan(availableFrom: date)
        case .markMissionStarted:
            let missionID = try validMissionID(
                mutation,
                context: context
            )
            let name = try validMissionName(
                mutation,
                missionID: missionID,
                context: context
            )
            guard let minutes = mutation.minutesAgo,
                  (0...720).contains(minutes) else {
                throw AICommandPipelineError.unsupportedOrIncompleteMutation(
                    mutation.kind.rawValue
                )
            }
            return .markMissionStarted(
                missionID: missionID,
                missionName: name,
                minutesAgo: minutes
            )
        case .addChecklistItem:
            guard
                let kind = mutation.checklistKind,
                kind == .today || kind == .shopping,
                let title = bounded(mutation.title, maximum: 160)
            else {
                throw AICommandPipelineError.unsupportedOrIncompleteMutation(
                    mutation.kind.rawValue
                )
            }
            return .addChecklistItem(kind: kind, title: title)
        case .markInventoryEmpty:
            guard let name = bounded(mutation.title, maximum: 120) else {
                throw AICommandPipelineError.unsupportedOrIncompleteMutation(
                    mutation.kind.rawValue
                )
            }
            return .markInventoryEmpty(name: name)
        case .updateInventory:
            guard
                var update = mutation.inventoryUpdate,
                let name = bounded(update.name, maximum: 120),
                update.exactQuantity.map({ $0.isFinite && $0 >= 0 }) ?? true,
                update.mealsRemaining.map({ $0 >= 0 && $0 <= 10_000 })
                    ?? true
            else {
                throw AICommandPipelineError.unsupportedOrIncompleteMutation(
                    mutation.kind.rawValue
                )
            }
            update.name = name
            return .updateInventory(update)
        case .requestMissionMove:
            let missionID = try validMissionID(
                mutation,
                context: context
            )
            let name = try validMissionName(
                mutation,
                missionID: missionID,
                context: context
            )
            return .requestMissionMove(
                missionID: missionID,
                missionName: name
            )
        case .skipMission:
            let missionID = try validMissionID(
                mutation,
                context: context
            )
            let name = try validMissionName(
                mutation,
                missionID: missionID,
                context: context
            )
            return .skipMission(
                missionID: missionID,
                missionName: name
            )
        case .addWorkShift:
            guard
                var shift = mutation.shift,
                let title = bounded(shift.title, maximum: 120),
                shift.end > shift.start,
                shift.end > context.referenceDate,
                shift.end.timeIntervalSince(shift.start) <= 24 * 60 * 60,
                shift.start <= context.referenceDate.addingTimeInterval(
                    366 * 86_400
                )
            else {
                throw AICommandPipelineError.invalidDateRange
            }
            shift.title = title
            shift.location = boundedOptional(
                shift.location,
                maximum: 160
            )
            return .addWorkShift(shift)
        case .addPainFlag:
            guard let bodyArea = bounded(mutation.bodyArea, maximum: 80)
            else {
                throw AICommandPipelineError.unsupportedOrIncompleteMutation(
                    mutation.kind.rawValue
                )
            }
            return .addPainFlag(bodyArea: bodyArea)
        }
    }

    private static func validMissionName(
        _ mutation: AIProviderMutation,
        missionID: EntityID?,
        context: CommandContext
    ) throws -> String {
        if let missionID,
           let localTitle = context.missions.first(where: {
               $0.id == missionID
           })?.title {
            return localTitle
        }
        guard let name = bounded(mutation.missionName, maximum: 160) else {
            throw AICommandPipelineError.invalidMissionReference
        }
        return name
    }

    private static func validMissionID(
        _ mutation: AIProviderMutation,
        context: CommandContext
    ) throws -> EntityID? {
        guard let value = mutation.missionID else { return nil }
        guard
            let uuid = UUID(uuidString: value),
            context.missions.contains(where: { $0.id.rawValue == uuid })
        else {
            throw AICommandPipelineError.invalidMissionReference
        }
        return EntityID(rawValue: uuid)
    }

    private static func bounded(
        _ value: String?,
        maximum: Int
    ) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximum else { return nil }
        return trimmed
    }

    private static func boundedOptional(
        _ value: String?,
        maximum: Int
    ) -> String? {
        guard let value else { return nil }
        return bounded(value, maximum: maximum)
    }

    private static func isHighImpact(_ mutation: ProposedMutation) -> Bool {
        switch mutation {
        case .requestMissionMove, .skipMission, .addWorkShift, .addPainFlag:
            true
        default:
            false
        }
    }
}

public enum AIProviderResponseDecoder {
    public static func decode(
        _ data: Data,
        maximumBytes: Int = 1_000_000
    ) throws -> AIProviderResponse {
        guard data.count <= maximumBytes else {
            throw AICommandPipelineError.responseTooLarge
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw AICommandPipelineError.invalidJSONStructure
        }
        let allowedTopLevel = Set([
            "schemaVersion",
            "detectedIntents",
            "confidence",
            "extractedEntities",
            "mutations",
            "affectedScheduleRange",
            "warnings"
        ])
        guard Set(dictionary.keys).isSubset(of: allowedTopLevel) else {
            throw AICommandPipelineError.invalidJSONStructure
        }
        if let intents =
            dictionary["detectedIntents"] as? [[String: Any]] {
            guard intents.allSatisfy({
                Set($0.keys).isSubset(of: ["kind", "confidence"])
            }) else {
                throw AICommandPipelineError.invalidJSONStructure
            }
        }
        if let entities =
            dictionary["extractedEntities"] as? [[String: Any]] {
            let allowedEntityKeys = Set([
                "kind",
                "value",
                "normalizedValue",
                "dateValue",
                "integerValue"
            ])
            guard entities.allSatisfy({
                Set($0.keys).isSubset(of: allowedEntityKeys)
            }) else {
                throw AICommandPipelineError.invalidJSONStructure
            }
        }
        if let range =
            dictionary["affectedScheduleRange"] as? [String: Any],
           !Set(range.keys).isSubset(of: ["start", "end"]) {
            throw AICommandPipelineError.invalidJSONStructure
        }
        if let mutations = dictionary["mutations"] as? [[String: Any]] {
            let allowedMutationKeys = Set([
                "kind",
                "availableFrom",
                "missionID",
                "missionName",
                "minutesAgo",
                "checklistKind",
                "title",
                "inventoryUpdate",
                "shift",
                "bodyArea"
            ])
            guard mutations.allSatisfy({
                Set($0.keys).isSubset(of: allowedMutationKeys)
            }) else {
                throw AICommandPipelineError.invalidJSONStructure
            }
            let allowedInventoryKeys = Set([
                "name",
                "state",
                "exactQuantity",
                "quantityUnit",
                "mealsRemaining",
                "quantityNote"
            ])
            let allowedShiftKeys = Set([
                "title",
                "start",
                "end",
                "location"
            ])
            for mutation in mutations {
                if let inventory =
                    mutation["inventoryUpdate"] as? [String: Any],
                   !Set(inventory.keys).isSubset(
                    of: allowedInventoryKeys
                   ) {
                    throw AICommandPipelineError.invalidJSONStructure
                }
                if let shift = mutation["shift"] as? [String: Any],
                   !Set(shift.keys).isSubset(of: allowedShiftKeys) {
                    throw AICommandPipelineError.invalidJSONStructure
                }
            }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AIProviderResponse.self, from: data)
    }
}
