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
        let mealMission = Mission(
            category: .nutrition,
            title: "Substantial meal",
            rigidity: .protected,
            importance: .high,
            estimatedDurationMinutes: 30,
            minimumUsefulBlockMinutes: 20,
            consistencyCost: .high,
            energyDemand: .low
        )
        let tidyMission = Mission(
            category: .household,
            title: "Light tidy",
            rigidity: .flexible,
            importance: .normal,
            urgency: .normal,
            estimatedDurationMinutes: 15,
            minimumUsefulBlockMinutes: 10,
            energyDemand: .low,
            physicalLoad: .light
        )

        let start = snapToFiveMinutes(referenceDate.addingTimeInterval(-20 * 60))
        let projectEnd = start.addingTimeInterval(60 * 60)
        let preparationEnd = projectEnd.addingTimeInterval(10 * 60)
        let travelEnd = preparationEnd.addingTimeInterval(16 * 60)
        let gymEnd = travelEnd.addingTimeInterval(60 * 60)
        let returnEnd = gymEnd.addingTimeInterval(16 * 60)
        let showerEnd = returnEnd.addingTimeInterval(30 * 60)
        let mealEnd = showerEnd.addingTimeInterval(30 * 60)
        let tidyEnd = mealEnd.addingTimeInterval(15 * 60)

        let blocks = [
            ScheduleBlock(
                missionID: projectMission.id,
                title: projectMission.title,
                category: .project,
                kind: .mission,
                rigidity: .protected,
                start: start,
                end: projectEnd
            ),
            ScheduleBlock(
                title: "Prepare for gym",
                category: .gym,
                kind: .preparation,
                rigidity: .fixed,
                start: projectEnd,
                end: preparationEnd
            ),
            ScheduleBlock(
                title: "Travel to gym",
                category: .gym,
                kind: .travel,
                rigidity: .fixed,
                start: preparationEnd,
                end: travelEnd
            ),
            ScheduleBlock(
                missionID: gymMission.id,
                title: gymMission.title,
                category: .gym,
                kind: .mission,
                rigidity: .protected,
                start: travelEnd,
                end: gymEnd
            ),
            ScheduleBlock(
                title: "Travel home",
                category: .gym,
                kind: .travel,
                rigidity: .fixed,
                start: gymEnd,
                end: returnEnd
            ),
            ScheduleBlock(
                title: "Shower and change",
                category: .recovery,
                kind: .preparation,
                rigidity: .fixed,
                start: returnEnd,
                end: showerEnd
            ),
            ScheduleBlock(
                missionID: mealMission.id,
                title: mealMission.title,
                category: .nutrition,
                kind: .meal,
                rigidity: .protected,
                start: showerEnd,
                end: mealEnd
            ),
            ScheduleBlock(
                missionID: tidyMission.id,
                title: tidyMission.title,
                category: .household,
                kind: .mission,
                rigidity: .flexible,
                start: mealEnd,
                end: tidyEnd
            )
        ]

        let nextTrainingStart = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let training = FixedCommitment(
            title: "Football training — configurable default",
            category: .football,
            start: nextTrainingStart,
            end: nextTrainingStart.addingTimeInterval(120 * 60),
            location: "Training ground"
        )

        return MissionControlSnapshot(
            profile: profile,
            goals: [goal],
            projects: [project],
            missions: [projectMission, gymMission, mealMission, tidyMission],
            scheduleBlocks: blocks,
            fixedCommitments: [training],
            routines: householdRoutines,
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
            ]
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

    private static func snapToFiveMinutes(_ date: Date) -> Date {
        let grid = 5.0 * 60.0
        let snapped = floor(date.timeIntervalSinceReferenceDate / grid) * grid
        return Date(timeIntervalSinceReferenceDate: snapped)
    }
}
