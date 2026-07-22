import Foundation
import MissionControlCore
import SwiftUI

struct ListsView: View {
    @ObservedObject var model: AppModel
    let openMenu: () -> Void

    @State private var editingRoutine: Routine?

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.snapshot.checklists) { checklist in
                    Section(checklist.title) {
                        ForEach(checklist.items) { item in
                            Button {
                                model.toggleChecklistItem(checklistID: checklist.id, itemID: item.id)
                            } label: {
                                HStack(spacing: 11) {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.isCompleted ? Color.green : Color.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                                            .strikethrough(item.isCompleted)
                                        if let quantity = item.quantity {
                                            Text(quantity)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Routine defaults") {
                    ForEach(model.snapshot.routines) { routine in
                        Button {
                            editingRoutine = routine
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(routine.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(recurrenceLabel(routine.recurrence))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !routine.note.isEmpty {
                                    Text(routine.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 3)
                    }
                }
            }
            .navigationTitle("Lists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ScreenMenuButton(action: openMenu)
                }
            }
        }
        .sheet(item: $editingRoutine) { routine in
            RoutineEditor(routine: routine, save: model.updateRoutine)
                .presentationDetents([.large])
        }
    }

    private func recurrenceLabel(_ recurrence: RecurrencePattern) -> String {
        switch recurrence.frequency {
        case .daily:
            recurrence.interval == 1 ? "Daily" : "Every \(recurrence.interval) days"
        case .weekly:
            recurrence.weekdays.map(\.shortName).joined(separator: ", ")
        case .monthly:
            "Monthly"
        case .afterEvent:
            "After \(recurrence.triggerCategory?.displayName.lowercased() ?? "event")"
        }
    }
}

private struct RoutineEditor: View {
    @Environment(\.dismiss) private var dismiss
    let save: (Routine) -> Void

    @State private var draft: Routine

    init(routine: Routine, save: @escaping (Routine) -> Void) {
        self.save = save
        _draft = State(initialValue: routine)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Routine") {
                    TextField("Title", text: $draft.title)
                    Toggle("Enabled", isOn: $draft.isEnabled)
                    Stepper(
                        "Expected time: \(draft.estimatedDurationMinutes) min",
                        value: $draft.estimatedDurationMinutes,
                        in: 5...240,
                        step: 5
                    )
                }

                Section("Recurrence") {
                    Picker("Cadence", selection: $draft.recurrence.frequency) {
                        ForEach(RecurrenceFrequency.allCases) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }

                    if draft.recurrence.frequency == .daily {
                        Stepper(
                            draft.recurrence.interval == 1
                                ? "Every day"
                                : "Every \(draft.recurrence.interval) days",
                            value: $draft.recurrence.interval,
                            in: 1...14
                        )
                    } else if draft.recurrence.frequency == .monthly {
                        Stepper(
                            "Every \(draft.recurrence.interval) month(s)",
                            value: $draft.recurrence.interval,
                            in: 1...12
                        )
                    } else if draft.recurrence.frequency == .weekly {
                        HStack(spacing: 5) {
                            ForEach(Weekday.allCases) { day in
                                let isSelected = draft.recurrence.weekdays.contains(day)
                                Button(String(day.shortName.prefix(2))) {
                                    if isSelected {
                                        draft.recurrence.weekdays.removeAll(where: { $0 == day })
                                    } else {
                                        draft.recurrence.weekdays.append(day)
                                        draft.recurrence.weekdays.sort(by: { $0.rawValue < $1.rawValue })
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

                    Stepper(
                        "Due window: \(draft.dueWindowMinutes / 60) hr",
                        value: $draft.dueWindowMinutes,
                        in: 60...(7 * 24 * 60),
                        step: 60
                    )
                }

                if !draft.note.isEmpty {
                    Section("Seed note") {
                        Text(draft.note)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if draft.recurrence.frequency == .weekly,
                           draft.recurrence.weekdays.isEmpty {
                            draft.recurrence.weekdays = [.sunday]
                        }
                        save(draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
