import Foundation

public struct ReplanningEngine: ScheduleReplanning {
    private let planner: SchedulingEngine
    private let identifiers: any IdentifierGenerating

    public init(
        planner: SchedulingEngine = SchedulingEngine(),
        identifiers: any IdentifierGenerating = StableIdentifierGenerator()
    ) {
        self.planner = planner
        self.identifiers = identifiers
    }

    public func replan(
        snapshot: MissionControlSnapshot,
        requests: [ReplanRequest]
    ) throws -> MissionControlSnapshot {
        guard !requests.isEmpty else { return snapshot }

        var working = snapshot
        let reportedTime = requests.map(\.requestedAt).max()
            ?? snapshot.schedulingPlanMetadata?.generatedAt
            ?? snapshot.scheduleBlocks.map(\.start).min()
            ?? Date(timeIntervalSince1970: 0)
        let planningTime = max(
            reportedTime,
            requests.filter { $0.reason == .lateStart }
                .compactMap(\.affectedStart)
                .max() ?? reportedTime
        )
        let affected = affectedRange(
            requests: requests,
            snapshot: snapshot,
            currentTime: reportedTime
        )
        let unconfirmedProtected = protectedSkipsAwaitingConfirmation(
            snapshot: snapshot,
            requests: requests
        )
        for missionID in unconfirmedProtected {
            if let index = working.missions.firstIndex(where: {
                $0.id == missionID
            }) {
                working.missions[index].status = .planned
            }
        }

        let locked = lockedBlocks(
            snapshot: working,
            currentTime: reportedTime,
            affected: affected,
            forcePreservedMissionIDs: unconfirmedProtected
        )
        var input = PlanningInput(
            snapshot: working,
            currentTime: planningTime,
            lockedBlocks: locked
        )
        let explicitlyReconsideredMissionIDs = Set(
            requests.compactMap { request -> EntityID? in
                guard
                    request.reason == .missionMove
                        || request.reason == .repeatedMiss
                        || request.reason == .projectPriorityRaised
                else {
                    return nil
                }
                return request.missionID
            }
        )
        input.existingPlan.removeAll(where: { block in
            block.missionID.map {
                explicitlyReconsideredMissionIDs.contains($0)
            } ?? false
        })
        var result = planner.makePlan(input: input)
        appendReplanningDecisions(
            to: &result,
            oldPlan: snapshot.scheduleBlocks,
            requests: requests,
            unconfirmedProtected: unconfirmedProtected
        )
        working.applySchedulingResult(result)

        let appliedIDs = Set(
            requests
                .filter {
                    guard let missionID = $0.missionID else { return true }
                    return !unconfirmedProtected.contains(missionID)
                }
                .map(\.id)
        )
        for index in working.replanRequests.indices
        where appliedIDs.contains(working.replanRequests[index].id) {
            working.replanRequests[index].status = .applied
        }
        working.schemaVersion = MissionControlSnapshot.currentSchemaVersion
        return working
    }

    private func affectedRange(
        requests: [ReplanRequest],
        snapshot: MissionControlSnapshot,
        currentTime: Date
    ) -> DateInterval {
        let start = requests.compactMap {
            if $0.reason == .lateStart {
                return $0.requestedAt
            }
            return $0.affectedStart ?? $0.requestedAt
        }.min() ?? currentTime
        let fallbackEnd = endOfDay(
            for: currentTime,
            timeZoneIdentifier: snapshot.profile.timeZoneIdentifier
        )
        let end = requests.compactMap(\.affectedEnd).max() ?? fallbackEnd
        return DateInterval(
            start: min(start, end),
            end: max(end, start.addingTimeInterval(60))
        )
    }

    private func protectedSkipsAwaitingConfirmation(
        snapshot: MissionControlSnapshot,
        requests: [ReplanRequest]
    ) -> Set<EntityID> {
        Set(
            requests.compactMap { request in
                guard
                    request.reason == .missionSkipped,
                    !request.confirmationProvided,
                    let missionID = request.missionID,
                    let mission = snapshot.mission(withID: missionID),
                    MissionExecution.skipAssessment(
                        for: mission
                    ).requiresConfirmation
                else {
                    return nil
                }
                return missionID
            }
        )
    }

    private func lockedBlocks(
        snapshot: MissionControlSnapshot,
        currentTime: Date,
        affected: DateInterval,
        forcePreservedMissionIDs: Set<EntityID>
    ) -> [ScheduleBlock] {
        let completedBlockIDs = Set(
            snapshot.completions.compactMap {
                guard $0.status == .completed || $0.status == .partial else {
                    return nil
                }
                return $0.scheduleBlockID
            }
        )
        let inProgressMissionIDs = Set(
            snapshot.missions
                .filter { $0.status == .inProgress }
                .map(\.id)
        )
        var inProgressBlockIDs = Set(
            snapshot.missionStartRecords.compactMap { record in
                guard inProgressMissionIDs.contains(record.missionID) else {
                    return nil
                }
                return record.scheduleBlockID
            }
        )
        for missionID in inProgressMissionIDs
        where !snapshot.missionStartRecords.contains(where: {
            $0.missionID == missionID && $0.scheduleBlockID != nil
        }) {
            let candidates = snapshot.scheduleBlocks
                .filter {
                    $0.missionID == missionID && $0.kind == .mission
                }
                .sorted(by: { $0.start < $1.start })
            let selected = candidates.first(where: {
                $0.start <= currentTime && currentTime < $0.end
            }) ?? candidates.first(where: {
                $0.start > currentTime
            }) ?? candidates.last
            if let selected {
                inProgressBlockIDs.insert(selected.id)
            }
        }

        return snapshot.scheduleBlocks.compactMap { source in
            if source.kind == .freeTime && source.end > currentTime {
                return nil
            }
            if source.kind == .fixedCommitment && source.end > currentTime {
                // Reconstruct future fixed blocks from authoritative commitments.
                return nil
            }

            let isPast = source.end <= currentTime
            let isCompleted = completedBlockIDs.contains(source.id)
            let isInProgress = inProgressBlockIDs.contains(source.id)
            let isForced = source.missionID.map {
                forcePreservedMissionIDs.contains($0)
            } ?? false
            let isUnaffectedFuture = !overlaps(
                source.start,
                source.end,
                affected.start,
                affected.end
            )

            guard
                isPast
                    || isCompleted
                    || isInProgress
                    || isForced
                    || isUnaffectedFuture
            else {
                return nil
            }

            if isCompleted,
               let record = snapshot.completions.last(where: {
                   $0.scheduleBlockID == source.id
               }),
               let actualStart = record.actualStart,
               let actualEnd = record.actualEnd,
               actualEnd > actualStart {
                var actual = source
                actual.start = actualStart
                actual.end = actualEnd
                return actual
            }

            if isInProgress,
               let missionID = source.missionID,
               let actualStart = snapshot.missionStartRecords
                   .last(where: {
                       $0.scheduleBlockID == source.id
                   })?.actualStart
                   ?? snapshot.missionStartRecords
                   .last(where: {
                       $0.missionID == missionID
                           && $0.scheduleBlockID == nil
                   })?.actualStart {
                var inProgress = source
                let plannedDuration = max(source.durationMinutes, 5)
                inProgress.start = actualStart
                inProgress.end = max(
                    actualStart.addingTimeInterval(
                        TimeInterval(plannedDuration * 60)
                    ),
                    currentTime.addingTimeInterval(5 * 60)
                )
                return inProgress
            }
            return source
        }
        .sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id < $1.id
        }
    }

    private func appendReplanningDecisions(
        to result: inout SchedulingResult,
        oldPlan: [ScheduleBlock],
        requests: [ReplanRequest],
        unconfirmedProtected: Set<EntityID>
    ) {
        let newMissionBlocks = result.blocks.filter {
            $0.kind == .mission && $0.missionID != nil
        }
        for old in oldPlan
        where old.kind == .mission {
            guard
                let missionID = old.missionID,
                let replacement = newMissionBlocks.first(where: {
                    $0.id == old.id
                }) ?? newMissionBlocks
                    .filter { $0.missionID == missionID }
                    .min(by: {
                        abs($0.start.timeIntervalSince(old.start))
                            < abs($1.start.timeIntervalSince(old.start))
                    }),
                replacement.start != old.start
            else {
                continue
            }
            let alreadyExplained = result.decisions.contains {
                $0.kind == .moved
                    && $0.missionID == missionID
                    && $0.previousStart == old.start
                    && $0.newStart == replacement.start
            }
            guard !alreadyExplained else { continue }
            result.decisions.append(
                SchedulingDecision(
                    id: identifiers.identifier(
                        namespace: "replan.move.\(old.id.rawValue.uuidString).\(Int(replacement.start.timeIntervalSince1970))"
                    ),
                    kind: .moved,
                    rule: .stability,
                    missionID: missionID,
                    scheduleBlockID: replacement.id,
                    title: replacement.title,
                    explanation: "The block moved only because it intersected the affected range or a new harder constraint.",
                    previousStart: old.start,
                    newStart: replacement.start
                )
            )
        }

        for missionID in unconfirmedProtected {
            let title = oldPlan.first(where: {
                $0.missionID == missionID
            })?.title ?? "Protected mission"
            result.decisions.append(
                SchedulingDecision(
                    id: identifiers.identifier(
                        namespace: "replan.confirmation.\(missionID.rawValue.uuidString)"
                    ),
                    kind: .confirmationRequired,
                    rule: .consequenceConfirmation,
                    missionID: missionID,
                    title: title,
                    explanation: "Skipping this protected or consequential mission requires an explicit confirmed decision. Its existing placement was preserved.",
                    requiresConfirmation: true
                )
            )
        }

        if requests.contains(where: { $0.reason == .repeatedMiss }) {
            result.decisions.append(
                SchedulingDecision(
                    id: identifiers.identifier(
                        namespace: "replan.repeatedMiss.\(requests.map { $0.id.rawValue.uuidString }.joined(separator: "."))"
                    ),
                    kind: .recoveryAdjusted,
                    rule: .repeatedMissFeedback,
                    missionID: requests.compactMap(\.missionID).first,
                    title: "Repeated-miss feedback applied",
                    explanation: "The latest classified cause changed deterministic timing recommendations without weakening protected goals."
                )
            )
        }
    }

    private func endOfDay(
        for date: Date,
        timeZoneIdentifier: String
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(
            identifier: timeZoneIdentifier
        ) ?? .current
        return calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) ?? date.addingTimeInterval(86_400)
    }

    private func overlaps(
        _ leftStart: Date,
        _ leftEnd: Date,
        _ rightStart: Date,
        _ rightEnd: Date
    ) -> Bool {
        leftStart < rightEnd && rightStart < leftEnd
    }
}
