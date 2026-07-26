import Foundation

public enum AIProviderSelection:
    String,
    CaseIterable,
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    case disabled
    case customJSON

    public var displayName: String {
        switch self {
        case .disabled: "Off"
        case .customJSON: "Custom HTTPS JSON provider"
        }
    }
}

public struct AIIntegrationSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var provider: AIProviderSelection
    public var endpointURLString: String
    public var modelIdentifier: String
    public var sharesRelevantMissionTitles: Bool
    public var sharesWorkShiftTimesWhenRelevant: Bool
    public var lastError: String?

    public init(
        isEnabled: Bool = false,
        provider: AIProviderSelection = .disabled,
        endpointURLString: String = "",
        modelIdentifier: String = "",
        sharesRelevantMissionTitles: Bool = true,
        sharesWorkShiftTimesWhenRelevant: Bool = false,
        lastError: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.provider = provider
        self.endpointURLString = endpointURLString
        self.modelIdentifier = modelIdentifier
        self.sharesRelevantMissionTitles = sharesRelevantMissionTitles
        self.sharesWorkShiftTimesWhenRelevant =
            sharesWorkShiftTimesWhenRelevant
        self.lastError = lastError
    }

    public var isConfigured: Bool {
        guard
            isEnabled,
            provider == .customJSON,
            let url = URL(string: endpointURLString),
            url.scheme?.lowercased() == "https",
            url.host != nil,
            url.user == nil,
            url.password == nil,
            url.query == nil,
            url.fragment == nil,
            endpointURLString.count <= 2_048
        else {
            return false
        }
        let model = modelIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return !model.isEmpty
            && model.count <= 160
            && model.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0)
            })
    }
}

public enum TimeZoneBehavior:
    String,
    CaseIterable,
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    case fixedProfile
    case followSystem

    public var displayName: String {
        switch self {
        case .fixedProfile: "Keep profile time zone"
        case .followSystem: "Follow iPhone time zone"
        }
    }
}

public struct PrivacySettings: Codable, Equatable, Sendable {
    public var retainsCommandTranscripts: Bool
    public var timeZoneBehavior: TimeZoneBehavior

    public init(
        retainsCommandTranscripts: Bool = true,
        timeZoneBehavior: TimeZoneBehavior = .fixedProfile
    ) {
        self.retainsCommandTranscripts = retainsCommandTranscripts
        self.timeZoneBehavior = timeZoneBehavior
    }
}

public enum CommandInterpretationSource:
    String,
    Codable,
    Equatable,
    Sendable
{
    case localRule
    case aiProvider
    case aiFallback
}

public struct RecognizedTextLine: Codable, Equatable, Sendable {
    public var text: String
    public var confidence: Double

    public init(text: String, confidence: Double) {
        self.text = text
        self.confidence = min(max(confidence, 0), 1)
    }
}

public struct WorkShiftImageRecognition: Codable, Equatable, Sendable {
    public var lines: [RecognizedTextLine]

    public init(lines: [RecognizedTextLine]) {
        self.lines = lines
    }
}

public struct WorkShiftImageReview: Equatable, Sendable {
    public var recognizedText: String
    public var parseResult: WorkShiftBatchParseResult
    public var ambiguities: [String]

    public init(
        recognizedText: String,
        parseResult: WorkShiftBatchParseResult,
        ambiguities: [String]
    ) {
        self.recognizedText = recognizedText
        self.parseResult = parseResult
        self.ambiguities = ambiguities
    }
}

public struct MissionControlBackup: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var exportedAt: Date
    public var snapshot: MissionControlSnapshot

    public init(
        formatVersion: Int = MissionControlBackup.currentFormatVersion,
        exportedAt: Date,
        snapshot: MissionControlSnapshot
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.snapshot = snapshot
    }
}

public enum SnapshotIntegrityIssueKind:
    String,
    Codable,
    Equatable,
    Sendable
{
    case unsupportedSchema
    case invalidTimeZone
    case invalidInterval
    case duplicateIdentifier
}

public struct SnapshotIntegrityIssue:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public var id: EntityID
    public var kind: SnapshotIntegrityIssueKind
    public var message: String

    public init(
        id: EntityID = EntityID(),
        kind: SnapshotIntegrityIssueKind,
        message: String
    ) {
        self.id = id
        self.kind = kind
        self.message = message
    }
}

public struct SnapshotDatasetProfile: Equatable, Sendable {
    public var historyRecordCount: Int
    public var scheduleBlockCount: Int
    public var commandCount: Int
    public var externalItemCount: Int
    public var workoutSetCount: Int

    public init(
        historyRecordCount: Int,
        scheduleBlockCount: Int,
        commandCount: Int,
        externalItemCount: Int,
        workoutSetCount: Int
    ) {
        self.historyRecordCount = historyRecordCount
        self.scheduleBlockCount = scheduleBlockCount
        self.commandCount = commandCount
        self.externalItemCount = externalItemCount
        self.workoutSetCount = workoutSetCount
    }
}
