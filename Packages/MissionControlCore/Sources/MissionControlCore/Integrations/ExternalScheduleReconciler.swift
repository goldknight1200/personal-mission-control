import Foundation

public enum PlatformIntegrationError: Error, Equatable {
    case permissionRequired(PlatformAuthorizationState)
    case invalidSubscriptionURL
    case invalidICalendar
    case missingCalendar
    case ownedEventUnavailable
    case unavailable
}

public struct ExternalScheduleReconciliation: Equatable, Sendable {
    public var insertedCommitmentIDs: [EntityID]
    public var updatedCommitmentIDs: [EntityID]
    public var removedCommitmentIDs: [EntityID]

    public init(
        insertedCommitmentIDs: [EntityID] = [],
        updatedCommitmentIDs: [EntityID] = [],
        removedCommitmentIDs: [EntityID] = []
    ) {
        self.insertedCommitmentIDs = insertedCommitmentIDs
        self.updatedCommitmentIDs = updatedCommitmentIDs
        self.removedCommitmentIDs = removedCommitmentIDs
    }

    public var hasScheduleChanges: Bool {
        !insertedCommitmentIDs.isEmpty
            || !updatedCommitmentIDs.isEmpty
            || !removedCommitmentIDs.isEmpty
    }
}

public enum ExternalScheduleReconciler {
    @discardableResult
    public static func reconcile(
        batch: ExternalEventBatch,
        snapshot: inout MissionControlSnapshot,
        identifiers: any IdentifierGenerating = StableIdentifierGenerator()
    ) -> ExternalScheduleReconciliation {
        var result = ExternalScheduleReconciliation()
        let sourceItems = snapshot.externalCalendarItems.filter {
            $0.sourceKind == batch.sourceKind
                && $0.sourceIdentifier == batch.sourceIdentifier
        }
        let existingByKey = sourceItems.reduce(
            into: [String: ExternalCalendarItem]()
        ) { partial, item in
            if let current = partial[item.reconciliationKey] {
                if current.lastSeenAt <= item.lastSeenAt {
                    partial[item.reconciliationKey] = item
                }
            } else {
                partial[item.reconciliationKey] = item
            }
        }

        var newestByKey: [String: ExternalCalendarEvent] = [:]
        for event in batch.events
        where event.sourceKind == batch.sourceKind
            && event.sourceIdentifier == batch.sourceIdentifier {
            if let current = newestByKey[event.reconciliationKey] {
                let currentDate = current.lastModifiedAt ?? .distantPast
                let incomingDate = event.lastModifiedAt ?? .distantPast
                if incomingDate >= currentDate {
                    newestByKey[event.reconciliationKey] = event
                }
            } else {
                newestByKey[event.reconciliationKey] = event
            }
        }

        let cancelledKeys = Set(
            newestByKey.values
                .filter(\.isCancelled)
                .map(\.reconciliationKey)
        )
        let visibleEvents = newestByKey.values.filter {
            !$0.isCancelled
                && $0.end > batch.coveredInterval.start
                && $0.start < batch.coveredInterval.end
        }
        let seenKeys = Set(visibleEvents.map(\.reconciliationKey))

        for event in visibleEvents.sorted(by: { $0.start < $1.start }) {
            if event.isAppOwned {
                if var item = existingByKey[event.reconciliationKey] {
                    item.lastSeenAt = batch.fetchedAt
                    item.lastModifiedAt = event.lastModifiedAt
                    replaceExternalItem(item, in: &snapshot)
                }
                continue
            }

            let itemID = existingByKey[event.reconciliationKey]?.id
                ?? identifiers.identifier(
                    namespace: "external-item.\(event.reconciliationKey)"
                )
            let commitmentID = existingByKey[event.reconciliationKey]?
                .linkedFixedCommitmentID
                ?? identifiers.identifier(
                    namespace: "external-commitment.\(event.reconciliationKey)"
                )
            let commitment = FixedCommitment(
                id: commitmentID,
                title: event.title,
                category: event.category,
                start: event.start,
                end: event.end,
                location: event.location,
                externalIdentifier: event.reconciliationKey,
                isExternallyManaged: true,
                isFootballMatch: event.isFootballMatch,
                contextTags: contextTags(for: event)
            )
            if let index = snapshot.fixedCommitments.firstIndex(where: {
                $0.id == commitmentID
            }) {
                if snapshot.fixedCommitments[index] != commitment {
                    snapshot.fixedCommitments[index] = commitment
                    result.updatedCommitmentIDs.append(commitmentID)
                }
            } else {
                snapshot.fixedCommitments.append(commitment)
                result.insertedCommitmentIDs.append(commitmentID)
            }
            replaceExternalItem(
                ExternalCalendarItem(
                    id: itemID,
                    sourceKind: event.sourceKind,
                    sourceIdentifier: event.sourceIdentifier,
                    externalIdentifier: event.externalIdentifier,
                    linkedFixedCommitmentID: commitmentID,
                    isAppOwned: false,
                    lastSeenAt: batch.fetchedAt,
                    lastModifiedAt: event.lastModifiedAt
                ),
                in: &snapshot
            )
        }

        for item in sourceItems where !item.isAppOwned {
            guard
                cancelledKeys.contains(item.reconciliationKey)
                    || shouldRemoveMissingItem(
                        item,
                        seenKeys: seenKeys,
                        coveredInterval: batch.coveredInterval,
                        snapshot: snapshot
                    )
            else {
                continue
            }
            snapshot.externalCalendarItems.removeAll { $0.id == item.id }
            if let commitmentID = item.linkedFixedCommitmentID {
                snapshot.fixedCommitments.removeAll {
                    $0.id == commitmentID && $0.isExternallyManaged
                }
                result.removedCommitmentIDs.append(commitmentID)
            }
        }
        return result
    }

    public static func removeSource(
        kind: ExternalScheduleSourceKind,
        sourceIdentifier: String,
        snapshot: inout MissionControlSnapshot
    ) -> [EntityID] {
        let matching = snapshot.externalCalendarItems.filter {
            $0.sourceKind == kind
                && $0.sourceIdentifier == sourceIdentifier
                && !$0.isAppOwned
        }
        let commitmentIDs = matching.compactMap(\.linkedFixedCommitmentID)
        let itemIDs = Set(matching.map(\.id))
        snapshot.externalCalendarItems.removeAll {
            itemIDs.contains($0.id)
        }
        let commitmentIDSet = Set(commitmentIDs)
        snapshot.fixedCommitments.removeAll {
            commitmentIDSet.contains($0.id) && $0.isExternallyManaged
        }
        return commitmentIDs
    }

    private static func shouldRemoveMissingItem(
        _ item: ExternalCalendarItem,
        seenKeys: Set<String>,
        coveredInterval: DateInterval,
        snapshot: MissionControlSnapshot
    ) -> Bool {
        guard !seenKeys.contains(item.reconciliationKey) else { return false }
        guard
            let commitmentID = item.linkedFixedCommitmentID,
            let commitment = snapshot.fixedCommitments.first(where: {
                $0.id == commitmentID
            })
        else {
            return true
        }
        return commitment.end > coveredInterval.start
            && commitment.start < coveredInterval.end
    }

    private static func replaceExternalItem(
        _ item: ExternalCalendarItem,
        in snapshot: inout MissionControlSnapshot
    ) {
        if let index = snapshot.externalCalendarItems.firstIndex(where: {
            $0.id == item.id
        }) {
            snapshot.externalCalendarItems[index] = item
        } else {
            snapshot.externalCalendarItems.append(item)
        }
    }

    private static func contextTags(
        for event: ExternalCalendarEvent
    ) -> [String] {
        var tags = ["external", event.sourceKind.rawValue]
        if event.isAllDay {
            tags.append("all-day")
        }
        if event.isFootballMatch {
            tags.append("football-fixture")
        }
        return tags
    }
}

public struct CalendarSyncService {
    private let provider: any CalendarProviding
    private let identifiers: any IdentifierGenerating

    public init(
        provider: any CalendarProviding,
        identifiers: any IdentifierGenerating = StableIdentifierGenerator()
    ) {
        self.provider = provider
        self.identifiers = identifiers
    }

    public func synchronize(
        snapshot sourceSnapshot: MissionControlSnapshot,
        interval: DateInterval,
        at date: Date
    ) async throws -> MissionControlSnapshot {
        var snapshot = sourceSnapshot
        let settings = snapshot.calendarIntegrationSettings
        guard settings.mode != .disabled else { return snapshot }
        let accessLevel: CalendarAccessLevel =
            settings.mode == .createOnly ? .writeOnly : .full
        let authorization = await provider.authorizationState(
            for: accessLevel
        )
        guard authorization == .authorized else {
            throw PlatformIntegrationError.permissionRequired(authorization)
        }

        if settings.mode == .importAndSync {
            let selectedSourceIDs = Set(settings.importsCalendarIDs)
            let events: [ExternalCalendarEvent]
            if selectedSourceIDs.isEmpty {
                events = []
            } else {
                events = try await provider.events(
                    in: interval,
                    calendarIDs: settings.importsCalendarIDs
                )
            }
            let previouslyImportedSourceIDs = Set(
                snapshot.externalCalendarItems.filter {
                    $0.sourceKind == .eventKit && !$0.isAppOwned
                }.map(\.sourceIdentifier)
            )
            let sourceIDs = selectedSourceIDs
                .union(previouslyImportedSourceIDs)
                .sorted()
            for sourceID in sourceIDs {
                _ = ExternalScheduleReconciler.reconcile(
                    batch: ExternalEventBatch(
                        sourceKind: .eventKit,
                        sourceIdentifier: sourceID,
                        coveredInterval: interval,
                        events: events.filter {
                            selectedSourceIDs.contains(sourceID)
                                && $0.sourceIdentifier == sourceID
                        },
                        fetchedAt: date
                    ),
                    snapshot: &snapshot,
                    identifiers: identifiers
                )
            }
        }

        if settings.exportsLocalCommitments {
            let localCommitments = snapshot.fixedCommitments.filter {
                !$0.isExternallyManaged
            }
            let existingOwned = snapshot.externalCalendarItems.filter {
                $0.sourceKind == .eventKit && $0.isAppOwned
            }
            let writableCommitments = settings.mode == .createOnly
                ? localCommitments.filter { commitment in
                    !existingOwned.contains(where: {
                        $0.linkedFixedCommitmentID == commitment.id
                    })
                }
                : localCommitments
            let requests = writableCommitments.map { commitment in
                CalendarEventWrite(
                    localFixedCommitmentID: commitment.id,
                    externalIdentifier: existingOwned.first(where: {
                        $0.linkedFixedCommitmentID == commitment.id
                    })?.externalIdentifier,
                    title: commitment.title,
                    start: commitment.start,
                    end: commitment.end,
                    location: commitment.location,
                    destinationCalendarID: settings.destinationCalendarID
                )
            }
            let writes: [CalendarEventWriteResult]
            if requests.isEmpty {
                writes = []
            } else {
                writes = try await provider.upsertAppOwnedEvents(requests)
            }
            let writtenLocalIDs = Set(writes.map(\.localFixedCommitmentID))
            for write in writes {
                let existing = existingOwned.first {
                    $0.linkedFixedCommitmentID
                        == write.localFixedCommitmentID
                }
                let item = ExternalCalendarItem(
                    id: existing?.id
                        ?? identifiers.identifier(
                            namespace:
                                "eventkit-owned.\(write.localFixedCommitmentID.rawValue.uuidString)"
                        ),
                    sourceKind: .eventKit,
                    sourceIdentifier: write.sourceIdentifier,
                    externalIdentifier: write.externalIdentifier,
                    linkedFixedCommitmentID: write.localFixedCommitmentID,
                    isAppOwned: true,
                    lastSeenAt: date,
                    lastModifiedAt: write.lastModifiedAt
                )
                if let index = snapshot.externalCalendarItems.firstIndex(
                    where: { $0.id == item.id }
                ) {
                    snapshot.externalCalendarItems[index] = item
                } else {
                    snapshot.externalCalendarItems.append(item)
                }
            }

            if settings.mode == .importAndSync {
                let localIDs = Set(localCommitments.map(\.id))
                for stale in existingOwned where
                    stale.linkedFixedCommitmentID.map(localIDs.contains)
                        != true
                {
                    try await provider.deleteAppOwnedEvent(
                        externalIdentifier: stale.externalIdentifier
                    )
                    snapshot.externalCalendarItems.removeAll {
                        $0.id == stale.id
                    }
                }
            }
            if !requests.isEmpty && writtenLocalIDs != Set(requests.map(
                \.localFixedCommitmentID
            )) {
                throw PlatformIntegrationError.missingCalendar
            }
        }

        snapshot.calendarIntegrationSettings.lastSyncAt = date
        snapshot.calendarIntegrationSettings.lastError = nil
        return snapshot
    }
}

public struct HealthSleepSyncService {
    private let provider: any HealthContextProviding

    public init(provider: any HealthContextProviding) {
        self.provider = provider
    }

    public func refresh(
        snapshot sourceSnapshot: MissionControlSnapshot,
        at date: Date
    ) async throws -> MissionControlSnapshot {
        var snapshot = sourceSnapshot
        guard snapshot.healthIntegrationSettings.sleepReadEnabled else {
            return snapshot
        }
        let availability = await provider.availabilityState()
        guard availability == .requested
            || availability == .authorized else {
            throw PlatformIntegrationError.permissionRequired(availability)
        }
        if let sample = try await provider.sleepRecoverySample(
            endingAt: date
        ) {
            let existing = snapshot.recoveryContext
            let healthNote =
                "Sleep duration from HealthKit; planning context only."
            let preservedNote = existing?.sleepSource == .healthKitSleep
                && existing?.note == healthNote
                ? nil
                : existing?.note
            snapshot.recoveryContext = RecoveryContext(
                recordedAt: date,
                sleepDurationMinutes: sample.asleepMinutes,
                fatigue: existing?.fatigue ?? .none,
                note: preservedNote ?? healthNote,
                sleepSource: .healthKitSleep,
                sleepWindowStart: sample.sleepWindowStart,
                sleepWindowEnd: sample.sleepWindowEnd
            )
        } else if let existing = snapshot.recoveryContext,
                  existing.sleepSource == .healthKitSleep {
            let healthNote =
                "Sleep duration from HealthKit; planning context only."
            let preservedNote = existing.note == healthNote
                ? nil
                : existing.note
            if existing.fatigue == .none && preservedNote == nil {
                snapshot.recoveryContext = nil
            } else {
                snapshot.recoveryContext = RecoveryContext(
                    recordedAt: date,
                    fatigue: existing.fatigue,
                    note: preservedNote,
                    sleepSource: .manual
                )
            }
        }
        snapshot.healthIntegrationSettings.lastRefreshAt = date
        snapshot.healthIntegrationSettings.lastError = nil
        return snapshot
    }
}

public struct ICalSyncService {
    private let provider: any ICalSubscriptionProviding
    private let identifiers: any IdentifierGenerating

    public init(
        provider: any ICalSubscriptionProviding,
        identifiers: any IdentifierGenerating = StableIdentifierGenerator()
    ) {
        self.provider = provider
        self.identifiers = identifiers
    }

    public func synchronize(
        subscriptionID: EntityID,
        snapshot sourceSnapshot: MissionControlSnapshot,
        interval: DateInterval,
        at date: Date
    ) async throws -> MissionControlSnapshot {
        var snapshot = sourceSnapshot
        guard let index = snapshot.iCalSubscriptions.firstIndex(where: {
            $0.id == subscriptionID
        }) else {
            return snapshot
        }
        let subscription = snapshot.iCalSubscriptions[index]
        guard subscription.isEnabled else { return snapshot }
        let batch = try await provider.events(
            for: subscription,
            in: interval,
            fetchedAt: date,
            timeZoneIdentifier: snapshot.profile.timeZoneIdentifier
        )
        guard
            batch.sourceKind == .iCal,
            batch.sourceIdentifier == subscription.id.rawValue.uuidString
        else {
            throw PlatformIntegrationError.invalidICalendar
        }
        _ = ExternalScheduleReconciler.reconcile(
            batch: batch,
            snapshot: &snapshot,
            identifiers: identifiers
        )
        snapshot.iCalSubscriptions[index].lastSyncAt = date
        snapshot.iCalSubscriptions[index].lastError = nil
        return snapshot
    }
}
