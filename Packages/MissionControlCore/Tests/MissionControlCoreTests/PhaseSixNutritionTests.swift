import Foundation
import XCTest
@testable import MissionControlCore

final class PhaseSixNutritionTests: XCTestCase {
    private let current = Date(timeIntervalSince1970: 1_785_061_800)

    func testCoverageDetectsApproximateDeficitAndSelectsSavedSuggestion() throws {
        var snapshot = emptyNutritionSnapshot()
        let meal = MealTemplate(
            title: "Fast substantial meal",
            estimatedCalories: 900,
            estimatedProteinGrams: 55,
            prepTimeMinutes: 10
        )
        snapshot.mealTemplates = [meal]
        snapshot.plannedMeals = [
            PlannedMeal(
                localDay: calendar.startOfDay(for: current),
                mealTemplateID: meal.id,
                title: meal.title,
                estimatedCalories: 900,
                estimatedProteinGrams: 55,
                isSubstantial: true
            )
        ]

        NutritionPlanningCoordinator.reconcile(
            snapshot: &snapshot,
            referenceDate: current
        )

        let coverage = try XCTUnwrap(
            snapshot.nutritionPlanningNeeds.first
        )
        XCTAssertTrue(coverage.clearDeficit)
        XCTAssertEqual(coverage.approximateCalorieDeficit, 2_500)
        XCTAssertEqual(coverage.approximateProteinDeficit, 125)
        XCTAssertEqual(coverage.substantialMealsCovered, 1)
        XCTAssertEqual(coverage.suggestedMealTemplateID, meal.id)
        XCTAssertEqual(coverage.suggestionDisposition, .scheduled)
    }

    func testDeficitSuggestionCreatesEditableFoodBlock() throws {
        var snapshot = emptyNutritionSnapshot()
        snapshot.profile.nutritionTargets.substantialMeals = 0
        snapshot.mealTemplates = [
            MealTemplate(
                title: "Saved snack",
                estimatedCalories: 650,
                estimatedProteinGrams: 35,
                prepTimeMinutes: 5,
                isSubstantial: false
            )
        ]
        NutritionPlanningCoordinator.reconcile(
            snapshot: &snapshot,
            referenceDate: current
        )

        let result = SchedulingEngine().makePlan(
            input: PlanningInput(
                snapshot: snapshot,
                currentTime: current
            )
        )

        let block = try XCTUnwrap(result.blocks.first(where: {
            $0.kind == .meal && $0.title.contains("food deficit")
        }))
        XCTAssertNotNil(block.missionID)
        XCTAssertTrue(
            result.decisions.contains {
                $0.scheduleBlockID == block.id
                    && $0.rule == .nutritionCoverage
                    && $0.explanation.contains("approximate")
            }
        )
    }

    func testDeclinedDeficitSuggestionIsNotScheduled() throws {
        var snapshot = emptyNutritionSnapshot()
        snapshot.profile.nutritionTargets.substantialMeals = 0
        NutritionPlanningCoordinator.reconcile(
            snapshot: &snapshot,
            referenceDate: current
        )
        let needID = try XCTUnwrap(
            snapshot.nutritionPlanningNeeds.first?.id
        )
        let index = try XCTUnwrap(
            snapshot.nutritionPlanningNeeds.firstIndex {
                $0.id == needID
            }
        )
        snapshot.nutritionPlanningNeeds[index].suggestionDisposition =
            .declined

        let result = SchedulingEngine().makePlan(
            input: PlanningInput(
                snapshot: snapshot,
                currentTime: current
            )
        )

        XCTAssertFalse(result.generatedMissions.contains {
            $0.nutritionPlanningNeedID == needID
        })
    }

    func testDeficitSuggestionReportsConflictWhenDayHasNoEatingWindow() {
        var snapshot = emptyNutritionSnapshot()
        snapshot.profile.nutritionTargets.substantialMeals = 0
        let day = calendar.startOfDay(for: current)
        snapshot.fixedCommitments = [
            FixedCommitment(
                title: "All-day fixed work",
                category: .work,
                start: localDate(2026, 7, 26, 7, 0),
                end: localDate(2026, 7, 27, 1, 0)
            )
        ]
        snapshot.nutritionPlanningNeeds = [
            NutritionPlanningNeed(
                localDay: day,
                substantialMealsRequired: 0,
                clearDeficit: true,
                suggestedMealDurationMinutes: 30,
                suggestionDisposition: .scheduled
            )
        ]

        let result = SchedulingEngine().makePlan(
            input: PlanningInput(
                snapshot: snapshot,
                currentTime: current
            )
        )

        XCTAssertFalse(result.blocks.contains {
            $0.kind == .meal && $0.title.contains("food deficit")
        })
        XCTAssertTrue(result.conflicts.contains {
            $0.kind == .noValidWindow
                && $0.title == "Food coverage still looks short"
        })
    }

    func testLikelyInventoryShortageAddsOneLinkedShoppingProposal() throws {
        var snapshot = emptyNutritionSnapshot()
        snapshot.profile.nutritionTargets.approximateCalories = 0
        snapshot.profile.nutritionTargets.approximateProteinGrams = 0
        snapshot.profile.nutritionTargets.substantialMeals = 0
        let chicken = InventoryItem(
            name: "Chicken",
            state: .available,
            mealsRemaining: 1,
            shoppingQuantity: "4 meals",
            updatedAt: current
        )
        let template = MealTemplate(
            title: "Chicken meal",
            estimatedCalories: 1_000,
            estimatedProteinGrams: 70,
            prepTimeMinutes: 10,
            inventoryUsage: [
                MealInventoryUsage(inventoryItemID: chicken.id)
            ]
        )
        snapshot.inventoryItems = [chicken]
        snapshot.mealTemplates = [template]
        snapshot.plannedMeals = [0, 1].map { offset in
            PlannedMeal(
                localDay: calendar.date(
                    byAdding: .day,
                    value: offset,
                    to: calendar.startOfDay(for: current)
                )!,
                mealTemplateID: template.id,
                title: template.title,
                estimatedCalories: template.estimatedCalories,
                estimatedProteinGrams:
                    template.estimatedProteinGrams
            )
        }

        let first = NutritionPlanningCoordinator.reconcile(
            snapshot: &snapshot,
            referenceDate: current
        )
        let second = NutritionPlanningCoordinator.reconcile(
            snapshot: &snapshot,
            referenceDate: current
        )

        XCTAssertEqual(first.addedShoppingItemIDs.count, 1)
        XCTAssertTrue(second.addedShoppingItemIDs.isEmpty)
        let item = try XCTUnwrap(
            snapshot.checklist(ofKind: .shopping)?.items.first
        )
        XCTAssertEqual(item.inventoryItemID, chicken.id)
        XCTAssertEqual(item.quantity, "4 meals")
        XCTAssertNotNil(item.suggestionReason)

        let checklist = try XCTUnwrap(
            snapshot.checklist(ofKind: .shopping)
        )
        snapshot.toggleChecklistItem(
            checklistID: checklist.id,
            itemID: item.id,
            at: current
        )
        let afterPurchase = NutritionPlanningCoordinator.reconcile(
            snapshot: &snapshot,
            referenceDate: current
        )
        XCTAssertTrue(afterPurchase.addedShoppingItemIDs.isEmpty)
        XCTAssertEqual(
            snapshot.inventoryItems.first?.mealsRemaining,
            4
        )
        XCTAssertEqual(
            snapshot.checklist(ofKind: .shopping)?.items.filter {
                !$0.isCompleted
            }.count,
            0
        )
    }

    func testMealCompletionOptionallyDecrementsLinkedInventoryOnce() throws {
        var snapshot = emptyNutritionSnapshot()
        let rice = InventoryItem(
            name: "Rice portions",
            state: .available,
            mealsRemaining: 3,
            updatedAt: current
        )
        let template = MealTemplate(
            title: "Rice bowl",
            estimatedCalories: 800,
            estimatedProteinGrams: 35,
            prepTimeMinutes: 10,
            inventoryUsage: [
                MealInventoryUsage(inventoryItemID: rice.id)
            ]
        )
        let plannedMeal = PlannedMeal(
            localDay: calendar.startOfDay(for: current),
            mealTemplateID: template.id,
            title: template.title,
            estimatedCalories: template.estimatedCalories,
            estimatedProteinGrams: template.estimatedProteinGrams
        )
        let mission = Mission(
            category: .nutrition,
            title: template.title,
            rigidity: .protected,
            estimatedDurationMinutes: 30,
            plannedMealID: plannedMeal.id,
            mealTemplateID: template.id
        )
        snapshot.inventoryItems = [rice]
        snapshot.mealTemplates = [template]
        snapshot.plannedMeals = [plannedMeal]
        snapshot.missions = [mission]

        snapshot.completeMission(id: mission.id, at: current)
        snapshot.completeMission(
            id: mission.id,
            at: current.addingTimeInterval(60)
        )

        XCTAssertEqual(snapshot.inventoryItems.first?.mealsRemaining, 2)
        XCTAssertEqual(snapshot.completions.count, 1)
    }

    func testMealCanKeepInventoryUnchangedWhenDecrementIsDisabled() {
        var snapshot = emptyNutritionSnapshot()
        let item = InventoryItem(
            name: "Prepared portions",
            state: .available,
            mealsRemaining: 2,
            updatedAt: current
        )
        let template = MealTemplate(
            title: "Shared meal",
            estimatedCalories: 700,
            estimatedProteinGrams: 40,
            prepTimeMinutes: 5,
            inventoryUsage: [
                MealInventoryUsage(inventoryItemID: item.id)
            ]
        )
        let plannedMeal = PlannedMeal(
            localDay: current,
            mealTemplateID: template.id,
            title: template.title,
            estimatedCalories: 700,
            estimatedProteinGrams: 40,
            decrementInventoryOnCompletion: false
        )
        let mission = Mission(
            category: .nutrition,
            title: template.title,
            rigidity: .protected,
            estimatedDurationMinutes: 30,
            plannedMealID: plannedMeal.id,
            mealTemplateID: template.id
        )
        snapshot.inventoryItems = [item]
        snapshot.mealTemplates = [template]
        snapshot.plannedMeals = [plannedMeal]
        snapshot.missions = [mission]

        snapshot.completeMission(id: mission.id, at: current)

        XCTAssertEqual(snapshot.inventoryItems.first?.mealsRemaining, 2)
    }

    private func emptyNutritionSnapshot() -> MissionControlSnapshot {
        var snapshot = MissionControlSeed.makeDemo(referenceDate: current)
        snapshot.missions = []
        snapshot.scheduleBlocks = []
        snapshot.fixedCommitments = []
        snapshot.routines = []
        snapshot.checklists = [
            Checklist(title: "Shopping", kind: .shopping)
        ]
        snapshot.completions = []
        snapshot.mealTemplates = []
        snapshot.plannedMeals = []
        snapshot.inventoryItems = []
        snapshot.nutritionPlanningNeeds = []
        snapshot.approvedWorkouts = []
        snapshot.schedulingPlanMetadata = nil
        return snapshot
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func localDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}
