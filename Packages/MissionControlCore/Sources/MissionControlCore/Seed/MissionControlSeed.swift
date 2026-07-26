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
            priorityOverride: .critical,
            weeklyPlannedMinutes: 6 * 60
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

        var seededHouseholdRoutines = householdRoutines
        for index in seededHouseholdRoutines.indices {
            seededHouseholdRoutines[index].anchorDate = horizonStart
        }

        let milk = InventoryItem(
            name: "Milk",
            state: .low,
            mealsRemaining: 1,
            shoppingQuantity: "2 bottles",
            updatedAt: referenceDate
        )
        let oats = InventoryItem(
            name: "Oats",
            state: .available,
            exactQuantity: 1,
            quantityUnit: "kg",
            lowQuantityThreshold: 0.2,
            shoppingQuantity: "1 bag",
            updatedAt: referenceDate
        )
        let chicken = InventoryItem(
            name: "Chicken",
            state: .available,
            mealsRemaining: 4,
            shoppingQuantity: "4 meals",
            updatedAt: referenceDate
        )
        let rice = InventoryItem(
            name: "Rice",
            state: .available,
            exactQuantity: 1,
            quantityUnit: "kg",
            lowQuantityThreshold: 0.2,
            shoppingQuantity: "1 bag",
            updatedAt: referenceDate
        )
        let oatsTemplate = MealTemplate(
            title: "Oats breakfast",
            estimatedCalories: 850,
            estimatedProteinGrams: 45,
            prepTimeMinutes: 10,
            inventoryUsage: [
                MealInventoryUsage(
                    inventoryItemID: milk.id,
                    note: "One serving"
                ),
                MealInventoryUsage(
                    inventoryItemID: oats.id,
                    amount: 0.1,
                    note: "About 100 g"
                )
            ],
            note: "Approximate saved breakfast."
        )
        let chickenRiceTemplate = MealTemplate(
            title: "Batch chicken and rice",
            estimatedCalories: 1_200,
            estimatedProteinGrams: 75,
            prepTimeMinutes: 10,
            inventoryUsage: [
                MealInventoryUsage(inventoryItemID: chicken.id),
                MealInventoryUsage(
                    inventoryItemID: rice.id,
                    amount: 0.15,
                    note: "About 150 g"
                )
            ],
            note: "Uses a prepared batch portion."
        )
        let dinnerTemplate = MealTemplate(
            title: "Flexible substantial dinner",
            estimatedCalories: 950,
            estimatedProteinGrams: 50,
            prepTimeMinutes: 25,
            note: "Edit the estimate when the usual dinner changes."
        )
        let snackTemplate = MealTemplate(
            title: "Easy calorie-and-protein snack",
            estimatedCalories: 650,
            estimatedProteinGrams: 35,
            prepTimeMinutes: 5,
            isSubstantial: false,
            note: "A practical fallback, not a precise nutrition prescription."
        )
        func workingSets(
            _ count: Int,
            _ minimumReps: Int,
            _ maximumReps: Int
        ) -> [WorkoutSetPrescription] {
            (0..<count).map { _ in
                WorkoutSetPrescription(
                    targetRepMinimum: minimumReps,
                    targetRepMaximum: maximumReps
                )
            }
        }
        let upperA = WorkoutSessionTemplate(
            title: "Upper A",
            detail: "Approved upper-body strength session.",
            exercises: [
                ExercisePrescription(
                    title: "Bench press",
                    sets: workingSets(3, 6, 8),
                    restDurationSeconds: 150,
                    targetLoad: 70,
                    progressionNotes: "Add load only after all sets reach the top of the range.",
                    bodyAreaTags: ["chest", "shoulder", "triceps"],
                    physicalLoad: .heavy
                ),
                ExercisePrescription(
                    title: "Chest-supported row",
                    sets: workingSets(3, 8, 10),
                    restDurationSeconds: 120,
                    bodyAreaTags: ["upper back", "biceps"]
                ),
                ExercisePrescription(
                    title: "Incline dumbbell press",
                    sets: workingSets(3, 8, 12),
                    restDurationSeconds: 90,
                    bodyAreaTags: ["chest", "shoulder", "triceps"]
                ),
                ExercisePrescription(
                    title: "Lat pulldown",
                    sets: workingSets(3, 8, 12),
                    restDurationSeconds: 90,
                    bodyAreaTags: ["upper back", "biceps"]
                )
            ]
        )
        let lowerA = WorkoutSessionTemplate(
            title: "Lower A",
            detail: "Approved lower-body strength session.",
            exercises: [
                ExercisePrescription(
                    title: "Back squat",
                    sets: workingSets(3, 5, 7),
                    restDurationSeconds: 180,
                    progressionNotes: "Keep two controlled reps in reserve.",
                    bodyAreaTags: ["lower body", "quadriceps", "glute"],
                    physicalLoad: .heavy
                ),
                ExercisePrescription(
                    title: "Romanian deadlift",
                    sets: workingSets(3, 6, 8),
                    restDurationSeconds: 150,
                    bodyAreaTags: ["lower body", "hamstring", "glute"],
                    physicalLoad: .heavy
                ),
                ExercisePrescription(
                    title: "Leg curl",
                    sets: workingSets(3, 10, 12),
                    restDurationSeconds: 90,
                    bodyAreaTags: ["hamstring"]
                ),
                ExercisePrescription(
                    title: "Standing calf raise",
                    sets: workingSets(3, 10, 15),
                    restDurationSeconds: 60,
                    bodyAreaTags: ["calf"]
                )
            ],
            estimatedDurationMinutes: 65
        )
        let upperB = WorkoutSessionTemplate(
            title: "Upper B",
            detail: "Approved upper-body strength session.",
            exercises: [
                ExercisePrescription(
                    title: "Overhead press",
                    sets: workingSets(3, 6, 8),
                    restDurationSeconds: 150,
                    bodyAreaTags: ["shoulder", "triceps"],
                    physicalLoad: .heavy
                ),
                ExercisePrescription(
                    title: "Pull-up",
                    sets: workingSets(3, 6, 10),
                    restDurationSeconds: 120,
                    bodyAreaTags: ["upper back", "biceps"]
                ),
                ExercisePrescription(
                    title: "Cable row",
                    sets: workingSets(3, 8, 12),
                    restDurationSeconds: 90,
                    bodyAreaTags: ["upper back", "biceps"]
                ),
                ExercisePrescription(
                    title: "Lateral raise",
                    sets: workingSets(3, 12, 15),
                    restDurationSeconds: 60,
                    bodyAreaTags: ["shoulder"]
                )
            ]
        )
        let lowerB = WorkoutSessionTemplate(
            title: "Lower B",
            detail: "Approved lower-body strength session.",
            exercises: [
                ExercisePrescription(
                    title: "Trap-bar deadlift",
                    sets: workingSets(3, 4, 6),
                    restDurationSeconds: 180,
                    bodyAreaTags: ["lower body", "hamstring", "glute"],
                    physicalLoad: .heavy
                ),
                ExercisePrescription(
                    title: "Bulgarian split squat",
                    sets: workingSets(3, 8, 10),
                    restDurationSeconds: 120,
                    bodyAreaTags: ["lower body", "quadriceps", "glute"],
                    physicalLoad: .heavy
                ),
                ExercisePrescription(
                    title: "Hip thrust",
                    sets: workingSets(3, 8, 12),
                    restDurationSeconds: 90,
                    bodyAreaTags: ["glute", "hamstring"]
                ),
                ExercisePrescription(
                    title: "Seated calf raise",
                    sets: workingSets(3, 10, 15),
                    restDurationSeconds: 60,
                    bodyAreaTags: ["calf"]
                )
            ],
            estimatedDurationMinutes: 65
        )
        let approvedProgram = WorkoutProgram(
            title: "Approved upper / lower",
            detail: "Four-session rotation used exactly as saved.",
            isApproved: true,
            isActive: true,
            sessionTemplates: [upperA, lowerA, upperB, lowerB]
        )
        let templates = [
            oatsTemplate,
            chickenRiceTemplate,
            dinnerTemplate,
            snackTemplate
        ]
        var plannedMeals: [PlannedMeal] = []
        for dayOffset in 0..<profile.planningPolicy.planningHorizonDays {
            guard let day = calendar.date(
                byAdding: .day,
                value: dayOffset,
                to: horizonStart
            ) else {
                continue
            }
            for (index, template) in templates.prefix(3).enumerated() {
                plannedMeals.append(
                    PlannedMeal(
                        localDay: day,
                        mealTemplateID: template.id,
                        title: template.title,
                        estimatedCalories: template.estimatedCalories,
                        estimatedProteinGrams:
                            template.estimatedProteinGrams,
                        estimatedDurationMinutes: max(
                            30,
                            template.prepTimeMinutes + 20
                        ),
                        isSubstantial: template.isSubstantial,
                        preferredStartMinute:
                            profile.nutritionTargets
                                .preferredMealStartMinutes[index]
                    )
                )
            }
        }

        var snapshot = MissionControlSnapshot(
            profile: profile,
            goals: [goal],
            projects: [project],
            missions: [projectMission, gymMission],
            scheduleBlocks: [],
            fixedCommitments: [],
            routines: [footballRoutine] + seededHouseholdRoutines,
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
                        ChecklistItem(
                            title: "Milk",
                            quantity: "2 bottles",
                            inventoryItemID: milk.id
                        ),
                        ChecklistItem(
                            title: "Rice",
                            quantity: "1 bag",
                            inventoryItemID: rice.id
                        ),
                        ChecklistItem(
                            title: "Chicken",
                            quantity: "4 meals",
                            inventoryItemID: chicken.id
                        )
                    ]
                )
            ],
            mealTemplates: templates,
            plannedMeals: plannedMeals,
            inventoryItems: [milk, oats, chicken, rice],
            approvedWorkouts: [
                ApprovedWorkout(
                    missionID: gymMission.id,
                    programID: approvedProgram.id,
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
            workoutPrograms: [approvedProgram]
        )
        _ = NutritionPlanningCoordinator.reconcile(
            snapshot: &snapshot,
            referenceDate: referenceDate
        )
        return snapshot
    }

    public static func makeFresh(
        referenceDate: Date = Date()
    ) -> MissionControlSnapshot {
        var profile = makeDemo(referenceDate: referenceDate).profile
        profile.displayName = ""
        return MissionControlSnapshot(profile: profile)
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

    public static var householdRoutines: [Routine] {
        let tidyingID = EntityID()
        let laundryID = EntityID()
        let groceriesID = EntityID()
        let mealPreparationID = EntityID()
        return [
        Routine(
            id: tidyingID,
            title: "Light tidying",
            category: .household,
            rigidity: .flexible,
            recurrence: RecurrencePattern(frequency: .daily),
            estimatedDurationMinutes: 15,
            dueWindowMinutes: 12 * 60,
            compatibleRoutineIDs: [laundryID],
            allowsCompatibleOverlap: true,
            bundlingNote: "Clean while football laundry is running."
        ),
        Routine(
            id: laundryID,
            title: "Football laundry",
            category: .household,
            rigidity: .protected,
            recurrence: RecurrencePattern(frequency: .afterEvent, triggerCategory: .football),
            estimatedDurationMinutes: 15,
            dueWindowMinutes: 24 * 60,
            note: "After training or a match; use the next viable window when needed.",
            compatibleRoutineIDs: [tidyingID],
            allowsCompatibleOverlap: true,
            bundlingNote: "Light tidying can overlap the machine cycle."
        ),
        Routine(
            id: groceriesID,
            title: "Groceries",
            category: .household,
            rigidity: .flexible,
            recurrence: RecurrencePattern(frequency: .daily, interval: 3),
            estimatedDurationMinutes: 35,
            dueWindowMinutes: 24 * 60,
            note: "Editable seed cadence: every two to three days.",
            flexibleCadence: FlexibleCadence(
                minimumDays: 2,
                maximumDays: 3
            ),
            compatibleRoutineIDs: [mealPreparationID],
            bundlingNote: "Keep groceries close to meal preparation or a supermarket work shift."
        ),
        Routine(
            id: mealPreparationID,
            title: "Meal preparation",
            category: .nutrition,
            rigidity: .protected,
            recurrence: RecurrencePattern(frequency: .daily, interval: 3),
            estimatedDurationMinutes: 75,
            dueWindowMinutes: 24 * 60,
            note: "Editable seed cadence: every two to three days.",
            flexibleCadence: FlexibleCadence(
                minimumDays: 2,
                maximumDays: 3
            ),
            compatibleRoutineIDs: [groceriesID],
            bundlingNote: "Schedule close to groceries when practical."
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

}
