import Foundation

public enum MissionOutcomeStatus: String, CaseIterable, Codable, Equatable, Sendable {
    case completed
    case skipped
    case partial

    public var displayName: String {
        rawValue.capitalized
    }
}

public enum MissionMissCause: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case avoidance
    case unrealisticDuration
    case fatigue
    case badTiming
    case changedPriority
    case externalDisruption

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .avoidance: "Avoidance"
        case .unrealisticDuration: "Unrealistic duration"
        case .fatigue: "Fatigue"
        case .badTiming: "Bad timing"
        case .changedPriority: "Changed priority"
        case .externalDisruption: "External disruption"
        }
    }

    public var recommendation: String {
        switch self {
        case .avoidance:
            "Use a smaller first step, while keeping the protected outcome visible."
        case .unrealisticDuration:
            "Recommend a more realistic duration before placing the next block."
        case .fatigue:
            "Prefer a lower-demand window or recovery before retrying."
        case .badTiming:
            "Recommend a different time of day with fewer transition costs."
        case .changedPriority:
            "Ask for an explicit priority review; do not silently weaken the goal."
        case .externalDisruption:
            "Preserve the intent and recommend the smallest viable reschedule."
        }
    }
}

public enum DailyCheckInKind: String, Codable, Equatable, Sendable {
    case morning
    case evening
}

public struct DailyCheckIn: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var kind: DailyCheckInKind
    public var recordedAt: Date
    public var hasChanges: Bool?
    public var note: String?
    public var sleepDurationMinutes: Int?
    public var nutritionTargetMet: Bool?

    public init(
        id: EntityID = EntityID(),
        kind: DailyCheckInKind,
        recordedAt: Date,
        hasChanges: Bool? = nil,
        note: String? = nil,
        sleepDurationMinutes: Int? = nil,
        nutritionTargetMet: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.recordedAt = recordedAt
        self.hasChanges = hasChanges
        self.note = note
        self.sleepDurationMinutes = sleepDurationMinutes
        self.nutritionTargetMet = nutritionTargetMet
    }
}

public enum UnresolvedMissionDisposition: String, CaseIterable, Codable, Equatable, Sendable {
    case laterToday
    case moveToTomorrow
    case weeklyBacklog
    case drop

    public var displayName: String {
        switch self {
        case .laterToday: "Move later today"
        case .moveToTomorrow: "Move to tomorrow"
        case .weeklyBacklog: "Return to weekly backlog"
        case .drop: "Drop"
        }
    }
}

public struct UnresolvedDispositionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var missionID: EntityID
    public var scheduleBlockID: EntityID
    public var disposition: UnresolvedMissionDisposition
    public var decidedAt: Date

    public init(
        id: EntityID = EntityID(),
        missionID: EntityID,
        scheduleBlockID: EntityID,
        disposition: UnresolvedMissionDisposition,
        decidedAt: Date
    ) {
        self.id = id
        self.missionID = missionID
        self.scheduleBlockID = scheduleBlockID
        self.disposition = disposition
        self.decidedAt = decidedAt
    }
}

public struct MissionMissDiagnosticRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var missionID: EntityID
    public var category: MissionCategory
    public var cause: MissionMissCause
    public var recordedAt: Date

    public init(
        id: EntityID = EntityID(),
        missionID: EntityID,
        category: MissionCategory,
        cause: MissionMissCause,
        recordedAt: Date
    ) {
        self.id = id
        self.missionID = missionID
        self.category = category
        self.cause = cause
        self.recordedAt = recordedAt
    }
}

public struct RepeatedMissDiagnostic: Equatable, Identifiable, Sendable {
    public var missionID: EntityID
    public var missionTitle: String
    public var category: MissionCategory
    public var recentMissCount: Int

    public var id: EntityID { missionID }

    public init(
        missionID: EntityID,
        missionTitle: String,
        category: MissionCategory,
        recentMissCount: Int
    ) {
        self.missionID = missionID
        self.missionTitle = missionTitle
        self.category = category
        self.recentMissCount = recentMissCount
    }
}

public struct WeeklyConsistencySummary: Equatable, Sendable {
    public var weekStart: Date
    public var weekEnd: Date
    public var footballCompleted: Int
    public var footballPlanned: Int
    public var gymCompleted: Int
    public var gymTargetMinimum: Int
    public var gymTargetPreferred: Int
    public var projectActualMinutes: Int
    public var projectPlannedMinutes: Int
    public var nutritionTargetDays: Int
    public var sleepTargetNights: Int

    public init(
        weekStart: Date,
        weekEnd: Date,
        footballCompleted: Int,
        footballPlanned: Int,
        gymCompleted: Int,
        gymTargetMinimum: Int,
        gymTargetPreferred: Int,
        projectActualMinutes: Int,
        projectPlannedMinutes: Int,
        nutritionTargetDays: Int,
        sleepTargetNights: Int
    ) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.footballCompleted = footballCompleted
        self.footballPlanned = footballPlanned
        self.gymCompleted = gymCompleted
        self.gymTargetMinimum = gymTargetMinimum
        self.gymTargetPreferred = gymTargetPreferred
        self.projectActualMinutes = projectActualMinutes
        self.projectPlannedMinutes = projectPlannedMinutes
        self.nutritionTargetDays = nutritionTargetDays
        self.sleepTargetNights = sleepTargetNights
    }
}
