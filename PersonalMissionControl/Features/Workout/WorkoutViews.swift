import Foundation
import MissionControlCore
import SwiftUI

struct TrainingProgramView: View {
    @ObservedObject var model: AppModel

    @State private var editingProgram: WorkoutProgram?
    @State private var clearanceFlag: PainFlag?
    @State private var clearanceNote = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if model.snapshot.workoutPrograms.isEmpty {
                    ContentUnavailableView(
                        "No approved program",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text(
                            "Add the exact program you intend to follow. Mission Control will not invent a replacement."
                        )
                    )
                } else {
                    ForEach(model.snapshot.workoutPrograms) { program in
                        programCard(program)
                    }
                }

                Button {
                    editingProgram = WorkoutProgram(
                        title: "New program",
                        detail: "Add the exact approved sessions and exercises."
                    )
                } label: {
                    Label("Add program", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                painSafeguards
            }
            .padding(18)
        }
        .background(Color.primary.opacity(0.018))
        .sheet(item: $editingProgram) { program in
            WorkoutProgramEditor(program: program) { saved in
                model.saveWorkoutProgram(saved)
                editingProgram = nil
            }
        }
        .sheet(item: $clearanceFlag) { flag in
            NavigationStack {
                Form {
                    Section("Reassessment") {
                        Text(
                            "Clearing this flag allows affected exercises to return to future plans. This is a planning safeguard, not a medical assessment."
                        )
                        TextField(
                            "What changed?",
                            text: $clearanceNote,
                            axis: .vertical
                        )
                    }
                }
                .navigationTitle("Clear \(flag.bodyArea) flag")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { clearanceFlag = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Clear flag") {
                            model.clearPainFlag(
                                id: flag.id,
                                note: clearanceNote.isEmpty
                                    ? "Explicitly reassessed and cleared."
                                    : clearanceNote
                            )
                            clearanceFlag = nil
                            clearanceNote = ""
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func programCard(_ program: WorkoutProgram) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(program.title)
                        .font(.title3.weight(.semibold))
                    Text(
                        program.isApproved
                            ? (program.isActive ? "Approved · Active" : "Approved · Inactive")
                            : "Draft · Not scheduled"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(
                        program.isApproved && program.isActive
                            ? Color.green
                            : Color.secondary
                    )
                }
                Spacer()
                Button("Edit") { editingProgram = program }
                    .buttonStyle(.bordered)
            }

            if !program.detail.isEmpty {
                Text(program.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(program.sessionTemplates.enumerated()), id: \.element.id) {
                index,
                session in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        if !session.detail.isEmpty {
                            Text(session.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(session.exercises.enumerated()), id: \.element.id) {
                            exerciseIndex,
                            exercise in
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(exerciseIndex + 1). \(exercise.title)")
                                Spacer()
                                Text(
                                    "\(exercise.sets.count) × \(exercise.sets.first?.targetRepText ?? "—")"
                                )
                                .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Text("\(index + 1). \(session.title)")
                            .font(.headline)
                        Spacer()
                        Text("\(session.estimatedDurationMinutes) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .missionControlCard()
    }

    @ViewBuilder
    private var painSafeguards: some View {
        let activeFlags = model.snapshot.painFlags.filter(\.isActive)
        VStack(alignment: .leading, spacing: 10) {
            Text("Planning safeguards")
                .font(.headline)
            if activeFlags.isEmpty {
                Label(
                    "No active body-area restrictions",
                    systemImage: "checkmark.shield"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                ForEach(activeFlags) { flag in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(flag.bodyArea.capitalized)
                                .font(.headline)
                            Text(flag.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reassess") {
                            clearanceNote = ""
                            clearanceFlag = flag
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Text(
                    "Affected movements stay out of plans until a flag is explicitly cleared. This is not medical diagnosis."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .missionControlCard()
    }
}

private struct WorkoutProgramEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkoutProgram

    let save: (WorkoutProgram) -> Void

    init(
        program: WorkoutProgram,
        save: @escaping (WorkoutProgram) -> Void
    ) {
        _draft = State(initialValue: program)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Program") {
                    TextField("Program name", text: $draft.title)
                    TextField(
                        "Notes",
                        text: $draft.detail,
                        axis: .vertical
                    )
                    Toggle("User-approved", isOn: $draft.isApproved)
                    Toggle("Active for scheduling", isOn: $draft.isActive)
                        .disabled(!draft.isApproved)
                }

                ForEach(Array(draft.sessionTemplates.indices), id: \.self) {
                    sessionIndex in
                    sessionSection(sessionIndex)
                }

                Button {
                    draft.sessionTemplates.append(
                        WorkoutSessionTemplate(
                            title: "New session",
                            exercises: []
                        )
                    )
                } label: {
                    Label("Add session", systemImage: "plus")
                }

                Section {
                    Text(
                        "Saving changes is explicit. Scheduling uses only approved, active programs and never creates replacement exercises."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Exact workout program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var normalized = draft
                        if !normalized.isApproved {
                            normalized.isActive = false
                        }
                        save(normalized)
                    }
                        .disabled(!canSave)
                }
            }
        }
    }

    @ViewBuilder
    private func sessionSection(_ sessionIndex: Int) -> some View {
        Section {
            TextField(
                "Session name",
                text: $draft.sessionTemplates[sessionIndex].title
            )
            TextField(
                "Session notes",
                text: $draft.sessionTemplates[sessionIndex].detail,
                axis: .vertical
            )
            Stepper(
                "Estimated time: \(draft.sessionTemplates[sessionIndex].estimatedDurationMinutes) min",
                value: $draft.sessionTemplates[sessionIndex]
                    .estimatedDurationMinutes,
                in: 15...180,
                step: 5
            )

            ForEach(
                Array(draft.sessionTemplates[sessionIndex].exercises.indices),
                id: \.self
            ) { exerciseIndex in
                exerciseEditor(
                    sessionIndex: sessionIndex,
                    exerciseIndex: exerciseIndex
                )
            }

            Button {
                draft.sessionTemplates[sessionIndex].exercises.append(
                    ExercisePrescription(
                        title: "New exercise",
                        sets: [
                            WorkoutSetPrescription(
                                targetRepMinimum: 8,
                                targetRepMaximum: 12
                            )
                        ],
                        restDurationSeconds: 90
                    )
                )
            } label: {
                Label("Add exercise", systemImage: "plus.circle")
            }

            Button("Remove session", role: .destructive) {
                draft.sessionTemplates.remove(at: sessionIndex)
            }
        } header: {
            Text("Session \(sessionIndex + 1)")
        }
    }

    @ViewBuilder
    private func exerciseEditor(
        sessionIndex: Int,
        exerciseIndex: Int
    ) -> some View {
        let exercise = draft.sessionTemplates[sessionIndex]
            .exercises[exerciseIndex]
        DisclosureGroup {
            TextField(
                "Exercise",
                text: $draft.sessionTemplates[sessionIndex]
                    .exercises[exerciseIndex].title
            )
            Stepper(
                "Sets: \(exercise.sets.count)",
                value: setCountBinding(
                    sessionIndex: sessionIndex,
                    exerciseIndex: exerciseIndex
                ),
                in: 1...10
            )
            Stepper(
                "Minimum reps: \(exercise.sets.first?.targetRepMinimum ?? 1)",
                value: minimumRepBinding(
                    sessionIndex: sessionIndex,
                    exerciseIndex: exerciseIndex
                ),
                in: 1...50
            )
            Stepper(
                "Maximum reps: \(exercise.sets.first?.targetRepMaximum ?? 1)",
                value: maximumRepBinding(
                    sessionIndex: sessionIndex,
                    exerciseIndex: exerciseIndex
                ),
                in: 1...50
            )
            Stepper(
                "Rest: \(exercise.restDurationSeconds) sec",
                value: $draft.sessionTemplates[sessionIndex]
                    .exercises[exerciseIndex].restDurationSeconds,
                in: 0...600,
                step: 15
            )
            TextField(
                "Optional target load",
                text: targetLoadBinding(
                    sessionIndex: sessionIndex,
                    exerciseIndex: exerciseIndex
                )
            )
            .keyboardType(.decimalPad)
            TextField(
                "Progression notes",
                text: optionalTextBinding(
                    sessionIndex: sessionIndex,
                    exerciseIndex: exerciseIndex,
                    keyPath: \.progressionNotes
                ),
                axis: .vertical
            )
            TextField(
                "Body areas, comma separated",
                text: bodyAreaBinding(
                    sessionIndex: sessionIndex,
                    exerciseIndex: exerciseIndex
                )
            )
            Picker(
                "Physical load",
                selection: $draft.sessionTemplates[sessionIndex]
                    .exercises[exerciseIndex].physicalLoad
            ) {
                Text("None").tag(PhysicalLoad.none)
                Text("Light").tag(PhysicalLoad.light)
                Text("Moderate").tag(PhysicalLoad.moderate)
                Text("Heavy").tag(PhysicalLoad.heavy)
            }

            HStack {
                Button {
                    moveExercise(
                        sessionIndex: sessionIndex,
                        from: exerciseIndex,
                        offset: -1
                    )
                } label: {
                    Label("Earlier", systemImage: "arrow.up")
                }
                .disabled(exerciseIndex == 0)

                Button {
                    moveExercise(
                        sessionIndex: sessionIndex,
                        from: exerciseIndex,
                        offset: 1
                    )
                } label: {
                    Label("Later", systemImage: "arrow.down")
                }
                .disabled(
                    exerciseIndex
                        == draft.sessionTemplates[sessionIndex]
                            .exercises.count - 1
                )
            }

            Button("Remove exercise", role: .destructive) {
                draft.sessionTemplates[sessionIndex]
                    .exercises.remove(at: exerciseIndex)
            }
        } label: {
            HStack {
                Text("\(exerciseIndex + 1). \(exercise.title)")
                Spacer()
                Text(
                    "\(exercise.sets.count) × \(exercise.sets.first?.targetRepText ?? "—")"
                )
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!draft.isApproved
                || !draft.sessionTemplates.isEmpty
                    && draft.sessionTemplates.allSatisfy {
                        !$0.title.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty && !$0.exercises.isEmpty
                    })
    }

    private func setCountBinding(
        sessionIndex: Int,
        exerciseIndex: Int
    ) -> Binding<Int> {
        Binding(
            get: {
                draft.sessionTemplates[sessionIndex]
                    .exercises[exerciseIndex].sets.count
            },
            set: { count in
                let exercise = draft.sessionTemplates[sessionIndex]
                    .exercises[exerciseIndex]
                let sample = exercise.sets.first
                    ?? WorkoutSetPrescription(targetReps: 8)
                if count > exercise.sets.count {
                    draft.sessionTemplates[sessionIndex]
                        .exercises[exerciseIndex].sets.append(
                            contentsOf: (exercise.sets.count..<count).map {
                                _ in
                                WorkoutSetPrescription(
                                    targetRepMinimum:
                                        sample.targetRepMinimum,
                                    targetRepMaximum:
                                        sample.targetRepMaximum
                                )
                            }
                        )
                } else {
                    draft.sessionTemplates[sessionIndex]
                        .exercises[exerciseIndex].sets =
                        Array(exercise.sets.prefix(count))
                }
            }
        )
    }

    private func minimumRepBinding(
        sessionIndex: Int,
        exerciseIndex: Int
    ) -> Binding<Int> {
        Binding(
            get: {
                draft.sessionTemplates[sessionIndex]
                    .exercises[exerciseIndex].sets.first?
                    .targetRepMinimum ?? 1
            },
            set: { value in
                for setIndex in draft.sessionTemplates[sessionIndex]
                    .exercises[exerciseIndex].sets.indices {
                    draft.sessionTemplates[sessionIndex]
                        .exercises[exerciseIndex].sets[setIndex]
                        .targetRepMinimum = value
                    draft.sessionTemplates[sessionIndex]
                        .exercises[exerciseIndex].sets[setIndex]
                        .targetRepMaximum = max(
                            value,
                            draft.sessionTemplates[sessionIndex]
                                .exercises[exerciseIndex].sets[setIndex]
                                .targetRepMaximum
                        )
                }
            }
        )
    }

    private func maximumRepBinding(
        sessionIndex: Int,
        exerciseIndex: Int
    ) -> Binding<Int> {
        Binding(
            get: {
                draft.sessionTemplates[sessionIndex]
                    .exercises[exerciseIndex].sets.first?
                    .targetRepMaximum ?? 1
            },
            set: { value in
                for setIndex in draft.sessionTemplates[sessionIndex]
                    .exercises[exerciseIndex].sets.indices {
                    let minimum = draft.sessionTemplates[sessionIndex]
                        .exercises[exerciseIndex].sets[setIndex]
                        .targetRepMinimum
                    draft.sessionTemplates[sessionIndex]
                        .exercises[exerciseIndex].sets[setIndex]
                        .targetRepMaximum = max(value, minimum)
                }
            }
        )
    }

    private func targetLoadBinding(
        sessionIndex: Int,
        exerciseIndex: Int
    ) -> Binding<String> {
        Binding(
            get: {
                draft.sessionTemplates[sessionIndex]
                    .exercises[exerciseIndex].targetLoad.map {
                        String(format: "%g", $0)
                    } ?? ""
            },
            set: { value in
                draft.sessionTemplates[sessionIndex]
                    .exercises[exerciseIndex].targetLoad = Double(
                        value.replacingOccurrences(of: ",", with: ".")
                    )
            }
        )
    }

    private func optionalTextBinding(
        sessionIndex: Int,
        exerciseIndex: Int,
        keyPath: WritableKeyPath<ExercisePrescription, String?>
    ) -> Binding<String> {
        Binding(
            get: {
                draft.sessionTemplates[sessionIndex]
                    .exercises[exerciseIndex][keyPath: keyPath] ?? ""
            },
            set: { value in
                draft.sessionTemplates[sessionIndex]
                    .exercises[exerciseIndex][keyPath: keyPath] =
                    value.isEmpty ? nil : value
            }
        )
    }

    private func bodyAreaBinding(
        sessionIndex: Int,
        exerciseIndex: Int
    ) -> Binding<String> {
        Binding(
            get: {
                draft.sessionTemplates[sessionIndex]
                    .exercises[exerciseIndex].bodyAreaTags
                    .joined(separator: ", ")
            },
            set: { value in
                draft.sessionTemplates[sessionIndex]
                    .exercises[exerciseIndex].bodyAreaTags =
                    value.split(separator: ",").map {
                        $0.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    }.filter { !$0.isEmpty }
            }
        )
    }

    private func moveExercise(
        sessionIndex: Int,
        from exerciseIndex: Int,
        offset: Int
    ) {
        let destination = exerciseIndex + offset
        guard draft.sessionTemplates[sessionIndex].exercises.indices
            .contains(destination) else {
            return
        }
        let exercise = draft.sessionTemplates[sessionIndex]
            .exercises.remove(at: exerciseIndex)
        draft.sessionTemplates[sessionIndex].exercises.insert(
            exercise,
            at: destination
        )
    }
}

struct WorkoutExecutionView: View {
    @ObservedObject var model: AppModel
    let block: ScheduleBlock

    @Environment(\.dismiss) private var dismiss
    @State private var workoutLogID: EntityID?
    @State private var weightText = ""
    @State private var repsText = ""

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let session, let log {
                            sessionHeader(session, log: log)
                            if let restEnd = log.restTimerEndsAt,
                               restEnd > context.date {
                                restCard(
                                    end: restEnd,
                                    now: context.date,
                                    logID: log.id
                                )
                            }
                            if let exercise = currentExercise(
                                session: session,
                                log: log
                            ), let setIndex = log.currentSetIndex,
                               exercise.sets.indices.contains(setIndex) {
                                currentSetCard(
                                    exercise: exercise,
                                    setIndex: setIndex,
                                    log: log
                                )
                            } else {
                                completeCard(log: log)
                            }
                            exercisePlan(session: session, log: log)
                        } else {
                            ContentUnavailableView(
                                "Approved session unavailable",
                                systemImage: "exclamationmark.shield",
                                description: Text(
                                    "This block has no valid approved-program prescription. No replacement workout was generated."
                                )
                            )
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle(session?.title ?? block.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            workoutLogID = model.startWorkout(
                scheduleBlockID: block.id
            )
            loadSuggestedInputs()
        }
    }

    private var activeBlock: ScheduleBlock {
        model.snapshot.scheduleBlocks.first(where: { $0.id == block.id })
            ?? block
    }

    private var session: WorkoutSessionTemplate? {
        model.workoutSession(for: activeBlock)
    }

    private var log: WorkoutLog? {
        if let workoutLogID {
            return model.snapshot.workoutLogs.first(where: {
                $0.id == workoutLogID
            })
        }
        return model.workoutLog(for: activeBlock)
    }

    private func sessionHeader(
        _ session: WorkoutSessionTemplate,
        log: WorkoutLog
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(log.isShortened ? "SHORTENED OCCURRENCE" : "APPROVED PROGRAM")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                Spacer()
                Text("\(log.selectedExerciseIDs.count) exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(session.title)
                .font(.title2.weight(.semibold))
            if log.isShortened {
                Text("The saved session template is unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .missionControlCard()
    }

    private func restCard(
        end: Date,
        now: Date,
        logID: EntityID
    ) -> some View {
        let seconds = max(Int(end.timeIntervalSince(now).rounded(.up)), 0)
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Rest")
                    .font(.headline)
                Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
                    .font(.title.monospacedDigit().weight(.semibold))
            }
            Spacer()
            Button("End rest") {
                model.endWorkoutRest(workoutLogID: logID)
            }
            .buttonStyle(.bordered)
        }
        .missionControlCard()
    }

    private func currentSetCard(
        exercise: ExercisePrescription,
        setIndex: Int,
        log: WorkoutLog
    ) -> some View {
        let prescription = exercise.sets[setIndex]
        return VStack(alignment: .leading, spacing: 13) {
            Text("Current exercise")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(exercise.title)
                .font(.title2.weight(.semibold))
            HStack {
                Label(
                    "Set \(setIndex + 1) of \(exercise.sets.count)",
                    systemImage: "list.number"
                )
                Spacer()
                Text("\(prescription.targetRepText) reps")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            if let targetLoad = exercise.targetLoad {
                Text("Optional target load: \(targetLoad, format: .number) kg")
                    .font(.subheadline)
            }
            if let notes = exercise.progressionNotes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let previous = model.previousWorkoutPerformance(
                exerciseID: exercise.id,
                currentLogID: log.id
            ) {
                Text("Previous: \(performanceText(previous))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No previous performance saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("Weight kg", text: $weightText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                TextField("Reps", text: $repsText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
            }

            Button {
                guard let reps = Int(repsText), reps >= 0 else { return }
                let weight = Double(
                    weightText.replacingOccurrences(of: ",", with: ".")
                )
                model.recordWorkoutSet(
                    workoutLogID: log.id,
                    weight: weight,
                    reps: reps
                )
                loadSuggestedInputs()
            } label: {
                Label("Log set and start rest", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(Int(repsText) == nil)
        }
        .missionControlCard()
    }

    private func completeCard(log: WorkoutLog) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("All selected sets logged", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)
            Button {
                model.finishWorkout(workoutLogID: log.id)
                dismiss()
            } label: {
                Text("Complete workout")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .missionControlCard()
    }

    private func exercisePlan(
        session: WorkoutSessionTemplate,
        log: WorkoutLog
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Session plan")
                .font(.headline)
            ForEach(
                session.exercises.filter {
                    log.selectedExerciseIDs.contains($0.id)
                }
            ) { exercise in
                let completed = log.exerciseLogs.first(where: {
                    $0.exerciseID == exercise.id
                })?.setLogs.count ?? 0
                HStack {
                    Image(
                        systemName: completed == exercise.sets.count
                            ? "checkmark.circle.fill"
                            : exercise.id == log.currentExerciseID
                                ? "record.circle"
                                : "circle"
                    )
                    .foregroundStyle(
                        completed == exercise.sets.count
                            ? Color.green
                            : Color.secondary
                    )
                    Text(exercise.title)
                    Spacer()
                    Text("\(completed)/\(exercise.sets.count)")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
        .missionControlCard()
    }

    private func currentExercise(
        session: WorkoutSessionTemplate,
        log: WorkoutLog
    ) -> ExercisePrescription? {
        session.exercises.first(where: {
            $0.id == log.currentExerciseID
        })
    }

    private func loadSuggestedInputs() {
        guard
            let session,
            let log,
            let exercise = currentExercise(session: session, log: log),
            let setIndex = log.currentSetIndex,
            exercise.sets.indices.contains(setIndex)
        else {
            weightText = ""
            repsText = ""
            return
        }
        let previous = model.previousWorkoutPerformance(
            exerciseID: exercise.id,
            currentLogID: log.id
        )?.setLogs.first(where: { $0.setNumber == setIndex + 1 })
        if let previousWeight = previous?.weight {
            weightText = String(format: "%g", previousWeight)
        } else if let targetLoad = exercise.targetLoad {
            weightText = String(format: "%g", targetLoad)
        } else {
            weightText = ""
        }
        repsText = previous.map { String($0.reps) }
            ?? String(exercise.sets[setIndex].targetRepMinimum)
    }

    private func performanceText(_ previous: WorkoutExerciseLog) -> String {
        previous.setLogs.map { set in
            let load = set.weight.map { "\(String(format: "%g", $0)) kg × " }
                ?? ""
            return "\(load)\(set.reps)"
        }.joined(separator: ", ")
    }
}
