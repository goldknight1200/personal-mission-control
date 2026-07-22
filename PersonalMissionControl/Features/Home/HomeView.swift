import MissionControlCore
import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AppModel
    let openMenu: () -> Void

    @State private var durationMission: Mission?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let now = context.date
                    let blocks = model.snapshot.scheduleBlocks
                    let currentBlock = ScheduleTimeline.currentBlock(in: blocks, at: now)
                    let upcoming = ScheduleTimeline.upcomingBlocks(in: blocks, after: now)
                    let currentMission = model.snapshot.mission(withID: currentBlock?.missionID)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            CurrentTimeOrb(
                                now: now,
                                block: currentBlock,
                                profile: model.snapshot.profile
                            )
                            .frame(height: min(max(geometry.size.height * 0.28, 210), 270))
                            .frame(maxWidth: .infinity)

                            if let currentBlock {
                                CurrentMissionCard(
                                    block: currentBlock,
                                    mission: currentMission,
                                    profile: model.snapshot.profile,
                                    toggleStep: { stepID in
                                        guard let missionID = currentMission?.id else { return }
                                        model.toggleMissionStep(missionID: missionID, stepID: stepID)
                                    },
                                    complete: {
                                        guard let missionID = currentMission?.id else { return }
                                        model.completeMission(
                                            missionID,
                                            at: now,
                                            plannedDurationMinutes: currentBlock.durationMinutes
                                        )
                                    },
                                    adjustDuration: {
                                        durationMission = currentMission
                                    }
                                )
                            } else {
                                OpenTimeCard(nextBlock: upcoming.first, profile: model.snapshot.profile)
                            }

                            if !upcoming.isEmpty {
                                Text("Up next")
                                    .font(.headline)
                                    .padding(.top, 4)

                                ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, block in
                                    UpcomingBlockCard(
                                        block: block,
                                        mission: model.snapshot.mission(withID: block.missionID),
                                        profile: model.snapshot.profile,
                                        label: index == 0 ? "Next" : "Later"
                                    )
                                    .opacity(index == 0 ? 1 : max(0.58, 0.9 - Double(index) * 0.08))
                                }
                            }

                            if let checklist = model.snapshot.checklist(ofKind: .today) {
                                TodayChecklistCard(
                                    checklist: checklist,
                                    toggle: { itemID in
                                        model.toggleChecklistItem(checklistID: checklist.id, itemID: itemID)
                                    }
                                )
                                .padding(.top, 6)
                            }

                            if let notice = model.persistenceNotice {
                                Label(notice, systemImage: "exclamationmark.triangle")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 28)
                    }
                }
            }
            .background(Color.primary.opacity(0.018))
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ScreenMenuButton(action: openMenu)
                }
            }
        }
        .sheet(item: $durationMission) { mission in
            DurationEditor(
                mission: mission,
                save: { minutes in
                    model.updateActualDuration(for: mission.id, minutes: minutes)
                }
            )
            .presentationDetents([.height(320)])
        }
    }
}

private struct CurrentTimeOrb: View {
    let now: Date
    let block: ScheduleBlock?
    let profile: UserProfile

    private var progress: Double {
        block.map { ScheduleTimeline.progress(of: $0, at: now) } ?? 0
    }

    private var accent: Color {
        profile.color(for: block?.category ?? .freeTime)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: 13)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: progress)

            VStack(spacing: 6) {
                Text(MissionControlFormatters.time(now, profile: profile))
                    .font(.system(size: 45, weight: .semibold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.75)

                Text(block == nil ? "Open time" : "Now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(block == nil ? Color.secondary : accent)

                if let block {
                    let remaining = max(Int(ceil(block.end.timeIntervalSince(now) / 60)), 0)
                    Text("\(remaining) min remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Breathing room is valid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .frame(width: 192, height: 192)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let block else {
            return "The time is \(MissionControlFormatters.time(now, profile: profile)). Nothing is scheduled now."
        }
        return "The time is \(MissionControlFormatters.time(now, profile: profile)). Current block \(block.title), \(Int(progress * 100)) percent complete."
    }
}

private struct CurrentMissionCard: View {
    let block: ScheduleBlock
    let mission: Mission?
    let profile: UserProfile
    let toggleStep: (EntityID) -> Void
    let complete: () -> Void
    let adjustDuration: () -> Void

    private var accent: Color { profile.color(for: block.category) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(block.category.displayName.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                Spacer()
                Text(MissionControlFormatters.timeRange(block, profile: profile))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(block.title)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if let mission, !mission.miniGoals.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(mission.miniGoals) { step in
                        Button {
                            toggleStep(step.id)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(step.isCompleted ? accent : Color.secondary)
                                Text(step.title)
                                    .foregroundStyle(step.isCompleted ? Color.secondary : Color.primary)
                                    .strikethrough(step.isCompleted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let mission {
                if mission.status == .completed {
                    HStack {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Adjust time", action: adjustDuration)
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Button(action: complete) {
                        Label("Mark complete", systemImage: "checkmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                }
            } else if block.kind.isTransition {
                Label("Visible transition time", systemImage: "arrow.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .missionControlCard()
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: 4)
                .padding(.vertical, 22)
        }
    }
}

private struct OpenTimeCard: View {
    let nextBlock: ScheduleBlock?
    let profile: UserProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing scheduled right now")
                .font(.title3.weight(.semibold))
            if let nextBlock {
                Text("Next: \(nextBlock.title) at \(MissionControlFormatters.time(nextBlock.start, profile: profile)).")
                    .foregroundStyle(.secondary)
            } else {
                Text("The remaining time is intentionally open.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .missionControlCard()
    }
}

private struct UpcomingBlockCard: View {
    let block: ScheduleBlock
    let mission: Mission?
    let profile: UserProfile
    let label: String

    private var accent: Color { profile.color(for: block.category) }

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .fill(block.kind.isTransition ? Color.secondary.opacity(0.4) : accent)
                .frame(width: 4, height: 42)

            VStack(alignment: .leading, spacing: 5) {
                Text(label.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(block.kind.isTransition ? Color.secondary : accent)
                Text(block.title)
                    .font(.body.weight(block.kind.isTransition ? .regular : .semibold))
                    .foregroundStyle(block.kind.isTransition ? Color.secondary : Color.primary)
                if block.kind.isTransition {
                    Text(block.kind == .travel ? "Travel" : "Preparation")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if mission?.status == .completed {
                    Text("Completed")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Spacer(minLength: 8)

            Text(MissionControlFormatters.timeRange(block, profile: profile))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(block.kind.isTransition ? 0.025 : 0.045))
        )
        .accessibilityElement(children: .combine)
    }
}

private struct TodayChecklistCard: View {
    let checklist: Checklist
    let toggle: (EntityID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today checklist")
                    .font(.headline)
                Spacer()
                Text("\(checklist.items.filter(\.isCompleted).count)/\(checklist.items.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(checklist.items) { item in
                Button {
                    toggle(item.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isCompleted ? Color.green : Color.secondary)
                        Text(item.title)
                            .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                            .strikethrough(item.isCompleted)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .missionControlCard()
    }
}

private struct DurationEditor: View {
    @Environment(\.dismiss) private var dismiss
    let mission: Mission
    let save: (Int) -> Void

    @State private var minutes: Int

    init(mission: Mission, save: @escaping (Int) -> Void) {
        self.mission = mission
        self.save = save
        _minutes = State(initialValue: mission.actualDurationMinutes ?? mission.estimatedDurationMinutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Actual duration") {
                    Stepper("\(minutes) minutes", value: $minutes, in: 5...360, step: 5)
                    Text("Planned: \(mission.estimatedDurationMinutes) minutes")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Correct time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(minutes)
                        dismiss()
                    }
                }
            }
        }
    }
}
