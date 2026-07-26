import Foundation

public enum WorkoutPlanning {
    public static func nextSessions(
        in program: WorkoutProgram,
        after logs: [WorkoutLog],
        count: Int
    ) -> [WorkoutSessionTemplate] {
        guard count > 0, !program.sessionTemplates.isEmpty else { return [] }
        let completed = logs
            .filter {
                $0.programID == program.id
                    && ($0.status == .completed || $0.status == .partial)
            }
            .sorted {
                ($0.completedAt ?? $0.startedAt)
                    < ($1.completedAt ?? $1.startedAt)
            }
        let startIndex: Int
        if let last = completed.last,
           let lastIndex = program.sessionTemplates.firstIndex(where: {
               $0.id == last.sessionTemplateID
           }) {
            startIndex = (lastIndex + 1) % program.sessionTemplates.count
        } else {
            startIndex = 0
        }
        return (0..<count).map { offset in
            program.sessionTemplates[
                (startIndex + offset) % program.sessionTemplates.count
            ]
        }
    }

    public static func blockedExerciseIDs(
        in session: WorkoutSessionTemplate,
        painFlags: [PainFlag]
    ) -> [EntityID] {
        let activeAreas = painFlags
            .filter(\.isActive)
            .map { normalizedBodyArea($0.bodyArea) }
        guard !activeAreas.isEmpty else { return [] }
        return session.exercises.compactMap { exercise in
            let tags = exercise.bodyAreaTags.map(normalizedBodyArea)
            let isBlocked = tags.contains { tag in
                activeAreas.contains { area in
                    materiallyMatches(tag, area)
                }
            }
            return isBlocked ? exercise.id : nil
        }
    }

    public static func shortenedSuggestion(
        program: WorkoutProgram,
        session: WorkoutSessionTemplate,
        availableExerciseIDs: [EntityID],
        completedSessionsThisWeek: Int,
        weeklyTarget: Int
    ) -> ShortenedWorkoutSuggestion? {
        guard completedSessionsThisWeek < weeklyTarget else { return nil }
        let available = session.exercises.filter {
            availableExerciseIDs.contains($0.id)
        }
        guard available.count >= 3 else { return nil }
        let selectedCount = max(2, Int(ceil(Double(available.count) / 2)))
        let selected = Array(available.prefix(selectedCount))
        guard selected.count < available.count else { return nil }
        let proportion = Double(selected.count) / Double(available.count)
        let duration = max(
            20,
            min(
                session.estimatedDurationMinutes - 5,
                Int((Double(session.estimatedDurationMinutes) * proportion)
                    .rounded(.up))
            )
        )
        return ShortenedWorkoutSuggestion(
            programID: program.id,
            sessionTemplateID: session.id,
            exerciseIDs: selected.map(\.id),
            estimatedDurationMinutes: duration,
            explanation: "Use the first \(selected.count) approved exercises to preserve weekly consistency. The saved program is unchanged."
        )
    }

    private static let lowerBodyAreas: Set<String> = [
        "lower body",
        "hamstring",
        "quadriceps",
        "quad",
        "knee",
        "calf",
        "ankle",
        "glute",
        "hip"
    ]

    private static func normalizedBodyArea(_ value: String) -> String {
        value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func materiallyMatches(
        _ tag: String,
        _ painArea: String
    ) -> Bool {
        tag.contains(painArea)
            || painArea.contains(tag)
            || lowerBodyAreas.contains(tag)
                && lowerBodyAreas.contains(painArea)
    }
}

public enum WorkoutExecution {
    @discardableResult
    public static func start(
        snapshot: inout MissionControlSnapshot,
        scheduleBlockID: EntityID,
        at date: Date
    ) -> EntityID? {
        if let existing = snapshot.workoutLogs.first(where: {
            $0.scheduleBlockID == scheduleBlockID
                && $0.status == .inProgress
        }) {
            return existing.id
        }
        guard
            let block = snapshot.scheduleBlocks.first(where: {
                $0.id == scheduleBlockID
            }),
            let missionID = block.missionID,
            let metadata = block.workout,
            let program = snapshot.workoutPrograms.first(where: {
                $0.id == metadata.programID
            }),
            let session = program.sessionTemplates.first(where: {
                $0.id == metadata.sessionTemplateID
            }),
            let firstExerciseID = metadata.exerciseIDs.first,
            session.exercises.contains(where: { $0.id == firstExerciseID })
        else {
            return nil
        }
        let log = WorkoutLog(
            programID: program.id,
            sessionTemplateID: session.id,
            missionID: missionID,
            scheduleBlockID: block.id,
            selectedExerciseIDs: metadata.exerciseIDs,
            isShortened: metadata.isShortened,
            startedAt: date,
            currentExerciseID: firstExerciseID,
            currentSetIndex: 0
        )
        snapshot.workoutLogs.append(log)
        return log.id
    }

    @discardableResult
    public static func recordSet(
        snapshot: inout MissionControlSnapshot,
        workoutLogID: EntityID,
        weight: Double?,
        reps: Int,
        at date: Date
    ) -> Bool {
        guard
            reps >= 0,
            let logIndex = snapshot.workoutLogs.firstIndex(where: {
                $0.id == workoutLogID && $0.status == .inProgress
            }),
            let exerciseID = snapshot.workoutLogs[logIndex].currentExerciseID,
            let setIndex = snapshot.workoutLogs[logIndex].currentSetIndex,
            let program = snapshot.workoutPrograms.first(where: {
                $0.id == snapshot.workoutLogs[logIndex].programID
            }),
            let session = program.sessionTemplates.first(where: {
                $0.id == snapshot.workoutLogs[logIndex].sessionTemplateID
            }),
            let exercise = session.exercises.first(where: {
                $0.id == exerciseID
            }),
            exercise.sets.indices.contains(setIndex)
        else {
            return false
        }
        let set = exercise.sets[setIndex]
        let setLog = WorkoutSetLog(
            prescriptionSetID: set.id,
            setNumber: setIndex + 1,
            weight: weight,
            reps: reps,
            completedAt: date
        )
        if let exerciseIndex = snapshot.workoutLogs[logIndex]
            .exerciseLogs.firstIndex(where: {
                $0.exerciseID == exerciseID
            }) {
            snapshot.workoutLogs[logIndex]
                .exerciseLogs[exerciseIndex].setLogs.append(setLog)
        } else {
            snapshot.workoutLogs[logIndex].exerciseLogs.append(
                WorkoutExerciseLog(
                    exerciseID: exerciseID,
                    setLogs: [setLog]
                )
            )
        }
        snapshot.workoutLogs[logIndex].restTimerEndsAt =
            exercise.restDurationSeconds > 0
                ? date.addingTimeInterval(
                    TimeInterval(exercise.restDurationSeconds)
                )
                : nil

        if exercise.sets.indices.contains(setIndex + 1) {
            snapshot.workoutLogs[logIndex].currentSetIndex = setIndex + 1
            return true
        }
        let selected = snapshot.workoutLogs[logIndex].selectedExerciseIDs
        guard let selectedIndex = selected.firstIndex(of: exerciseID),
              selected.indices.contains(selectedIndex + 1) else {
            snapshot.workoutLogs[logIndex].currentExerciseID = nil
            snapshot.workoutLogs[logIndex].currentSetIndex = nil
            return true
        }
        snapshot.workoutLogs[logIndex].currentExerciseID =
            selected[selectedIndex + 1]
        snapshot.workoutLogs[logIndex].currentSetIndex = 0
        return true
    }

    @discardableResult
    public static func finish(
        snapshot: inout MissionControlSnapshot,
        workoutLogID: EntityID,
        status: WorkoutLogStatus = .completed,
        at date: Date
    ) -> Bool {
        guard
            status != .inProgress,
            let index = snapshot.workoutLogs.firstIndex(where: {
                $0.id == workoutLogID
            })
        else {
            return false
        }
        snapshot.workoutLogs[index].status = status
        snapshot.workoutLogs[index].completedAt = date
        snapshot.workoutLogs[index].currentExerciseID = nil
        snapshot.workoutLogs[index].currentSetIndex = nil
        snapshot.workoutLogs[index].restTimerEndsAt = nil
        return true
    }

    public static func endRest(
        snapshot: inout MissionControlSnapshot,
        workoutLogID: EntityID
    ) {
        guard let index = snapshot.workoutLogs.firstIndex(where: {
            $0.id == workoutLogID
        }) else {
            return
        }
        snapshot.workoutLogs[index].restTimerEndsAt = nil
    }

    public static func previousExerciseLog(
        exerciseID: EntityID,
        before currentLogID: EntityID?,
        in logs: [WorkoutLog]
    ) -> WorkoutExerciseLog? {
        logs
            .filter {
                $0.id != currentLogID
                    && ($0.status == .completed || $0.status == .partial)
            }
            .sorted {
                ($0.completedAt ?? $0.startedAt)
                    > ($1.completedAt ?? $1.startedAt)
            }
            .compactMap { log in
                log.exerciseLogs.first(where: {
                    $0.exerciseID == exerciseID
                })
            }
            .first
    }
}
