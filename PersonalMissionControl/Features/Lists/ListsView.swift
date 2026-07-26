import Foundation
import MissionControlCore
import SwiftUI

struct ListsView: View {
    @ObservedObject var model: AppModel
    let openMenu: () -> Void

    @State private var selectedKind: ChecklistKind = .today
    @State private var newItemTitle = ""
    @State private var editingItem: ChecklistEditSelection?
    @State private var editingRoutine: Routine?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("List", selection: $selectedKind) {
                    ForEach(ChecklistKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedKind {
                case .today, .shopping:
                    checklistView(selectedKind)
                case .routines:
                    routinesView
                }
            }
            .navigationTitle("Lists")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if selectedKind == .routines {
                        Button {
                            editingRoutine = Routine(
                                title: "",
                                category: .household,
                                rigidity: .flexible,
                                recurrence: RecurrencePattern(
                                    frequency: .weekly,
                                    weekdays: [.sunday]
                                ),
                                estimatedDurationMinutes: 20,
                                dueWindowMinutes: 180,
                                anchorDate: Date()
                            )
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add routine")
                    }
                    ScreenMenuButton(action: openMenu)
                }
            }
        }
        .sheet(item: $editingItem) { selection in
            ChecklistItemEditor(
                checklistID: selection.checklistID,
                kind: selection.kind,
                item: selection.item,
                inventory: model.snapshot.inventoryItems,
                save: model.saveChecklistItem
            )
        }
        .sheet(item: $editingRoutine) { routine in
            RoutineEditor(
                routine: routine,
                allRoutines: model.snapshot.routines,
                save: model.saveRoutine
            )
            .presentationDetents([.large])
        }
    }

    private func checklistView(_ kind: ChecklistKind) -> some View {
        let checklist = model.snapshot.checklist(ofKind: kind)
        return List {
            Section {
                HStack(spacing: 10) {
                    TextField(
                        kind == .shopping
                            ? "Add shopping item"
                            : "Add one-off",
                        text: $newItemTitle
                    )
                    .submitLabel(.done)
                    .onSubmit(addCurrentItem)
                    Button(action: addCurrentItem) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .disabled(newItemTitle.trimmed.isEmpty)
                    .accessibilityLabel("Add item")
                }
                if kind == .shopping {
                    Label(
                        "Type here or hold the center microphone and say “add … to my shopping list.”",
                        systemImage: "mic"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Section(kind == .shopping ? "To buy" : "One-offs") {
                if checklist?.items.isEmpty != false {
                    Text(
                        kind == .shopping
                            ? "Nothing waiting to be bought."
                            : "No one-offs for today."
                    )
                    .foregroundStyle(.secondary)
                }
                ForEach(checklist?.items ?? []) { item in
                    HStack(spacing: 11) {
                        Button {
                            guard let checklist else { return }
                            model.toggleChecklistItem(
                                checklistID: checklist.id,
                                itemID: item.id
                            )
                        } label: {
                            Image(
                                systemName: item.isCompleted
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .foregroundStyle(
                                item.isCompleted ? Color.green : Color.secondary
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            item.isCompleted
                                ? "Mark not purchased"
                                : kind == .shopping
                                    ? "Mark purchased"
                                    : "Mark completed"
                        )
                        Button {
                            guard let checklist else { return }
                            editingItem = ChecklistEditSelection(
                                checklistID: checklist.id,
                                kind: kind,
                                item: item
                            )
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .foregroundStyle(
                                            item.isCompleted
                                                ? Color.secondary
                                                : Color.primary
                                        )
                                        .strikethrough(item.isCompleted)
                                    HStack(spacing: 8) {
                                        if let quantity = item.quantity,
                                           !quantity.isEmpty {
                                            Text(quantity)
                                        }
                                        if let dueDate = item.dueDate {
                                            Text(
                                                dueDate.formatted(
                                                    date: .abbreviated,
                                                    time: .shortened
                                                )
                                            )
                                        }
                                        if item.inventoryItemID != nil {
                                            Label(
                                                "Inventory linked",
                                                systemImage: "shippingbox"
                                            )
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    if let reason = item.suggestionReason {
                                        Label(
                                            reason,
                                            systemImage:
                                                "cart.badge.plus"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .contextMenu {
                        Button("Edit") {
                            guard let checklist else { return }
                            editingItem = ChecklistEditSelection(
                                checklistID: checklist.id,
                                kind: kind,
                                item: item
                            )
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            guard let checklist else { return }
                            model.deleteChecklistItem(
                                checklistID: checklist.id,
                                itemID: item.id
                            )
                        }
                        Button("Edit") {
                            guard let checklist else { return }
                            editingItem = ChecklistEditSelection(
                                checklistID: checklist.id,
                                kind: kind,
                                item: item
                            )
                        }
                        .tint(.indigo)
                    }
                }
            }

            if kind == .shopping {
                Section {
                    Text("Pending items appear as the checklist on a generated Groceries mission. Completing them from Home also marks them purchased here. The planner may attach that trip to a supermarket shift.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var routinesView: some View {
        List {
            Section {
                Text("Routines use a preferred cadence plus a flexible due window. Compatible work may be kept together without turning every preference into a rigid appointment.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Recurring responsibilities") {
                if model.snapshot.routines.isEmpty {
                    Text("No routines yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.snapshot.routines) { routine in
                    Button {
                        editingRoutine = routine
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(routine.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(routine.isEnabled ? "On" : "Off")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(
                                        routine.isEnabled
                                            ? Color.green
                                            : Color.secondary
                                    )
                            }
                            HStack(spacing: 10) {
                                Label(
                                    recurrenceLabel(routine),
                                    systemImage: "repeat"
                                )
                                Label(
                                    dueWindowLabel(routine),
                                    systemImage: "clock.arrow.circlepath"
                                )
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if !routine.bundlingNote.isEmpty {
                                Label(
                                    routine.bundlingNote,
                                    systemImage: "link"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            model.deleteRoutine(routine.id)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func addCurrentItem() {
        let title = newItemTitle.trimmed
        guard !title.isEmpty else { return }
        model.addChecklistItem(kind: selectedKind, title: title)
        newItemTitle = ""
    }

    private func recurrenceLabel(_ routine: Routine) -> String {
        if let cadence = routine.flexibleCadence {
            return "Every \(cadence.minimumDays)–\(cadence.maximumDays) days"
        }
        switch routine.recurrence.frequency {
        case .daily:
            return routine.recurrence.interval == 1
                ? "Daily"
                : "Every \(routine.recurrence.interval) days"
        case .weekly:
            return routine.recurrence.weekdays.map(\.shortName)
                .joined(separator: ", ")
        case .monthly:
            return "Every \(routine.recurrence.interval) month(s)"
        case .afterEvent:
            return "After \(routine.recurrence.triggerCategory?.displayName.lowercased() ?? "event")"
        }
    }

    private func dueWindowLabel(_ routine: Routine) -> String {
        if routine.dueWindowMinutes < 60 {
            return "\(routine.dueWindowMinutes) min window"
        }
        return "\(routine.dueWindowMinutes / 60) hr window"
    }
}

private struct ChecklistEditSelection: Identifiable {
    let checklistID: EntityID
    let kind: ChecklistKind
    let item: ChecklistItem
    var id: EntityID { item.id }
}

private struct ChecklistItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    let checklistID: EntityID
    let kind: ChecklistKind
    let inventory: [InventoryItem]
    let save: (EntityID, ChecklistItem) -> Void

    @State private var draft: ChecklistItem
    @State private var hasDueDate: Bool

    init(
        checklistID: EntityID,
        kind: ChecklistKind,
        item: ChecklistItem,
        inventory: [InventoryItem],
        save: @escaping (EntityID, ChecklistItem) -> Void
    ) {
        self.checklistID = checklistID
        self.kind = kind
        self.inventory = inventory
        self.save = save
        _draft = State(initialValue: item)
        _hasDueDate = State(initialValue: item.dueDate != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(kind == .shopping ? "Shopping item" : "One-off") {
                    TextField("Item", text: $draft.title)
                    TextField(
                        kind == .shopping ? "Quantity or note" : "Note",
                        text: Binding(
                            get: { draft.quantity ?? "" },
                            set: { draft.quantity = $0.trimmed.isEmpty ? nil : $0 }
                        )
                    )
                    Toggle(
                        kind == .shopping ? "Purchased" : "Completed",
                        isOn: $draft.isCompleted
                    )
                }
                Section("Due") {
                    Toggle("Use due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker(
                            "Due",
                            selection: Binding(
                                get: { draft.dueDate ?? Date() },
                                set: { draft.dueDate = $0 }
                            )
                        )
                    }
                }
                if kind == .shopping {
                    Section("Inventory link") {
                        Picker("Item", selection: $draft.inventoryItemID) {
                            Text("No link").tag(EntityID?.none)
                            ForEach(inventory) { item in
                                Text(item.name).tag(Optional(item.id))
                            }
                        }
                        Text("Linking is optional. Linked items can be proposed when planned meals are likely to use the remaining inventory.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !hasDueDate { draft.dueDate = nil }
                        save(checklistID, draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmed.isEmpty)
                }
            }
        }
    }
}

private struct RoutineEditor: View {
    @Environment(\.dismiss) private var dismiss
    let allRoutines: [Routine]
    let save: (Routine) -> Void

    @State private var draft: Routine
    @State private var usesFlexibleCadence: Bool
    @State private var hasPreferredTime: Bool
    @State private var hasAnchor: Bool

    init(
        routine: Routine,
        allRoutines: [Routine],
        save: @escaping (Routine) -> Void
    ) {
        self.allRoutines = allRoutines
        self.save = save
        _draft = State(initialValue: routine)
        _usesFlexibleCadence = State(
            initialValue: routine.flexibleCadence != nil
        )
        _hasPreferredTime = State(
            initialValue: routine.recurrence.preferredStartMinute != nil
        )
        _hasAnchor = State(initialValue: routine.anchorDate != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Routine") {
                    TextField("Title", text: $draft.title)
                    Picker("Area", selection: $draft.category) {
                        ForEach(MissionCategory.allCases) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    Picker("Rigidity", selection: $draft.rigidity) {
                        ForEach(MissionRigidity.allCases) { rigidity in
                            Text(rigidity.rawValue.capitalized).tag(rigidity)
                        }
                    }
                    Toggle("Enabled", isOn: $draft.isEnabled)
                    Stepper(
                        "Expected time: \(draft.estimatedDurationMinutes) min",
                        value: $draft.estimatedDurationMinutes,
                        in: 5...480,
                        step: 5
                    )
                }

                Section("Cadence") {
                    Picker("Pattern", selection: $draft.recurrence.frequency) {
                        ForEach(RecurrenceFrequency.allCases) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }
                    if draft.recurrence.frequency == .daily {
                        Toggle(
                            "Use flexible day range",
                            isOn: $usesFlexibleCadence
                        )
                        if usesFlexibleCadence {
                            Stepper(
                                "Earliest: \(draft.flexibleCadence?.minimumDays ?? 2) days",
                                value: minimumCadence,
                                in: 1...30
                            )
                            Stepper(
                                "Latest: \(draft.flexibleCadence?.maximumDays ?? 3) days",
                                value: maximumCadence,
                                in: 1...31
                            )
                        } else {
                            Stepper(
                                draft.recurrence.interval == 1
                                    ? "Every day"
                                    : "Every \(draft.recurrence.interval) days",
                                value: $draft.recurrence.interval,
                                in: 1...30
                            )
                        }
                    } else if draft.recurrence.frequency == .weekly {
                        weekdayPicker
                    } else if draft.recurrence.frequency == .monthly {
                        Stepper(
                            "Every \(draft.recurrence.interval) month(s)",
                            value: $draft.recurrence.interval,
                            in: 1...12
                        )
                    } else {
                        Picker(
                            "Trigger",
                            selection: $draft.recurrence.triggerCategory
                        ) {
                            Text("Choose event").tag(MissionCategory?.none)
                            ForEach(MissionCategory.allCases) { category in
                                Text(category.displayName)
                                    .tag(Optional(category))
                            }
                        }
                    }

                    Toggle("Use anchor date", isOn: $hasAnchor)
                    if hasAnchor {
                        DatePicker(
                            "Anchor",
                            selection: Binding(
                                get: { draft.anchorDate ?? Date() },
                                set: { draft.anchorDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                    }

                    Toggle("Prefer a time", isOn: $hasPreferredTime)
                    if hasPreferredTime {
                        DatePicker(
                            "Preferred",
                            selection: preferredTime,
                            displayedComponents: .hourAndMinute
                        )
                    }
                    Stepper(
                        dueWindowText,
                        value: $draft.dueWindowMinutes,
                        in: 30...(7 * 24 * 60),
                        step: 30
                    )
                    Text("The planner may place the responsibility anywhere inside this window.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Bundling and overlap") {
                    let compatible = allRoutines.filter { $0.id != draft.id }
                    if compatible.isEmpty {
                        Text("Add another routine to define compatible work.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(compatible) { routine in
                        Toggle(
                            routine.title,
                            isOn: compatibilityBinding(routine.id)
                        )
                    }
                    Toggle(
                        "May overlap compatible work",
                        isOn: $draft.allowsCompatibleOverlap
                    )
                    TextField(
                        "Example: clean while laundry is running",
                        text: $draft.bundlingNote,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                }

                Section("Notes") {
                    TextField("Context", text: $draft.note, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(draft.title.isEmpty ? "New routine" : "Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        normalizeAndSave()
                    }
                    .disabled(draft.title.trimmed.isEmpty)
                }
            }
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 5) {
            ForEach(Weekday.allCases) { day in
                let isSelected = draft.recurrence.weekdays.contains(day)
                Button(String(day.shortName.prefix(2))) {
                    if isSelected {
                        draft.recurrence.weekdays.removeAll(where: { $0 == day })
                    } else {
                        draft.recurrence.weekdays.append(day)
                        draft.recurrence.weekdays.sort(by: {
                            $0.rawValue < $1.rawValue
                        })
                    }
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            isSelected
                                ? Color.accentColor.opacity(0.18)
                                : Color.primary.opacity(0.04)
                        )
                )
                .buttonStyle(.plain)
                .accessibilityLabel(day.shortName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var minimumCadence: Binding<Int> {
        Binding(
            get: { draft.flexibleCadence?.minimumDays ?? 2 },
            set: { value in
                let maximum = max(
                    draft.flexibleCadence?.maximumDays ?? 3,
                    value
                )
                draft.flexibleCadence = FlexibleCadence(
                    minimumDays: value,
                    maximumDays: maximum
                )
                draft.recurrence.interval = maximum
            }
        )
    }

    private var maximumCadence: Binding<Int> {
        Binding(
            get: { draft.flexibleCadence?.maximumDays ?? 3 },
            set: { value in
                let minimum = min(
                    draft.flexibleCadence?.minimumDays ?? 2,
                    value
                )
                draft.flexibleCadence = FlexibleCadence(
                    minimumDays: minimum,
                    maximumDays: value
                )
                draft.recurrence.interval = value
            }
        )
    }

    private var preferredTime: Binding<Date> {
        Binding(
            get: {
                let minute = draft.recurrence.preferredStartMinute ?? 18 * 60
                return Calendar.current.date(
                    bySettingHour: minute / 60,
                    minute: minute % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents(
                    [.hour, .minute],
                    from: date
                )
                draft.recurrence.preferredStartMinute =
                    (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private var dueWindowText: String {
        let minutes = draft.dueWindowMinutes
        if minutes < 60 { return "Due window: \(minutes) min" }
        let hours = Double(minutes) / 60
        return "Due window: "
            + hours.formatted(.number.precision(.fractionLength(1)))
            + " hr"
    }

    private func compatibilityBinding(_ id: EntityID) -> Binding<Bool> {
        Binding(
            get: { draft.compatibleRoutineIDs.contains(id) },
            set: { selected in
                if selected {
                    if !draft.compatibleRoutineIDs.contains(id) {
                        draft.compatibleRoutineIDs.append(id)
                    }
                } else {
                    draft.compatibleRoutineIDs.removeAll(where: { $0 == id })
                }
            }
        )
    }

    private func normalizeAndSave() {
        if !usesFlexibleCadence {
            draft.flexibleCadence = nil
        } else if draft.flexibleCadence == nil {
            draft.flexibleCadence = FlexibleCadence(
                minimumDays: 2,
                maximumDays: 3
            )
            draft.recurrence.interval = 3
        }
        if !hasPreferredTime {
            draft.recurrence.preferredStartMinute = nil
        }
        if !hasAnchor {
            draft.anchorDate = nil
        }
        if draft.recurrence.frequency == .weekly,
           draft.recurrence.weekdays.isEmpty {
            draft.recurrence.weekdays = [.sunday]
        }
        if draft.recurrence.frequency == .afterEvent,
           draft.recurrence.triggerCategory == nil {
            draft.recurrence.triggerCategory = .personal
        }
        save(draft)
        dismiss()
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
