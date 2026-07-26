import Foundation

public enum WorkShiftImageImportCoordinator {
    public static func review(
        recognition: WorkShiftImageRecognition,
        title: String,
        location: String?,
        referenceDate: Date,
        timeZoneIdentifier: String,
        existingCommitments: [FixedCommitment],
        minimumConfidence: Double = 0.72
    ) -> WorkShiftImageReview {
        let usableLines = recognition.lines.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.confidence >= minimumConfidence
        }
        let recognizedText = usableLines
            .map(\.text)
            .joined(separator: "\n")
        let parsed = WorkShiftBatchParser().parse(
            recognizedText,
            title: title,
            location: location,
            referenceDate: referenceDate,
            timeZoneIdentifier: timeZoneIdentifier,
            existingCommitments: existingCommitments
        )
        var ambiguities = recognition.lines
            .filter {
                !$0.text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty && $0.confidence < minimumConfidence
            }
            .map {
                "Low-confidence text was not used: \"\($0.text)\""
            }
        if let unparsed = parsed.unparsedInput {
            ambiguities.append(
                "No reliable date/time range could be extracted from: \"\(unparsed)\""
            )
        }
        if recognition.lines.isEmpty {
            ambiguities.append("No text was detected in the selected image.")
        }
        return WorkShiftImageReview(
            recognizedText: recognizedText,
            parseResult: parsed,
            ambiguities: ambiguities
        )
    }
}

public enum SnapshotIntegrityValidator {
    public static func issues(
        in snapshot: MissionControlSnapshot
    ) -> [SnapshotIntegrityIssue] {
        var issues: [SnapshotIntegrityIssue] = []
        if snapshot.schemaVersion < 1
            || snapshot.schemaVersion
                > MissionControlSnapshot.currentSchemaVersion {
            issues.append(
                SnapshotIntegrityIssue(
                    kind: .unsupportedSchema,
                    message:
                        "Snapshot schema \(snapshot.schemaVersion) is not supported."
                )
            )
        }
        if TimeZone(identifier: snapshot.profile.timeZoneIdentifier) == nil {
            issues.append(
                SnapshotIntegrityIssue(
                    kind: .invalidTimeZone,
                    message: "The profile time zone is invalid."
                )
            )
        }
        let policy = snapshot.profile.planningPolicy
        if TimeZone(identifier: policy.timeZoneIdentifier) == nil
            || policy.timeZoneIdentifier
                != snapshot.profile.timeZoneIdentifier
            || policy.planningHorizonDays <= 0
            || policy.minimumFocusedBlockMinutes <= 0
            || policy.sleepTargetMinutes <= 0
            || policy.practicalSleepMinimumMinutes < 0
            || policy.practicalSleepMinimumMinutes
                > policy.sleepTargetMinutes
            || policy.reconsiderDemandingWorkBelowMinutes < 0
            || policy.reconsiderDemandingWorkBelowMinutes
                > policy.practicalSleepMinimumMinutes
            || !(0..<24 * 60).contains(policy.preferredWakeMinute)
            || policy.generatedGridMinutes <= 0 {
            appendInvalidValueIssue(
                "The planning policy contains an invalid threshold.",
                to: &issues
            )
        }
        let profile = snapshot.profile
        if profile.footballPattern.historicalTrainingDurationMinutes <= 0
            || !(0..<24 * 60).contains(
                profile.footballPattern.historicalTrainingStartMinute
            )
            || profile.gymWeeklyTarget.minimum < 0
            || profile.gymWeeklyTarget.preferred
                < profile.gymWeeklyTarget.minimum
            || profile.transitions.workTravelEachWayMinutes < 0
            || profile.transitions.footballTravelEachWayMinutes < 0
            || profile.transitions.gymTravelEachWayMinutes < 0
            || profile.transitions.shoppingTravelMinutes < 0
            || !valid(profile.transitions.workPreparationMinutes)
            || !valid(profile.transitions.footballPreparationMinutes)
            || !valid(profile.transitions.gymPreparationMinutes)
            || !valid(profile.transitions.gymShowerChangeMinutes)
            || !valid(profile.transitions.footballShowerChangeMinutes) {
            appendInvalidValueIssue(
                "The profile contains an invalid target or transition.",
                to: &issues
            )
        }
        let nutritionTargets = snapshot.profile.nutritionTargets
        if nutritionTargets.approximateCalories < 0
            || nutritionTargets.approximateProteinGrams < 0
            || nutritionTargets.substantialMeals < 0
            || nutritionTargets.preferredMealStartMinutes.contains(
                where: { !(0..<24 * 60).contains($0) }
            )
            || nutritionTargets.clearCalorieDeficitThreshold < 0
            || nutritionTargets.clearProteinDeficitThreshold < 0
            || nutritionTargets.clearSubstantialMealDeficitThreshold < 0
            || nutritionTargets.additionalEatingBlockMinutes <= 0
            || nutritionTargets.inventoryShoppingLeadHours < 0 {
            appendInvalidValueIssue(
                "Nutrition targets contain an invalid value.",
                to: &issues
            )
        }
        let goalIDs = Set(snapshot.goals.map(\.id))
        let projectIDs = Set(snapshot.projects.map(\.id))
        let missionIDs = Set(snapshot.missions.map(\.id))
        let fixedCommitmentIDs = Set(snapshot.fixedCommitments.map(\.id))
        let routineIDs = Set(snapshot.routines.map(\.id))
        let mealTemplateIDs = Set(snapshot.mealTemplates.map(\.id))
        let plannedMealIDs = Set(snapshot.plannedMeals.map(\.id))
        let inventoryItemIDs = Set(snapshot.inventoryItems.map(\.id))
        let workoutProgramIDs = Set(snapshot.workoutPrograms.map(\.id))
        let nutritionNeedIDs = Set(snapshot.nutritionPlanningNeeds.map(\.id))
        for project in snapshot.projects
        where project.weeklyPlannedMinutes < 0
            || (project.goalID.map({ !goalIDs.contains($0) }) ?? false) {
            if project.weeklyPlannedMinutes < 0 {
                appendInvalidValueIssue(
                    "Project \(project.id.rawValue.uuidString) has invalid planned minutes.",
                    to: &issues
                )
            } else {
                appendOrphanedReferenceIssue(
                    "Project \(project.id.rawValue.uuidString) references a missing goal.",
                    to: &issues
                )
            }
        }
        for mission in snapshot.missions
        where mission.estimatedDurationMinutes <= 0
            || mission.minimumUsefulBlockMinutes <= 0
            || (mission.actualDurationMinutes ?? 0) < 0
            || mission.preparationMinutes < 0
            || mission.travelBeforeMinutes < 0
            || mission.travelAfterMinutes < 0
            || !valid(mission.dueWindow) {
            appendInvalidValueIssue(
                "Mission \(mission.id.rawValue.uuidString) contains an invalid duration or due window.",
                to: &issues
            )
        }
        for mission in snapshot.missions
        where (mission.projectID.map({
            !projectIDs.contains($0)
        }) ?? false)
            || (mission.sourceRoutineID.map({
                !routineIDs.contains($0)
            }) ?? false)
            || (mission.plannedMealID.map({
                !plannedMealIDs.contains($0)
            }) ?? false)
            || (mission.mealTemplateID.map({
                !mealTemplateIDs.contains($0)
            }) ?? false)
            || (mission.nutritionPlanningNeedID.map({
                !nutritionNeedIDs.contains($0)
            }) ?? false) {
            appendOrphanedReferenceIssue(
                "Mission \(mission.id.rawValue.uuidString) has a missing active reference.",
                to: &issues
            )
        }
        for commitment in snapshot.fixedCommitments
        where !commitment.start.timeIntervalSinceReferenceDate.isFinite
            || !commitment.end.timeIntervalSinceReferenceDate.isFinite
            || commitment.end <= commitment.start {
            issues.append(
                SnapshotIntegrityIssue(
                    kind: .invalidInterval,
                    message:
                        "Fixed commitment \(commitment.id.rawValue.uuidString) has an invalid interval."
                )
            )
        }
        for block in snapshot.scheduleBlocks
        where !block.start.timeIntervalSinceReferenceDate.isFinite
            || !block.end.timeIntervalSinceReferenceDate.isFinite
            || block.end <= block.start {
            issues.append(
                SnapshotIntegrityIssue(
                    kind: .invalidInterval,
                    message:
                        "Schedule block \(block.id.rawValue.uuidString) has an invalid interval."
                )
            )
        }
        for block in snapshot.scheduleBlocks
        where (block.missionID.map({
            !missionIDs.contains($0)
        }) ?? false)
            || (block.fixedCommitmentID.map({
                !fixedCommitmentIDs.contains($0)
            }) ?? false) {
            appendOrphanedReferenceIssue(
                "Schedule block \(block.id.rawValue.uuidString) has a missing source.",
                to: &issues
            )
        }
        for adjustment in snapshot.manualScheduleAdjustments
        where !adjustment.block.start.timeIntervalSinceReferenceDate.isFinite
            || !adjustment.block.end.timeIntervalSinceReferenceDate.isFinite
            || adjustment.block.end <= adjustment.block.start {
            issues.append(
                SnapshotIntegrityIssue(
                    kind: .invalidInterval,
                    message:
                        "Manual adjustment \(adjustment.id.rawValue.uuidString) has an invalid interval."
                )
            )
        }
        for routine in snapshot.routines
        where routine.recurrence.interval <= 0
            || routine.estimatedDurationMinutes <= 0
            || routine.dueWindowMinutes < 0
            || (routine.recurrence.preferredStartMinute.map({
                !(0..<24 * 60).contains($0)
            }) ?? false)
            || (routine.flexibleCadence.map({
                $0.minimumDays <= 0 || $0.maximumDays < $0.minimumDays
            }) ?? false) {
            appendInvalidValueIssue(
                "Routine \(routine.id.rawValue.uuidString) contains an invalid recurrence or duration.",
                to: &issues
            )
        }
        for routine in snapshot.routines
        where routine.compatibleRoutineIDs.contains(where: {
            !routineIDs.contains($0)
        }) {
            appendOrphanedReferenceIssue(
                "Routine \(routine.id.rawValue.uuidString) references a missing compatible routine.",
                to: &issues
            )
        }
        for completion in snapshot.completions
        where completion.plannedDurationMinutes <= 0
            || completion.actualDurationMinutes < 0
            || (
                completion.actualStart != nil
                    && completion.actualEnd != nil
                    && completion.actualEnd! < completion.actualStart!
            ) {
            appendInvalidValueIssue(
                "Completion \(completion.id.rawValue.uuidString) contains invalid timing.",
                to: &issues
            )
        }
        for checkIn in snapshot.dailyCheckIns
        where (checkIn.sleepDurationMinutes ?? 0) < 0 {
            appendInvalidValueIssue(
                "Daily check-in \(checkIn.id.rawValue.uuidString) has invalid sleep duration.",
                to: &issues
            )
        }
        for painFlag in snapshot.painFlags
        where (painFlag.clearedAt.map({
            $0 < painFlag.reportedAt
        }) ?? false) {
            appendInvalidValueIssue(
                "Pain flag \(painFlag.id.rawValue.uuidString) has invalid clearance timing.",
                to: &issues
            )
        }
        for request in snapshot.replanRequests
        where request.affectedStart != nil
            && request.affectedEnd != nil
            && request.affectedEnd! < request.affectedStart! {
            issues.append(
                SnapshotIntegrityIssue(
                    kind: .invalidInterval,
                    message:
                        "Replan request \(request.id.rawValue.uuidString) has an invalid affected interval."
                )
            )
        }
        for template in snapshot.mealTemplates
        where template.estimatedCalories < 0
            || template.estimatedProteinGrams < 0
            || template.prepTimeMinutes < 0
            || template.inventoryUsage.contains(where: {
                !$0.amount.isFinite || $0.amount <= 0
            }) {
            appendInvalidValueIssue(
                "Meal template \(template.id.rawValue.uuidString) contains invalid estimates.",
                to: &issues
            )
        }
        for template in snapshot.mealTemplates
        where template.inventoryUsage.contains(where: {
            !inventoryItemIDs.contains($0.inventoryItemID)
        }) {
            appendOrphanedReferenceIssue(
                "Meal template \(template.id.rawValue.uuidString) references missing inventory.",
                to: &issues
            )
        }
        for meal in snapshot.plannedMeals
        where meal.estimatedCalories < 0
            || meal.estimatedProteinGrams < 0
            || meal.estimatedDurationMinutes <= 0
            || (meal.preferredStartMinute.map({
                !(0..<24 * 60).contains($0)
            }) ?? false) {
            appendInvalidValueIssue(
                "Planned meal \(meal.id.rawValue.uuidString) contains invalid estimates.",
                to: &issues
            )
        }
        for meal in snapshot.plannedMeals
        where (meal.mealTemplateID.map({
            !mealTemplateIDs.contains($0)
        }) ?? false) {
            appendOrphanedReferenceIssue(
                "Planned meal \(meal.id.rawValue.uuidString) references a missing template.",
                to: &issues
            )
        }
        for item in snapshot.inventoryItems
        where (item.exactQuantity.map({
            !$0.isFinite || $0 < 0
        }) ?? false)
            || (item.mealsRemaining ?? 0) < 0
            || (item.lowQuantityThreshold.map({
                !$0.isFinite || $0 < 0
            }) ?? false) {
            appendInvalidValueIssue(
                "Inventory item \(item.id.rawValue.uuidString) contains an invalid quantity.",
                to: &issues
            )
        }
        for workout in snapshot.approvedWorkouts
        where workout.weeklySessionTarget < 0
            || (workout.preferredStartMinute.map({
                !(0..<24 * 60).contains($0)
            }) ?? false) {
            appendInvalidValueIssue(
                "Approved workout \(workout.id.rawValue.uuidString) contains an invalid target.",
                to: &issues
            )
        }
        for workout in snapshot.approvedWorkouts
        where !missionIDs.contains(workout.missionID)
            || (workout.programID.map({
                !workoutProgramIDs.contains($0)
            }) ?? false) {
            appendOrphanedReferenceIssue(
                "Approved workout \(workout.id.rawValue.uuidString) has a missing mission or program.",
                to: &issues
            )
        }
        for program in snapshot.workoutPrograms {
            for session in program.sessionTemplates
            where session.estimatedDurationMinutes <= 0 {
                appendInvalidValueIssue(
                    "Workout session \(session.id.rawValue.uuidString) has an invalid duration.",
                    to: &issues
                )
            }
            for exercise in program.sessionTemplates.flatMap(\.exercises)
            where exercise.sets.isEmpty
                || exercise.restDurationSeconds < 0
                || (exercise.targetLoad.map({
                    !$0.isFinite || $0 < 0
                }) ?? false)
                || exercise.sets.contains(where: {
                    $0.targetRepMinimum <= 0
                        || $0.targetRepMaximum < $0.targetRepMinimum
                }) {
                appendInvalidValueIssue(
                    "Exercise \(exercise.id.rawValue.uuidString) contains an invalid prescription.",
                    to: &issues
                )
            }
        }
        for log in snapshot.workoutLogs
        where (log.completedAt.map({ $0 < log.startedAt }) ?? false)
            || (log.currentSetIndex.map({ $0 < 0 }) ?? false)
            || log.exerciseLogs.flatMap(\.setLogs).contains(where: {
                $0.setNumber <= 0
                    || $0.reps < 0
                    || ($0.weight.map({
                        !$0.isFinite || $0 < 0
                    }) ?? false)
            }) {
            appendInvalidValueIssue(
                "Workout log \(log.id.rawValue.uuidString) contains invalid execution data.",
                to: &issues
            )
        }
        for need in snapshot.nutritionPlanningNeeds
        where need.substantialMealsRequired < 0
            || need.substantialMealsCovered < 0
            || need.estimatedCalories < 0
            || need.estimatedProteinGrams < 0
            || need.approximateCalorieDeficit < 0
            || need.approximateProteinDeficit < 0
            || need.suggestedMealDurationMinutes <= 0
            || need.suggestedCalories < 0
            || need.suggestedProteinGrams < 0
            || (need.suggestedStartMinute.map({
                !(0..<24 * 60).contains($0)
            }) ?? false) {
            appendInvalidValueIssue(
                "Nutrition need \(need.id.rawValue.uuidString) contains invalid estimates.",
                to: &issues
            )
        }
        for need in snapshot.nutritionPlanningNeeds
        where (need.suggestedMealTemplateID.map({
            !mealTemplateIDs.contains($0)
        }) ?? false) {
            appendOrphanedReferenceIssue(
                "Nutrition need \(need.id.rawValue.uuidString) references a missing template.",
                to: &issues
            )
        }
        if let recovery = snapshot.recoveryContext,
           (recovery.sleepDurationMinutes ?? 0) < 0
            || (
                recovery.sleepWindowStart != nil
                    && recovery.sleepWindowEnd != nil
                    && recovery.sleepWindowEnd! < recovery.sleepWindowStart!
            ) {
            appendInvalidValueIssue(
                "Recovery context contains invalid sleep timing.",
                to: &issues
            )
        }
        if let metadata = snapshot.schedulingPlanMetadata,
           metadata.horizonEnd <= metadata.horizonStart
            || metadata.gridMinutes <= 0 {
            appendInvalidValueIssue(
                "Scheduling metadata contains an invalid horizon or grid.",
                to: &issues
            )
        }
        for conflict in snapshot.schedulingConflicts
        where conflict.rangeStart != nil
            && conflict.rangeEnd != nil
            && conflict.rangeEnd! < conflict.rangeStart! {
            issues.append(
                SnapshotIntegrityIssue(
                    kind: .invalidInterval,
                    message:
                        "Scheduling conflict \(conflict.id.rawValue.uuidString) has an invalid range."
                )
            )
        }
        appendDuplicateIssue(
            ids: snapshot.goals.map(\.id),
            collection: "goals",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.projects.map(\.id),
            collection: "projects",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.missions.map(\.id),
            collection: "missions",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.fixedCommitments.map(\.id),
            collection: "fixed commitments",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.scheduleBlocks.map(\.id),
            collection: "schedule blocks",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.routines.map(\.id),
            collection: "routines",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.checklists.map(\.id),
            collection: "checklists",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.checklists.flatMap(\.items).map(\.id),
            collection: "checklist items",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.completions.map(\.id),
            collection: "completion history",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.painFlags.map(\.id),
            collection: "pain flags",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.missionStartRecords.map(\.id),
            collection: "mission start records",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.replanRequests.map(\.id),
            collection: "replan requests",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.commandHistory.map(\.id),
            collection: "command history",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.dailyCheckIns.map(\.id),
            collection: "daily check-ins",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.unresolvedDispositions.map(\.id),
            collection: "unresolved dispositions",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.missDiagnostics.map(\.id),
            collection: "miss diagnostics",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.mealTemplates.map(\.id),
            collection: "meal templates",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.plannedMeals.map(\.id),
            collection: "planned meals",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.inventoryItems.map(\.id),
            collection: "inventory items",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.approvedWorkouts.map(\.id),
            collection: "approved workouts",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.workoutPrograms.map(\.id),
            collection: "workout programs",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.workoutPrograms.flatMap(\.sessionTemplates).map(\.id),
            collection: "workout session templates",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.workoutPrograms
                .flatMap(\.sessionTemplates)
                .flatMap(\.exercises)
                .map(\.id),
            collection: "workout exercise prescriptions",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.workoutPrograms
                .flatMap(\.sessionTemplates)
                .flatMap(\.exercises)
                .flatMap(\.sets)
                .map(\.id),
            collection: "workout set prescriptions",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.workoutLogs.map(\.id),
            collection: "workout logs",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.workoutLogs
                .flatMap(\.exerciseLogs)
                .flatMap(\.setLogs)
                .map(\.id),
            collection: "workout set logs",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.nutritionPlanningNeeds.map(\.id),
            collection: "nutrition planning needs",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.manualScheduleAdjustments.map(\.id),
            collection: "manual schedule adjustments",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.schedulingDecisions.map(\.id),
            collection: "scheduling decisions",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.schedulingConflicts.map(\.id),
            collection: "scheduling conflicts",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.externalCalendarItems.map(\.id),
            collection: "external calendar items",
            to: &issues
        )
        appendDuplicateIssue(
            ids: snapshot.iCalSubscriptions.map(\.id),
            collection: "iCal subscriptions",
            to: &issues
        )
        return issues
    }

    private static func valid(_ dueWindow: DueWindow?) -> Bool {
        guard
            let earliest = dueWindow?.earliest,
            let latest = dueWindow?.latest
        else {
            return true
        }
        return earliest <= latest
    }

    private static func valid(_ range: MinuteRange) -> Bool {
        range.minimum >= 0 && range.maximum >= range.minimum
    }

    private static func appendInvalidValueIssue(
        _ message: String,
        to issues: inout [SnapshotIntegrityIssue]
    ) {
        issues.append(
            SnapshotIntegrityIssue(
                kind: .invalidValue,
                message: message
            )
        )
    }

    private static func appendOrphanedReferenceIssue(
        _ message: String,
        to issues: inout [SnapshotIntegrityIssue]
    ) {
        issues.append(
            SnapshotIntegrityIssue(
                kind: .orphanedReference,
                message: message
            )
        )
    }

    private static func appendDuplicateIssue(
        ids: [EntityID],
        collection: String,
        to issues: inout [SnapshotIntegrityIssue]
    ) {
        guard Set(ids).count != ids.count else { return }
        issues.append(
            SnapshotIntegrityIssue(
                kind: .duplicateIdentifier,
                message: "Duplicate identifiers were found in \(collection)."
            )
        )
    }
}

public enum MissionControlBackupService {
    public static func encode(
        snapshot: MissionControlSnapshot,
        exportedAt: Date
    ) throws -> Data {
        let issues = SnapshotIntegrityValidator.issues(in: snapshot)
        guard issues.isEmpty else {
            throw MissionControlBackupError.invalidSnapshot(issues)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(
            MissionControlBackup(
                exportedAt: exportedAt,
                snapshot: snapshot
            )
        )
    }

    public static func decode(
        _ data: Data,
        maximumBytes: Int = 25_000_000
    ) throws -> MissionControlBackup {
        guard data.count <= maximumBytes else {
            throw MissionControlBackupError.fileTooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let backup = try decoder.decode(MissionControlBackup.self, from: data)
        guard
            backup.formatVersion
                == MissionControlBackup.currentFormatVersion
        else {
            throw MissionControlBackupError.unsupportedFormat
        }
        let issues = SnapshotIntegrityValidator.issues(in: backup.snapshot)
        guard issues.isEmpty else {
            throw MissionControlBackupError.invalidSnapshot(issues)
        }
        return backup
    }
}

public enum MissionControlBackupError: Error, Equatable {
    case fileTooLarge
    case unsupportedFormat
    case invalidSnapshot([SnapshotIntegrityIssue])
}

public enum SnapshotDatasetProfiler {
    public static func profile(
        _ snapshot: MissionControlSnapshot
    ) -> SnapshotDatasetProfile {
        let workoutSetCount = snapshot.workoutLogs.reduce(into: 0) {
            partial, log in
            partial += log.exerciseLogs.reduce(into: 0) {
                $0 += $1.setLogs.count
            }
        }
        return SnapshotDatasetProfile(
            historyRecordCount:
                snapshot.completions.count
                + snapshot.missionStartRecords.count
                + snapshot.dailyCheckIns.count
                + snapshot.missDiagnostics.count,
            scheduleBlockCount: snapshot.scheduleBlocks.count,
            commandCount: snapshot.commandHistory.count,
            externalItemCount: snapshot.externalCalendarItems.count,
            workoutSetCount: workoutSetCount
        )
    }
}
