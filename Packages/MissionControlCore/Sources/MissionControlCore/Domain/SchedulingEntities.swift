import Foundation

public enum FatigueLevel: String, CaseIterable, Codable, Equatable, Sendable {
    case none
    case mild
    case moderate
    case high
}

public enum RecoveryContextSource:
    String,
    Codable,
    Equatable,
    Sendable
{
    case manual
    case healthKitSleep
}

/// Minimal local recovery information required by the deterministic planner.
///
/// Detailed HealthKit samples remain outside the core and are not required.
public struct RecoveryContext: Codable, Equatable, Sendable {
    public var recordedAt: Date
    public var sleepDurationMinutes: Int?
    public var fatigue: FatigueLevel
    public var note: String?
    public var sleepSource: RecoveryContextSource
    public var sleepWindowStart: Date?
    public var sleepWindowEnd: Date?

    public init(
        recordedAt: Date,
        sleepDurationMinutes: Int? = nil,
        fatigue: FatigueLevel = .none,
        note: String? = nil,
        sleepSource: RecoveryContextSource = .manual,
        sleepWindowStart: Date? = nil,
        sleepWindowEnd: Date? = nil
    ) {
        self.recordedAt = recordedAt
        self.sleepDurationMinutes = sleepDurationMinutes
        self.fatigue = fatigue
        self.note = note
        self.sleepSource = sleepSource
        self.sleepWindowStart = sleepWindowStart
        self.sleepWindowEnd = sleepWindowEnd
    }

    private enum CodingKeys: String, CodingKey {
        case recordedAt
        case sleepDurationMinutes
        case fatigue
        case note
        case sleepSource = "source"
        case sleepWindowStart
        case sleepWindowEnd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordedAt = try container.decode(Date.self, forKey: .recordedAt)
        sleepDurationMinutes = try container.decodeIfPresent(
            Int.self,
            forKey: .sleepDurationMinutes
        )
        fatigue = try container.decodeIfPresent(
            FatigueLevel.self,
            forKey: .fatigue
        ) ?? .none
        note = try container.decodeIfPresent(String.self, forKey: .note)
        sleepSource = try container.decodeIfPresent(
            RecoveryContextSource.self,
            forKey: .sleepSource
        ) ?? .manual
        sleepWindowStart = try container.decodeIfPresent(
            Date.self,
            forKey: .sleepWindowStart
        )
        sleepWindowEnd = try container.decodeIfPresent(
            Date.self,
            forKey: .sleepWindowEnd
        )
    }
}

/// Scheduling projection of a user-approved workout program.
public struct ApprovedWorkout: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var missionID: EntityID
    public var programID: EntityID?
    public var preferredWeekdays: [Weekday]
    public var weeklySessionTarget: Int
    public var preferredStartMinute: Int?
    public var isEnabled: Bool

    public init(
        id: EntityID = EntityID(),
        missionID: EntityID,
        programID: EntityID? = nil,
        preferredWeekdays: [Weekday] = [],
        weeklySessionTarget: Int = 1,
        preferredStartMinute: Int? = nil,
        isEnabled: Bool = true
    ) {
        precondition(weeklySessionTarget >= 0)
        self.id = id
        self.missionID = missionID
        self.programID = programID
        self.preferredWeekdays = preferredWeekdays
        self.weeklySessionTarget = weeklySessionTarget
        self.preferredStartMinute = preferredStartMinute
        self.isEnabled = isEnabled
    }
}

/// An approximate daily food-coverage projection used by the deterministic
/// scheduler. Estimates are deliberately coarse and remain user-editable.
public struct NutritionPlanningNeed: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var localDay: Date
    public var substantialMealsRequired: Int
    public var substantialMealsCovered: Int
    public var estimatedCalories: Int
    public var estimatedProteinGrams: Int
    public var approximateCalorieDeficit: Int
    public var approximateProteinDeficit: Int
    public var clearDeficit: Bool
    public var suggestedMealDurationMinutes: Int
    public var suggestedMealTemplateID: EntityID?
    public var suggestedTitle: String
    public var suggestedCalories: Int
    public var suggestedProteinGrams: Int
    public var suggestedStartMinute: Int?
    public var suggestionDisposition: NutritionSuggestionDisposition
    public var suggestionIsUserEdited: Bool
    public var note: String?

    public init(
        id: EntityID = EntityID(),
        localDay: Date,
        substantialMealsRequired: Int,
        substantialMealsCovered: Int = 0,
        estimatedCalories: Int = 0,
        estimatedProteinGrams: Int = 0,
        approximateCalorieDeficit: Int = 0,
        approximateProteinDeficit: Int = 0,
        clearDeficit: Bool = false,
        suggestedMealDurationMinutes: Int = 30,
        suggestedMealTemplateID: EntityID? = nil,
        suggestedTitle: String = "Additional eating block",
        suggestedCalories: Int = 0,
        suggestedProteinGrams: Int = 0,
        suggestedStartMinute: Int? = nil,
        suggestionDisposition: NutritionSuggestionDisposition = .notNeeded,
        suggestionIsUserEdited: Bool = false,
        note: String? = nil
    ) {
        precondition(substantialMealsRequired >= 0)
        precondition(substantialMealsCovered >= 0)
        precondition(estimatedCalories >= 0)
        precondition(estimatedProteinGrams >= 0)
        precondition(approximateCalorieDeficit >= 0)
        precondition(approximateProteinDeficit >= 0)
        precondition(suggestedMealDurationMinutes > 0)
        self.id = id
        self.localDay = localDay
        self.substantialMealsRequired = substantialMealsRequired
        self.substantialMealsCovered = substantialMealsCovered
        self.estimatedCalories = estimatedCalories
        self.estimatedProteinGrams = estimatedProteinGrams
        self.approximateCalorieDeficit = approximateCalorieDeficit
        self.approximateProteinDeficit = approximateProteinDeficit
        self.clearDeficit = clearDeficit
        self.suggestedMealDurationMinutes = suggestedMealDurationMinutes
        self.suggestedMealTemplateID = suggestedMealTemplateID
        self.suggestedTitle = suggestedTitle
        self.suggestedCalories = suggestedCalories
        self.suggestedProteinGrams = suggestedProteinGrams
        self.suggestedStartMinute = suggestedStartMinute
        self.suggestionDisposition = suggestionDisposition
        self.suggestionIsUserEdited = suggestionIsUserEdited
        self.note = note
    }

    public var missingMealCount: Int {
        max(substantialMealsRequired - substantialMealsCovered, 0)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case localDay
        case substantialMealsRequired
        case substantialMealsCovered
        case estimatedCalories
        case estimatedProteinGrams
        case approximateCalorieDeficit
        case approximateProteinDeficit
        case clearDeficit
        case suggestedMealDurationMinutes
        case suggestedMealTemplateID
        case suggestedTitle
        case suggestedCalories
        case suggestedProteinGrams
        case suggestedStartMinute
        case suggestionDisposition
        case suggestionIsUserEdited
        case note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(EntityID.self, forKey: .id)
        localDay = try container.decode(Date.self, forKey: .localDay)
        substantialMealsRequired = try container.decode(
            Int.self,
            forKey: .substantialMealsRequired
        )
        substantialMealsCovered = try container.decodeIfPresent(
            Int.self,
            forKey: .substantialMealsCovered
        ) ?? 0
        estimatedCalories = try container.decodeIfPresent(
            Int.self,
            forKey: .estimatedCalories
        ) ?? 0
        estimatedProteinGrams = try container.decodeIfPresent(
            Int.self,
            forKey: .estimatedProteinGrams
        ) ?? 0
        approximateCalorieDeficit = try container.decodeIfPresent(
            Int.self,
            forKey: .approximateCalorieDeficit
        ) ?? 0
        approximateProteinDeficit = try container.decodeIfPresent(
            Int.self,
            forKey: .approximateProteinDeficit
        ) ?? 0
        clearDeficit = try container.decodeIfPresent(
            Bool.self,
            forKey: .clearDeficit
        ) ?? false
        suggestedMealDurationMinutes = try container.decodeIfPresent(
            Int.self,
            forKey: .suggestedMealDurationMinutes
        ) ?? 30
        suggestedMealTemplateID = try container.decodeIfPresent(
            EntityID.self,
            forKey: .suggestedMealTemplateID
        )
        suggestedTitle = try container.decodeIfPresent(
            String.self,
            forKey: .suggestedTitle
        ) ?? "Additional eating block"
        suggestedCalories = try container.decodeIfPresent(
            Int.self,
            forKey: .suggestedCalories
        ) ?? 0
        suggestedProteinGrams = try container.decodeIfPresent(
            Int.self,
            forKey: .suggestedProteinGrams
        ) ?? 0
        suggestedStartMinute = try container.decodeIfPresent(
            Int.self,
            forKey: .suggestedStartMinute
        )
        suggestionDisposition = try container.decodeIfPresent(
            NutritionSuggestionDisposition.self,
            forKey: .suggestionDisposition
        ) ?? (clearDeficit ? .scheduled : .notNeeded)
        suggestionIsUserEdited = try container.decodeIfPresent(
            Bool.self,
            forKey: .suggestionIsUserEdited
        ) ?? false
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

public enum SchedulingDecisionKind: String, Codable, Equatable, Sendable {
    case placed
    case preserved
    case moved
    case omitted
    case protected
    case transitionInserted
    case recoveryAdjusted
    case freeTimePreserved
    case confirmationRequired
}

public enum SchedulingRule: String, Codable, Equatable, Sendable {
    case fixedCommitment
    case immutableExternalEvent
    case sleepProtection
    case nutritionCoverage
    case protectedCommitment
    case projectPriority
    case routineDueWindow
    case compatibleBundling
    case dependency
    case preparationAndTravel
    case fiveMinuteGrid
    case recoveryContext
    case preMatchRestriction
    case postMatchRestriction
    case footballTrainingLoad
    case painRestriction
    case minimumUsefulBlock
    case stability
    case freeTime
    case overload
    case repeatedMissFeedback
    case consequenceConfirmation
}

public struct SchedulingDecision: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var kind: SchedulingDecisionKind
    public var rule: SchedulingRule
    public var missionID: EntityID?
    public var routineID: EntityID?
    public var scheduleBlockID: EntityID?
    public var title: String
    public var explanation: String
    public var previousStart: Date?
    public var newStart: Date?
    public var requiresConfirmation: Bool

    public init(
        id: EntityID = EntityID(),
        kind: SchedulingDecisionKind,
        rule: SchedulingRule,
        missionID: EntityID? = nil,
        routineID: EntityID? = nil,
        scheduleBlockID: EntityID? = nil,
        title: String,
        explanation: String,
        previousStart: Date? = nil,
        newStart: Date? = nil,
        requiresConfirmation: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.rule = rule
        self.missionID = missionID
        self.routineID = routineID
        self.scheduleBlockID = scheduleBlockID
        self.title = title
        self.explanation = explanation
        self.previousStart = previousStart
        self.newStart = newStart
        self.requiresConfirmation = requiresConfirmation
    }
}

public enum SchedulingConflictKind: String, Codable, Equatable, Sendable {
    case fixedOverlap
    case sleepConflict
    case transitionUnavailable
    case noValidWindow
    case dependencyUnavailable
    case recoveryRestricted
    case dueWindowMissed
    case recurrenceAnchorMissing
}

public enum SchedulingConflictSeverity: String, Codable, Equatable, Sendable {
    case warning
    case blocking
}

public struct SchedulingConflict: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var kind: SchedulingConflictKind
    public var severity: SchedulingConflictSeverity
    public var title: String
    public var explanation: String
    public var affectedMissionID: EntityID?
    public var affectedCommitmentIDs: [EntityID]
    public var rangeStart: Date?
    public var rangeEnd: Date?

    public init(
        id: EntityID = EntityID(),
        kind: SchedulingConflictKind,
        severity: SchedulingConflictSeverity,
        title: String,
        explanation: String,
        affectedMissionID: EntityID? = nil,
        affectedCommitmentIDs: [EntityID] = [],
        rangeStart: Date? = nil,
        rangeEnd: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.title = title
        self.explanation = explanation
        self.affectedMissionID = affectedMissionID
        self.affectedCommitmentIDs = affectedCommitmentIDs
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
    }
}

public struct SchedulingPlanMetadata: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var horizonStart: Date
    public var horizonEnd: Date
    public var gridMinutes: Int

    public init(
        generatedAt: Date,
        horizonStart: Date,
        horizonEnd: Date,
        gridMinutes: Int = 5
    ) {
        precondition(horizonEnd > horizonStart)
        precondition(gridMinutes > 0)
        self.generatedAt = generatedAt
        self.horizonStart = horizonStart
        self.horizonEnd = horizonEnd
        self.gridMinutes = gridMinutes
    }

    public func contains(_ date: Date) -> Bool {
        date >= horizonStart && date < horizonEnd
    }
}
