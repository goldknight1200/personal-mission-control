import Foundation
import MissionControlCore
import SwiftUI

struct GoalsView: View {
    @ObservedObject var model: AppModel
    let openMenu: () -> Void

    @State private var editingProject: Project?

    var body: some View {
        NavigationStack {
            List {
                Section("Goals") {
                    ForEach(model.snapshot.goals) { goal in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(goal.title, systemImage: "scope")
                                .font(.headline)
                                .foregroundStyle(model.snapshot.profile.color(for: goal.category))
                            if !goal.detail.isEmpty {
                                Text(goal.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }

                Section("Projects") {
                    ForEach(model.snapshot.projects) { project in
                        Button {
                            editingProject = project
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(project.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(project.status.displayName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.indigo)
                                }
                                Text(project.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let targetDate = project.targetDate {
                                    Label(targetDate.formatted(date: .abbreviated, time: .omitted), systemImage: "flag")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 5)
                    }
                }

                Section {
                    Text("Project creation, priority changes, and training-program management arrive in later focused phases. This view only reflects local seed data.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ScreenMenuButton(action: openMenu)
                }
            }
        }
        .sheet(item: $editingProject) { project in
            ProjectEditor(project: project, save: model.updateProject)
                .presentationDetents([.large])
        }
    }
}

private struct ProjectEditor: View {
    @Environment(\.dismiss) private var dismiss
    let save: (Project) -> Void

    @State private var draft: Project
    @State private var hasTargetDate: Bool

    init(project: Project, save: @escaping (Project) -> Void) {
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
                        .lineLimit(3...6)
                    Picker("Status", selection: $draft.status) {
                        ForEach(ProjectStatus.allCases) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
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
                    Text("The seeded two-week horizon is editable. Saving a change regenerates the local seven-day plan.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if hasTargetDate, draft.targetDate == nil {
                            draft.targetDate = Date()
                        } else if !hasTargetDate {
                            draft.targetDate = nil
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
