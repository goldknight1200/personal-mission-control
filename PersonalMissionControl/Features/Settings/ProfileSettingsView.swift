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
