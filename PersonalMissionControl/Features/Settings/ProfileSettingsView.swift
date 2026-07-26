import Foundation
import MissionControlCore
import SwiftUI

struct ProfileSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (UserProfile) -> Void

    @State private var draft: UserProfile

    init(profile: UserProfile, onSave: @escaping (UserProfile) -> Void) {
        self.onSave = onSave
        _draft = State(initialValue: profile)
    }

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name", text: $draft.displayName)
                TextField("Time zone", text: $draft.timeZoneIdentifier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if TimeZone(identifier: draft.timeZoneIdentifier) == nil {
                    Text("Enter an IANA time zone such as Europe/Berlin.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Toggle("Use 24-hour time", isOn: $draft.uses24HourTime)
                Toggle("Regular university lectures", isOn: $draft.hasRegularUniversityLectures)
            }

            Section("Planning defaults") {
                Stepper(
                    "Planning horizon: \(draft.planningPolicy.planningHorizonDays) days",
                    value: $draft.planningPolicy.planningHorizonDays,
                    in: 1...21
                )
                Stepper(
                    "Focused block minimum: \(draft.planningPolicy.minimumFocusedBlockMinutes) min",
                    value: $draft.planningPolicy.minimumFocusedBlockMinutes,
                    in: 10...120,
                    step: 5
                )
                Stepper(
                    "Generated grid: \(draft.planningPolicy.generatedGridMinutes) min",
                    value: $draft.planningPolicy.generatedGridMinutes,
                    in: 1...15
                )
            }

            Section("Sleep targets") {
                Stepper(
                    "Target: \(draft.planningPolicy.sleepTargetMinutes / 60)h \(draft.planningPolicy.sleepTargetMinutes % 60)m",
                    value: $draft.planningPolicy.sleepTargetMinutes,
                    in: draft.planningPolicy.practicalSleepMinimumMinutes...600,
                    step: 15
                )
                Stepper(
                    "Practical minimum: \(draft.planningPolicy.practicalSleepMinimumMinutes / 60)h \(draft.planningPolicy.practicalSleepMinimumMinutes % 60)m",
                    value: $draft.planningPolicy.practicalSleepMinimumMinutes,
                    in: draft.planningPolicy.reconsiderDemandingWorkBelowMinutes...draft.planningPolicy.sleepTargetMinutes,
                    step: 15
                )
                Stepper(
                    "Reconsider demanding work below: \(draft.planningPolicy.reconsiderDemandingWorkBelowMinutes / 60)h \(draft.planningPolicy.reconsiderDemandingWorkBelowMinutes % 60)m",
                    value: $draft.planningPolicy.reconsiderDemandingWorkBelowMinutes,
                    in: 240...draft.planningPolicy.practicalSleepMinimumMinutes,
                    step: 15
                )
                Stepper(
                    "Preferred wake: \(MissionControlFormatters.minuteOfDay(draft.planningPolicy.preferredWakeMinute))",
                    value: $draft.planningPolicy.preferredWakeMinute,
                    in: 4 * 60...12 * 60,
                    step: 15
                )
                Text("These are editable planning defaults: 7.5-hour target, 6.5-hour practical minimum, and a six-hour context threshold.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Typical work pattern") {
                weekdayPicker(selection: $draft.workPattern.typicalWeekdays)
                Toggle("Entered shifts become fixed", isOn: $draft.workPattern.actualShiftsAreFixedCommitments)
            }

            Section("Football defaults") {
                Text("Training days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                weekdayPicker(selection: $draft.footballPattern.trainingWeekdays)
                Text("Likely match days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                weekdayPicker(selection: $draft.footballPattern.likelyMatchWeekdays)
                Stepper(
                    "Historical start: \(MissionControlFormatters.minuteOfDay(draft.footballPattern.historicalTrainingStartMinute))",
                    value: $draft.footballPattern.historicalTrainingStartMinute,
                    in: 0...(23 * 60 + 30),
                    step: 30
                )
                Stepper(
                    "Historical duration: \(draft.footballPattern.historicalTrainingDurationMinutes) min",
                    value: $draft.footballPattern.historicalTrainingDurationMinutes,
                    in: 30...240,
                    step: 15
                )
                Text("These times are configurable historical defaults, not authoritative fixtures.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Gym target") {
                Stepper(
                    "Minimum: \(draft.gymWeeklyTarget.minimum) sessions",
                    value: $draft.gymWeeklyTarget.minimum,
                    in: 0...draft.gymWeeklyTarget.preferred
                )
                Stepper(
                    "Preferred: \(draft.gymWeeklyTarget.preferred) sessions",
                    value: $draft.gymWeeklyTarget.preferred,
                    in: draft.gymWeeklyTarget.minimum...7
                )
            }

            Section("Transition estimates") {
                minuteStepper("Work each way", value: $draft.transitions.workTravelEachWayMinutes)
                minuteStepper("Football each way", value: $draft.transitions.footballTravelEachWayMinutes)
                minuteStepper("Gym each way", value: $draft.transitions.gymTravelEachWayMinutes)
                minuteStepper("Shopping", value: $draft.transitions.shoppingTravelMinutes)
                minuteRangeSteppers("Work preparation", range: $draft.transitions.workPreparationMinutes)
                minuteRangeSteppers("Football preparation", range: $draft.transitions.footballPreparationMinutes)
                minuteRangeSteppers("Gym preparation", range: $draft.transitions.gymPreparationMinutes)
                minuteRangeSteppers("Gym shower/change", range: $draft.transitions.gymShowerChangeMinutes)
                minuteRangeSteppers("Football shower/change", range: $draft.transitions.footballShowerChangeMinutes)
            }

            Section("Nutrition targets") {
                Stepper(
                    "About \(draft.nutritionTargets.approximateCalories) kcal",
                    value: $draft.nutritionTargets.approximateCalories,
                    in: 1_200...6_000,
                    step: 100
                )
                Stepper(
                    "About \(draft.nutritionTargets.approximateProteinGrams) g protein",
                    value: $draft.nutritionTargets.approximateProteinGrams,
                    in: 40...350,
                    step: 5
                )
                Stepper(
                    "\(draft.nutritionTargets.substantialMeals) substantial meals",
                    value: $draft.nutritionTargets.substantialMeals,
                    in: 1...8
                )
                ForEach(
                    draft.nutritionTargets.preferredMealStartMinutes.indices,
                    id: \.self
                ) { index in
                    Stepper(
                        "Meal \(index + 1): \(MissionControlFormatters.minuteOfDay(draft.nutritionTargets.preferredMealStartMinutes[index]))",
                        value: $draft.nutritionTargets.preferredMealStartMinutes[index],
                        in: 0...23 * 60 + 55,
                        step: 5
                    )
                }
                Text("Targets are practical estimates, not an exact tracking requirement.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Household defaults") {
                Text("The editable routine records are visible under Lists: daily tidying, post-football laundry, groceries and meal prep every two to three days, Sunday trash, and monthly bedsheets.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Save changes") {
                    draft.planningPolicy.timeZoneIdentifier = draft.timeZoneIdentifier
                    onSave(draft)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .disabled(TimeZone(identifier: draft.timeZoneIdentifier) == nil)
            }
        }
    }

    private func weekdayPicker(selection: Binding<[Weekday]>) -> some View {
        HStack(spacing: 5) {
            ForEach(Weekday.allCases) { day in
                let isSelected = selection.wrappedValue.contains(day)
                Button(String(day.shortName.prefix(2))) {
                    if isSelected {
                        selection.wrappedValue.removeAll(where: { $0 == day })
                    } else {
                        selection.wrappedValue.append(day)
                        selection.wrappedValue.sort(by: { $0.rawValue < $1.rawValue })
                    }
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
                )
                .buttonStyle(.plain)
                .accessibilityLabel(day.shortName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func minuteStepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper("\(title): \(value.wrappedValue) min", value: value, in: 0...90, step: 1)
    }

    @ViewBuilder
    private func minuteRangeSteppers(_ title: String, range: Binding<MinuteRange>) -> some View {
        Stepper(
            "\(title) minimum: \(range.wrappedValue.minimum) min",
            value: range.minimum,
            in: 0...range.wrappedValue.maximum
        )
        Stepper(
            "\(title) maximum: \(range.wrappedValue.maximum) min",
            value: range.maximum,
            in: range.wrappedValue.minimum...90
        )
    }
}

struct AppearanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (UserProfile) -> Void

    @State private var draft: UserProfile

    init(profile: UserProfile, onSave: @escaping (UserProfile) -> Void) {
        self.onSave = onSave
        _draft = State(initialValue: profile)
    }

    var body: some View {
        Form {
            Section {
                ForEach(MissionCategory.allCases) { category in
                    Picker(category.displayName, selection: accentBinding(for: category)) {
                        ForEach(AccentName.allCases) { accent in
                            Label(accent.displayName, systemImage: "circle.fill")
                                .foregroundStyle(accent.color)
                                .tag(accent)
                        }
                    }
                }
            } header: {
                Text("Category accents")
            } footer: {
                Text("Accents support recognition. Status and meaning never depend on color alone.")
            }

            Section {
                Button("Save changes") {
                    onSave(draft)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func accentBinding(for category: MissionCategory) -> Binding<AccentName> {
        Binding(
            get: { draft.accent(for: category) },
            set: { newValue in
                if let index = draft.categoryAccents.firstIndex(where: { $0.category == category }) {
                    draft.categoryAccents[index].accent = newValue
                } else {
                    draft.categoryAccents.append(
                        CategoryAccentPreference(category: category, accent: newValue)
                    )
                }
            }
        )
    }
}

@MainActor
struct NutritionView: View {
    @ObservedObject var model: AppModel

    @State private var targets: NutritionTargets
    @State private var templateEditor: MealTemplateEditorSelection?
    @State private var plannedMealEditor: PlannedMealEditorSelection?
    @State private var inventoryEditor: InventoryEditorSelection?
    @State private var suggestionEditor: NutritionSuggestionEditorSelection?

    init(model: AppModel) {
        self.model = model
        _targets = State(
            initialValue: model.snapshot.profile.nutritionTargets
        )
    }

    var body: some View {
        List {
            Section {
                Text("These are planning estimates. They are not clinical measurements, and the app does not require detailed food logging.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            targetsSection
            coverageSection
            plannedMealsSection
            templatesSection
            inventorySection
            mealPrepSection
        }
        .listStyle(.insetGrouped)
        .sheet(item: $templateEditor) { selection in
            MealTemplateEditor(
                template: selection.template,
                inventory: model.snapshot.inventoryItems
            ) { template in
                model.saveMealTemplate(template)
            }
        }
        .sheet(item: $plannedMealEditor) { selection in
            PlannedMealEditor(
                plannedMeal: selection.plannedMeal,
                templates: model.snapshot.mealTemplates,
                initialDay: selection.initialDay
            ) { meal in
                model.savePlannedMeal(meal)
            }
        }
        .sheet(item: $inventoryEditor) { selection in
            InventoryItemEditor(item: selection.item) { item in
                model.saveInventoryItem(item)
            }
        }
        .sheet(item: $suggestionEditor) { selection in
            NutritionSuggestionEditor(
                need: selection.need,
                templates: model.snapshot.mealTemplates
            ) { need in
                model.saveNutritionSuggestion(need)
            }
        }
    }

    private var targetsSection: some View {
        Section("Editable daily targets") {
            Stepper(
                "About \(targets.approximateCalories) kcal",
                value: $targets.approximateCalories,
                in: 1_200...6_000,
                step: 100
            )
            Stepper(
                "About \(targets.approximateProteinGrams) g protein",
                value: $targets.approximateProteinGrams,
                in: 40...350,
                step: 5
            )
            Stepper(
                "\(targets.substantialMeals) substantial meals",
                value: $targets.substantialMeals,
                in: 1...8
            )
            DisclosureGroup("Coverage thresholds") {
                Stepper(
                    "Calorie gap: \(targets.clearCalorieDeficitThreshold) kcal",
                    value: $targets.clearCalorieDeficitThreshold,
                    in: 100...1_500,
                    step: 50
                )
                Stepper(
                    "Protein gap: \(targets.clearProteinDeficitThreshold) g",
                    value: $targets.clearProteinDeficitThreshold,
                    in: 5...100,
                    step: 5
                )
                Stepper(
                    "Meal gap: \(targets.clearSubstantialMealDeficitThreshold)",
                    value:
                        $targets.clearSubstantialMealDeficitThreshold,
                    in: 1...4
                )
                Stepper(
                    "Extra block: \(targets.additionalEatingBlockMinutes) min",
                    value: $targets.additionalEatingBlockMinutes,
                    in: 10...90,
                    step: 5
                )
                Stepper(
                    "Shopping lead: \(targets.inventoryShoppingLeadHours) h",
                    value: $targets.inventoryShoppingLeadHours,
                    in: 0...72,
                    step: 6
                )
            }
            Button("Save nutrition settings") {
                var profile = model.snapshot.profile
                profile.nutritionTargets = targets
                model.updateProfile(profile)
            }
        }
    }

    private var coverageSection: some View {
        Section("Daily coverage") {
            ForEach(
                visibleNutritionNeeds
            ) { need in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(
                            need.localDay.formatted(
                                .dateTime.weekday(.abbreviated)
                                    .day()
                                    .month(.abbreviated)
                            )
                        )
                        .font(.headline)
                        Spacer()
                        Label(
                            need.clearDeficit
                                ? "Likely short"
                                : "Probably covered",
                            systemImage: need.clearDeficit
                                ? "exclamationmark.circle"
                                : "checkmark.circle"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            need.clearDeficit ? Color.orange : Color.green
                        )
                    }
                    Text(
                        "≈\(need.estimatedCalories) / \(targets.approximateCalories) kcal · ≈\(need.estimatedProteinGrams) / \(targets.approximateProteinGrams) g protein · \(need.substantialMealsCovered) / \(targets.substantialMeals) substantial meals"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if need.clearDeficit {
                        Text(
                            "Approximate gap: \(need.approximateCalorieDeficit) kcal and \(need.approximateProteinDeficit) g protein."
                        )
                        .font(.caption)
                        Text(suggestionSummary(need))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            if isSuggestionCompleted(need) {
                                Label(
                                    "Additional block completed",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .foregroundStyle(.green)
                            } else if need.suggestionDisposition == .declined {
                                Button("Restore suggestion") {
                                    model.restoreNutritionSuggestion(need.id)
                                }
                            } else {
                                Button("Edit suggestion") {
                                    suggestionEditor =
                                        NutritionSuggestionEditorSelection(
                                            need: need
                                        )
                                }
                                Button("Decline", role: .destructive) {
                                    model.declineNutritionSuggestion(need.id)
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var plannedMealsSection: some View {
        Section {
            if model.snapshot.plannedMeals.isEmpty {
                Text("No meals are planned yet. Add saved templates to a day to make coverage useful.")
                    .foregroundStyle(.secondary)
            }
            ForEach(
                visiblePlannedMeals
            ) { meal in
                Button {
                    plannedMealEditor = PlannedMealEditorSelection(
                        plannedMeal: meal,
                        initialDay: meal.localDay
                    )
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(meal.title)
                                .foregroundStyle(.primary)
                            Text(
                                "\(meal.localDay.formatted(date: .abbreviated, time: .omitted)) · ≈\(meal.estimatedCalories) kcal · ≈\(meal.estimatedProteinGrams) g"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        model.deletePlannedMeal(meal.id)
                    }
                }
            }
            Button {
                plannedMealEditor = PlannedMealEditorSelection(
                    plannedMeal: nil,
                    initialDay: Date()
                )
            } label: {
                Label("Plan a meal", systemImage: "plus")
            }
            .disabled(model.snapshot.mealTemplates.isEmpty)
        } header: {
            Text("Planned meals")
        } footer: {
            if model.snapshot.mealTemplates.isEmpty {
                Text("Create a meal template first.")
            }
        }
    }

    private var templatesSection: some View {
        Section("Saved meal templates") {
            ForEach(model.snapshot.mealTemplates) { template in
                Button {
                    templateEditor = MealTemplateEditorSelection(
                        template: template
                    )
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(template.title)
                                .foregroundStyle(.primary)
                            Text(
                                "≈\(template.estimatedCalories) kcal · ≈\(template.estimatedProteinGrams) g · \(template.prepTimeMinutes) min prep"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !template.isEnabled {
                            Text("Paused")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        model.deleteMealTemplate(template.id)
                    }
                }
            }
            Button {
                templateEditor = MealTemplateEditorSelection(template: nil)
            } label: {
                Label("New meal template", systemImage: "plus")
            }
        }
    }

    private var inventorySection: some View {
        Section {
            ForEach(model.snapshot.inventoryItems) { item in
                Button {
                    inventoryEditor = InventoryEditorSelection(item: item)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .foregroundStyle(.primary)
                            Text(item.quantityDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.state.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                item.state == .available
                                    ? Color.secondary
                                    : Color.orange
                            )
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        model.deleteInventoryItem(item.id)
                    }
                }
            }
            Button {
                inventoryEditor = InventoryEditorSelection(item: nil)
            } label: {
                Label("New inventory item", systemImage: "plus")
            }
        } header: {
            Text("Food inventory")
        } footer: {
            Text("Voice examples: “Milk is low,” “we have 3 meals of chicken left,” or “set rice to 2 kg.” Linked meal completion can decrement inventory.")
        }
    }

    private var mealPrepSection: some View {
        Section("Meal prep") {
            if let routine = mealPreparationRoutine {
                let cadence = routine.flexibleCadence
                Stepper(
                    "Earliest: every \(cadence?.minimumDays ?? 2) days",
                    value: mealPrepMinimumBinding(routine),
                    in: 1...(cadence?.maximumDays ?? 3)
                )
                Stepper(
                    "Latest: every \(cadence?.maximumDays ?? 3) days",
                    value: mealPrepMaximumBinding(routine),
                    in: (cadence?.minimumDays ?? 2)...7
                )
                Text("The scheduler places this protected batch-prep session in a useful window and keeps it near groceries when practical.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Add a Meal preparation routine under Lists to schedule batch cooking.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mealPreparationRoutine: Routine? {
        model.snapshot.routines.first {
            $0.title.lowercased().contains("meal preparation")
        }
    }

    private var visibleNutritionNeeds: [NutritionPlanningNeed] {
        let interval = visiblePlanningInterval
        return model.snapshot.nutritionPlanningNeeds.filter {
            $0.localDay >= interval.start && $0.localDay < interval.end
        }.sorted { $0.localDay < $1.localDay }
    }

    private var visiblePlannedMeals: [PlannedMeal] {
        let interval = visiblePlanningInterval
        return model.snapshot.plannedMeals.filter {
            $0.localDay >= interval.start && $0.localDay < interval.end
        }.sorted {
            if $0.localDay == $1.localDay {
                return ($0.preferredStartMinute ?? 0)
                    < ($1.preferredStartMinute ?? 0)
            }
            return $0.localDay < $1.localDay
        }
    }

    private var visiblePlanningInterval: DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(
            identifier: model.snapshot.profile.timeZoneIdentifier
        ) ?? .current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(
            byAdding: .day,
            value:
                model.snapshot.profile.planningPolicy.planningHorizonDays,
            to: start
        ) ?? start.addingTimeInterval(7 * 86_400)
        return DateInterval(start: start, end: end)
    }

    private func suggestionSummary(
        _ need: NutritionPlanningNeed
    ) -> String {
        if isSuggestionCompleted(need) {
            return "The additional eating block was completed. The original approximate gap remains visible for context."
        }
        if need.suggestionDisposition == .declined {
            return "Suggestion declined. The estimate remains visible."
        }
        let time = need.suggestedStartMinute.map {
            MissionControlFormatters.minuteOfDay($0)
        } ?? "a suitable window"
        if need.suggestedCalories == 0
            && need.suggestedProteinGrams == 0 {
            return "\(need.suggestedTitle) is scheduled around \(time). Its estimate is intentionally left open for you to edit."
        }
        return "\(need.suggestedTitle) is scheduled around \(time), adding roughly \(need.suggestedCalories) kcal and \(need.suggestedProteinGrams) g protein."
    }

    private func isSuggestionCompleted(
        _ need: NutritionPlanningNeed
    ) -> Bool {
        let missionID = StableIdentifierGenerator().identifier(
            namespace: "nutrition.suggestion.\(need.id.rawValue.uuidString)"
        )
        return model.snapshot.completions.contains {
            $0.missionID == missionID
                && ($0.status == .completed || $0.status == .partial)
        }
    }

    private func mealPrepMinimumBinding(_ routine: Routine) -> Binding<Int> {
        Binding(
            get: { routine.flexibleCadence?.minimumDays ?? 2 },
            set: { value in
                var updated = routine
                let maximum = max(
                    value,
                    routine.flexibleCadence?.maximumDays ?? 3
                )
                updated.flexibleCadence = FlexibleCadence(
                    minimumDays: value,
                    maximumDays: maximum
                )
                model.saveRoutine(updated)
            }
        )
    }

    private func mealPrepMaximumBinding(_ routine: Routine) -> Binding<Int> {
        Binding(
            get: { routine.flexibleCadence?.maximumDays ?? 3 },
            set: { value in
                var updated = routine
                let minimum = min(
                    value,
                    routine.flexibleCadence?.minimumDays ?? 2
                )
                updated.flexibleCadence = FlexibleCadence(
                    minimumDays: minimum,
                    maximumDays: value
                )
                model.saveRoutine(updated)
            }
        )
    }
}

private struct MealTemplateEditorSelection: Identifiable {
    let id = EntityID()
    let template: MealTemplate?
}

private struct PlannedMealEditorSelection: Identifiable {
    let id = EntityID()
    let plannedMeal: PlannedMeal?
    let initialDay: Date
}

private struct InventoryEditorSelection: Identifiable {
    let id = EntityID()
    let item: InventoryItem?
}

private struct NutritionSuggestionEditorSelection: Identifiable {
    let id = EntityID()
    let need: NutritionPlanningNeed
}

private struct MealTemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    let inventory: [InventoryItem]
    let onSave: (MealTemplate) -> Void

    @State private var draft: MealTemplate

    init(
        template: MealTemplate?,
        inventory: [InventoryItem],
        onSave: @escaping (MealTemplate) -> Void
    ) {
        self.inventory = inventory
        self.onSave = onSave
        _draft = State(
            initialValue: template ?? MealTemplate(
                title: "",
                estimatedCalories: 700,
                estimatedProteinGrams: 35,
                prepTimeMinutes: 15
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Approximate meal") {
                    TextField("Name", text: $draft.title)
                    Stepper(
                        "About \(draft.estimatedCalories) kcal",
                        value: $draft.estimatedCalories,
                        in: 0...3_000,
                        step: 50
                    )
                    Stepper(
                        "About \(draft.estimatedProteinGrams) g protein",
                        value: $draft.estimatedProteinGrams,
                        in: 0...200,
                        step: 5
                    )
                    Stepper(
                        "\(draft.prepTimeMinutes) min prep",
                        value: $draft.prepTimeMinutes,
                        in: 0...180,
                        step: 5
                    )
                    Toggle("Counts as a substantial meal", isOn: $draft.isSubstantial)
                    Toggle("Use in suggestions", isOn: $draft.isEnabled)
                    TextField(
                        "Optional note",
                        text: Binding(
                            get: { draft.note ?? "" },
                            set: { draft.note = $0.isEmpty ? nil : $0 }
                        ),
                        axis: .vertical
                    )
                }
                if !inventory.isEmpty {
                    Section("Optional inventory usage") {
                        ForEach(inventory) { item in
                            Toggle(
                                item.name,
                                isOn: usageBinding(for: item.id)
                            )
                        }
                        Text("A selected item uses one unit or one meal portion by default. Inventory remains an estimate.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Meal template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.title = draft.title.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(
                        draft.title.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
    }

    private func usageBinding(for itemID: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                draft.inventoryUsage.contains {
                    $0.inventoryItemID == itemID
                }
            },
            set: { isUsed in
                if isUsed {
                    if !draft.inventoryUsage.contains(where: {
                        $0.inventoryItemID == itemID
                    }) {
                        draft.inventoryUsage.append(
                            MealInventoryUsage(
                                inventoryItemID: itemID
                            )
                        )
                    }
                } else {
                    draft.inventoryUsage.removeAll {
                        $0.inventoryItemID == itemID
                    }
                }
            }
        )
    }
}

private struct PlannedMealEditor: View {
    @Environment(\.dismiss) private var dismiss
    let templates: [MealTemplate]
    let onSave: (PlannedMeal) -> Void

    @State private var draft: PlannedMeal

    init(
        plannedMeal: PlannedMeal?,
        templates: [MealTemplate],
        initialDay: Date,
        onSave: @escaping (PlannedMeal) -> Void
    ) {
        self.templates = templates
        self.onSave = onSave
        let template = plannedMeal == nil ? templates.first : nil
        _draft = State(
            initialValue: plannedMeal ?? PlannedMeal(
                localDay: initialDay,
                mealTemplateID: template?.id,
                title: template?.title ?? "",
                estimatedCalories: template?.estimatedCalories ?? 700,
                estimatedProteinGrams:
                    template?.estimatedProteinGrams ?? 35,
                estimatedDurationMinutes: max(
                    30,
                    (template?.prepTimeMinutes ?? 10) + 20
                ),
                isSubstantial: template?.isSubstantial ?? true,
                preferredStartMinute: 13 * 60
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    DatePicker(
                        "Day",
                        selection: $draft.localDay,
                        displayedComponents: .date
                    )
                    Picker(
                        "Saved meal",
                        selection: templateSelection
                    ) {
                        Text("Custom estimate").tag(EntityID?.none)
                        ForEach(templates) { template in
                            Text(template.title).tag(Optional(template.id))
                        }
                    }
                    TextField("Title", text: $draft.title)
                    Stepper(
                        "About \(draft.estimatedCalories) kcal",
                        value: $draft.estimatedCalories,
                        in: 0...3_000,
                        step: 50
                    )
                    Stepper(
                        "About \(draft.estimatedProteinGrams) g protein",
                        value: $draft.estimatedProteinGrams,
                        in: 0...200,
                        step: 5
                    )
                    Stepper(
                        "\(draft.estimatedDurationMinutes) min block",
                        value: $draft.estimatedDurationMinutes,
                        in: 10...180,
                        step: 5
                    )
                    Stepper(
                        "Around \(MissionControlFormatters.minuteOfDay(draft.preferredStartMinute ?? 13 * 60))",
                        value: Binding(
                            get: { draft.preferredStartMinute ?? 13 * 60 },
                            set: { draft.preferredStartMinute = $0 }
                        ),
                        in: 0...(23 * 60 + 55),
                        step: 5
                    )
                    Toggle("Substantial meal", isOn: $draft.isSubstantial)
                    Toggle(
                        "Decrement linked inventory when completed",
                        isOn: $draft.decrementInventoryOnCompletion
                    )
                }
            }
            .navigationTitle("Planned meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.title = draft.title.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(
                        draft.title.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
    }

    private var templateSelection: Binding<EntityID?> {
        Binding(
            get: { draft.mealTemplateID },
            set: { templateID in
                draft.mealTemplateID = templateID
                guard let template = templates.first(where: {
                    $0.id == templateID
                }) else {
                    return
                }
                draft.title = template.title
                draft.estimatedCalories = template.estimatedCalories
                draft.estimatedProteinGrams =
                    template.estimatedProteinGrams
                draft.estimatedDurationMinutes = max(
                    30,
                    template.prepTimeMinutes + 20
                )
                draft.isSubstantial = template.isSubstantial
            }
        )
    }
}

private enum InventoryTrackingMode: String, CaseIterable, Identifiable {
    case qualitative
    case meals
    case exact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qualitative: "Simple"
        case .meals: "Meals left"
        case .exact: "Exact"
        }
    }
}

private struct InventoryItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (InventoryItem) -> Void

    @State private var draft: InventoryItem
    @State private var mode: InventoryTrackingMode

    init(
        item: InventoryItem?,
        onSave: @escaping (InventoryItem) -> Void
    ) {
        self.onSave = onSave
        let initial = item ?? InventoryItem(
            name: "",
            state: .available,
            updatedAt: Date()
        )
        _draft = State(initialValue: initial)
        _mode = State(
            initialValue: initial.mealsRemaining != nil
                ? .meals
                : initial.exactQuantity != nil ? .exact : .qualitative
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Inventory") {
                    TextField("Item", text: $draft.name)
                    Picker("Tracking", selection: $mode) {
                        ForEach(InventoryTrackingMode.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    switch mode {
                    case .qualitative:
                        Picker("State", selection: $draft.state) {
                            ForEach(InventoryState.allCases) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        TextField(
                            "Optional note",
                            text: Binding(
                                get: { draft.quantityNote ?? "" },
                                set: {
                                    draft.quantityNote =
                                        $0.isEmpty ? nil : $0
                                }
                            )
                        )
                    case .meals:
                        Stepper(
                            "\(draft.mealsRemaining ?? 1) meals remaining",
                            value: Binding(
                                get: { draft.mealsRemaining ?? 1 },
                                set: { draft.mealsRemaining = $0 }
                            ),
                            in: 0...50
                        )
                    case .exact:
                        TextField(
                            "Quantity",
                            value: Binding(
                                get: { draft.exactQuantity ?? 1 },
                                set: { draft.exactQuantity = $0 }
                            ),
                            format: .number
                        )
                        .keyboardType(.decimalPad)
                        TextField(
                            "Unit, e.g. kg",
                            text: Binding(
                                get: { draft.quantityUnit ?? "" },
                                set: {
                                    draft.quantityUnit =
                                        $0.isEmpty ? nil : $0
                                }
                            )
                        )
                        TextField(
                            "Low threshold",
                            value: Binding(
                                get: {
                                    draft.lowQuantityThreshold ?? 0.25
                                },
                                set: {
                                    draft.lowQuantityThreshold = $0
                                }
                            ),
                            format: .number
                        )
                        .keyboardType(.decimalPad)
                    }
                    TextField(
                        "Usual shopping amount",
                        text: Binding(
                            get: { draft.shoppingQuantity ?? "" },
                            set: {
                                draft.shoppingQuantity =
                                    $0.isEmpty ? nil : $0
                            }
                        )
                    )
                    Toggle(
                        "Propose shopping before shortage",
                        isOn: $draft.automaticallyAddToShopping
                    )
                }
            }
            .navigationTitle("Inventory item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        normalizeDraft()
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(
                        draft.name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
    }

    private func normalizeDraft() {
        draft.name = draft.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        draft.updatedAt = Date()
        switch mode {
        case .qualitative:
            draft.exactQuantity = nil
            draft.quantityUnit = nil
            draft.mealsRemaining = nil
        case .meals:
            draft.exactQuantity = nil
            draft.quantityUnit = nil
            let remaining = draft.mealsRemaining ?? 1
            draft.mealsRemaining = remaining
            draft.state = remaining == 0
                ? .empty
                : remaining <= 1 ? .low : .available
        case .exact:
            draft.mealsRemaining = nil
            let remaining = max(draft.exactQuantity ?? 0, 0)
            draft.exactQuantity = remaining
            draft.state = remaining == 0
                ? .empty
                : remaining <= (draft.lowQuantityThreshold ?? 0)
                    ? .low
                    : .available
        }
    }
}

private struct NutritionSuggestionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let templates: [MealTemplate]
    let onSave: (NutritionPlanningNeed) -> Void

    @State private var draft: NutritionPlanningNeed

    init(
        need: NutritionPlanningNeed,
        templates: [MealTemplate],
        onSave: @escaping (NutritionPlanningNeed) -> Void
    ) {
        self.templates = templates
        self.onSave = onSave
        _draft = State(initialValue: need)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Practical addition") {
                    Picker(
                        "Saved option",
                        selection: templateSelection
                    ) {
                        Text("Generic eating block").tag(EntityID?.none)
                        ForEach(templates.filter(\.isEnabled)) { template in
                            Text(template.title).tag(Optional(template.id))
                        }
                    }
                    TextField("Title", text: $draft.suggestedTitle)
                    Stepper(
                        "About \(draft.suggestedCalories) kcal",
                        value: $draft.suggestedCalories,
                        in: 0...3_000,
                        step: 50
                    )
                    Stepper(
                        "About \(draft.suggestedProteinGrams) g protein",
                        value: $draft.suggestedProteinGrams,
                        in: 0...200,
                        step: 5
                    )
                    Stepper(
                        "\(draft.suggestedMealDurationMinutes) min",
                        value: $draft.suggestedMealDurationMinutes,
                        in: 10...120,
                        step: 5
                    )
                    Stepper(
                        "Around \(MissionControlFormatters.minuteOfDay(draft.suggestedStartMinute ?? 20 * 60))",
                        value: Binding(
                            get: {
                                draft.suggestedStartMinute ?? 20 * 60
                            },
                            set: { draft.suggestedStartMinute = $0 }
                        ),
                        in: 0...(23 * 60 + 55),
                        step: 5
                    )
                    Text("The scheduler will move this within the day if the preferred time conflicts with a fixed commitment.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Food suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.suggestionDisposition = .scheduled
                        draft.suggestionIsUserEdited = true
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(
                        draft.suggestedTitle.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
    }

    private var templateSelection: Binding<EntityID?> {
        Binding(
            get: { draft.suggestedMealTemplateID },
            set: { templateID in
                draft.suggestedMealTemplateID = templateID
                guard let template = templates.first(where: {
                    $0.id == templateID
                }) else {
                    draft.suggestedTitle = "Additional eating block"
                    return
                }
                draft.suggestedTitle = template.title
                draft.suggestedCalories = template.estimatedCalories
                draft.suggestedProteinGrams =
                    template.estimatedProteinGrams
                draft.suggestedMealDurationMinutes = max(
                    draft.suggestedMealDurationMinutes,
                    template.prepTimeMinutes
                )
            }
        )
    }
}
