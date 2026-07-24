import MissionControlCore
import SwiftUI

struct PlanView: View {
    enum RangeOption: String, CaseIterable, Identifiable {
        case day = "Day"
        case week = "Week"
        case month = "Month"

        var id: String { rawValue }
    }

    @ObservedObject var model: AppModel
    let openMenu: () -> Void

    @State private var selectedRange: RangeOption = .day
    @State private var showExplanations = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Plan range", selection: $selectedRange) {
                    ForEach(RangeOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if !model.snapshot.schedulingConflicts.isEmpty {
                    Button {
                        showExplanations = true
                    } label: {
                        Label(
                            "\(model.snapshot.schedulingConflicts.count) planning conflict\(model.snapshot.schedulingConflicts.count == 1 ? "" : "s")",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)
                    }
                    .buttonStyle(.plain)
                }

                switch selectedRange {
                case .day:
                    dayPlan
                case .week:
                    weekPlan
                case .month:
                    ContentUnavailableView {
                        Label("Month overview", systemImage: "calendar")
                    } description: {
                        Text("Phase 2 produces a precise current day and deterministic seven-day horizon. Month planning remains outside this phase.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showExplanations = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Planning explanations")

                    ScreenMenuButton(action: openMenu)
                }
            }
        }
        .sheet(isPresented: $showExplanations) {
            PlanningExplanationsView(model: model)
        }
    }

    private var dayPlan: some View {
        let blocks = blocks(on: Date())
        return Group {
            if blocks.isEmpty {
                ContentUnavailableView(
                    "No blocks today",
                    systemImage: "calendar.badge.clock",
                    description: Text("Regenerate the local plan to refresh the seven-day horizon.")
                )
            } else {
                List(blocks) { block in
                    PlanBlockRow(
                        block: block,
                        profile: model.snapshot.profile
                    )
                }
                .listStyle(.plain)
            }
        }
    }

    private var weekPlan: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(horizonDays, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(dayLabel(day))
                            .font(.headline)

                        let dayBlocks = blocks(on: day)
                        if dayBlocks.isEmpty {
                            Text("Open day")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .missionControlCard()
                        } else {
                            ForEach(dayBlocks) { block in
                                PlanBlockRow(
                                    block: block,
                                    profile: model.snapshot.profile
                                )
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .background(
                                    RoundedRectangle(
                                        cornerRadius: 16,
                                        style: .continuous
                                    )
                                    .fill(Color.primary.opacity(0.04))
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }

    private var horizonDays: [Date] {
        let calendar = localCalendar
        let start = model.snapshot.schedulingPlanMetadata?.horizonStart
            ?? calendar.startOfDay(for: Date())
        return (0..<model.snapshot.profile.planningPolicy.planningHorizonDays)
            .compactMap {
                calendar.date(byAdding: .day, value: $0, to: start)
            }
    }

    private func blocks(on day: Date) -> [ScheduleBlock] {
        let start = localCalendar.startOfDay(for: day)
        let end = localCalendar.date(
            byAdding: .day,
            value: 1,
            to: start
        ) ?? start.addingTimeInterval(86_400)
        model.snapshot.scheduleBlocks
            .filter { $0.start < end && $0.end > start }
            .sorted(by: { $0.start < $1.start })
    }

    private var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(
            identifier: model.snapshot.profile.timeZoneIdentifier
        ) ?? .current
        return calendar
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = localCalendar
        formatter.timeZone = localCalendar.timeZone
        formatter.dateFormat = "EEEE, d MMM"
        return formatter.string(from: date)
    }
}

private struct PlanBlockRow: View {
    let block: ScheduleBlock
    let profile: UserProfile

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    block.kind.isTransition
                        || block.kind == .sleep
                        || block.kind == .freeTime
                        ? Color.secondary.opacity(0.4)
                        : profile.color(for: block.category)
                )
                .frame(width: 4, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(block.title)
                    .foregroundStyle(isQuiet ? Color.secondary : Color.primary)
                Text(block.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(MissionControlFormatters.timeRange(block, profile: profile))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var isQuiet: Bool {
        block.kind.isTransition
            || block.kind == .sleep
            || block.kind == .freeTime
    }
}

private struct PlanningExplanationsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if let metadata = model.snapshot.schedulingPlanMetadata {
                    Section("Plan") {
                        LabeledContent("Generated") {
                            Text(metadata.generatedAt, style: .time)
                        }
                        LabeledContent("Horizon") {
                            Text("\(model.snapshot.profile.planningPolicy.planningHorizonDays) days")
                        }
                        LabeledContent("Flexible grid") {
                            Text("\(metadata.gridMinutes) minutes")
                        }
                    }
                }

                if !model.snapshot.schedulingConflicts.isEmpty {
                    Section("Conflicts requiring attention") {
                        ForEach(model.snapshot.schedulingConflicts) { conflict in
                            VStack(alignment: .leading, spacing: 5) {
                                Label(
                                    conflict.title,
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.headline)
                                .foregroundStyle(.orange)
                                Text(conflict.explanation)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Decisions") {
                    ForEach(model.snapshot.schedulingDecisions) { decision in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(decision.title)
                                .font(.headline)
                            Text(decision.explanation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(decision.rule.rawValue)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Why this plan?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Regenerate") {
                        model.regeneratePlan()
                    }
                }
            }
        }
    }
}
