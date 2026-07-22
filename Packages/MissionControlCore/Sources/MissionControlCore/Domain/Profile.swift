import Foundation

public struct MinuteRange: Codable, Equatable, Sendable {
    public var minimum: Int
    public var maximum: Int

    public init(minimum: Int, maximum: Int) {
        precondition(minimum >= 0 && maximum >= minimum)
        self.minimum = minimum
        self.maximum = maximum
    }
}

public struct WeeklyTarget: Codable, Equatable, Sendable {
    public var minimum: Int
    public var preferred: Int

    public init(minimum: Int, preferred: Int) {
        precondition(minimum >= 0 && preferred >= minimum)
        self.minimum = minimum
        self.preferred = preferred
    }
}

public struct WorkPattern: Codable, Equatable, Sendable {
    public var typicalWeekdays: [Weekday]
    public var actualShiftsAreFixedCommitments: Bool

    public init(typicalWeekdays: [Weekday], actualShiftsAreFixedCommitments: Bool) {
        self.typicalWeekdays = typicalWeekdays
        self.actualShiftsAreFixedCommitments = actualShiftsAreFixedCommitments
    }
}

public struct FootballPattern: Codable, Equatable, Sendable {
    public var trainingWeekdays: [Weekday]
    public var historicalTrainingStartMinute: Int
    public var historicalTrainingDurationMinutes: Int
    public var likelyMatchWeekdays: [Weekday]
    public var historicalTimeIsConfigurable: Bool

    public init(
        trainingWeekdays: [Weekday],
        historicalTrainingStartMinute: Int,
        historicalTrainingDurationMinutes: Int,
        likelyMatchWeekdays: [Weekday],
        historicalTimeIsConfigurable: Bool
    ) {
        self.trainingWeekdays = trainingWeekdays
        self.historicalTrainingStartMinute = historicalTrainingStartMinute
        self.historicalTrainingDurationMinutes = historicalTrainingDurationMinutes
        self.likelyMatchWeekdays = likelyMatchWeekdays
        self.historicalTimeIsConfigurable = historicalTimeIsConfigurable
    }
}

public struct TransitionDefaults: Codable, Equatable, Sendable {
    public var workTravelEachWayMinutes: Int
    public var footballTravelEachWayMinutes: Int
    public var gymTravelEachWayMinutes: Int
    public var shoppingTravelMinutes: Int
    public var workPreparationMinutes: MinuteRange
    public var footballPreparationMinutes: MinuteRange
    public var gymPreparationMinutes: MinuteRange
    public var gymShowerChangeMinutes: MinuteRange
    public var footballShowerChangeMinutes: MinuteRange

    public init(
        workTravelEachWayMinutes: Int,
        footballTravelEachWayMinutes: Int,
        gymTravelEachWayMinutes: Int,
        shoppingTravelMinutes: Int,
        workPreparationMinutes: MinuteRange,
        footballPreparationMinutes: MinuteRange,
        gymPreparationMinutes: MinuteRange,
        gymShowerChangeMinutes: MinuteRange,
        footballShowerChangeMinutes: MinuteRange
    ) {
        self.workTravelEachWayMinutes = workTravelEachWayMinutes
        self.footballTravelEachWayMinutes = footballTravelEachWayMinutes
        self.gymTravelEachWayMinutes = gymTravelEachWayMinutes
        self.shoppingTravelMinutes = shoppingTravelMinutes
        self.workPreparationMinutes = workPreparationMinutes
        self.footballPreparationMinutes = footballPreparationMinutes
        self.gymPreparationMinutes = gymPreparationMinutes
        self.gymShowerChangeMinutes = gymShowerChangeMinutes
        self.footballShowerChangeMinutes = footballShowerChangeMinutes
    }
}

public struct NutritionTargets: Codable, Equatable, Sendable {
    public var approximateCalories: Int
    public var approximateProteinGrams: Int
    public var substantialMeals: Int

    public init(approximateCalories: Int, approximateProteinGrams: Int, substantialMeals: Int) {
        self.approximateCalories = approximateCalories
        self.approximateProteinGrams = approximateProteinGrams
        self.substantialMeals = substantialMeals
    }
}

public struct UserProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var displayName: String
    public var timeZoneIdentifier: String
    public var uses24HourTime: Bool
    public var hasRegularUniversityLectures: Bool
    public var planningPolicy: PlanningPolicy
    public var workPattern: WorkPattern
    public var footballPattern: FootballPattern
    public var gymWeeklyTarget: WeeklyTarget
    public var transitions: TransitionDefaults
    public var nutritionTargets: NutritionTargets
    public var categoryAccents: [CategoryAccentPreference]

    public init(
        id: EntityID = EntityID(),
        displayName: String,
        timeZoneIdentifier: String,
        uses24HourTime: Bool,
        hasRegularUniversityLectures: Bool,
        planningPolicy: PlanningPolicy,
        workPattern: WorkPattern,
        footballPattern: FootballPattern,
        gymWeeklyTarget: WeeklyTarget,
        transitions: TransitionDefaults,
        nutritionTargets: NutritionTargets,
        categoryAccents: [CategoryAccentPreference]
    ) {
        self.id = id
        self.displayName = displayName
        self.timeZoneIdentifier = timeZoneIdentifier
        self.uses24HourTime = uses24HourTime
        self.hasRegularUniversityLectures = hasRegularUniversityLectures
        self.planningPolicy = planningPolicy
        self.workPattern = workPattern
        self.footballPattern = footballPattern
        self.gymWeeklyTarget = gymWeeklyTarget
        self.transitions = transitions
        self.nutritionTargets = nutritionTargets
        self.categoryAccents = categoryAccents
    }

    public func accent(for category: MissionCategory) -> AccentName {
        categoryAccents.first(where: { $0.category == category })?.accent ?? .blue
    }
}
