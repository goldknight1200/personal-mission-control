import Foundation
import MissionControlCore
import SwiftUI

enum VoiceCommandSubmission {
    case applied(CommandApplicationResult)
    case confirmationRequired(StructuredCommand)
    case rejected(String)
}

extension AppModel {
    func prepareActiveExecution() async {
        notificationAuthorizationState = await notificationService.authorizationState()
        if notificationAuthorizationState == .authorized
            || notificationAuthorizationState == .provisional {
            await reconcileNotifications()
        }
    }

    func requestNotificationAuthorization() async {
        notificationAuthorizationState = await notificationService.requestAuthorization()
        if notificationAuthorizationState == .authorized
            || notificationAuthorizationState == .provisional {
            await reconcileNotifications()
        }
    }

    func reconcileNotifications(at date: Date = Date()) async {
        guard notificationAuthorizationState == .authorized
            || notificationAuthorizationState == .provisional else {
            return
        }
        let existing = await notificationService.pendingMissionNotifications()
        let reconciliation = NotificationSchedulePlanner.reconciliation(
            snapshot: snapshot,
            existing: existing,
            now: date
        )
        do {
            try await notificationService.reconcile(reconciliation)
        } catch {
            persistenceNotice = "Notifications could not be updated. Schedule data was not changed."
        }
    }

    func latenessState(for block: ScheduleBlock, at date: Date) -> MissionLatenessState? {
        guard let mission = snapshot.mission(withID: block.missionID) else {
            return nil
        }
        let blockAwareStarts = snapshot.missionStartRecords.filter {
            $0.missionID == mission.id && $0.scheduleBlockID != nil
        }
        let effectiveStatus: MissionStatus =
            mission.status == .inProgress
                && !blockAwareStarts.isEmpty
                && !blockAwareStarts.contains(where: {
                    $0.scheduleBlockID == block.id
                })
            ? .planned
            : mission.status
        return MissionExecution.latenessState(
            block: block,
            missionStatus: effectiveStatus,
            hasResolution: snapshot.completions.contains(where: {
                $0.scheduleBlockID == block.id
            }) || snapshot.unresolvedDispositions.contains(where: {
                $0.scheduleBlockID == block.id
            }),
            at: date
        )
    }

    func mostRelevantUnresolvedBlock(at date: Date) -> ScheduleBlock? {
        snapshot.scheduleBlocks
            .filter { block in
                guard let state = latenessState(for: block, at: date) else {
                    return false
                }
                return state == .due || state == .late15 || state == .late30
            }
            .sorted(by: { $0.start < $1.start })
            .last
    }

    func presentExecutionAction(
        _ kind: MissionNotificationActionKind,
        missionID: EntityID,
        scheduleBlockID: EntityID,
        at date: Date = Date(),
        notificationStage: MissionNotificationStage = .start
    ) {
        switch kind {
        case .alreadyStarted:
            let suggestedMinutes: Int
            switch notificationStage {
            case .late30: suggestedMinutes = 30
            case .late15: suggestedMinutes = 15
            case .preStart, .start: suggestedMinutes = 1
            }
            executionPrompt = .alreadyStarted(
                missionID: missionID,
                scheduleBlockID: scheduleBlockID,
                referenceDate: date,
                suggestedMinutesAgo: suggestedMinutes
            )
        case .startNow:
            startMissionNow(
                missionID: missionID,
                scheduleBlockID: scheduleBlockID,
                at: date
            )
        case .replan:
            presentRecovery(
                missionID: missionID,
                scheduleBlockID: scheduleBlockID,
                at: date
            )
        case .skip:
            requestSkip(
                missionID: missionID,
                scheduleBlockID: scheduleBlockID,
                at: date
            )
        }
    }

    func confirmAlreadyStarted(
        missionID: EntityID,
        scheduleBlockID: EntityID,
        minutesAgo: Int,
        at date: Date
    ) {
        guard snapshot.mission(withID: missionID) != nil else { return }
        let actualStart = date.addingTimeInterval(
            -TimeInterval(max(minutesAgo, 0) * 60)
        )
        let request = ReplanRequest(
            reason: .actualStartCorrected,
            missionID: missionID,
            requestedAt: date,
            affectedStart: actualStart,
            affectedEnd: endOfDay(for: date)
        )
        let committed = commitReplanningMutation(
            requests: [request]
        ) { working in
            _ = MissionExecution.markStarted(
                snapshot: &working,
                missionID: missionID,
                scheduleBlockID: scheduleBlockID,
                actualStart: actualStart,
                reportedAt: date
            )
        }
        if committed {
            executionPrompt = nil
        }
    }

    func startMissionNow(
        missionID: EntityID,
        scheduleBlockID: EntityID,
        at date: Date = Date()
    ) {
        guard snapshot.mission(withID: missionID) != nil else { return }
        let request = ReplanRequest(
            reason: .startNow,
            missionID: missionID,
            requestedAt: date,
            affectedStart: date,
            affectedEnd: endOfDay(for: date)
        )
        let committed = commitReplanningMutation(
            requests: [request]
        ) { working in
            _ = MissionExecution.markStarted(
                snapshot: &working,
                missionID: missionID,
                scheduleBlockID: scheduleBlockID,
                actualStart: date,
                reportedAt: date
            )
        }
        if committed {
            executionPrompt = nil
        }
    }

    func presentRecovery(
        missionID: EntityID,
        scheduleBlockID: EntityID,
        at date: Date = Date()
    ) {
        guard
            let mission = snapshot.mission(withID: missionID),
            let block = snapshot.scheduleBlocks.first(where: {
                $0.id == scheduleBlockID
            })
        else {
            return
        }
        executionPrompt = .recovery(
            MissionRecoveryPlanner.proposal(
                mission: mission,
                block: block,
                snapshot: snapshot
            ),
            referenceDate: date
        )
    }

    func applyRecoveryAlternative(
        _ alternative: RecoveryAlternativeKind,
        proposal: MissionRecoveryProposal,
        at date: Date
    ) {
        switch alternative {
        case .startNow:
            startMissionNow(
                missionID: proposal.missionID,
                scheduleBlockID: proposal.scheduleBlockID,
                at: date
            )
        case .laterToday:
            deferMission(
                missionID: proposal.missionID,
                scheduleBlockID: proposal.scheduleBlockID,
                disposition: .laterToday,
                replanReason: .missionDeferredToday,
                at: date
            )
        case .tomorrow:
            deferMission(
                missionID: proposal.missionID,
                scheduleBlockID: proposal.scheduleBlockID,
                disposition: .moveToTomorrow,
                replanReason: .movedToTomorrow,
                at: date
            )
        case .weeklyBacklog:
            deferMission(
                missionID: proposal.missionID,
                scheduleBlockID: proposal.scheduleBlockID,
                disposition: .weeklyBacklog,
                replanReason: .returnedToBacklog,
                at: date
            )
        }
    }

    func requestSkip(
        missionID: EntityID,
        scheduleBlockID: EntityID,
        at date: Date = Date()
    ) {
        guard let mission = snapshot.mission(withID: missionID) else { return }
        let assessment = MissionExecution.skipAssessment(for: mission)
        if assessment.requiresConfirmation {
            executionPrompt = .confirmSkip(
                missionID: missionID,
                scheduleBlockID: scheduleBlockID,
                missionTitle: mission.title,
                consequence: assessment.consequence
                    ?? "This skip has consequences.",
                referenceDate: date
            )
        } else {
            performSkip(
                missionID: missionID,
                scheduleBlockID: scheduleBlockID,
                at: date,
                reason: "Skipped from the execution recovery flow.",
                confirmationProvided: false
            )
        }
    }

    func confirmSkip(
        missionID: EntityID,
        scheduleBlockID: EntityID,
        at date: Date
    ) {
        performSkip(
            missionID: missionID,
            scheduleBlockID: scheduleBlockID,
            at: date,
            reason: "Skipped after reviewing the consequence.",
            confirmationProvided: true
        )
    }

    func recordPartialMission(
        missionID: EntityID,
        scheduleBlockID: EntityID,
        at date: Date = Date()
    ) {
        guard let block = snapshot.scheduleBlocks.first(where: {
            $0.id == scheduleBlockID && $0.missionID == missionID
        }) else {
            return
        }
        let actualDuration = elapsedMinutes(
            missionID: missionID,
            scheduleBlockID: scheduleBlockID,
            fallbackStart: block.start,
            at: date
        )
        let request = ReplanRequest(
            reason: .taskFinishedEarly,
            missionID: missionID,
            requestedAt: date,
            affectedStart: date,
            affectedEnd: endOfDay(for: date)
        )
        let committed = commitReplanningMutation(requests: [request]) { working in
            _ = MissionExecution.resolve(
                snapshot: &working,
                missionID: missionID,
                scheduleBlockID: scheduleBlockID,
                status: .partial,
                at: date,
                actualDurationMinutes: actualDuration,
                reason: "Work ended with partial progress."
            )
            if working.scheduleBlocks.contains(where: {
                $0.id != scheduleBlockID
                    && $0.missionID == missionID
                    && $0.start > date
            }), let index = working.missions.firstIndex(where: {
                $0.id == missionID
            }) {
                working.missions[index].status = .planned
            }
        }
        if committed {
            executionPrompt = nil
        }
    }

    func recordMorningNoChanges(at date: Date = Date()) {
        commitMutation { working in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(
                identifier: working.profile.timeZoneIdentifier
            ) ?? .current
            if let index = working.dailyCheckIns.firstIndex(where: {
                $0.kind == .morning
                    && calendar.isDate($0.recordedAt, inSameDayAs: date)
            }) {
                working.dailyCheckIns[index].hasChanges = false
                working.dailyCheckIns[index].recordedAt = date
            } else {
                working.dailyCheckIns.append(
                    DailyCheckIn(
                        kind: .morning,
                        recordedAt: date,
                        hasChanges: false
                    )
                )
            }
        }
    }

    func eveningSummary(at date: Date = Date()) -> EveningExecutionSummary {
        DailyReflection.eveningSummary(snapshot: snapshot, at: date)
    }

    func resolveEveningItem(
        scheduleBlockID: EntityID,
        disposition: UnresolvedMissionDisposition,
        at date: Date = Date()
    ) {
        guard
            disposition != .laterToday,
            let block = snapshot.scheduleBlocks.first(where: {
                $0.id == scheduleBlockID
            }),
            let missionID = block.missionID,
            let mission = snapshot.mission(withID: missionID)
        else {
            return
        }
        let outcome: MissionOutcomeStatus = mission.status == .inProgress
            ? .partial
            : .skipped
        let reason: ReplanReason
        switch disposition {
        case .moveToTomorrow: reason = .movedToTomorrow
        case .weeklyBacklog: reason = .returnedToBacklog
        case .drop: reason = .missionSkipped
        case .laterToday: return
        }
        let request = ReplanRequest(
            reason: reason,
            missionID: missionID,
            requestedAt: date,
            affectedStart: date,
            affectedEnd: endOfDay(for: date)
        )
        let committed = commitReplanningMutation(
            requests: [request]
        ) { working in
            _ = MissionExecution.resolve(
                snapshot: &working,
                missionID: missionID,
                scheduleBlockID: scheduleBlockID,
                status: outcome,
                at: date,
                reason: disposition.displayName
            )
            working.unresolvedDispositions.append(
                UnresolvedDispositionRecord(
                    missionID: missionID,
                    scheduleBlockID: scheduleBlockID,
                    disposition: disposition,
                    decidedAt: date
                )
            )
            if disposition == .moveToTomorrow
                || disposition == .weeklyBacklog {
                if let index = working.missions.firstIndex(where: {
                    $0.id == missionID
                }) {
                    working.missions[index].status = .planned
                }
            } else if disposition == .drop,
                      let index = working.missions.firstIndex(where: {
                          $0.id == missionID
                      }) {
                working.missions[index].status = .skipped
            }
        }
        if committed {
            maybePresentRepeatedMissDiagnostic(
                missionID: missionID,
                at: date
            )
        }
    }

    func weeklyConsistency(containing date: Date = Date()) -> WeeklyConsistencySummary {
        WeeklyConsistencyAggregator.summarize(
            snapshot: snapshot,
            containing: date
        )
    }

    func classifyRepeatedMiss(
        _ diagnostic: RepeatedMissDiagnostic,
        cause: MissionMissCause,
        at date: Date = Date()
    ) {
        let committed = commitMutation { working in
            working.missDiagnostics.append(
                MissionMissDiagnosticRecord(
                    missionID: diagnostic.missionID,
                    category: diagnostic.category,
                    cause: cause,
                    recordedAt: date
                )
            )
            if let recordIndex = working.completions.lastIndex(where: {
                $0.missionID == diagnostic.missionID
                    && $0.status == .skipped
            }) {
                working.completions[recordIndex].missCause = cause
            }
        }
        if committed {
            executionPrompt = nil
        }
    }

    func dismissExecutionPrompt() {
        executionPrompt = nil
    }

    private func handleNotificationAction(_ action: MissionNotificationAction) {
        presentExecutionAction(
            action.kind,
            missionID: action.missionID,
            scheduleBlockID: action.scheduleBlockID,
            at: action.receivedAt,
            notificationStage: action.notificationStage
        )
    }

    private func performSkip(
        missionID: EntityID,
        scheduleBlockID: EntityID,
        at date: Date,
        reason: String,
        confirmationProvided: Bool
    ) {
        let request = ReplanRequest(
            reason: .missionSkipped,
            missionID: missionID,
            requestedAt: date,
            affectedStart: date,
            affectedEnd: endOfDay(for: date),
            confirmationProvided: confirmationProvided
        )
        let committed = commitReplanningMutation(
            requests: [request]
        ) { working in
            _ = MissionExecution.resolve(
                snapshot: &working,
                missionID: missionID,
                scheduleBlockID: scheduleBlockID,
                status: .skipped,
                at: date,
                reason: reason
            )
            if working.scheduleBlocks.contains(where: {
                $0.id != scheduleBlockID
                    && $0.missionID == missionID
                    && $0.start > date
            }), let index = working.missions.firstIndex(where: {
                $0.id == missionID
            }) {
                working.missions[index].status = .planned
            }
        }
        if committed {
            maybePresentRepeatedMissDiagnostic(missionID: missionID, at: date)
        }
    }

    private func deferMission(
        missionID: EntityID,
        scheduleBlockID: EntityID,
        disposition: UnresolvedMissionDisposition,
        replanReason: ReplanReason,
        at date: Date
    ) {
        let request = ReplanRequest(
            reason: replanReason,
            missionID: missionID,
            requestedAt: date,
            affectedStart: date,
            affectedEnd: endOfDay(for: date)
        )
        let committed = commitReplanningMutation(
            requests: [request]
        ) { working in
            _ = MissionExecution.resolve(
                snapshot: &working,
                missionID: missionID,
                scheduleBlockID: scheduleBlockID,
                status: .skipped,
                at: date,
                reason: disposition.displayName
            )
            working.unresolvedDispositions.append(
                UnresolvedDispositionRecord(
                    missionID: missionID,
                    scheduleBlockID: scheduleBlockID,
                    disposition: disposition,
                    decidedAt: date
                )
            )
            if let index = working.missions.firstIndex(where: {
                $0.id == missionID
            }) {
                working.missions[index].status = .planned
            }
        }
        if committed {
            maybePresentRepeatedMissDiagnostic(missionID: missionID, at: date)
        }
    }

    @discardableResult
    private func commitReplanningMutation(
        requests: [ReplanRequest],
        _ mutation: (inout MissionControlSnapshot) -> Void
    ) -> Bool {
        var working = snapshot
        mutation(&working)
        working.replanRequests.append(contentsOf: requests)
        working.schemaVersion = MissionControlSnapshot.currentSchemaVersion
        do {
            let replanned = try scheduleReplanner.replan(
                snapshot: working,
                requests: requests
            )
            if isRepositoryWritable {
                try repository.saveSnapshot(replanned)
            }
            snapshot = replanned
            if usesDurableStorage && isRepositoryWritable {
                persistenceNotice = nil
            }
            scheduleNotificationReconciliation()
            return true
        } catch {
            persistenceNotice = "The execution change could not be saved. "
                + "Existing schedule data was preserved."
            return false
        }
    }

    private func maybePresentRepeatedMissDiagnostic(
        missionID: EntityID,
        at date: Date
    ) {
        if let diagnostic = RepeatedMissAnalyzer.diagnostic(
            snapshot: snapshot,
            missionID: missionID,
            at: date
        ) {
            executionPrompt = .diagnostic(diagnostic)
        } else {
            executionPrompt = nil
        }
    }

    private func endOfDay(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(
            identifier: snapshot.profile.timeZoneIdentifier
        ) ?? .current
        return calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) ?? date
    }

    private func elapsedMinutes(
        missionID: EntityID,
        scheduleBlockID: EntityID?,
        fallbackStart: Date,
        at date: Date
    ) -> Int {
        let actualStart = snapshot.missionStartRecords.last(where: {
            if let scheduleBlockID {
                return $0.scheduleBlockID == scheduleBlockID
            }
            return $0.missionID == missionID
                && $0.scheduleBlockID == nil
        })?.actualStart ?? fallbackStart
        return max(Int(date.timeIntervalSince(actualStart) / 60), 1)
    }
}

enum MissionExecutionPrompt: Identifiable, Equatable {
    case alreadyStarted(
        missionID: EntityID,
        scheduleBlockID: EntityID,
        referenceDate: Date,
        suggestedMinutesAgo: Int
    )
    case recovery(MissionRecoveryProposal, referenceDate: Date)
    case confirmSkip(
        missionID: EntityID,
        scheduleBlockID: EntityID,
        missionTitle: String,
        consequence: String,
        referenceDate: Date
    )
    case diagnostic(RepeatedMissDiagnostic)

    var id: String {
        switch self {
        case let .alreadyStarted(_, blockID, _, _):
            "already-\(blockID.rawValue.uuidString)"
        case let .recovery(proposal, _):
            "recovery-\(proposal.id.rawValue.uuidString)"
        case let .confirmSkip(_, blockID, _, _, _):
            "skip-\(blockID.rawValue.uuidString)"
        case let .diagnostic(diagnostic):
            "diagnostic-\(diagnostic.id.rawValue.uuidString)"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: MissionControlSnapshot
    @Published private(set) var persistenceNotice: String?
    @Published private(set) var notificationAuthorizationState:
        NotificationAuthorizationState = .notDetermined
    @Published var executionPrompt: MissionExecutionPrompt?

    private let repository: any MissionControlRepository
    private let usesDurableStorage: Bool
    private let commandInterpreter: any CommandInterpreting
    private let commandApplicator: CommandMutationApplicator
    private let scheduleReplanner: any ScheduleReplanning
    private let notificationService: any NotificationService
    private var isRepositoryWritable = true

    init(
        repository: any MissionControlRepository,
        referenceDate: Date = Date(),
        startupNotice: String? = nil,
        usesDurableStorage: Bool = true,
        commandInterpreter: any CommandInterpreting = LocalCommandParser(),
        scheduleReplanner: any ScheduleReplanning = ReplanningEngine(),
        notificationService: (any NotificationService)? = nil
    ) {
        self.repository = repository
        self.usesDurableStorage = usesDurableStorage
        self.commandInterpreter = commandInterpreter
        self.scheduleReplanner = scheduleReplanner
        self.notificationService =
            notificationService ?? UnavailableNotificationService()
        commandApplicator = CommandMutationApplicator(replanner: scheduleReplanner)
        persistenceNotice = startupNotice

        do {
            if let stored = try repository.loadSnapshot() {
                snapshot = stored
            } else {
                let seed = MissionControlSeed.makeDemo(referenceDate: referenceDate)
                snapshot = seed
                try repository.saveSnapshot(seed)
            }
        } catch {
            snapshot = MissionControlSeed.makeDemo(referenceDate: referenceDate)
            isRepositoryWritable = false
            persistenceNotice = "Local persistence could not be opened. Changes will last for this session."
        }

        if snapshot.schedulingPlanMetadata?.contains(referenceDate) != true {
            let result = SchedulingEngine().makePlan(
                input: PlanningInput(
                    snapshot: snapshot,
                    currentTime: referenceDate
                )
            )
            snapshot.applySchedulingResult(result)
            if isRepositoryWritable {
                do {
                    try repository.saveSnapshot(snapshot)
                } catch {
                    persistenceNotice = "The seven-day plan is available for this session, but it could not be persisted."
                }
            }
        }

        self.notificationService.actionHandler = { [weak self] action in
            self?.handleNotificationAction(action)
        }
    }

    func completeMission(
        _ id: EntityID,
        scheduleBlockID: EntityID? = nil,
        at date: Date = Date(),
        plannedDurationMinutes: Int
    ) {
        guard snapshot.mission(withID: id)?.status != .completed else { return }
        let block = scheduleBlockID.flatMap { blockID in
            snapshot.scheduleBlocks.first(where: { $0.id == blockID })
        }
        let actualDuration = block.map {
            elapsedMinutes(
                missionID: id,
                scheduleBlockID: scheduleBlockID,
                fallbackStart: $0.start,
                at: date
            )
        } ?? max(plannedDurationMinutes, 1)
        let difference = actualDuration - max(plannedDurationMinutes, 1)
        if abs(difference) >= 5 {
            let request = ReplanRequest(
                reason: difference < 0
                    ? .taskFinishedEarly
                    : .taskFinishedLate,
                missionID: id,
                requestedAt: date,
                affectedStart: date,
                affectedEnd: endOfDay(for: date)
            )
            _ = commitReplanningMutation(requests: [request]) { working in
                _ = working.completeMission(
                    id: id,
                    at: date,
                    actualDurationMinutes: actualDuration,
                    scheduleBlockID: scheduleBlockID
                )
                if working.scheduleBlocks.contains(where: {
                    $0.id != scheduleBlockID
                        && $0.missionID == id
                        && $0.start > date
                }), let index = working.missions.firstIndex(where: {
                    $0.id == id
                }) {
                    working.missions[index].status = .planned
                }
            }
        } else {
            commitMutation(scheduleChanged: true) { working in
                _ = working.completeMission(
                    id: id,
                    at: date,
                    actualDurationMinutes: actualDuration,
                    scheduleBlockID: scheduleBlockID
                )
                if working.scheduleBlocks.contains(where: {
                    $0.id != scheduleBlockID
                        && $0.missionID == id
                        && $0.start > date
                }), let index = working.missions.firstIndex(where: {
                    $0.id == id
                }) {
                    working.missions[index].status = .planned
                }
            }
        }
    }

    func updateActualDuration(for missionID: EntityID, minutes: Int) {
        commitMutation { working in
            working.updateActualDuration(for: missionID, minutes: minutes)
        }
    }

    func toggleMissionStep(missionID: EntityID, stepID: EntityID) {
        commitMutation { working in
            working.toggleMissionStep(missionID: missionID, stepID: stepID)
        }
    }

    func toggleChecklistItem(checklistID: EntityID, itemID: EntityID) {
        commitMutation { working in
            working.toggleChecklistItem(checklistID: checklistID, itemID: itemID)
        }
    }

    func updateProfile(_ profile: UserProfile) {
        commitPlanningMutation { working in
            working.profile = profile
            for index in working.nutritionPlanningNeeds.indices {
                working.nutritionPlanningNeeds[index].substantialMealsRequired =
                    profile.nutritionTargets.substantialMeals
            }
            if working.approvedWorkouts.count == 1 {
                working.approvedWorkouts[0].weeklySessionTarget =
                    profile.gymWeeklyTarget.minimum
            }
            if let index = working.routines.firstIndex(where: {
                $0.category == .football
                    && $0.note.contains("Historical preference only")
            }) {
                working.routines[index].recurrence.weekdays =
                    profile.footballPattern.trainingWeekdays
                working.routines[index].recurrence.preferredStartMinute =
                    profile.footballPattern.historicalTrainingStartMinute
                working.routines[index].estimatedDurationMinutes =
                    profile.footballPattern
                        .historicalTrainingDurationMinutes
            }
        }
    }

    func updateProject(_ project: Project) {
        commitPlanningMutation { working in
            working.updateProject(project)
        }
    }

    func updateRoutine(_ routine: Routine) {
        commitPlanningMutation { working in
            working.updateRoutine(routine)
        }
    }

    func regeneratePlan(at date: Date = Date()) {
        commitPlanningMutation(at: date) { _ in }
    }

    func submitVoiceCommand(
        rawTranscript: String,
        confirmedTranscript: String,
        at date: Date = Date()
    ) -> VoiceCommandSubmission {
        let raw = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirmed = confirmedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !confirmed.isEmpty else {
            return .rejected("Enter or record a command before sending.")
        }

        let command = commandInterpreter.interpret(
            rawTranscript: raw.isEmpty ? confirmed : raw,
            confirmedTranscript: confirmed,
            context: CommandContext(snapshot: snapshot, referenceDate: date)
        )
        guard !command.proposedMutations.isEmpty else {
            return .rejected(
                command.warnings.first?.message
                    ?? "No supported local command was found."
            )
        }
        if command.confirmationRequirement.isRequired {
            return .confirmationRequired(command)
        }
        return applyPreparedCommand(command, finalConfirmationProvided: true)
    }

    func confirmVoiceCommand(_ command: StructuredCommand) -> VoiceCommandSubmission {
        applyPreparedCommand(command, finalConfirmationProvided: true)
    }

    private func applyPreparedCommand(
        _ command: StructuredCommand,
        finalConfirmationProvided: Bool
    ) -> VoiceCommandSubmission {
        do {
            var result = try commandApplicator.apply(
                command,
                to: snapshot,
                finalConfirmationProvided: finalConfirmationProvided
            )
            if DailyReflection.shouldShowMorning(
                snapshot: result.snapshot,
                at: command.createdAt
            ) {
                result.snapshot.dailyCheckIns.append(
                    DailyCheckIn(
                        kind: .morning,
                        recordedAt: command.createdAt,
                        hasChanges: true,
                        note: "A confirmed command updated the provisional plan."
                    )
                )
            }
            result.snapshot.schemaVersion = MissionControlSnapshot.currentSchemaVersion
            if isRepositoryWritable {
                try repository.saveSnapshot(result.snapshot)
            }
            snapshot = result.snapshot
            if usesDurableStorage && isRepositoryWritable {
                persistenceNotice = nil
            }
            scheduleNotificationReconciliation()
            return .applied(result)
        } catch let error as CommandApplicationError {
            switch error {
            case .noSupportedMutations:
                return .rejected("No supported mutation was produced.")
            case .confirmationRequired:
                return .rejected("Review and confirm the consequences first.")
            case let .unresolvedMission(name):
                return .rejected("No unique mission matched “\(name)”.")
            case .invalidDuration:
                return .rejected("The reported duration is invalid.")
            case .invalidDate:
                return .rejected("The proposed date or time is no longer valid.")
            }
        } catch {
            persistenceNotice = "The voice command was not saved. No schedule data changed."
            return .rejected("The command could not be applied safely.")
        }
    }

    @discardableResult
    private func commitMutation(
        scheduleChanged: Bool = false,
        _ mutation: (inout MissionControlSnapshot) -> Void
    ) -> Bool {
        var working = snapshot
        mutation(&working)
        working.schemaVersion = MissionControlSnapshot.currentSchemaVersion
        do {
            if isRepositoryWritable {
                try repository.saveSnapshot(working)
            }
            snapshot = working
            if usesDurableStorage && isRepositoryWritable {
                persistenceNotice = nil
            }
            if scheduleChanged {
                scheduleNotificationReconciliation()
            }
            return true
        } catch {
            persistenceNotice = "The change could not be saved. Existing schedule data was preserved."
            return false
        }
    }

    private func scheduleNotificationReconciliation() {
        Task { @MainActor [weak self] in
            await self?.reconcileNotifications()
        }
    }

    @discardableResult
    private func commitPlanningMutation(
        at date: Date = Date(),
        _ mutation: (inout MissionControlSnapshot) -> Void
    ) -> Bool {
        var working = snapshot
        mutation(&working)
        let result = SchedulingEngine().makePlan(
            input: PlanningInput(
                snapshot: working,
                currentTime: date
            )
        )
        working.applySchedulingResult(result)
        do {
            if isRepositoryWritable {
                try repository.saveSnapshot(working)
            }
            snapshot = working
            if usesDurableStorage && isRepositoryWritable {
                persistenceNotice = nil
            }
            scheduleNotificationReconciliation()
            return true
        } catch {
            persistenceNotice = "The planning change could not be saved. Existing schedule data was preserved."
            return false
        }
    }
}
