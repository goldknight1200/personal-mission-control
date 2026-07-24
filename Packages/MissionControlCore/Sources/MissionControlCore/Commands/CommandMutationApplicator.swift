import Foundation

public enum CommandApplicationError: Error, Equatable, Sendable {
    case noSupportedMutations
    case confirmationRequired
    case unresolvedMission(String)
    case invalidDuration
    case invalidDate
}

public struct CommandApplicationResult: Equatable, Sendable {
    public var snapshot: MissionControlSnapshot
    public var appliedMutationCount: Int
    public var replanRequests: [ReplanRequest]

    public init(
        snapshot: MissionControlSnapshot,
        appliedMutationCount: Int,
        replanRequests: [ReplanRequest]
    ) {
        self.snapshot = snapshot
        self.appliedMutationCount = appliedMutationCount
        self.replanRequests = replanRequests
    }
}

public struct CommandMutationApplicator {
    private let replanner: any ScheduleReplanning

    public init(replanner: any ScheduleReplanning) {
        self.replanner = replanner
    }

    public func apply(
        _ command: StructuredCommand,
        to snapshot: MissionControlSnapshot,
        finalConfirmationProvided: Bool
    ) throws -> CommandApplicationResult {
        guard !command.proposedMutations.isEmpty else {
            throw CommandApplicationError.noSupportedMutations
        }
        if command.confirmationRequirement.isRequired && !finalConfirmationProvided {
            throw CommandApplicationError.confirmationRequired
        }
        if snapshot.commandHistory.contains(where: { $0.id == command.id }) {
            return CommandApplicationResult(
                snapshot: snapshot,
                appliedMutationCount: 0,
                replanRequests: []
            )
        }

        var working = snapshot
        var requests: [ReplanRequest] = []

        for mutation in command.proposedMutations {
            switch mutation {
            case let .requestDayReplan(availableFrom):
                requests.append(
                    ReplanRequest(
                        reason: .lateStart,
                        requestedAt: command.createdAt,
                        affectedStart: availableFrom,
                        affectedEnd: command.affectedScheduleRange.end
                    )
                )

            case let .markMissionStarted(missionID, missionName, minutesAgo):
                guard minutesAgo >= 0 else {
                    throw CommandApplicationError.invalidDuration
                }
                let resolvedID = try requireMissionID(
                    missionID,
                    missionName: missionName,
                    snapshot: working
                )
                let actualStart = command.createdAt.addingTimeInterval(
                    -TimeInterval(minutesAgo * 60)
                )
                let scheduleBlockID = executionBlockID(
                    missionID: resolvedID,
                    at: command.createdAt,
                    snapshot: working
                )
                guard MissionExecution.markStarted(
                    snapshot: &working,
                    missionID: resolvedID,
                    scheduleBlockID: scheduleBlockID,
                    actualStart: actualStart,
                    reportedAt: command.createdAt
                ) else {
                    throw CommandApplicationError.unresolvedMission(missionName)
                }
                requests.append(
                    ReplanRequest(
                        reason: .actualStartCorrected,
                        missionID: resolvedID,
                        requestedAt: command.createdAt,
                        affectedStart: actualStart,
                        affectedEnd: command.affectedScheduleRange.end
                    )
                )

            case let .addChecklistItem(kind, title):
                if let checklistIndex = working.checklists.firstIndex(where: { $0.kind == kind }) {
                    working.checklists[checklistIndex].items.append(
                        ChecklistItem(title: title)
                    )
                } else {
                    working.checklists.append(
                        Checklist(
                            title: kind.displayName,
                            kind: kind,
                            items: [ChecklistItem(title: title)]
                        )
                    )
                }

            case let .markInventoryEmpty(name):
                if let inventoryIndex = working.inventoryItems.firstIndex(where: {
                    normalized($0.name) == normalized(name)
                }) {
                    working.inventoryItems[inventoryIndex].state = .empty
                    working.inventoryItems[inventoryIndex].quantityNote = nil
                    working.inventoryItems[inventoryIndex].updatedAt = command.createdAt
                } else {
                    working.inventoryItems.append(
                        InventoryItem(
                            name: name,
                            state: .empty,
                            updatedAt: command.createdAt
                        )
                    )
                }

            case let .requestMissionMove(missionID, missionName):
                let resolvedID = try requireMissionID(
                    missionID,
                    missionName: missionName,
                    snapshot: working
                )
                requests.append(
                    ReplanRequest(
                        reason: .missionMove,
                        missionID: resolvedID,
                        requestedAt: command.createdAt,
                        affectedStart: command.affectedScheduleRange.start,
                        affectedEnd: command.affectedScheduleRange.end
                    )
                )

            case let .skipMission(missionID, missionName):
                let resolvedID = try requireMissionID(
                    missionID,
                    missionName: missionName,
                    snapshot: working
                )
                let scheduleBlockID = executionBlockID(
                    missionID: resolvedID,
                    at: command.createdAt,
                    snapshot: working
                )
                guard MissionExecution.resolve(
                    snapshot: &working,
                    missionID: resolvedID,
                    scheduleBlockID: scheduleBlockID,
                    status: .skipped,
                    at: command.createdAt,
                    reason: "Skipped through a confirmed voice command."
                ) != nil else {
                    throw CommandApplicationError.unresolvedMission(missionName)
                }
                if working.scheduleBlocks.contains(where: {
                    $0.id != scheduleBlockID
                        && $0.missionID == resolvedID
                        && $0.start > command.createdAt
                }), let missionIndex = working.missions.firstIndex(where: {
                    $0.id == resolvedID
                }) {
                    working.missions[missionIndex].status = .planned
                }
                requests.append(
                    ReplanRequest(
                        reason: .missionSkipped,
                        missionID: resolvedID,
                        requestedAt: command.createdAt,
                        affectedStart: command.affectedScheduleRange.start,
                        affectedEnd: command.affectedScheduleRange.end,
                        confirmationProvided: finalConfirmationProvided
                    )
                )

            case let .addWorkShift(shift):
                guard shift.end > shift.start,
                      shift.end > command.createdAt else {
                    throw CommandApplicationError.invalidDate
                }
                let commitment = FixedCommitment(
                    title: shift.title,
                    category: .work,
                    start: shift.start,
                    end: shift.end
                )
                working.fixedCommitments.append(commitment)
                working.scheduleBlocks.append(
                    ScheduleBlock(
                        fixedCommitmentID: commitment.id,
                        title: commitment.title,
                        category: .work,
                        kind: .fixedCommitment,
                        rigidity: .fixed,
                        start: commitment.start,
                        end: commitment.end,
                        isImmutable: true
                    )
                )
                requests.append(
                    ReplanRequest(
                        reason: .fixedCommitmentAdded,
                        requestedAt: command.createdAt,
                        affectedStart: shift.start,
                        affectedEnd: shift.end
                    )
                )

            case let .addPainFlag(bodyArea):
                working.painFlags.append(
                    PainFlag(
                        bodyArea: bodyArea,
                        reportedAt: command.createdAt,
                        note: command.confirmedTranscript
                    )
                )
                requests.append(
                    ReplanRequest(
                        reason: .painReported,
                        requestedAt: command.createdAt,
                        affectedStart: command.affectedScheduleRange.start,
                        affectedEnd: command.affectedScheduleRange.end
                    )
                )
            }
        }

        working.replanRequests.append(contentsOf: requests)
        if !working.commandHistory.contains(where: { $0.id == command.id }) {
            working.commandHistory.append(command)
        }
        working.schemaVersion = MissionControlSnapshot.currentSchemaVersion

        let replanned = try replanner.replan(snapshot: working, requests: requests)
        return CommandApplicationResult(
            snapshot: replanned,
            appliedMutationCount: command.proposedMutations.count,
            replanRequests: requests
        )
    }

    private func requireMissionID(
        _ id: EntityID?,
        missionName: String,
        snapshot: MissionControlSnapshot
    ) throws -> EntityID {
        if let id, snapshot.missions.contains(where: { $0.id == id }) {
            return id
        }
        throw CommandApplicationError.unresolvedMission(missionName)
    }

    private func normalized(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func executionBlockID(
        missionID: EntityID,
        at date: Date,
        snapshot: MissionControlSnapshot
    ) -> EntityID? {
        let blocks = snapshot.scheduleBlocks
            .filter {
                $0.missionID == missionID && $0.kind == .mission
            }
            .sorted(by: { $0.start < $1.start })
        if let active = blocks.first(where: {
            $0.start <= date && date < $0.end
        }) {
            return active.id
        }
        if let upcoming = blocks.first(where: { $0.start > date }) {
            return upcoming.id
        }
        return blocks.last?.id
    }
}
