import Foundation

public struct WorkoutSetPrescription: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var targetRepMinimum: Int
    public var targetRepMaximum: Int

    public init(
        id: EntityID = EntityID(),
        targetReps: Int
    ) {
        self.init(
            id: id,
            targetRepMinimum: targetReps,
            targetRepMaximum: targetReps
        )
    }

    public init(
        id: EntityID = EntityID(),
        targetRepMinimum: Int,
        targetRepMaximum: Int
    ) {
        precondition(targetRepMinimum > 0)
        precondition(targetRepMaximum >= targetRepMinimum)
        self.id = id
        self.targetRepMinimum = targetRepMinimum
        self.targetRepMaximum = targetRepMaximum
    }

    public var targetRepText: String {
        targetRepMinimum == targetRepMaximum
            ? "\(targetRepMinimum)"
            : "\(targetRepMinimum)–\(targetRepMaximum)"
    }
}

public struct ExercisePrescription: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var title: String
    public var sets: [WorkoutSetPrescription]
    public var restDurationSeconds: Int
    public var targetLoad: Double?
    public var progressionNotes: String?
    public var bodyAreaTags: [String]
    public var physicalLoad: PhysicalLoad

    public init(
        id: EntityID = EntityID(),
        title: String,
        sets: [WorkoutSetPrescription],
        restDurationSeconds: Int,
        targetLoad: Double? = nil,
        progressionNotes: String? = nil,
        bodyAreaTags: [String] = [],
        physicalLoad: PhysicalLoad = .moderate
    ) {
        precondition(!sets.isEmpty)
        precondition(restDurationSeconds >= 0)
        self.id = id
        self.title = title
        self.sets = sets
        self.restDurationSeconds = restDurationSeconds
        self.targetLoad = targetLoad
        self.progressionNotes = progressionNotes
        self.bodyAreaTags = bodyAreaTags
        self.physicalLoad = physicalLoad
    }
}

public struct WorkoutSessionTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var title: String
    public var detail: String
    public var exercises: [ExercisePrescription]
    public var estimatedDurationMinutes: Int

    public init(
        id: EntityID = EntityID(),
        title: String,
        detail: String = "",
        exercises: [ExercisePrescription],
        estimatedDurationMinutes: Int = 60
    ) {
        precondition(estimatedDurationMinutes > 0)
        self.id = id
        self.title = title
        self.detail = detail
        self.exercises = exercises
        self.estimatedDurationMinutes = estimatedDurationMinutes
    }

    public var physicalLoad: PhysicalLoad {
        if exercises.contains(where: { $0.physicalLoad == .heavy }) {
            return .heavy
        }
        if exercises.contains(where: { $0.physicalLoad == .moderate }) {
            return .moderate
        }
        if exercises.contains(where: { $0.physicalLoad == .light }) {
            return .light
        }
        return .none
    }

    public var bodyAreaTags: [String] {
        Array(Set(exercises.flatMap(\.bodyAreaTags))).sorted()
    }
}

public struct WorkoutProgram: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var title: String
    public var detail: String
    public var isApproved: Bool
    public var isActive: Bool
    public var sessionTemplates: [WorkoutSessionTemplate]

    public init(
        id: EntityID = EntityID(),
        title: String,
        detail: String = "",
        isApproved: Bool = false,
        isActive: Bool = false,
        sessionTemplates: [WorkoutSessionTemplate] = []
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isApproved = isApproved
        self.isActive = isActive
        self.sessionTemplates = sessionTemplates
    }
}

public struct ScheduledWorkoutMetadata: Codable, Equatable, Sendable {
    public var programID: EntityID
    public var sessionTemplateID: EntityID
    public var exerciseIDs: [EntityID]
    public var blockedExerciseIDs: [EntityID]
    public var isShortened: Bool

    public init(
        programID: EntityID,
        sessionTemplateID: EntityID,
        exerciseIDs: [EntityID],
        blockedExerciseIDs: [EntityID] = [],
        isShortened: Bool = false
    ) {
        self.programID = programID
        self.sessionTemplateID = sessionTemplateID
        self.exerciseIDs = exerciseIDs
        self.blockedExerciseIDs = blockedExerciseIDs
        self.isShortened = isShortened
    }
}

public struct WorkoutSetLog: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var prescriptionSetID: EntityID
    public var setNumber: Int
    public var weight: Double?
    public var reps: Int
    public var completedAt: Date

    public init(
        id: EntityID = EntityID(),
        prescriptionSetID: EntityID,
        setNumber: Int,
        weight: Double?,
        reps: Int,
        completedAt: Date
    ) {
        precondition(setNumber > 0)
        precondition(reps >= 0)
        self.id = id
        self.prescriptionSetID = prescriptionSetID
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.completedAt = completedAt
    }
}

public struct WorkoutExerciseLog: Codable, Equatable, Identifiable, Sendable {
    public var exerciseID: EntityID
    public var setLogs: [WorkoutSetLog]

    public var id: EntityID { exerciseID }

    public init(
        exerciseID: EntityID,
        setLogs: [WorkoutSetLog] = []
    ) {
        self.exerciseID = exerciseID
        self.setLogs = setLogs
    }
}

public enum WorkoutLogStatus: String, Codable, Equatable, Sendable {
    case inProgress
    case completed
    case partial
}

public struct WorkoutLog: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var programID: EntityID
    public var sessionTemplateID: EntityID
    public var missionID: EntityID
    public var scheduleBlockID: EntityID
    public var selectedExerciseIDs: [EntityID]
    public var isShortened: Bool
    public var startedAt: Date
    public var completedAt: Date?
    public var status: WorkoutLogStatus
    public var exerciseLogs: [WorkoutExerciseLog]
    public var currentExerciseID: EntityID?
    public var currentSetIndex: Int?
    public var restTimerEndsAt: Date?

    public init(
        id: EntityID = EntityID(),
        programID: EntityID,
        sessionTemplateID: EntityID,
        missionID: EntityID,
        scheduleBlockID: EntityID,
        selectedExerciseIDs: [EntityID],
        isShortened: Bool = false,
        startedAt: Date,
        completedAt: Date? = nil,
        status: WorkoutLogStatus = .inProgress,
        exerciseLogs: [WorkoutExerciseLog] = [],
        currentExerciseID: EntityID? = nil,
        currentSetIndex: Int? = nil,
        restTimerEndsAt: Date? = nil
    ) {
        self.id = id
        self.programID = programID
        self.sessionTemplateID = sessionTemplateID
        self.missionID = missionID
        self.scheduleBlockID = scheduleBlockID
        self.selectedExerciseIDs = selectedExerciseIDs
        self.isShortened = isShortened
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.exerciseLogs = exerciseLogs
        self.currentExerciseID = currentExerciseID
        self.currentSetIndex = currentSetIndex
        self.restTimerEndsAt = restTimerEndsAt
    }
}

public struct ShortenedWorkoutSuggestion: Equatable, Sendable {
    public var programID: EntityID
    public var sessionTemplateID: EntityID
    public var exerciseIDs: [EntityID]
    public var estimatedDurationMinutes: Int
    public var explanation: String

    public init(
        programID: EntityID,
        sessionTemplateID: EntityID,
        exerciseIDs: [EntityID],
        estimatedDurationMinutes: Int,
        explanation: String
    ) {
        self.programID = programID
        self.sessionTemplateID = sessionTemplateID
        self.exerciseIDs = exerciseIDs
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.explanation = explanation
    }
}
