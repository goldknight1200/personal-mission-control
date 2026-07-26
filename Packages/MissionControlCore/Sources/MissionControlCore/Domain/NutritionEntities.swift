import Foundation

public struct MealInventoryUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var inventoryItemID: EntityID
    public var amount: Double
    public var note: String?

    public init(
        id: EntityID = EntityID(),
        inventoryItemID: EntityID,
        amount: Double = 1,
        note: String? = nil
    ) {
        precondition(amount > 0)
        self.id = id
        self.inventoryItemID = inventoryItemID
        self.amount = amount
        self.note = note
    }
}

public struct MealTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var title: String
    public var estimatedCalories: Int
    public var estimatedProteinGrams: Int
    public var prepTimeMinutes: Int
    public var isSubstantial: Bool
    public var inventoryUsage: [MealInventoryUsage]
    public var note: String?
    public var isEnabled: Bool

    public init(
        id: EntityID = EntityID(),
        title: String,
        estimatedCalories: Int,
        estimatedProteinGrams: Int,
        prepTimeMinutes: Int,
        isSubstantial: Bool = true,
        inventoryUsage: [MealInventoryUsage] = [],
        note: String? = nil,
        isEnabled: Bool = true
    ) {
        precondition(estimatedCalories >= 0)
        precondition(estimatedProteinGrams >= 0)
        precondition(prepTimeMinutes >= 0)
        self.id = id
        self.title = title
        self.estimatedCalories = estimatedCalories
        self.estimatedProteinGrams = estimatedProteinGrams
        self.prepTimeMinutes = prepTimeMinutes
        self.isSubstantial = isSubstantial
        self.inventoryUsage = inventoryUsage
        self.note = note
        self.isEnabled = isEnabled
    }
}

public struct PlannedMeal: Codable, Equatable, Identifiable, Sendable {
    public var id: EntityID
    public var localDay: Date
    public var mealTemplateID: EntityID?
    public var title: String
    public var estimatedCalories: Int
    public var estimatedProteinGrams: Int
    public var estimatedDurationMinutes: Int
    public var isSubstantial: Bool
    public var preferredStartMinute: Int?
    public var decrementInventoryOnCompletion: Bool

    public init(
        id: EntityID = EntityID(),
        localDay: Date,
        mealTemplateID: EntityID? = nil,
        title: String,
        estimatedCalories: Int,
        estimatedProteinGrams: Int,
        estimatedDurationMinutes: Int = 30,
        isSubstantial: Bool = true,
        preferredStartMinute: Int? = nil,
        decrementInventoryOnCompletion: Bool = true
    ) {
        precondition(estimatedCalories >= 0)
        precondition(estimatedProteinGrams >= 0)
        precondition(estimatedDurationMinutes > 0)
        self.id = id
        self.localDay = localDay
        self.mealTemplateID = mealTemplateID
        self.title = title
        self.estimatedCalories = estimatedCalories
        self.estimatedProteinGrams = estimatedProteinGrams
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.isSubstantial = isSubstantial
        self.preferredStartMinute = preferredStartMinute
        self.decrementInventoryOnCompletion =
            decrementInventoryOnCompletion
    }
}

public enum NutritionSuggestionDisposition:
    String,
    CaseIterable,
    Codable,
    Equatable,
    Sendable
{
    case notNeeded
    case scheduled
    case declined
}

public struct NutritionReconciliationResult: Equatable, Sendable {
    public var changedNutritionNeedIDs: [EntityID]
    public var addedShoppingItemIDs: [EntityID]

    public init(
        changedNutritionNeedIDs: [EntityID] = [],
        addedShoppingItemIDs: [EntityID] = []
    ) {
        self.changedNutritionNeedIDs = changedNutritionNeedIDs
        self.addedShoppingItemIDs = addedShoppingItemIDs
    }
}
