import Foundation

public enum NutritionPlanningCoordinator {
    @discardableResult
    public static func reconcile(
        snapshot: inout MissionControlSnapshot,
        referenceDate: Date,
        identifiers: any IdentifierGenerating = StableIdentifierGenerator()
    ) -> NutritionReconciliationResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(
            identifier: snapshot.profile.timeZoneIdentifier
        ) ?? .current
        let horizonStart = calendar.startOfDay(for: referenceDate)
        let horizonEnd = calendar.date(
            byAdding: .day,
            value: snapshot.profile.planningPolicy.planningHorizonDays,
            to: horizonStart
        ) ?? horizonStart.addingTimeInterval(7 * 86_400)
        let targets = snapshot.profile.nutritionTargets
        let priorNeeds = snapshot.nutritionPlanningNeeds
        var updatedNeeds: [NutritionPlanningNeed] = []
        var changedNeedIDs: [EntityID] = []

        for offset in 0..<snapshot.profile.planningPolicy
            .planningHorizonDays {
            guard let day = calendar.date(
                byAdding: .day,
                value: offset,
                to: horizonStart
            ) else {
                continue
            }
            let meals = snapshot.plannedMeals.filter {
                calendar.isDate($0.localDay, inSameDayAs: day)
            }
            let calories = meals.reduce(0) {
                $0 + $1.estimatedCalories
            }
            let protein = meals.reduce(0) {
                $0 + $1.estimatedProteinGrams
            }
            let substantialMeals = meals.filter(\.isSubstantial).count
            let calorieDeficit = max(
                targets.approximateCalories - calories,
                0
            )
            let proteinDeficit = max(
                targets.approximateProteinGrams - protein,
                0
            )
            let substantialDeficit = max(
                targets.substantialMeals - substantialMeals,
                0
            )
            let isClearDeficit =
                (
                    calorieDeficit > 0
                        && calorieDeficit
                            >= targets.clearCalorieDeficitThreshold
                )
                || (
                    proteinDeficit > 0
                        && proteinDeficit
                            >= targets.clearProteinDeficitThreshold
                )
                || (
                    substantialDeficit > 0
                        && substantialDeficit
                            >= targets.clearSubstantialMealDeficitThreshold
                )
            let existing = priorNeeds.first {
                calendar.isDate($0.localDay, inSameDayAs: day)
            }
            var need = existing ?? NutritionPlanningNeed(
                id: identifiers.identifier(
                    namespace: "nutrition.need.\(dayKey(day, calendar: calendar))"
                ),
                localDay: day,
                substantialMealsRequired: targets.substantialMeals
            )
            need.localDay = day
            need.substantialMealsRequired = targets.substantialMeals
            need.substantialMealsCovered = substantialMeals
            need.estimatedCalories = calories
            need.estimatedProteinGrams = protein
            need.approximateCalorieDeficit = calorieDeficit
            need.approximateProteinDeficit = proteinDeficit
            need.clearDeficit = isClearDeficit
            need.note = "Approximate planning estimate, not a precise nutrition measurement."

            if isClearDeficit {
                if need.suggestionDisposition != .declined {
                    need.suggestionDisposition = .scheduled
                }
                if !need.suggestionIsUserEdited {
                    let template = bestSuggestion(
                        templates: snapshot.mealTemplates,
                        calorieDeficit: calorieDeficit,
                        proteinDeficit: proteinDeficit,
                        missingSubstantialMeals: substantialDeficit
                    )
                    need.suggestedMealTemplateID = template?.id
                    need.suggestedTitle =
                        template?.title ?? "Additional eating block"
                    need.suggestedCalories =
                        template?.estimatedCalories ?? 0
                    need.suggestedProteinGrams =
                        template?.estimatedProteinGrams ?? 0
                    need.suggestedMealDurationMinutes = max(
                        targets.additionalEatingBlockMinutes,
                        template?.prepTimeMinutes ?? 0
                    )
                    need.suggestedStartMinute = suggestedStartMinute(
                        meals: meals,
                        preferredMealStartMinutes:
                            targets.preferredMealStartMinutes
                    )
                }
            } else {
                need.suggestionDisposition = .notNeeded
                need.suggestionIsUserEdited = false
            }
            updatedNeeds.append(need)
            if existing != need {
                changedNeedIDs.append(need.id)
            }
        }

        updatedNeeds.append(contentsOf: priorNeeds.filter {
            let day = calendar.startOfDay(for: $0.localDay)
            return day < horizonStart || day >= horizonEnd
        })
        snapshot.nutritionPlanningNeeds = updatedNeeds.sorted {
            $0.localDay < $1.localDay
        }

        let addedShoppingItemIDs = reconcileShoppingShortages(
            snapshot: &snapshot,
            referenceDate: referenceDate,
            horizonEnd: horizonEnd,
            calendar: calendar,
            identifiers: identifiers
        )
        return NutritionReconciliationResult(
            changedNutritionNeedIDs: changedNeedIDs,
            addedShoppingItemIDs: addedShoppingItemIDs
        )
    }

    private static func bestSuggestion(
        templates: [MealTemplate],
        calorieDeficit: Int,
        proteinDeficit: Int,
        missingSubstantialMeals: Int
    ) -> MealTemplate? {
        templates.filter(\.isEnabled).max { left, right in
            suggestionScore(
                left,
                calorieDeficit: calorieDeficit,
                proteinDeficit: proteinDeficit,
                missingSubstantialMeals: missingSubstantialMeals
            ) < suggestionScore(
                right,
                calorieDeficit: calorieDeficit,
                proteinDeficit: proteinDeficit,
                missingSubstantialMeals: missingSubstantialMeals
            )
        }
    }

    private static func suggestionScore(
        _ template: MealTemplate,
        calorieDeficit: Int,
        proteinDeficit: Int,
        missingSubstantialMeals: Int
    ) -> Double {
        let calorieCoverage = Double(
            min(template.estimatedCalories, max(calorieDeficit, 1))
        ) / Double(max(calorieDeficit, 1))
        let proteinCoverage = Double(
            min(template.estimatedProteinGrams, max(proteinDeficit, 1))
        ) / Double(max(proteinDeficit, 1))
        let substantialBonus =
            missingSubstantialMeals > 0 && template.isSubstantial ? 1.0 : 0
        let practicality = 1 / Double(max(template.prepTimeMinutes, 5))
        return calorieCoverage + proteinCoverage + substantialBonus
            + practicality
    }

    private static func suggestedStartMinute(
        meals: [PlannedMeal],
        preferredMealStartMinutes: [Int]
    ) -> Int {
        let usedMinutes = Set(meals.compactMap(\.preferredStartMinute))
        if let unused = preferredMealStartMinutes.first(where: {
            !usedMinutes.contains($0)
        }) {
            return unused
        }
        let latest = meals.compactMap(\.preferredStartMinute).max()
            ?? preferredMealStartMinutes.max()
            ?? 19 * 60
        return min(latest + 150, 22 * 60)
    }

    private static func reconcileShoppingShortages(
        snapshot: inout MissionControlSnapshot,
        referenceDate: Date,
        horizonEnd: Date,
        calendar: Calendar,
        identifiers: any IdentifierGenerating
    ) -> [EntityID] {
        let nextShoppingWindow = nextShoppingWindow(
            snapshot: snapshot,
            after: referenceDate
        )
        var consumptionByInventory: [EntityID: [(Date, Double)]] = [:]
        let templateByID = Dictionary(
            uniqueKeysWithValues: snapshot.mealTemplates.map { ($0.id, $0) }
        )
        let consumptionStart = calendar.startOfDay(for: referenceDate)
        for meal in snapshot.plannedMeals
        where meal.localDay >= consumptionStart
            && meal.localDay < horizonEnd {
            let missionID = identifiers.identifier(
                namespace:
                    "nutrition.planned.\(meal.id.rawValue.uuidString)"
            )
            guard !snapshot.completions.contains(where: {
                $0.missionID == missionID
                    && ($0.status == .completed || $0.status == .partial)
            }) else {
                continue
            }
            guard let templateID = meal.mealTemplateID,
                  let template = templateByID[templateID] else {
                continue
            }
            for usage in template.inventoryUsage {
                consumptionByInventory[usage.inventoryItemID, default: []]
                    .append((meal.localDay, usage.amount))
            }
        }
        for need in snapshot.nutritionPlanningNeeds
        where need.clearDeficit
            && need.suggestionDisposition == .scheduled
            && need.localDay >= consumptionStart
            && need.localDay < horizonEnd {
            let missionID = identifiers.identifier(
                namespace:
                    "nutrition.suggestion.\(need.id.rawValue.uuidString)"
            )
            guard !snapshot.completions.contains(where: {
                $0.missionID == missionID
                    && ($0.status == .completed || $0.status == .partial)
            }) else {
                continue
            }
            guard let templateID = need.suggestedMealTemplateID,
                  let template = templateByID[templateID] else {
                continue
            }
            for usage in template.inventoryUsage {
                consumptionByInventory[usage.inventoryItemID, default: []]
                    .append((need.localDay, usage.amount))
            }
        }

        var addedIDs: [EntityID] = []
        for inventory in snapshot.inventoryItems
        where inventory.automaticallyAddToShopping {
            let events = consumptionByInventory[inventory.id, default: []]
                .sorted { $0.0 < $1.0 }
            let shortageDate = predictedShortageDate(
                inventory: inventory,
                consumptionEvents: events,
                referenceDate: referenceDate
            )
            guard let shortageDate,
                  shortageDate < horizonEnd else {
                continue
            }
            if let nextShoppingWindow,
               shortageDate > nextShoppingWindow {
                continue
            }
            let leadSeconds = TimeInterval(
                snapshot.profile.nutritionTargets.inventoryShoppingLeadHours
                    * 60 * 60
            )
            let dueDate = max(
                referenceDate,
                shortageDate.addingTimeInterval(-leadSeconds)
            )
            let reason =
                "Likely to run short before the next practical shopping window. Approximate estimate."
            if updateExistingShoppingItem(
                inventory: inventory,
                dueDate: dueDate,
                reason: reason,
                snapshot: &snapshot
            ) {
                continue
            }
            let completedCycles = snapshot.checklists
                .filter { $0.kind == .shopping }
                .flatMap(\.items)
                .filter {
                    $0.inventoryItemID == inventory.id && $0.isCompleted
                }
                .count
            let itemID = identifiers.identifier(
                namespace:
                    "shopping.shortage.\(inventory.id.rawValue.uuidString).\(completedCycles)"
            )
            let item = ChecklistItem(
                id: itemID,
                title: inventory.name,
                dueDate: dueDate,
                quantity: inventory.shoppingQuantity,
                inventoryItemID: inventory.id,
                suggestionReason: reason
            )
            _ = snapshot.addChecklistItem(kind: .shopping, item: item)
            addedIDs.append(itemID)
        }
        return addedIDs
    }

    private static func predictedShortageDate(
        inventory: InventoryItem,
        consumptionEvents: [(Date, Double)],
        referenceDate: Date
    ) -> Date? {
        if inventory.state == .empty || inventory.state == .low {
            return referenceDate
        }
        let available = inventory.exactQuantity
            ?? inventory.mealsRemaining.map { Double($0) }
        guard let available else {
            return nil
        }
        var consumed = 0.0
        for (date, amount) in consumptionEvents {
            consumed += amount
            if consumed > available {
                return date
            }
        }
        return nil
    }

    private static func nextShoppingWindow(
        snapshot: MissionControlSnapshot,
        after date: Date
    ) -> Date? {
        let scheduled = snapshot.scheduleBlocks.filter {
            $0.end >= date && isShoppingText($0.title)
        }.map { max($0.start, date) }
        let supermarketCommitments = snapshot.fixedCommitments.filter {
            $0.end >= date
                && (
                    $0.contextTags.contains(where: {
                        $0.lowercased() == "supermarket"
                    })
                    || isShoppingText($0.title)
                    || ($0.location.map(isShoppingText) ?? false)
                )
        }.map(\.end)
        return (scheduled + supermarketCommitments).min()
    }

    private static func isShoppingText(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.contains("grocer")
            || normalized.contains("shopping")
            || normalized.contains("supermarket")
    }

    private static func updateExistingShoppingItem(
        inventory: InventoryItem,
        dueDate: Date,
        reason: String,
        snapshot: inout MissionControlSnapshot
    ) -> Bool {
        for checklistIndex in snapshot.checklists.indices
        where snapshot.checklists[checklistIndex].kind == .shopping {
            guard let itemIndex = snapshot.checklists[checklistIndex].items
                .firstIndex(where: {
                    !$0.isCompleted
                        && (
                            $0.inventoryItemID == inventory.id
                            || $0.title.caseInsensitiveCompare(
                                inventory.name
                            ) == .orderedSame
                        )
                }) else {
                continue
            }
            snapshot.checklists[checklistIndex].items[itemIndex]
                .inventoryItemID = inventory.id
            snapshot.checklists[checklistIndex].items[itemIndex].dueDate =
                min(
                    snapshot.checklists[checklistIndex].items[itemIndex]
                        .dueDate ?? dueDate,
                    dueDate
                )
            snapshot.checklists[checklistIndex].items[itemIndex]
                .suggestionReason = reason
            if snapshot.checklists[checklistIndex].items[itemIndex]
                .quantity == nil {
                snapshot.checklists[checklistIndex].items[itemIndex]
                    .quantity = inventory.shoppingQuantity
            }
            return true
        }
        return false
    }

    private static func dayKey(
        _ date: Date,
        calendar: Calendar
    ) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

public extension MissionControlSnapshot {
    mutating func decrementInventoryForCompletedMeal(
        missionID: EntityID,
        at date: Date
    ) {
        guard let mission = mission(withID: missionID),
              let templateID = mission.mealTemplateID,
              let template = mealTemplates.first(where: {
                  $0.id == templateID
              }) else {
            return
        }
        if let plannedMealID = mission.plannedMealID,
           plannedMeals.first(where: {
               $0.id == plannedMealID
           })?.decrementInventoryOnCompletion == false {
            return
        }
        for usage in template.inventoryUsage {
            guard let index = inventoryItems.firstIndex(where: {
                $0.id == usage.inventoryItemID
            }) else {
                continue
            }
            if let quantity = inventoryItems[index].exactQuantity {
                let remaining = max(quantity - usage.amount, 0)
                inventoryItems[index].exactQuantity = remaining
                if remaining == 0 {
                    inventoryItems[index].state = .empty
                } else if let threshold =
                    inventoryItems[index].lowQuantityThreshold,
                    remaining <= threshold {
                    inventoryItems[index].state = .low
                } else {
                    inventoryItems[index].state = .available
                }
            } else if let meals = inventoryItems[index].mealsRemaining {
                let remaining = max(meals - Int(ceil(usage.amount)), 0)
                inventoryItems[index].mealsRemaining = remaining
                inventoryItems[index].state = remaining == 0
                    ? .empty
                    : remaining <= 1 ? .low : .available
            }
            inventoryItems[index].updatedAt = date
        }
    }
}
