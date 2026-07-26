import Foundation
import MissionControlCore
import SwiftUI

struct GoalsView: View {
    @ObservedObject var model: AppModel
    let openMenu: () -> Void

    @State private var editingGoal: Goal?
    @State private var editingProject: Project?
    @State private var selectedProject: Project?

    var body: some View {
        NavigationStack {
            List {
                Section("Broad goals") {
                    if model.snapshot.goals.isEmpty {
                        Text("Add a broad objective, then connect projects to it.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.snapshot.goals) { goal in
                        Button {
                            editingGoal = goal
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label(goal.title, systemImage: "scope")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if !goal.isActive {
                                        Text("Paused")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if !goal.detail.isEmpty {
                                    Text(goal.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                model.deleteGoal(goal.id)
                            }
                        }
                    }
                }

                ForEach(ProjectStatus.allCases) { status in
                    let projects = model.snapshot.projects.filter {
                        $0.status == status
                    }
                    Section(status.displayName) {
                        if projects.isEmpty {
                            Text(emptyProjectText(status))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(projects) { project in
                            Button {
                                selectedProject = project
                            } label: {
                                ProjectSummaryRow(
                                    project: project,
                                    progress: model.weeklyProgress(
                                        for: project.id
                                    ),
                                    goal: project.goalID.flatMap { goalID in
                                        model.snapshot.goals.first(where: {
                                            $0.id == goalID
                                        })
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    model.deleteProject(project.id)
                                }
                                Button("Edit") {
                                    editingProject = project
                                }
                                .tint(.indigo)
                            }
                        }
                    }
                }

                Section("Approved training") {
                    NavigationLink {
                        TrainingProgramView(model: model)
                            .navigationTitle("Training programs")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        HStack {
                            Label(
                                model.snapshot.workoutPrograms.first(where: {
                                    $0.isApproved && $0.isActive
                                })?.title ?? "Set an approved program",
                                systemImage:
                                    "figure.strengthtraining.traditional"
                            )
                            Spacer()
                            Text(
                                "\(model.snapshot.profile.gymWeeklyTarget.minimum)–\(model.snapshot.profile.gymWeeklyTarget.preferred) / week"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            editingGoal = Goal(
                                title: "",
                                category: .project
                            )
                        } label: {
                            Label("New goal", systemImage: "scope")
                        }
                        Button {
                            editingProject = Project(
                                title: "",
                                status: .backlog
                            )
                        } label: {
                            Label("New project", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add goal or project")
                    ScreenMenuButton(action: openMenu)
                }
            }
        }
        .sheet(item: $editingGoal) { goal in
            GoalEditor(goal: goal, save: model.saveGoal)
                .presentationDetents([.large])
        }
        .sheet(item: $editingProject) { project in
            ProjectEditor(
                project: project,
                goals: model.snapshot.goals,
                save: model.saveProject
            )
            .presentationDetents([.large])
        }
        .sheet(item: $selectedProject) { project in
            ProjectDetailView(model: model, projectID: project.id)
        }
    }

    private func emptyProjectText(_ status: ProjectStatus) -> String {
        switch status {
        case .activePriority:
            "No project currently has first call on focused time."
        case .maintained:
            "No project is set for steady weekly exposure."
        case .backlog:
            "The backlog is clear."
        }
    }
}

private struct ProjectSummaryRow: View {
    let project: Project
    let progress: ProjectWeeklyProgress?
    let goal: Goal?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if let priority = project.priorityOverride {
                    Text(priority.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            if let goal {
                Label(goal.title, systemImage: "scope")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !project.detail.isEmpty {
                Text(project.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let progress {
                HStack(spacing: 14) {
                    HoursLabel(
                        title: "Target",
                        minutes: progress.targetMinutes
                    )
                    HoursLabel(
                        title: "Planned",
                        minutes: progress.scheduledMinutes
                    )
                    HoursLabel(
                        title: "Actual",
                        minutes: progress.actualMinutes
                    )
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

private struct HoursLabel: View {
    let title: String
    let minutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(Self.hours(minutes))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    static func hours(_ minutes: Int) -> String {
        let value = Double(minutes) / 60
        return value.formatted(
            .number.precision(.fractionLength(value.rounded() == value ? 0 : 1))
        ) + "h"
    }
}

private struct ProjectDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    let projectID: EntityID

    @State private var editingProject: Project?
    @State private var editingMission: Mission?

    private var project: Project? {
        model.snapshot.projects.first(where: { $0.id == projectID })
    }

    private var missions: [Mission] {
        model.snapshot.missions
            .filter { $0.projectID == projectID && $0.sourceRoutineID == nil }
            .sorted(by: { $0.title < $1.title })
    }

    var body: some View {
        NavigationStack {
            List {
                if let project {
                    if let reassessment = model.activityReassessment(
                        for: projectID
                    ) {
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(
                                    "Is this still genuinely active?",
                                    systemImage: "questionmark.circle"
                                )
                                .font(.headline)
                                Text(
                                    "\(reassessment.recentSkipCount) project blocks were skipped recently. Confirm its place instead of rescheduling it forever."
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                HStack {
                                    Button("Keep active") {
                                        model.reviewProjectActivity(
                                            projectID: projectID,
                                            status: .activePriority
                                        )
                                    }
                                    .buttonStyle(.borderedProminent)
                                    Button("Maintain") {
                                        model.reviewProjectActivity(
                                            projectID: projectID,
                                            status: .maintained
                                        )
                                    }
                                    .buttonStyle(.bordered)
                                    Button("Backlog") {
                                        model.reviewProjectActivity(
                                            projectID: projectID,
                                            status: .backlog
                                        )
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .font(.caption.weight(.semibold))
                            }
                            .padding(.vertical, 5)
                        }
                    }

                    Section("Project") {
                        LabeledContent("Status", value: project.status.displayName)
                        LabeledContent("Your priority") {
                            Text(project.priorityOverride?.displayName ?? "Automatic")
                        }
                        if let target = project.targetDate {
                            LabeledContent("Target") {
                                Text(target.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                        if let progress = model.weeklyProgress(for: projectID) {
                            HStack(spacing: 24) {
                                HoursLabel(
                                    title: "Weekly target",
                                    minutes: progress.targetMinutes
                                )
                                HoursLabel(
                                    title: "In plan",
                                    minutes: progress.scheduledMinutes
                                )
                                HoursLabel(
                                    title: "Actual",
                                    minutes: progress.actualMinutes
                                )
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Section("AI recommendation") {
                        Label(
                            "Not configured",
                            systemImage: "sparkles"
                        )
                        .foregroundStyle(.secondary)
                        Text("A future optional interpreter may suggest a priority with an explanation. It cannot override your selection or plan the schedule.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Schedulable missions") {
                        if missions.isEmpty {
                            Text("Add a mission to give the planner concrete work for this project.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(missions) { mission in
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    editingMission = mission
                                } label: {
                                    HStack {
                                        Text(mission.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text("\(mission.estimatedDurationMinutes) min")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                if !mission.miniGoals.isEmpty {
                                    ForEach(mission.miniGoals) { step in
                                        Button {
                                            model.toggleMissionStep(
                                                missionID: mission.id,
                                                stepID: step.id
                                            )
                                        } label: {
                                            Label(
                                                step.title,
                                                systemImage: step.isCompleted
                                                    ? "checkmark.circle.fill"
                                                    : "circle"
                                            )
                                            .font(.subheadline)
                                            .foregroundStyle(
                                                step.isCompleted
                                                    ? Color.secondary
                                                    : Color.primary
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    model.deleteMission(mission.id)
                                }
                            }
                        }
                        Button {
                            editingMission = Mission(
                                projectID: projectID,
                                category: .project,
                                title: "",
                                rigidity: .flexible,
                                importance: .normal,
                                urgency: .normal,
                                estimatedDurationMinutes: 60,
                                minimumUsefulBlockMinutes: 30,
                                allowsSplitting: true,
                                userPriorityOverride:
                                    project.priorityOverride
                            )
                        } label: {
                            Label("Add mission", systemImage: "plus")
                        }
                    }
                }
            }
            .navigationTitle(project?.title ?? "Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        editingProject = project
                    }
                    .disabled(project == nil)
                }
            }
        }
        .sheet(item: $editingProject) { project in
            ProjectEditor(
                project: project,
                goals: model.snapshot.goals,
                save: model.saveProject
            )
        }
        .sheet(item: $editingMission) { mission in
            MissionEditor(mission: mission, save: model.saveMission)
        }
    }
}

private struct GoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    let save: (Goal) -> Void
    @State private var draft: Goal
    @State private var hasTargetDate: Bool

    init(goal: Goal, save: @escaping (Goal) -> Void) {
        self.save = save
        _draft = State(initialValue: goal)
        _hasTargetDate = State(initialValue: goal.targetDate != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Objective") {
                    TextField("Goal", text: $draft.title)
                    TextField("What does this change?", text: $draft.detail, axis: .vertical)
                        .lineLimit(3...7)
                    Picker("Area", selection: $draft.category) {
                        ForEach(MissionCategory.allCases) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    Toggle("Active", isOn: $draft.isActive)
                }
                Section("Horizon") {
                    Toggle("Use target date", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker(
                            "Target",
                            selection: Binding(
                                get: { draft.targetDate ?? Date() },
                                set: { draft.targetDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                    }
                }
            }
            .navigationTitle(draft.title.isEmpty ? "New goal" : "Edit goal")
            .navigationBarTitleDisplayMode(.inline)
            .editorToolbar(
                cancel: { dismiss() },
                save: {
                    if !hasTargetDate { draft.targetDate = nil }
                    save(draft)
                    dismiss()
                },
                saveDisabled: draft.title.trimmed.isEmpty
            )
        }
    }
}

private struct ProjectEditor: View {
    @Environment(\.dismiss) private var dismiss
    let goals: [Goal]
    let save: (Project) -> Void
    @State private var draft: Project
    @State private var hasTargetDate: Bool

    init(
        project: Project,
        goals: [Goal],
        save: @escaping (Project) -> Void
    ) {
        self.goals = goals
        self.save = save
        _draft = State(initialValue: project)
        _hasTargetDate = State(initialValue: project.targetDate != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Title", text: $draft.title)
                    TextField("Description", text: $draft.detail, axis: .vertical)
                        .lineLimit(3...7)
                    Picker("Goal", selection: $draft.goalID) {
                        Text("No linked goal").tag(EntityID?.none)
                        ForEach(goals) { goal in
                            Text(goal.title).tag(Optional(goal.id))
                        }
                    }
                    Picker("Status", selection: $draft.status) {
                        ForEach(ProjectStatus.allCases) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                }

                Section("Planning weight") {
                    Picker("Your priority", selection: $draft.priorityOverride) {
                        Text("Automatic").tag(PriorityLevel?.none)
                        ForEach(PriorityLevel.allCases, id: \.rawValue) {
                            priority in
                            Text(priority.displayName).tag(Optional(priority))
                        }
                    }
                    Stepper(
                        "Weekly target: \(HoursLabel.hours(draft.weeklyPlannedMinutes))",
                        value: $draft.weeklyPlannedMinutes,
                        in: 0...(40 * 60),
                        step: 30
                    )
                    Text("Maintained projects receive reasonable exposure when the week allows it; they are not forced into every day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Horizon") {
                    Toggle("Use target date", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker(
                            "Target",
                            selection: Binding(
                                get: { draft.targetDate ?? Date() },
                                set: { draft.targetDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                    }
                }
            }
            .navigationTitle(draft.title.isEmpty ? "New project" : "Edit project")
            .navigationBarTitleDisplayMode(.inline)
            .editorToolbar(
                cancel: { dismiss() },
                save: {
                    if !hasTargetDate { draft.targetDate = nil }
                    save(draft)
                    dismiss()
                },
                saveDisabled: draft.title.trimmed.isEmpty
            )
        }
    }
}

private struct MissionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let save: (Mission) -> Void
    @State private var draft: Mission
    @State private var newStep = ""

    init(mission: Mission, save: @escaping (Mission) -> Void) {
        self.save = save
        _draft = State(initialValue: mission)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mission") {
                    TextField("Concrete work", text: $draft.title)
                    Picker("Rigidity", selection: $draft.rigidity) {
                        ForEach(MissionRigidity.allCases) { rigidity in
                            Text(rigidity.rawValue.capitalized).tag(rigidity)
                        }
                    }
                    Stepper(
                        "Expected time: \(draft.estimatedDurationMinutes) min",
                        value: $draft.estimatedDurationMinutes,
                        in: 10...480,
                        step: 5
                    )
                    Stepper(
                        "Minimum useful block: \(draft.minimumUsefulBlockMinutes) min",
                        value: $draft.minimumUsefulBlockMinutes,
                        in: 10...120,
                        step: 5
                    )
                    Toggle("May split across blocks", isOn: $draft.allowsSplitting)
                }

                Section("Mission checklist") {
                    ForEach($draft.miniGoals) { $step in
                        HStack {
                            Image(
                                systemName: step.isCompleted
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            TextField("Step", text: $step.title)
                        }
                    }
                    .onDelete { offsets in
                        draft.miniGoals.remove(atOffsets: offsets)
                    }
                    HStack {
                        TextField("Add a step", text: $newStep)
                        Button("Add") {
                            let title = newStep.trimmed
                            guard !title.isEmpty else { return }
                            draft.miniGoals.append(MissionStep(title: title))
                            newStep = ""
                        }
                        .disabled(newStep.trimmed.isEmpty)
                    }
                }
            }
            .navigationTitle(draft.title.isEmpty ? "New mission" : "Edit mission")
            .navigationBarTitleDisplayMode(.inline)
            .editorToolbar(
                cancel: { dismiss() },
                save: {
                    draft.minimumUsefulBlockMinutes = min(
                        draft.minimumUsefulBlockMinutes,
                        draft.estimatedDurationMinutes
                    )
                    draft.miniGoals.removeAll(where: {
                        $0.title.trimmed.isEmpty
                    })
                    save(draft)
                    dismiss()
                },
                saveDisabled: draft.title.trimmed.isEmpty
            )
        }
    }
}

private extension PriorityLevel {
    var displayName: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        case .critical: "Critical"
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension View {
    func editorToolbar(
        cancel: @escaping () -> Void,
        save: @escaping () -> Void,
        saveDisabled: Bool
    ) -> some View {
        toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(saveDisabled)
            }
        }
    }
}
