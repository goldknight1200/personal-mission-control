import Foundation
import MissionControlCore
import SwiftUI

enum VoiceCommandSubmission {
    case applied(CommandApplicationResult)
    case confirmationRequired(StructuredCommand)
    case rejected(String)
}

extension AppModel {
    func preparePlatformIntegrations(at date: Date = Date()) async {
        let calendarMode = snapshot.calendarIntegrationSettings.mode
        if calendarMode == .disabled {
            calendarAuthorizationState = .disabled
        } else {
            let level: CalendarAccessLevel =
                calendarMode == .createOnly ? .writeOnly : .full
            calendarAuthorizationState =
                await calendarProvider.authorizationState(for: level)
            if calendarAuthorizationState == .authorized {
                await reloadCalendars()
                await syncCalendar(at: date)
            }
        }

        if snapshot.healthIntegrationSettings.sleepReadEnabled {
            healthAuthorizationState =
                await healthProvider.availabilityState()
            if healthAuthorizationState == .requested
                || healthAuthorizationState == .authorized {
                await refreshHealthSleep(at: date)
            }
        } else {
            healthAuthorizationState = .disabled
        }

        await syncEnabledICalSubscriptions(at: date)
    }

    func setCalendarMode(
        _ mode: CalendarIntegrationMode,
        at date: Date = Date()
    ) async {
        if mode == .disabled {
            commitPlanningMutation(at: date) { working in
                let imported = working.externalCalendarItems.filter {
                    $0.sourceKind == .eventKit && !$0.isAppOwned
                }
                let fixedIDs = Set(
                    imported.compactMap(\.linkedFixedCommitmentID)
                )
                let itemIDs = Set(imported.map(\.id))
                working.externalCalendarItems.removeAll {
                    itemIDs.contains($0.id)
                }
                working.fixedCommitments.removeAll {
                    fixedIDs.contains($0.id) && $0.isExternallyManaged
                }
                working.calendarIntegrationSettings.mode = .disabled
                working.calendarIntegrationSettings.lastError = nil
            }
            calendarAuthorizationState = .disabled
            availableCalendars = []
            return
        }
        commitMutation { working in
            working.calendarIntegrationSettings.mode = mode
            working.calendarIntegrationSettings.lastError = nil
            if mode == .createOnly {
                working.calendarIntegrationSettings.destinationCalendarID =
                    nil
            }
        }
        let level: CalendarAccessLevel =
            mode == .createOnly ? .writeOnly : .full
        var state = await calendarProvider.authorizationState(for: level)
        if state == .notDetermined || state == .limited {
            state = await calendarProvider.requestAccess(level)
        }
        calendarAuthorizationState = state
        guard state == .authorized else {
            setCalendarError(permissionMessage(for: state))
            return
        }
        await reloadCalendars()
        if mode == .importAndSync,
           snapshot.calendarIntegrationSettings.importsCalendarIDs.isEmpty {
            let identifiers = availableCalendars.map(\.id)
            commitMutation { working in
                working.calendarIntegrationSettings.importsCalendarIDs =
                    identifiers
            }
        }
        await syncCalendar(at: date)
    }

    func updateCalendarExports(
        enabled: Bool,
        destinationCalendarID: String?
    ) {
        commitMutation { working in
            working.calendarIntegrationSettings.exportsLocalCommitments =
                enabled
            working.calendarIntegrationSettings.destinationCalendarID =
                destinationCalendarID
        }
        scheduleCalendarSyncWithoutPrompt()
    }

    func setCalendarImported(
        _ calendarID: String,
        isImported: Bool
    ) {
        commitMutation { working in
            var imported = Set(
                working.calendarIntegrationSettings.importsCalendarIDs
            )
            if isImported {
                imported.insert(calendarID)
            } else {
                imported.remove(calendarID)
            }
            working.calendarIntegrationSettings.importsCalendarIDs =
                imported.sorted()
        }
        scheduleCalendarSyncWithoutPrompt()
    }

    func reloadCalendars() async {
        guard calendarAuthorizationState == .authorized else {
            availableCalendars = []
            return
        }
        availableCalendars = await calendarProvider.calendars()
    }

    func syncCalendar(at date: Date = Date()) async {
        guard
            snapshot.calendarIntegrationSettings.mode != .disabled,
            calendarAuthorizationState == .authorized
        else {
            return
        }
        if isCalendarSyncing {
            isCalendarSyncPending = true
            return
        }
        isCalendarSyncing = true
        defer {
            isCalendarSyncing = false
            if isCalendarSyncPending {
                isCalendarSyncPending = false
                scheduleCalendarSyncWithoutPrompt()
            }
        }
        let original = snapshot
        do {
            let synchronized = try await CalendarSyncService(
                provider: calendarProvider
            ).synchronize(
                snapshot: original,
                interval: integrationInterval(around: date),
                at: date
            )
            applyCalendarIntegrationSnapshot(synchronized, at: date)
        } catch {
            setCalendarError(integrationMessage(for: error))
        }
    }

    func setHealthSleepEnabled(
        _ enabled: Bool,
        at date: Date = Date()
    ) async {
        commitMutation { working in
            working.healthIntegrationSettings.sleepReadEnabled = enabled
            working.healthIntegrationSettings.lastError = nil
        }
        guard enabled else {
            healthAuthorizationState = .disabled
            if let recovery = snapshot.recoveryContext,
               recovery.sleepSource == .healthKitSleep {
                commitPlanningMutation(at: date) { working in
                    let healthNote =
                        "Sleep duration from HealthKit; planning context only."
                    let preservedNote = recovery.note == healthNote
                        ? nil
                        : recovery.note
                    if recovery.fatigue == .none && preservedNote == nil {
                        working.recoveryContext = nil
                    } else {
                        working.recoveryContext = RecoveryContext(
                            recordedAt: date,
                            fatigue: recovery.fatigue,
                            note: preservedNote,
                            sleepSource: .manual
                        )
                    }
                }
            }
            return
        }
        var state = await healthProvider.availabilityState()
        if state == .notDetermined {
            state = await healthProvider.requestSleepReadAccess()
        }
        healthAuthorizationState = state
        if state == .requested || state == .authorized {
            await refreshHealthSleep(at: date)
        } else {
            setHealthError(permissionMessage(for: state))
        }
    }

    func refreshHealthSleep(at date: Date = Date()) async {
        guard
            !isHealthRefreshing,
            snapshot.healthIntegrationSettings.sleepReadEnabled
        else {
            return
        }
        isHealthRefreshing = true
        defer { isHealthRefreshing = false }
        do {
            let refreshed = try await HealthSleepSyncService(
                provider: healthProvider
            ).refresh(snapshot: snapshot, at: date)
            commitPlanningMutation(at: date) { working in
                working.recoveryContext = refreshed.recoveryContext
                working.healthIntegrationSettings =
                    refreshed.healthIntegrationSettings
            }
        } catch {
            setHealthError(integrationMessage(for: error))
        }
    }

    func saveICalSubscription(
        _ subscription: ICalSubscription,
        at date: Date = Date()
    ) async {
        commitMutation { working in
            if let index = working.iCalSubscriptions.firstIndex(where: {
                $0.id == subscription.id
            }) {
                working.iCalSubscriptions[index] = subscription
            } else {
                working.iCalSubscriptions.append(subscription)
            }
        }
        if subscription.isEnabled {
            await syncICalSubscription(subscription.id, at: date)
        }
    }

    func deleteICalSubscription(
        _ id: EntityID,
        at date: Date = Date()
    ) {
        let sourceIdentifier = id.rawValue.uuidString
        commitPlanningMutation(at: date) { working in
            working.iCalSubscriptions.removeAll { $0.id == id }
            _ = ExternalScheduleReconciler.removeSource(
                kind: .iCal,
                sourceIdentifier: sourceIdentifier,
                snapshot: &working
            )
        }
    }

    func setICalSubscriptionEnabled(
        _ id: EntityID,
        enabled: Bool,
        at date: Date = Date()
    ) async {
        guard let subscription = snapshot.iCalSubscriptions.first(where: {
            $0.id == id
        }) else {
            return
        }
        if enabled {
            commitMutation { working in
                if let index = working.iCalSubscriptions.firstIndex(
                    where: { $0.id == id }
                ) {
                    working.iCalSubscriptions[index].isEnabled = true
                    working.iCalSubscriptions[index].lastError = nil
                }
            }
            await syncICalSubscription(id, at: date)
        } else {
            let sourceIdentifier = subscription.id.rawValue.uuidString
            commitPlanningMutation(at: date) { working in
                if let index = working.iCalSubscriptions.firstIndex(
                    where: { $0.id == id }
                ) {
                    working.iCalSubscriptions[index].isEnabled = false
                    working.iCalSubscriptions[index].lastError = nil
                }
                _ = ExternalScheduleReconciler.removeSource(
                    kind: .iCal,
                    sourceIdentifier: sourceIdentifier,
                    snapshot: &working
                )
            }
        }
    }

    func syncEnabledICalSubscriptions(at date: Date = Date()) async {
        for subscription in snapshot.iCalSubscriptions
        where subscription.isEnabled {
            await syncICalSubscription(subscription.id, at: date)
        }
    }

    func syncICalSubscription(
        _ id: EntityID,
        at date: Date = Date()
    ) async {
        guard !syncingICalSubscriptionIDs.contains(id) else { return }
        syncingICalSubscriptionIDs.insert(id)
        defer { syncingICalSubscriptionIDs.remove(id) }
        do {
            let synchronized = try await ICalSyncService(
                provider: iCalProvider
            ).synchronize(
                subscriptionID: id,
                snapshot: snapshot,
                interval: integrationInterval(
                    around: date,
                    daysAhead: 240
                ),
                at: date
            )
            applyICalIntegrationSnapshot(
                synchronized,
                subscriptionID: id,
                at: date
            )
        } catch {
            let message = integrationMessage(for: error)
            commitMutation { working in
                if let index = working.iCalSubscriptions.firstIndex(
                    where: { $0.id == id }
                ) {
                    working.iCalSubscriptions[index].lastError = message
                }
            }
        }
    }

    func replanTodayFromSystemAction(at date: Date = Date()) -> Bool {
        commitReplanningMutation(
            requests: [
                ReplanRequest(
                    reason: .manualReplan,
                    requestedAt: date,
                    affectedStart: date,
                    affectedEnd: endOfDay(for: date)
                )
            ]
        ) { _ in }
    }

    func completeCurrentMissionFromSystemAction(
        at date: Date = Date()
    ) -> String? {
        guard
            let block = ScheduleTimeline.currentBlock(
                in: snapshot.scheduleBlocks,
                at: date
            ),
            let missionID = block.missionID,
            let mission = snapshot.mission(withID: missionID)
        else {
            return nil
        }
        if let workoutLog = workoutLog(for: block),
           workoutLog.status == .inProgress {
            finishWorkout(workoutLogID: workoutLog.id, at: date)
            return mission.title
        }
        completeMission(
            missionID,
            scheduleBlockID: block.id,
            at: date,
            plannedDurationMinutes: block.durationMinutes
        )
        return mission.title
    }

    private func applyCalendarIntegrationSnapshot(
        _ synchronized: MissionControlSnapshot,
        at date: Date
    ) {
        applyExternalSourceSnapshot(
            synchronized,
            sourceKind: .eventKit,
            sourceIdentifier: nil,
            at: date
        ) { working in
            working.calendarIntegrationSettings =
                synchronized.calendarIntegrationSettings
        }
    }

    private func applyICalIntegrationSnapshot(
        _ synchronized: MissionControlSnapshot,
        subscriptionID: EntityID,
        at date: Date
    ) {
        let sourceID = subscriptionID.rawValue.uuidString
        applyExternalSourceSnapshot(
            synchronized,
            sourceKind: .iCal,
            sourceIdentifier: sourceID,
            at: date
        ) { working in
            if
                let incoming = synchronized.iCalSubscriptions.first(
                    where: { $0.id == subscriptionID }
                ),
                let index = working.iCalSubscriptions.firstIndex(
                    where: { $0.id == subscriptionID }
                )
            {
                working.iCalSubscriptions[index] = incoming
            }
        }
    }

    private func applyExternalSourceSnapshot(
        _ synchronized: MissionControlSnapshot,
        sourceKind: ExternalScheduleSourceKind,
        sourceIdentifier: String?,
        at date: Date,
        additionalMutation:
            @escaping (inout MissionControlSnapshot) -> Void
    ) {
        let matches: (ExternalCalendarItem) -> Bool = { item in
            item.sourceKind == sourceKind
                && (
                    sourceIdentifier == nil
                        || item.sourceIdentifier == sourceIdentifier
                )
        }
        let oldItems = snapshot.externalCalendarItems.filter(matches)
        let newItems = synchronized.externalCalendarItems.filter(matches)
        let oldIDs = Set(oldItems.compactMap(\.linkedFixedCommitmentID))
        let newIDs = Set(newItems.compactMap(\.linkedFixedCommitmentID))
        let incomingCommitments = synchronized.fixedCommitments.filter {
            newIDs.contains($0.id) && $0.isExternallyManaged
        }
        let changedCommitments =
            snapshot.fixedCommitments.filter { oldIDs.contains($0.id) }
            != incomingCommitments

        let mutation: (inout MissionControlSnapshot) -> Void = { working in
            let currentIDs = Set(
                working.externalCalendarItems.filter(matches)
                    .compactMap(\.linkedFixedCommitmentID)
            )
            working.externalCalendarItems.removeAll(where: matches)
            working.externalCalendarItems.append(contentsOf: newItems)
            working.fixedCommitments.removeAll {
                currentIDs.contains($0.id) && $0.isExternallyManaged
            }
            working.fixedCommitments.append(
                contentsOf: incomingCommitments
            )
            additionalMutation(&working)
        }
        if changedCommitments {
            let dates = incomingCommitments.flatMap { [$0.start, $0.end] }
                + snapshot.fixedCommitments.filter {
                    oldIDs.contains($0.id)
                }.flatMap { [$0.start, $0.end] }
            _ = commitReplanningMutation(
                requests: [
                    ReplanRequest(
                        reason: .externalScheduleChanged,
                        requestedAt: date,
                        affectedStart: dates.min() ?? date,
                        affectedEnd: dates.max() ?? endOfDay(for: date)
                    )
                ],
                mutation
            )
        } else {
            _ = commitMutation(mutation)
        }
    }

    private func integrationInterval(
        around date: Date,
        daysAhead: Int = 120
    ) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(
            identifier: snapshot.profile.timeZoneIdentifier
        ) ?? .current
        let start = calendar.date(
            byAdding: .day,
            value: -7,
            to: calendar.startOfDay(for: date)
        ) ?? date.addingTimeInterval(-7 * 86_400)
        let end = calendar.date(
            byAdding: .day,
            value: daysAhead,
            to: calendar.startOfDay(for: date)
        ) ?? date.addingTimeInterval(TimeInterval(daysAhead * 86_400))
        return DateInterval(start: start, end: end)
    }

    private func setCalendarError(_ message: String) {
        commitMutation { working in
            working.calendarIntegrationSettings.lastError = message
        }
    }

    private func setHealthError(_ message: String) {
        commitMutation { working in
            working.healthIntegrationSettings.lastError = message
        }
    }

    private func permissionMessage(
        for state: PlatformAuthorizationState
    ) -> String {
        switch state {
        case .denied:
            "Access was denied. The local planner remains available."
        case .restricted:
            "Access is restricted on this device."
        case .unavailable:
            "This integration is unavailable on this device."
        case .limited:
            "The current permission does not cover this integration mode."
        default:
            "Permission is required before this integration can sync."
        }
    }

    private func integrationMessage(for error: Error) -> String {
        if let integrationError = error as? PlatformIntegrationError {
            switch integrationError {
            case let .permissionRequired(state):
                return permissionMessage(for: state)
            case .invalidSubscriptionURL:
                return "Use a valid HTTPS or webcal subscription URL."
            case .invalidICalendar:
                return "The subscription did not return a valid iCalendar feed."
            case .missingCalendar:
                return "The selected writable calendar is no longer available."
            case .ownedEventUnavailable:
                return "A previously exported event is no longer available. It was not recreated, preventing a duplicate."
            case .unavailable:
                return "This integration is unavailable. Existing local data was preserved."
            }
        }
        return "The integration could not refresh. Existing local data was preserved."
    }

    private func scheduleCalendarSyncWithoutPrompt() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let mode = self.snapshot.calendarIntegrationSettings.mode
            guard mode != .disabled else { return }
            let level: CalendarAccessLevel =
                mode == .createOnly ? .writeOnly : .full
            let state = await self.calendarProvider.authorizationState(
                for: level
            )
            self.calendarAuthorizationState = state
            guard state == .authorized else { return }
            await self.syncCalendar()
        }
    }

    private func scheduleCalendarExportIfLocalCommitmentsChanged(
        from previous: MissionControlSnapshot,
        to current: MissionControlSnapshot
    ) {
        guard current.calendarIntegrationSettings.exportsLocalCommitments
        else {
            return
        }
        let previousLocal = previous.fixedCommitments.filter {
            !$0.isExternallyManaged
        }.sorted { $0.id < $1.id }
        let currentLocal = current.fixedCommitments.filter {
            !$0.isExternallyManaged
        }.sorted { $0.id < $1.id }
        if previousLocal != currentLocal {
            scheduleCalendarSyncWithoutPrompt()
        }
    }
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
        if isNotificationSyncing {
            isNotificationSyncPending = true
            return
        }
        isNotificationSyncing = true
        var reconciliationDate = date
        repeat {
            isNotificationSyncPending = false
            let snapshotForReconciliation = snapshot
            let existing =
                await notificationService.pendingMissionNotifications()
            let reconciliation = NotificationSchedulePlanner.reconciliation(
                snapshot: snapshotForReconciliation,
                existing: existing,
                now: reconciliationDate
            )
            do {
                try await notificationService.reconcile(reconciliation)
            } catch {
                persistenceNotice =
                    "Notifications could not be updated. Schedule data was not changed."
            }
            reconciliationDate = Date()
        } while isNotificationSyncPending
        isNotificationSyncing = false
    }

    func handleSignificantTimeChange(
        at date: Date = Date(),
        systemTimeZone: TimeZone = .autoupdatingCurrent
    ) {
        commitPlanningMutation(at: date) { working in
            if working.privacySettings.timeZoneBehavior == .followSystem {
                working.profile.timeZoneIdentifier = systemTimeZone.identifier
                working.profile.planningPolicy.timeZoneIdentifier =
                    systemTimeZone.identifier
            }
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
        let shortened = shortenedWorkoutSuggestion(
            scheduleBlockID: scheduleBlockID,
            at: date
        )
        if assessment.requiresConfirmation || shortened != nil {
            executionPrompt = .confirmSkip(
                missionID: missionID,
                scheduleBlockID: scheduleBlockID,
                missionTitle: mission.title,
                consequence: assessment.consequence
                    ?? "This skip has consequences.",
                shortenedWorkout: shortened,
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
        let previous = snapshot
        var working = snapshot
        mutation(&working)
        let referenceDate = requests.first?.requestedAt ?? Date()
        let nutritionResult = NutritionPlanningCoordinator.reconcile(
            snapshot: &working,
            referenceDate: referenceDate
        )
        var effectiveRequests = requests
        if !nutritionResult.addedShoppingItemIDs.isEmpty {
            effectiveRequests.append(
                ReplanRequest(
                    reason: .shoppingListChanged,
                    requestedAt: referenceDate,
                    affectedStart: referenceDate,
                    affectedEnd:
                        working.schedulingPlanMetadata?.horizonEnd
                        ?? referenceDate.addingTimeInterval(
                            TimeInterval(
                                working.profile.planningPolicy
                                    .planningHorizonDays * 86_400
                            )
                        )
                )
            )
        }
        working.replanRequests.append(contentsOf: effectiveRequests)
        working.schemaVersion = MissionControlSnapshot.currentSchemaVersion
        do {
            let replanned = try scheduleReplanner.replan(
                snapshot: working,
                requests: effectiveRequests
            )
            if isRepositoryWritable {
                try repository.saveSnapshot(replanned)
            }
            snapshot = replanned
            scheduleCalendarExportIfLocalCommitmentsChanged(
                from: previous,
                to: replanned
            )
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
        shortenedWorkout: ShortenedWorkoutSuggestion?,
        referenceDate: Date
    )
    case diagnostic(RepeatedMissDiagnostic)

    var id: String {
        switch self {
        case let .alreadyStarted(_, blockID, _, _):
            "already-\(blockID.rawValue.uuidString)"
        case let .recovery(proposal, _):
            "recovery-\(proposal.id.rawValue.uuidString)"
        case let .confirmSkip(_, blockID, _, _, _, _):
            "skip-\(blockID.rawValue.uuidString)"
        case let .diagnostic(diagnostic):
            "diagnostic-\(diagnostic.id.rawValue.uuidString)"
        }
    }
}

extension AppModel {
    func workoutProgram(for block: ScheduleBlock) -> WorkoutProgram? {
        snapshot.workoutProgram(withID: block.workout?.programID)
    }

    func workoutSession(for block: ScheduleBlock) -> WorkoutSessionTemplate? {
        snapshot.workoutSession(
            programID: block.workout?.programID,
            sessionTemplateID: block.workout?.sessionTemplateID
        )
    }

    func workoutLog(for block: ScheduleBlock) -> WorkoutLog? {
        snapshot.workoutLogs
            .filter { $0.scheduleBlockID == block.id }
            .sorted(by: { $0.startedAt > $1.startedAt })
            .first
    }

    func previousWorkoutPerformance(
        exerciseID: EntityID,
        currentLogID: EntityID?
    ) -> WorkoutExerciseLog? {
        WorkoutExecution.previousExerciseLog(
            exerciseID: exerciseID,
            before: currentLogID,
            in: snapshot.workoutLogs
        )
    }

    @discardableResult
    func startWorkout(
        scheduleBlockID: EntityID,
        at date: Date = Date()
    ) -> EntityID? {
        var workoutLogID: EntityID?
        let committed = commitMutation(scheduleChanged: true) { working in
            guard
                let block = working.scheduleBlocks.first(where: {
                    $0.id == scheduleBlockID
                }),
                let missionID = block.missionID
            else {
                return
            }
            workoutLogID = WorkoutExecution.start(
                snapshot: &working,
                scheduleBlockID: scheduleBlockID,
                at: date
            )
            if workoutLogID != nil {
                _ = MissionExecution.markStarted(
                    snapshot: &working,
                    missionID: missionID,
                    scheduleBlockID: scheduleBlockID,
                    actualStart: date,
                    reportedAt: date
                )
            }
        }
        return committed ? workoutLogID : nil
    }

    func recordWorkoutSet(
        workoutLogID: EntityID,
        weight: Double?,
        reps: Int,
        at date: Date = Date()
    ) {
        commitMutation { working in
            _ = WorkoutExecution.recordSet(
                snapshot: &working,
                workoutLogID: workoutLogID,
                weight: weight,
                reps: reps,
                at: date
            )
        }
    }

    func endWorkoutRest(workoutLogID: EntityID) {
        commitMutation { working in
            WorkoutExecution.endRest(
                snapshot: &working,
                workoutLogID: workoutLogID
            )
        }
    }

    func finishWorkout(
        workoutLogID: EntityID,
        at date: Date = Date()
    ) {
        guard
            let log = snapshot.workoutLogs.first(where: {
                $0.id == workoutLogID
            }),
            let block = snapshot.scheduleBlocks.first(where: {
                $0.id == log.scheduleBlockID
            })
        else {
            return
        }
        let actualDuration = elapsedMinutes(
            missionID: log.missionID,
            scheduleBlockID: log.scheduleBlockID,
            fallbackStart: block.start,
            at: date
        )
        commitPlanningMutation(at: date) { working in
            _ = WorkoutExecution.finish(
                snapshot: &working,
                workoutLogID: workoutLogID,
                at: date
            )
            _ = working.completeMission(
                id: log.missionID,
                at: date,
                actualDurationMinutes: actualDuration,
                scheduleBlockID: log.scheduleBlockID
            )
            if working.scheduleBlocks.contains(where: {
                $0.id != log.scheduleBlockID
                    && $0.missionID == log.missionID
                    && $0.start > date
            }), let missionIndex = working.missions.firstIndex(where: {
                $0.id == log.missionID
            }) {
                working.missions[missionIndex].status = .planned
            }
        }
    }

    func shortenedWorkoutSuggestion(
        scheduleBlockID: EntityID,
        at date: Date = Date()
    ) -> ShortenedWorkoutSuggestion? {
        guard
            let block = snapshot.scheduleBlocks.first(where: {
                $0.id == scheduleBlockID
            }),
            let metadata = block.workout,
            !metadata.isShortened,
            let program = workoutProgram(for: block),
            let session = workoutSession(for: block)
        else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(
            identifier: snapshot.profile.timeZoneIdentifier
        ) ?? .current
        let interval = calendar.dateInterval(
            of: .weekOfYear,
            for: date
        )
        let completedThisWeek = snapshot.workoutLogs.filter { log in
            guard
                log.programID == program.id,
                log.status == .completed || log.status == .partial,
                let completedAt = log.completedAt,
                let interval
            else {
                return false
            }
            return interval.contains(completedAt)
        }.count
        let target = snapshot.approvedWorkouts.first(where: {
            $0.programID == program.id && $0.isEnabled
        })?.weeklySessionTarget
            ?? snapshot.profile.gymWeeklyTarget.minimum
        return WorkoutPlanning.shortenedSuggestion(
            program: program,
            session: session,
            availableExerciseIDs: metadata.exerciseIDs,
            completedSessionsThisWeek: completedThisWeek,
            weeklyTarget: target
        )
    }

    func applyShortenedWorkoutSuggestion(
        scheduleBlockID: EntityID,
        suggestion: ShortenedWorkoutSuggestion,
        at date: Date
    ) {
        guard
            let source = snapshot.scheduleBlocks.first(where: {
                $0.id == scheduleBlockID
            }),
            let missionID = source.missionID
        else {
            return
        }
        let request = ReplanRequest(
            reason: .startNow,
            missionID: missionID,
            requestedAt: date,
            affectedStart: date,
            affectedEnd: endOfDay(for: date)
        )
        let committed = commitReplanningMutation(requests: [request]) {
            working in
            guard let index = working.scheduleBlocks.firstIndex(where: {
                $0.id == scheduleBlockID
            }) else {
                return
            }
            working.scheduleBlocks[index].workout?.exerciseIDs =
                suggestion.exerciseIDs
            working.scheduleBlocks[index].workout?.isShortened = true
            working.scheduleBlocks[index].title =
                "Shortened \(working.scheduleBlocks[index].title)"
            working.scheduleBlocks[index].end =
                working.scheduleBlocks[index].start.addingTimeInterval(
                    TimeInterval(suggestion.estimatedDurationMinutes * 60)
                )
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

    func saveWorkoutProgram(_ program: WorkoutProgram) {
        commitPlanningMutation { working in
            if program.isActive {
                for index in working.workoutPrograms.indices
                where working.workoutPrograms[index].id != program.id {
                    working.workoutPrograms[index].isActive = false
                }
            }
            working.upsertWorkoutProgram(program)
            if let workoutIndex = working.approvedWorkouts.firstIndex(
                where: { $0.programID == program.id }
            ) {
                working.approvedWorkouts[workoutIndex].isEnabled =
                    program.isApproved && program.isActive
            } else if program.isApproved,
                      program.isActive,
                      let mission = working.missions.first(where: {
                          $0.category == .gym
                      }) {
                if let existing = working.approvedWorkouts.firstIndex(where: {
                    $0.missionID == mission.id
                }) {
                    working.approvedWorkouts[existing].programID = program.id
                    working.approvedWorkouts[existing].isEnabled = true
                } else {
                    working.approvedWorkouts.append(
                        ApprovedWorkout(
                            missionID: mission.id,
                            programID: program.id,
                            weeklySessionTarget:
                                working.profile.gymWeeklyTarget.minimum
                        )
                    )
                }
            }
            for index in working.approvedWorkouts.indices {
                guard let programID =
                    working.approvedWorkouts[index].programID else {
                    continue
                }
                let linked = working.workoutPrograms.first(where: {
                    $0.id == programID
                })
                working.approvedWorkouts[index].isEnabled =
                    linked?.isApproved == true && linked?.isActive == true
            }
        }
    }

    func clearPainFlag(
        id: EntityID,
        note: String,
        at date: Date = Date()
    ) {
        commitPlanningMutation(at: date) { working in
            working.clearPainFlag(id: id, at: date, note: note)
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
    @Published private(set) var calendarAuthorizationState:
        PlatformAuthorizationState = .disabled
    @Published private(set) var healthAuthorizationState:
        PlatformAuthorizationState = .disabled
    @Published private(set) var availableCalendars: [CalendarDescriptor] = []
    @Published private(set) var isCalendarSyncing = false
    @Published private(set) var isHealthRefreshing = false
    @Published private(set) var lastAIRequestInspection: String?

    private let repository: any MissionControlRepository
    private let usesDurableStorage: Bool
    private let commandInterpreter: any CommandInterpreting
    private let commandApplicator: CommandMutationApplicator
    private let scheduleReplanner: any ScheduleReplanning
    private let notificationService: any NotificationService
    private let calendarProvider: any CalendarProviding
    private let healthProvider: any HealthContextProviding
    private let iCalProvider: any ICalSubscriptionProviding
    private let shiftImageRecognizer: any WorkShiftImageTextRecognizing
    private let secretStore: any SecretStoring
    private let aiProviderFactory:
        ((AIIntegrationSettings) -> (any AICommandProvider)?)?
    private var syncingICalSubscriptionIDs: Set<EntityID> = []
    private var isCalendarSyncPending = false
    private var isNotificationSyncing = false
    private var isNotificationSyncPending = false
    private var isRepositoryWritable = true

    private static let aiCredentialKey =
        "ai-provider-bearer-token"

    init(
        repository: any MissionControlRepository,
        referenceDate: Date = Date(),
        startupNotice: String? = nil,
        usesDurableStorage: Bool = true,
        commandInterpreter: any CommandInterpreting = LocalCommandParser(),
        scheduleReplanner: any ScheduleReplanning = ReplanningEngine(),
        notificationService: (any NotificationService)? = nil,
        calendarProvider: any CalendarProviding =
            UnavailableCalendarProvider(),
        healthProvider: any HealthContextProviding =
            UnavailableHealthContextProvider(),
        iCalProvider: any ICalSubscriptionProviding =
            UnavailableICalSubscriptionProvider(),
        shiftImageRecognizer: any WorkShiftImageTextRecognizing =
            UnavailableWorkShiftImageTextRecognizer(),
        secretStore: any SecretStoring = UnavailableSecretStore(),
        aiProviderFactory:
            ((AIIntegrationSettings) -> (any AICommandProvider)?)? = nil
    ) {
        self.repository = repository
        self.usesDurableStorage = usesDurableStorage
        self.commandInterpreter = commandInterpreter
        self.scheduleReplanner = scheduleReplanner
        self.notificationService =
            notificationService ?? UnavailableNotificationService()
        self.calendarProvider = calendarProvider
        self.healthProvider = healthProvider
        self.iCalProvider = iCalProvider
        self.shiftImageRecognizer = shiftImageRecognizer
        self.secretStore = secretStore
        self.aiProviderFactory = aiProviderFactory
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

        let nutritionReconciliation =
            NutritionPlanningCoordinator.reconcile(
                snapshot: &snapshot,
                referenceDate: referenceDate
            )
        if snapshot.schedulingPlanMetadata?.contains(referenceDate) != true
            || !nutritionReconciliation.changedNutritionNeedIDs.isEmpty
            || !nutritionReconciliation.addedShoppingItemIDs.isEmpty {
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
        self.calendarProvider.changeHandler = { [weak self] in
            Task { @MainActor in
                guard
                    let self,
                    self.snapshot.calendarIntegrationSettings.mode
                        == .importAndSync
                else {
                    return
                }
                await self.syncCalendar()
            }
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
            commitPlanningMutation(at: date) { working in
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

    func toggleMissionStep(
        missionID: EntityID,
        stepID: EntityID,
        at date: Date = Date()
    ) {
        commitMutation { working in
            working.toggleMissionStep(
                missionID: missionID,
                stepID: stepID,
                at: date
            )
        }
    }

    func toggleChecklistItem(
        checklistID: EntityID,
        itemID: EntityID,
        at date: Date = Date()
    ) {
        let kind = snapshot.checklists.first(where: {
            $0.id == checklistID
        })?.kind
        if kind == .shopping {
            commitPlanningMutation { working in
                working.toggleChecklistItem(
                    checklistID: checklistID,
                    itemID: itemID,
                    at: date
                )
            }
        } else {
            commitMutation { working in
                working.toggleChecklistItem(
                    checklistID: checklistID,
                    itemID: itemID,
                    at: date
                )
            }
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

    func saveGoal(_ goal: Goal) {
        commitMutation { working in
            working.upsertGoal(goal)
        }
    }

    func deleteGoal(_ id: EntityID) {
        commitPlanningMutation { working in
            working.removeGoal(id: id)
        }
    }

    func saveProject(_ project: Project) {
        commitPlanningMutation { working in
            working.upsertProject(project)
            for index in working.missions.indices
            where working.missions[index].projectID == project.id {
                working.missions[index].userPriorityOverride =
                    project.priorityOverride
            }
        }
    }

    func deleteProject(_ id: EntityID) {
        commitPlanningMutation { working in
            working.removeProject(id: id)
        }
    }

    func saveMission(_ mission: Mission) {
        commitPlanningMutation { working in
            working.upsertMission(mission)
        }
    }

    func deleteMission(_ id: EntityID) {
        commitPlanningMutation { working in
            working.removeMission(id: id)
        }
    }

    func saveRoutine(_ routine: Routine) {
        commitPlanningMutation { working in
            working.upsertRoutine(routine)
            for index in working.routines.indices
            where working.routines[index].id != routine.id {
                let otherID = working.routines[index].id
                if routine.compatibleRoutineIDs.contains(otherID) {
                    if !working.routines[index].compatibleRoutineIDs
                        .contains(routine.id) {
                        working.routines[index].compatibleRoutineIDs
                            .append(routine.id)
                    }
                } else {
                    working.routines[index].compatibleRoutineIDs.removeAll(
                        where: { $0 == routine.id }
                    )
                }
            }
        }
    }

    func deleteRoutine(_ id: EntityID) {
        commitPlanningMutation { working in
            working.removeRoutine(id: id)
        }
    }

    func addChecklistItem(
        kind: ChecklistKind,
        title: String,
        quantity: String? = nil,
        dueDate: Date? = nil,
        inventoryItemID: EntityID? = nil
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuantity = quantity?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let mutation: (inout MissionControlSnapshot) -> Void = { working in
            _ = working.addChecklistItem(
                kind: kind,
                item: ChecklistItem(
                    title: trimmed,
                    dueDate: dueDate,
                    quantity: trimmedQuantity?.isEmpty == false
                        ? trimmedQuantity
                        : nil,
                    inventoryItemID: inventoryItemID
                )
            )
        }
        if kind == .shopping {
            commitPlanningMutation(mutation)
        } else {
            commitMutation(mutation)
        }
    }

    func saveChecklistItem(
        checklistID: EntityID,
        item: ChecklistItem
    ) {
        let kind = snapshot.checklists.first(where: {
            $0.id == checklistID
        })?.kind
        let mutation: (inout MissionControlSnapshot) -> Void = { working in
            working.upsertChecklistItem(
                checklistID: checklistID,
                item: item
            )
        }
        if kind == .shopping {
            commitPlanningMutation(mutation)
        } else {
            commitMutation(mutation)
        }
    }

    func deleteChecklistItem(
        checklistID: EntityID,
        itemID: EntityID
    ) {
        let kind = snapshot.checklists.first(where: {
            $0.id == checklistID
        })?.kind
        let mutation: (inout MissionControlSnapshot) -> Void = { working in
            working.removeChecklistItem(
                checklistID: checklistID,
                itemID: itemID
            )
        }
        if kind == .shopping {
            commitPlanningMutation(mutation)
        } else {
            commitMutation(mutation)
        }
    }

    func saveMealTemplate(_ template: MealTemplate) {
        commitPlanningMutation { working in
            working.upsertMealTemplate(template)
            for index in working.plannedMeals.indices
            where working.plannedMeals[index].mealTemplateID == template.id {
                working.plannedMeals[index].title = template.title
                working.plannedMeals[index].estimatedCalories =
                    template.estimatedCalories
                working.plannedMeals[index].estimatedProteinGrams =
                    template.estimatedProteinGrams
                working.plannedMeals[index].isSubstantial =
                    template.isSubstantial
            }
        }
    }

    func deleteMealTemplate(_ id: EntityID) {
        commitPlanningMutation { working in
            working.removeMealTemplate(id: id)
        }
    }

    func savePlannedMeal(_ meal: PlannedMeal) {
        commitPlanningMutation { working in
            working.upsertPlannedMeal(meal)
        }
    }

    func deletePlannedMeal(_ id: EntityID) {
        commitPlanningMutation { working in
            working.removePlannedMeal(id: id)
        }
    }

    func saveInventoryItem(_ item: InventoryItem) {
        commitPlanningMutation { working in
            working.upsertInventoryItem(item)
        }
    }

    func deleteInventoryItem(_ id: EntityID) {
        commitPlanningMutation { working in
            working.removeInventoryItem(id: id)
        }
    }

    func saveNutritionSuggestion(_ need: NutritionPlanningNeed) {
        commitPlanningMutation { working in
            guard let index = working.nutritionPlanningNeeds.firstIndex(
                where: { $0.id == need.id }
            ) else {
                return
            }
            working.nutritionPlanningNeeds[index] = need
        }
    }

    func declineNutritionSuggestion(_ id: EntityID) {
        commitPlanningMutation { working in
            guard let index = working.nutritionPlanningNeeds.firstIndex(
                where: { $0.id == id }
            ) else {
                return
            }
            working.nutritionPlanningNeeds[index].suggestionDisposition =
                .declined
            let missionID = StableIdentifierGenerator().identifier(
                namespace: "nutrition.suggestion.\(id.rawValue.uuidString)"
            )
            working.manualScheduleAdjustments.removeAll {
                $0.block.missionID == missionID
            }
        }
    }

    func restoreNutritionSuggestion(_ id: EntityID) {
        commitPlanningMutation { working in
            guard let index = working.nutritionPlanningNeeds.firstIndex(
                where: { $0.id == id }
            ) else {
                return
            }
            working.nutritionPlanningNeeds[index].suggestionDisposition =
                .scheduled
            working.nutritionPlanningNeeds[index].suggestionIsUserEdited =
                false
        }
    }

    func weeklyProgress(
        for projectID: EntityID,
        containing date: Date = Date()
    ) -> ProjectWeeklyProgress? {
        ProjectPlanningAnalytics.weeklyProgress(
            projectID: projectID,
            snapshot: snapshot,
            containing: date
        )
    }

    func activityReassessment(
        for projectID: EntityID,
        at date: Date = Date()
    ) -> ProjectActivityReassessment? {
        ProjectPlanningAnalytics.reassessment(
            projectID: projectID,
            snapshot: snapshot,
            at: date
        )
    }

    func reviewProjectActivity(
        projectID: EntityID,
        status: ProjectStatus,
        at date: Date = Date()
    ) {
        guard var project = snapshot.projects.first(where: {
            $0.id == projectID
        }) else {
            return
        }
        project.status = status
        project.lastActiveReviewAt = date
        saveProject(project)
    }

    func applyWorkShifts(
        _ entries: [WorkShiftBatchEntry],
        at date: Date = Date()
    ) {
        guard !entries.isEmpty else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(
            identifier: snapshot.profile.timeZoneIdentifier
        ) ?? .current
        let requests = entries.map { entry in
            let affectedStart = calendar.startOfDay(
                for: entry.payload.start
            )
            let affectedEnd = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: entry.payload.end)
            ) ?? entry.payload.end
            return ReplanRequest(
                reason: entry.isChange
                    ? .fixedCommitmentChanged
                    : .fixedCommitmentAdded,
                requestedAt: date,
                affectedStart: affectedStart,
                affectedEnd: affectedEnd
            )
        }
        _ = commitReplanningMutation(requests: requests) { working in
            for entry in entries {
                let context = [
                    entry.payload.title,
                    entry.payload.location ?? ""
                ].joined(separator: " ").lowercased()
                let tags = context.contains("supermarket")
                    || context.contains("aldi")
                    || context.contains("lidl")
                    ? ["supermarket"]
                    : []
                if let existingID = entry.existingCommitmentID,
                   let index = working.fixedCommitments.firstIndex(where: {
                       $0.id == existingID
                   }) {
                    working.fixedCommitments[index].title =
                        entry.payload.title
                    working.fixedCommitments[index].start =
                        entry.payload.start
                    working.fixedCommitments[index].end = entry.payload.end
                    working.fixedCommitments[index].location =
                        entry.payload.location
                    working.fixedCommitments[index].contextTags = tags
                } else {
                    working.fixedCommitments.append(
                        FixedCommitment(
                            title: entry.payload.title,
                            category: .work,
                            start: entry.payload.start,
                            end: entry.payload.end,
                            location: entry.payload.location,
                            contextTags: tags
                        )
                    )
                }
            }
        }
    }

    func deleteFixedCommitment(
        _ id: EntityID,
        at date: Date = Date()
    ) {
        guard let commitment = snapshot.fixedCommitments.first(where: {
            $0.id == id
        }), !commitment.isExternallyManaged else {
            return
        }
        let request = ReplanRequest(
            reason: .fixedCommitmentChanged,
            requestedAt: date,
            affectedStart: commitment.start,
            affectedEnd: commitment.end
        )
        _ = commitReplanningMutation(requests: [request]) { working in
            working.fixedCommitments.removeAll(where: { $0.id == id })
        }
    }

    func moveScheduleBlock(
        _ blockID: EntityID,
        start: Date,
        end: Date,
        at date: Date = Date()
    ) {
        let resolvedBlock = snapshot.scheduleBlocks.first(where: {
            $0.id == blockID
        }) ?? snapshot.fixedCommitments.first(where: {
            $0.id == blockID
        }).map { commitment in
            ScheduleBlock(
                id: commitment.id,
                fixedCommitmentID: commitment.id,
                title: commitment.title,
                category: commitment.category,
                kind: .fixedCommitment,
                rigidity: .fixed,
                start: commitment.start,
                end: commitment.end,
                isImmutable: commitment.isExternallyManaged
            )
        }
        guard
            end > start,
            let block = resolvedBlock,
            !block.isImmutable
        else {
            return
        }
        if let commitmentID = block.fixedCommitmentID,
           let commitment = snapshot.fixedCommitments.first(where: {
               $0.id == commitmentID
           }),
           !commitment.isExternallyManaged {
            let request = ReplanRequest(
                reason: .fixedCommitmentChanged,
                requestedAt: date,
                affectedStart: min(block.start, start),
                affectedEnd: max(block.end, end)
            )
            _ = commitReplanningMutation(requests: [request]) { working in
                guard let index = working.fixedCommitments.firstIndex(
                    where: { $0.id == commitmentID }
                ) else {
                    return
                }
                working.fixedCommitments[index].start = start
                working.fixedCommitments[index].end = end
            }
            return
        }
        guard block.missionID != nil else { return }
        var adjusted = block
        adjusted.start = start
        adjusted.end = end
        commitPlanningMutation(at: date) { working in
            working.manualScheduleAdjustments.removeAll(where: {
                $0.block.id == blockID
            })
            working.manualScheduleAdjustments.append(
                ManualScheduleAdjustment(
                    block: adjusted,
                    createdAt: date
                )
            )
        }
    }

    func returnScheduleBlockToAutomatic(
        _ blockID: EntityID,
        at date: Date = Date()
    ) {
        commitPlanningMutation(at: date) { working in
            working.manualScheduleAdjustments.removeAll(where: {
                $0.block.id == blockID
            })
            working.scheduleBlocks.removeAll(where: { $0.id == blockID })
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

    func submitReviewedCommand(
        rawTranscript: String,
        confirmedTranscript: String,
        at date: Date = Date()
    ) async -> VoiceCommandSubmission {
        let settings = snapshot.aiIntegrationSettings
        guard settings.isEnabled else {
            return submitVoiceCommand(
                rawTranscript: rawTranscript,
                confirmedTranscript: confirmedTranscript,
                at: date
            )
        }
        let raw = rawTranscript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let confirmed = confirmedTranscript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !confirmed.isEmpty else {
            return .rejected("Enter or record a command before sending.")
        }
        guard settings.isConfigured,
              let factory = aiProviderFactory,
              let provider = factory(settings) else {
            return submitVoiceCommand(
                rawTranscript: raw,
                confirmedTranscript: confirmed,
                at: date
            )
        }
        let context = CommandContext(
            snapshot: snapshot,
            referenceDate: date
        )
        let minimizedRequest = AICommandContextMinimizer.request(
            confirmedText: confirmed,
            context: context,
            settings: settings
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(minimizedRequest) {
            lastAIRequestInspection = String(
                decoding: data,
                as: UTF8.self
            )
        } else {
            lastAIRequestInspection = nil
        }
        let interpreter = ProviderBackedAICommandInterpreter(
            provider: provider,
            settings: settings
        )
        do {
            let command = try await interpreter.interpret(
                rawTranscript: raw.isEmpty ? confirmed : raw,
                confirmedTranscript: confirmed,
                context: context
            )
            guard !command.proposedMutations.isEmpty else {
                return .rejected("No supported command was found.")
            }
            if command.confirmationRequirement.isRequired {
                return .confirmationRequired(command)
            }
            return applyPreparedCommand(
                command,
                finalConfirmationProvided: true
            )
        } catch {
            return .rejected(
                "The provider could not interpret this command. Supported commands still work with local parsing; review the wording or turn AI off."
            )
        }
    }

    func aiRequestInspection(
        confirmedTranscript: String,
        at date: Date = Date()
    ) -> String? {
        let settings = snapshot.aiIntegrationSettings
        let confirmed = confirmedTranscript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard settings.isConfigured, !confirmed.isEmpty else { return nil }
        let request = AICommandContextMinimizer.request(
            confirmedText: confirmed,
            context: CommandContext(
                snapshot: snapshot,
                referenceDate: date
            ),
            settings: settings
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(request) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    func confirmVoiceCommand(_ command: StructuredCommand) -> VoiceCommandSubmission {
        if let token = command.contextRevisionToken,
           token != CommandContext(
            snapshot: snapshot,
            referenceDate: Date()
           ).revisionToken {
            return .rejected(
                "The plan changed after this proposal was prepared. Send the command again to review current consequences."
            )
        }
        return applyPreparedCommand(
            command,
            finalConfirmationProvided: true
        )
    }

    private func applyPreparedCommand(
        _ command: StructuredCommand,
        finalConfirmationProvided: Bool
    ) -> VoiceCommandSubmission {
        let previous = snapshot
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
            if !result.snapshot.privacySettings.retainsCommandTranscripts {
                for index in result.snapshot.commandHistory.indices {
                    result.snapshot.commandHistory[index]
                        .removeTranscriptContent()
                }
            }
            result.snapshot.schemaVersion = MissionControlSnapshot.currentSchemaVersion
            if isRepositoryWritable {
                try repository.saveSnapshot(result.snapshot)
            }
            snapshot = result.snapshot
            scheduleCalendarExportIfLocalCommitmentsChanged(
                from: previous,
                to: result.snapshot
            )
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
        let previous = snapshot
        var working = snapshot
        mutation(&working)
        working.schemaVersion = MissionControlSnapshot.currentSchemaVersion
        do {
            if isRepositoryWritable {
                try repository.saveSnapshot(working)
            }
            snapshot = working
            scheduleCalendarExportIfLocalCommitmentsChanged(
                from: previous,
                to: working
            )
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
        let previous = snapshot
        var working = snapshot
        mutation(&working)
        _ = NutritionPlanningCoordinator.reconcile(
            snapshot: &working,
            referenceDate: date
        )
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
            scheduleCalendarExportIfLocalCommitmentsChanged(
                from: previous,
                to: working
            )
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

extension AppModel {
    var hasAIProviderCredential: Bool {
        secretStore.containsSecret(for: Self.aiCredentialKey)
    }

    var datasetProfile: SnapshotDatasetProfile {
        SnapshotDatasetProfiler.profile(snapshot)
    }

    func updateAISettings(_ settings: AIIntegrationSettings) {
        commitMutation { working in
            working.aiIntegrationSettings = settings
        }
        if !settings.isEnabled {
            lastAIRequestInspection = nil
        }
    }

    @discardableResult
    func saveAIProviderCredential(_ credential: String) -> Bool {
        do {
            try secretStore.setSecret(
                credential,
                for: Self.aiCredentialKey
            )
            persistenceNotice = nil
            return true
        } catch {
            persistenceNotice =
                "The provider credential could not be saved securely."
            return false
        }
    }

    func removeAIProviderCredential() {
        do {
            try secretStore.removeSecret(for: Self.aiCredentialKey)
        } catch {
            persistenceNotice =
                "The provider credential could not be removed."
        }
    }

    func updatePrivacySettings(_ settings: PrivacySettings) {
        commitMutation { working in
            working.privacySettings = settings
            if !settings.retainsCommandTranscripts {
                for index in working.commandHistory.indices {
                    working.commandHistory[index].removeTranscriptContent()
                }
            }
        }
        if !settings.retainsCommandTranscripts {
            lastAIRequestInspection = nil
        }
    }

    func reviewWorkShiftImage(
        _ data: Data,
        title: String,
        location: String?,
        at date: Date = Date()
    ) async throws -> WorkShiftImageReview {
        guard data.count <= 25_000_000 else {
            throw WorkShiftImageRecognitionError.unreadableImage
        }
        let recognition = try await shiftImageRecognizer.recognizeText(
            in: data
        )
        return WorkShiftImageImportCoordinator.review(
            recognition: recognition,
            title: title,
            location: location,
            referenceDate: date,
            timeZoneIdentifier: snapshot.profile.timeZoneIdentifier,
            existingCommitments: snapshot.fixedCommitments
        )
    }

    func makeBackupData(at date: Date = Date()) throws -> Data {
        try MissionControlBackupService.encode(
            snapshot: snapshot,
            exportedAt: date
        )
    }

    func reviewBackupData(_ data: Data) throws -> MissionControlBackup {
        try MissionControlBackupService.decode(data)
    }

    @discardableResult
    func restoreBackup(_ backup: MissionControlBackup) -> Bool {
        guard isRepositoryWritable else {
            persistenceNotice =
                "Durable storage is unavailable, so a backup cannot replace local data safely."
            return false
        }
        var restored = backup.snapshot
        restored.schemaVersion = MissionControlSnapshot.currentSchemaVersion
        guard SnapshotIntegrityValidator.issues(in: restored).isEmpty else {
            persistenceNotice =
                "The backup failed local integrity validation."
            return false
        }
        do {
            try repository.saveSnapshot(restored)
            snapshot = restored
            scheduleNotificationReconciliation()
            scheduleCalendarSyncWithoutPrompt()
            persistenceNotice = nil
            return true
        } catch {
            persistenceNotice =
                "The backup could not be restored. Existing data was preserved."
            return false
        }
    }

    @discardableResult
    func deleteAllLocalData(at date: Date = Date()) -> Bool {
        guard isRepositoryWritable else {
            persistenceNotice =
                "Durable storage is unavailable, so local data cannot be deleted safely."
            return false
        }
        do {
            try secretStore.removeSecret(for: Self.aiCredentialKey)
            try repository.deleteSnapshot()
        } catch {
            persistenceNotice =
                "Local data could not be deleted safely. Existing data was preserved."
            return false
        }
        var fresh = MissionControlSeed.makeFresh(referenceDate: date)
        let result = SchedulingEngine().makePlan(
            input: PlanningInput(
                snapshot: fresh,
                currentTime: date
            )
        )
        fresh.applySchedulingResult(result)
        snapshot = fresh
        lastAIRequestInspection = nil
        calendarAuthorizationState = .disabled
        healthAuthorizationState = .disabled
        availableCalendars = []
        do {
            try repository.saveSnapshot(fresh)
            persistenceNotice = nil
        } catch {
            isRepositoryWritable = false
            persistenceNotice =
                "Local data was deleted. The new empty profile is session-only because storage could not be recreated."
        }
        scheduleNotificationReconciliation()
        return true
    }
}
