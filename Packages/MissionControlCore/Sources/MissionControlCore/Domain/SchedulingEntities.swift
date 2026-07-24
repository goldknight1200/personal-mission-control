import Foundation

public enum FatigueLevel: String, CaseIterable, Codable, Equatable, Sendable {
    case none
    case mild
    case moderate
    case high
}

/// Minimal local recovery information required by the deterministic planner.
///
/// Detailed HealthKit samples remain outside the core and are not required.
public struct RecoveryContext: Codable, Equatable, Sendable {
    public var recordedAt: Date
    public var sleepDurationMinutes: Int?
    public var fatigue: FatigueLevel
    public var note: String?

    public init(
        recordedAt: Date,
        sleepDurationMinutes: Int? = nil,
        fatigue: FatigueLevel = .none,
        note: String? = nil
    ) {
        self.recordedAt = recordedAt
        self.sleepDurationMinutes = sleepDurationMinutes
        self.fatigue = fatigue
        self.note = note
    }
}

/// Scheduling-only projection of a user-approved workout.
///
/// Exercise prescriptions and workout execution remain Phase 7 concerns.
public struct ApprovedWorkout: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var missionID: EntityID
    public var preferredWeekdays: [Weekday]
    public var weeklySessionTarget: Int
    public var preferredStartMinute: Int?
    public var isEnabled: Bool

    public init(
        id: EntityID = EntityID(),
        missionID: EntityID,
        preferredWeekdays: [Weekday] = [],
        weeklySessionTarget: Int = 1,
        preferredStartMinute: Int? = nil,
        isEnabled: Bool = true
    ) {
        precondition(weeklySessionTarget >= 0)
        self.id = id
        self.missionID = missionID
        self.preferredWeekdays = preferredWeekdays
        self.weeklySessionTarget = weeklySessionTarget
        self.preferredStartMinute = preferredStartMinute
        self.isEnabled = isEnabled
    }
}

/// A daily aggregate used to reserve practical eating time.
///
/// Full meal templates, inventory inference, and macro planning remain Phase 6.
public struct NutritionPlanningNeed: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var localDay: Date
    public var substantialMealsRequired: Int
    public var substantialMealsCovered: Int
    public var clearDeficit: Bool
    public var suggestedMealDurationMinutes: Int
    public var note: String?

    public init(
        id: EntityID = EntityID(),
        localDay: Date,
        substantialMealsRequired: Int,
        substantialMealsCovered: Int = 0,
        clearDeficit: Bool = false,
        suggestedMealDurationMinutes: Int = 30,
        note: String? = nil
    ) {
        precondition(substantialMealsRequired >= 0)
        precondition(substantialMealsCovered >= 0)
        precondition(suggestedMealDurationMinutes > 0)
        self.id = id
        self.localDay = localDay
        self.substantialMealsRequired = substantialMealsRequired
        self.substantialMealsCovered = substantialMealsCovered
        self.clearDeficit = clearDeficit
        self.suggestedMealDurationMinutes = suggestedMealDurationMinutes
        self.note = note
    }

    public var missingMealCount: Int {
        max(substantialMealsRequired - substantialMealsCovered, 0)
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
