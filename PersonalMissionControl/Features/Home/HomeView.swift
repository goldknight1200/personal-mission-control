import MissionControlCore
import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AppModel
    let openMenu: () -> Void
    let voicePressed: () -> Void
    let voiceReleased: () -> Void
    let voiceFallback: () -> Void

    @State private var durationMission: Mission?
    @State private var workoutBlock: ScheduleBlock?

    var body: some View {
        NavigationStack {
            GeometryReader { _ in
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let now = context.date
                    let todayStart = localCalendar.startOfDay(for: now)
                    let tomorrow = localCalendar.date(
                        byAdding: .day,
                        value: 1,
                        to: todayStart
                    ) ?? now.addingTimeInterval(86_400)
                    let blocks = model.snapshot.scheduleBlocks.filter {
                        $0.start < tomorrow && $0.end > todayStart
                    }
                    let currentBlock = ScheduleTimeline.currentBlock(in: blocks, at: now)
                    let upcoming = ScheduleTimeline.upcomingBlocks(in: blocks, after: now)
                    let currentMission = model.snapshot.mission(withID: currentBlock?.missionID)
                    let unresolvedBlock = model.mostRelevantUnresolvedBlock(at: now)
                    let eveningSummary = model.eveningSummary(at: now)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            CurrentTimeOrb(
                                now: now,
                                block: currentBlock,
                                profile: model.snapshot.profile
                            )
                            .frame(minHeight: 210)
                            .frame(maxWidth: .infinity)

                            if DailyReflection.shouldShowMorning(
                                snapshot: model.snapshot,
                                at: now
                            ) {
                                MorningCheckInCard(
                                    noChanges: {
                                        model.recordMorningNoChanges(at: now)
                                    },
                                    voicePressed: voicePressed,
                                    voiceReleased: voiceReleased,
                                    voiceFallback: voiceFallback
                                )
                            }

                            if model.notificationAuthorizationState == .notDetermined {
                                NotificationPermissionCard {
                                    Task {
                                        await model.requestNotificationAuthorization()
                                    }
                                }
                            }

                            if let unresolvedBlock,
                               let missionID = unresolvedBlock.missionID {
                                MissedMissionCard(
                                    block: unresolvedBlock,
                                    missionTitle: model.snapshot.mission(
                                        withID: missionID
                                    )?.title ?? unresolvedBlock.title,
                                    profile: model.snapshot.profile,
                                    action: { action in
                                        let notificationStage:
                                            MissionNotificationStage
                                        switch model.latenessState(
                                            for: unresolvedBlock,
                                            at: now
                                        ) {
                                        case .some(.late30):
                                            notificationStage = .late30
                                        case .some(.late15):
                                            notificationStage = .late15
                                        default:
                                            notificationStage = .start
                                        }
                                        model.presentExecutionAction(
                                            action,
                                            missionID: missionID,
                                            scheduleBlockID: unresolvedBlock.id,
                                            at: now,
                                            notificationStage: notificationStage
                                        )
                                    }
                                )
                            }

                            if let currentBlock {
                                CurrentMissionCard(
                                    block: currentBlock,
                                    mission: currentMission,
                                    workoutSession:
                                        model.workoutSession(
                                            for: currentBlock
                                        ),
                                    profile: model.snapshot.profile,
                                    toggleStep: { stepID in
                                        guard let missionID = currentMission?.id else { return }
                                        model.toggleMissionStep(missionID: missionID, stepID: stepID)
                                    },
                                    complete: {
                                        guard let missionID = currentMission?.id else { return }
                                        model.completeMission(
                                            missionID,
                                            scheduleBlockID: currentBlock.id,
                                            at: now,
                                            plannedDurationMinutes: currentBlock.durationMinutes
                                        )
                                    },
                                    partial: {
                                        guard let missionID = currentMission?.id else { return }
                                        model.recordPartialMission(
                                            missionID: missionID,
                                            scheduleBlockID: currentBlock.id,
                                            at: now
                                        )
                                    },
                                    adjustDuration: {
                                        durationMission = currentMission
                                    },
                                    openWorkout: {
                                        workoutBlock = currentBlock
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

                            if DailyReflection.shouldShowEvening(
                                snapshot: model.snapshot,
                                at: now
                            ) {
                                EveningSummaryCard(
                                    summary: eveningSummary,
                                    missionTitle: { block in
                                        model.snapshot.mission(
                                            withID: block.missionID
                                        )?.title ?? block.title
                                    },
                                    resolve: { blockID, disposition in
                                        model.resolveEveningItem(
                                            scheduleBlockID: blockID,
                                            disposition: disposition,
                                            at: now
                                        )
                                    }
                                )
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
        .sheet(item: $workoutBlock) { block in
            WorkoutExecutionView(model: model, block: block)
        }
    }

    private var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(
            identifier: model.snapshot.profile.timeZoneIdentifier
        ) ?? .current
        return calendar
    }
}

private struct MorningCheckInCard: View {
    let noChanges: () -> Void
    let voicePressed: () -> Void
    let voiceReleased: () -> Void
    let voiceFallback: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Anything changed?")
                    .font(.title3.weight(.semibold))
                Text("The provisional plan is ready.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("No changes", action: noChanges)
                .buttonStyle(.bordered)

            Image(systemName: isPressed ? "waveform" : "mic.fill")
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(isPressed ? Color.red : Color.accentColor))
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !isPressed else { return }
                            isPressed = true
                            voicePressed()
                        }
                        .onEnded { _ in
                            guard isPressed else { return }
                            isPressed = false
                            voiceReleased()
                        }
                )
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Tell Mission Control what changed")
                .accessibilityHint("Press and hold to record, then release to review.")
                .accessibilityAction {
                    voiceFallback()
                }
        }
        .missionControlCard()
    }
}

private struct NotificationPermissionCard: View {
    let allow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Keep the day aligned")
                    .font(.headline)
                Text("Allow local mission reminders and recovery actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Allow", action: allow)
                .buttonStyle(.borderedProminent)
        }
        .missionControlCard()
    }
}

private struct MissedMissionCard: View {
    let block: ScheduleBlock
    let missionTitle: String
    let profile: UserProfile
    let action: (MissionNotificationActionKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Plan needs attention", systemImage: "clock.badge.exclamationmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                Spacer()
                Text(MissionControlFormatters.time(block.start, profile: profile))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(missionTitle)
                .font(.title3.weight(.semibold))

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                recoveryButton("Already Started", .alreadyStarted)
                recoveryButton("Start Now", .startNow)
                recoveryButton("Replan", .replan)
                recoveryButton("Skip", .skip)
            }
        }
        .missionControlCard()
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.orange.opacity(0.3))
        )
    }

    private func recoveryButton(
        _ title: String,
        _ kind: MissionNotificationActionKind
    ) -> some View {
        Button(title) {
            action(kind)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }
}

private struct EveningSummaryCard: View {
    let summary: EveningExecutionSummary
    let missionTitle: (ScheduleBlock) -> String
    let resolve: (EntityID, UnresolvedMissionDisposition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Evening summary")
                .font(.headline)

            HStack(spacing: 18) {
                count(summary.completedCount, "Completed", .green)
                count(summary.partialCount, "Partial", .orange)
                count(summary.skippedCount, "Skipped", .secondary)
            }

            if summary.unresolvedBlocks.isEmpty {
                Label("Nothing needs a decision.", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                Text("Decide only the unresolved items")
                    .font(.subheadline.weight(.semibold))

                ForEach(summary.unresolvedBlocks) { block in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(missionTitle(block))
                            .font(.headline)
                        HStack {
                            dispositionButton("Tomorrow", .moveToTomorrow, block.id)
                            dispositionButton("Backlog", .weeklyBacklog, block.id)
                            dispositionButton("Drop", .drop, block.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .missionControlCard()
    }

    private func count(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func dispositionButton(
        _ title: String,
        _ disposition: UnresolvedMissionDisposition,
        _ blockID: EntityID
    ) -> some View {
        Button(title) {
            resolve(blockID, disposition)
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
    }
}

private struct CurrentTimeOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var orbSize = 192
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize = 45

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
                .animation(
                    reduceMotion ? nil : .linear(duration: 0.3),
                    value: progress
                )

            VStack(spacing: 6) {
                Text(MissionControlFormatters.time(now, profile: profile))
                    .font(
                        .system(
                            size: timeSize,
                            weight: .semibold,
                            design: .rounded
                        )
                        .monospacedDigit()
                    )
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
        .frame(width: orbSize, height: orbSize)
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
    let workoutSession: WorkoutSessionTemplate?
    let profile: UserProfile
    let toggleStep: (EntityID) -> Void
    let complete: () -> Void
    let partial: () -> Void
    let adjustDuration: () -> Void
    let openWorkout: () -> Void

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

            if let workoutSession {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(
                        workoutSession.exercises.filter {
                            block.workout?.exerciseIDs.contains($0.id)
                                ?? false
                        }
                    ) { exercise in
                        HStack {
                            Image(systemName: "circle")
                                .foregroundStyle(accent)
                            Text(exercise.title)
                            Spacer()
                            Text(
                                "\(exercise.sets.count) × \(exercise.sets.first?.targetRepText ?? "—")"
                            )
                            .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    if let blockedCount =
                        block.workout?.blockedExerciseIDs.count,
                       blockedCount > 0 {
                        Label(
                            "\(blockedCount) affected movement\(blockedCount == 1 ? "" : "s") held out",
                            systemImage: "shield.lefthalf.filled"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
            } else if let mission, !mission.miniGoals.isEmpty {
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
                if mission.status == .completed || mission.status == .partial {
                    HStack {
                        Label(
                            mission.status == .completed ? "Completed" : "Partial",
                            systemImage: mission.status == .completed
                                ? "checkmark.circle.fill"
                                : "circle.lefthalf.filled"
                        )
                            .font(.headline)
                            .foregroundStyle(
                                mission.status == .completed ? Color.green : Color.orange
                            )
                        Spacer()
                        Button("Adjust time", action: adjustDuration)
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    if workoutSession != nil {
                        Button(action: openWorkout) {
                            Label(
                                "Open workout",
                                systemImage: "figure.strengthtraining.traditional"
                            )
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                    } else {
                        HStack {
                            Button("Partial", action: partial)
                                .buttonStyle(.bordered)
                            Button(action: complete) {
                                Label("Complete", systemImage: "checkmark")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                        }
                    }
                }
            } else if block.kind.isTransition {
                Label("Visible transition time", systemImage: "arrow.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if block.kind == .sleep {
                Label("Protected recovery", systemImage: "moon.zzz")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if block.kind == .freeTime {
                Label("Intentionally open", systemImage: "leaf")
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
                .fill(isQuiet ? Color.secondary.opacity(0.4) : accent)
                .frame(width: 4, height: 42)

            VStack(alignment: .leading, spacing: 5) {
                Text(label.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isQuiet ? Color.secondary : accent)
                Text(block.title)
                    .font(.body.weight(isQuiet ? .regular : .semibold))
                    .foregroundStyle(isQuiet ? Color.secondary : Color.primary)
                if block.kind.isTransition {
                    Text(block.kind == .travel ? "Travel" : "Preparation")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if block.kind == .sleep {
                    Text("Recovery")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if block.kind == .freeTime {
                    Text("Preserved")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if mission?.status == .completed {
                    Text("Completed")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if mission?.status == .partial {
                    Text("Partial")
                        .font(.caption)
                        .foregroundStyle(.orange)
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
                .fill(Color.primary.opacity(isQuiet ? 0.025 : 0.045))
        )
        .accessibilityElement(children: .combine)
    }

    private var isQuiet: Bool {
        block.kind.isTransition
            || block.kind == .sleep
            || block.kind == .freeTime
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
