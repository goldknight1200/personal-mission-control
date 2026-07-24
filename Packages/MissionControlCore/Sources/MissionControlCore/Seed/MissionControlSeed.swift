import Foundation

public enum MissionControlSeed {
    public static func makeDemo(referenceDate: Date = Date()) -> MissionControlSnapshot {
        let timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let profile = UserProfile(
            displayName: "Ethan",
            timeZoneIdentifier: timeZone.identifier,
            uses24HourTime: true,
            hasRegularUniversityLectures: false,
            planningPolicy: .baseline,
            workPattern: WorkPattern(
                typicalWeekdays: [.monday, .wednesday, .friday, .saturday],
                actualShiftsAreFixedCommitments: true
            ),
            footballPattern: FootballPattern(
                trainingWeekdays: [.tuesday, .thursday],
                historicalTrainingStartMinute: 18 * 60 + 30,
                historicalTrainingDurationMinutes: 120,
                likelyMatchWeekdays: [.saturday, .sunday],
                historicalTimeIsConfigurable: true
            ),
            gymWeeklyTarget: WeeklyTarget(minimum: 4, preferred: 5),
            transitions: TransitionDefaults(
                workTravelEachWayMinutes: 10,
                footballTravelEachWayMinutes: 10,
                gymTravelEachWayMinutes: 16,
                shoppingTravelMinutes: 5,
                workPreparationMinutes: MinuteRange(minimum: 10, maximum: 15),
                footballPreparationMinutes: MinuteRange(minimum: 10, maximum: 15),
                gymPreparationMinutes: MinuteRange(minimum: 5, maximum: 9),
                gymShowerChangeMinutes: MinuteRange(minimum: 25, maximum: 30),
                footballShowerChangeMinutes: MinuteRange(minimum: 25, maximum: 30)
            ),
            nutritionTargets: NutritionTargets(
                approximateCalories: 3_400,
                approximateProteinGrams: 180,
                substantialMeals: 3
            ),
            categoryAccents: defaultAccents
        )

        let goal = Goal(
            title: "Build a dependable personal operating system",
            detail: "Reduce daily decision load while protecting recovery and consistency.",
            category: .project
        )
        let project = Project(
            goalID: goal.id,
            title: "Personal Mission Control",
            detail: "Deliver a useful local vertical slice.",
            status: .activePriority,
            targetDate: calendar.date(byAdding: .day, value: 14, to: referenceDate),
            priorityOverride: .critical
        )

        let projectMission = Mission(
            projectID: project.id,
            category: .project,
            title: "Build the first usable vertical slice",
            miniGoals: [
                MissionStep(title: "Keep the core framework-independent"),
                MissionStep(title: "Make the Home timeline clear"),
                MissionStep(title: "Persist completion locally")
            ],
            rigidity: .protected,
            importance: .critical,
            urgency: .high,
            deadline: project.targetDate,
            estimatedDurationMinutes: 60,
            minimumUsefulBlockMinutes: 30,
            consistencyCost: .high,
            backlogCost: .high,
            energyDemand: .high,
            allowsSplitting: true,
            userPriorityOverride: .critical
        )
        let gymMission = Mission(
            category: .gym,
            title: "Approved gym session",
            miniGoals: [
                MissionStep(title: "Follow the approved session"),
                MissionStep(title: "Record working sets")
            ],
            rigidity: .protected,
            importance: .high,
            urgency: .normal,
            estimatedDurationMinutes: 60,
            minimumUsefulBlockMinutes: 45,
            consistencyCost: .high,
            energyDemand: .high,
            physicalLoad: .moderate,
            preparationMinutes: 8,
            travelBeforeMinutes: profile.transitions.gymTravelEachWayMinutes,
            travelAfterMinutes: profile.transitions.gymTravelEachWayMinutes,
            location: "Gym"
        )
        let horizonStart = calendar.startOfDay(for: referenceDate)
        let nutritionNeeds = (0..<profile.planningPolicy.planningHorizonDays)
            .compactMap { dayOffset -> NutritionPlanningNeed? in
                guard let day = calendar.date(
                    byAdding: .day,
                    value: dayOffset,
                    to: horizonStart
                ) else {
                    return nil
                }
                return NutritionPlanningNeed(
                    localDay: day,
                    substantialMealsRequired:
                        profile.nutritionTargets.substantialMeals
                )
            }
        let footballRoutine = Routine(
            title: "Football training — configurable default",
            category: .football,
            rigidity: .protected,
            recurrence: RecurrencePattern(
                frequency: .weekly,
                weekdays: profile.footballPattern.trainingWeekdays,
                preferredStartMinute:
                    profile.footballPattern.historicalTrainingStartMinute
            ),
            estimatedDurationMinutes:
                profile.footballPattern.historicalTrainingDurationMinutes,
            dueWindowMinutes: 120,
            note: "Historical preference only; actual sessions can replace it."
        )

        return MissionControlSnapshot(
            profile: profile,
            goals: [goal],
            projects: [project],
            missions: [projectMission, gymMission],
            scheduleBlocks: [],
            fixedCommitments: [],
            routines: [footballRoutine] + householdRoutines,
            checklists: [
                Checklist(
                    title: "Today",
                    kind: .today,
                    items: [
                        ChecklistItem(title: "Reply to the university email"),
                        ChecklistItem(title: "Refill water bottle"),
                        ChecklistItem(title: "Put gym kit by the door")
                    ]
                ),
                Checklist(
                    title: "Shopping",
                    kind: .shopping,
                    items: [
                        ChecklistItem(title: "Milk", quantity: "2 bottles"),
                        ChecklistItem(title: "Rice", quantity: "1 bag"),
                        ChecklistItem(title: "Chicken", quantity: "4 meals")
                    ]
                )
            ],
            inventoryItems: [
                InventoryItem(
                    name: "Milk",
                    state: .low,
                    quantityNote: "One serving remaining",
                    updatedAt: referenceDate
                )
            ],
            approvedWorkouts: [
                ApprovedWorkout(
                    missionID: gymMission.id,
                    preferredWeekdays: [
                        .monday,
                        .wednesday,
                        .friday,
                        .sunday
                    ],
                    weeklySessionTarget: profile.gymWeeklyTarget.minimum,
                    preferredStartMinute: 16 * 60
                )
            ],
            nutritionPlanningNeeds: nutritionNeeds
        )
    }

    public static let defaultAccents: [CategoryAccentPreference] = [
        CategoryAccentPreference(category: .work, accent: .blue),
        CategoryAccentPreference(category: .football, accent: .green),
        CategoryAccentPreference(category: .gym, accent: .orange),
        CategoryAccentPreference(category: .project, accent: .indigo),
        CategoryAccentPreference(category: .nutrition, accent: .teal),
        CategoryAccentPreference(category: .household, accent: .purple),
        CategoryAccentPreference(category: .personal, accent: .blue),
        CategoryAccentPreference(category: .recovery, accent: .green),
        CategoryAccentPreference(category: .travel, accent: .gray),
        CategoryAccentPreference(category: .preparation, accent: .gray),
        CategoryAccentPreference(category: .freeTime, accent: .teal)
    ]

    public static let householdRoutines: [Routine] = [
        Routine(
            title: "Light tidying",
            category: .household,
            rigidity: .flexible,
            recurrence: RecurrencePattern(frequency: .daily),
            estimatedDurationMinutes: 15,
            dueWindowMinutes: 12 * 60
        ),
        Routine(
            title: "Football laundry",
            category: .household,
            rigidity: .protected,
            recurrence: RecurrencePattern(frequency: .afterEvent, triggerCategory: .football),
            estimatedDurationMinutes: 15,
            dueWindowMinutes: 24 * 60,
            note: "After training or a match; use the next viable window when needed."
        ),
        Routine(
            title: "Groceries",
            category: .household,
            rigidity: .flexible,
            recurrence: RecurrencePattern(frequency: .daily, interval: 3),
            estimatedDurationMinutes: 35,
            dueWindowMinutes: 24 * 60,
            note: "Editable seed cadence: every two to three days."
        ),
        Routine(
            title: "Meal preparation",
            category: .nutrition,
            rigidity: .protected,
            recurrence: RecurrencePattern(frequency: .daily, interval: 3),
            estimatedDurationMinutes: 75,
            dueWindowMinutes: 24 * 60,
            note: "Editable seed cadence: every two to three days."
        ),
        Routine(
            title: "Take out trash",
            category: .household,
            rigidity: .flexible,
            recurrence: RecurrencePattern(
                frequency: .weekly,
                weekdays: [.sunday],
                preferredStartMinute: 20 * 60
            ),
            estimatedDurationMinutes: 10,
            dueWindowMinutes: 180
        ),
        Routine(
            title: "Change bedsheets",
            category: .household,
            rigidity: .deferrable,
            recurrence: RecurrencePattern(frequency: .monthly),
            estimatedDurationMinutes: 20,
            dueWindowMinutes: 3 * 24 * 60
        )
    ]

}
