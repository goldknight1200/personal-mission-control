import Foundation

public enum MissionLatenessState: String, Codable, Equatable, Sendable {
    case upcoming
    case due
    case late15
    case late30
    case inProgress
    case resolved
}

public struct SkipAssessment: Equatable, Sendable {
    public var requiresConfirmation: Bool
    public var consequence: String?

    public init(requiresConfirmation: Bool, consequence: String? = nil) {
        self.requiresConfirmation = requiresConfirmation
        self.consequence = consequence
    }
}

public enum RecoveryAlternativeKind: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case startNow
    case laterToday
    case tomorrow
    case weeklyBacklog

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .startNow: "Start now"
        case .laterToday: "Find a later time today"
        case .tomorrow: "Move to tomorrow"
        case .weeklyBacklog: "Return to weekly backlog"
        }
    }
}

public struct RecoveryAlternative: Equatable, Identifiable, Sendable {
    public var kind: RecoveryAlternativeKind
    public var consequence: String
    public var recommendation: String?

    public var id: RecoveryAlternativeKind { kind }

    public init(
        kind: RecoveryAlternativeKind,
        consequence: String,
        recommendation: String? = nil
    ) {
        self.kind = kind
        self.consequence = consequence
        self.recommendation = recommendation
    }
}

public struct MissionRecoveryProposal: Equatable, Identifiable, Sendable {
    public var missionID: EntityID
    public var scheduleBlockID: EntityID
    public var missionTitle: String
    public var alternatives: [RecoveryAlternative]

    public var id: EntityID { scheduleBlockID }

    public init(
        missionID: EntityID,
        scheduleBlockID: EntityID,
        missionTitle: String,
        alternatives: [RecoveryAlternative]
    ) {
        self.missionID = missionID
        self.scheduleBlockID = scheduleBlockID
        self.missionTitle = missionTitle
        self.alternatives = alternatives
    }
}

public enum MissionExecution {
    public static func latenessState(
        block: ScheduleBlock,
        missionStatus: MissionStatus,
        hasResolution: Bool,
        at date: Date
    ) -> MissionLatenessState {
        if hasResolution || [.completed, .skipped, .partial].contains(missionStatus) {
            return .resolved
        }
        if missionStatus == .inProgress {
            return .inProgress
        }
        if date < block.start {
            return .upcoming
        }
        let minutesLate = Int(date.timeIntervalSince(block.start) / 60)
        if minutesLate >= 30 {
            return .late30
        }
        if minutesLate >= 15 {
            return .late15
        }
        return .due
    }

    public static func skipAssessment(for mission: Mission) -> SkipAssessment {
        let consequential = mission.rigidity == .protected
            || mission.rigidity == .fixed
            || mission.importance >= .high
            || mission.consistencyCost >= .high
            || mission.backlogCost >= .high
        guard consequential else {
            return SkipAssessment(requiresConfirmation: false)
        }
        return SkipAssessment(
            requiresConfirmation: true,
            consequence: "Skipping \(mission.title) can break a protected commitment "
                + "or increase consistency and backlog cost."
        )
    }

    public static func markStarted(
        snapshot: inout MissionControlSnapshot,
        missionID: EntityID,
        scheduleBlockID: EntityID? = nil,
        actualStart: Date,
        reportedAt: Date
    ) -> Bool {
        guard let missionIndex = snapshot.missions.firstIndex(where: {
            $0.id == missionID
        }) else {
            return false
        }
        snapshot.missions[missionIndex].status = .inProgress
        if let recordIndex = snapshot.missionStartRecords.lastIndex(where: {
            if let scheduleBlockID {
                return $0.scheduleBlockID == scheduleBlockID
            }
            return $0.missionID == missionID && $0.scheduleBlockID == nil
        }) {
            snapshot.missionStartRecords[recordIndex].scheduleBlockID =
                scheduleBlockID
            snapshot.missionStartRecords[recordIndex].actualStart = actualStart
            snapshot.missionStartRecords[recordIndex].reportedAt = reportedAt
        } else {
            snapshot.missionStartRecords.append(
                MissionStartRecord(
                    missionID: missionID,
                    scheduleBlockID: scheduleBlockID,
                    actualStart: actualStart,
                    reportedAt: reportedAt
                )
            )
        }
        return true
    }

    @discardableResult
    public static func resolve(
        snapshot: inout MissionControlSnapshot,
        missionID: EntityID,
        scheduleBlockID: EntityID?,
        status: MissionOutcomeStatus,
        at date: Date,
        actualDurationMinutes: Int? = nil,
        reason: String? = nil,
        missCause: MissionMissCause? = nil
    ) -> CompletionRecord? {
        guard let missionIndex = snapshot.missions.firstIndex(where: {
            $0.id == missionID
        }) else {
            return nil
        }
        let mission = snapshot.missions[missionIndex]
        let block = scheduleBlockID.flatMap { blockID in
            snapshot.scheduleBlocks.first(where: { $0.id == blockID })
        }
        let startRecord = snapshot.missionStartRecords.last(where: {
            if let scheduleBlockID {
                return $0.scheduleBlockID == scheduleBlockID
            }
            return $0.missionID == missionID
        }) ?? snapshot.missionStartRecords.last(where: {
            $0.missionID == missionID && $0.scheduleBlockID == nil
        })
        let actualStart = startRecord?.actualStart
        let inferredDuration: Int
        if let actualDurationMinutes {
            inferredDuration = max(actualDurationMinutes, 0)
        } else if let actualStart {
            inferredDuration = max(Int(date.timeIntervalSince(actualStart) / 60), 0)
        } else {
            inferredDuration = status == .skipped ? 0 : (block?.durationMinutes
                ?? mission.estimatedDurationMinutes)
        }
        let resolvedStart = actualStart
            ?? (status == .skipped
                ? nil
                : date.addingTimeInterval(-TimeInterval(inferredDuration * 60)))

        switch status {
        case .completed:
            snapshot.missions[missionIndex].status = .completed
        case .skipped:
            snapshot.missions[missionIndex].status = .skipped
        case .partial:
            snapshot.missions[missionIndex].status = .partial
        }
        snapshot.missions[missionIndex].actualDurationMinutes = inferredDuration

        let record = CompletionRecord(
            missionID: missionID,
            scheduleBlockID: scheduleBlockID,
            status: status,
            completedAt: date,
            actualStart: resolvedStart,
            actualEnd: date,
            plannedDurationMinutes: block?.durationMinutes
                ?? mission.estimatedDurationMinutes,
            actualDurationMinutes: inferredDuration,
            reason: reason,
            missCause: missCause
        )
        if let existingIndex = snapshot.completions.firstIndex(where: {
            if let scheduleBlockID {
                return $0.scheduleBlockID == scheduleBlockID
            }
            return $0.scheduleBlockID == nil && $0.missionID == missionID
        }) {
            var updated = record
            updated.id = snapshot.completions[existingIndex].id
            snapshot.completions[existingIndex] = updated
            return updated
        }
        snapshot.completions.append(record)
        return record
    }

    public static func updateActualDuration(
        snapshot: inout MissionControlSnapshot,
        missionID: EntityID,
        minutes: Int
    ) {
        guard minutes > 0 else { return }
        if let missionIndex = snapshot.missions.firstIndex(where: {
            $0.id == missionID
        }) {
            snapshot.missions[missionIndex].actualDurationMinutes = minutes
        }
        if let completionIndex = snapshot.completions.lastIndex(where: {
            $0.missionID == missionID
        }) {
            snapshot.completions[completionIndex].actualDurationMinutes = minutes
            if let end = snapshot.completions[completionIndex].actualEnd {
                let start = end.addingTimeInterval(-TimeInterval(minutes * 60))
                snapshot.completions[completionIndex].actualStart = start
                if let startIndex = snapshot.missionStartRecords.lastIndex(where: {
                    $0.missionID == missionID
                }) {
                    snapshot.missionStartRecords[startIndex].actualStart = start
                }
            }
        }
    }
}

public enum MissionRecoveryPlanner {
    public static func proposal(
        mission: Mission,
        block: ScheduleBlock,
        snapshot: MissionControlSnapshot
    ) -> MissionRecoveryProposal {
        let latestCause = snapshot.missDiagnostics
            .filter { $0.category == mission.category }
            .max(by: { $0.recordedAt < $1.recordedAt })?
            .cause
        let recommendation = latestCause?.recommendation
        var alternatives = [
            RecoveryAlternative(
                kind: .startNow,
                consequence: "The remaining day may need to move around this mission.",
                recommendation: recommendation
            ),
            RecoveryAlternative(
                kind: .laterToday,
                consequence: "Later blocks and transition time may move."
            ),
            RecoveryAlternative(
                kind: .tomorrow,
                consequence: mission.rigidity == .protected
                    ? "This delays a protected commitment and increases backlog risk."
                    : "This carries the work into tomorrow."
            )
        ]
        if mission.rigidity != .fixed {
            alternatives.append(
                RecoveryAlternative(
                    kind: .weeklyBacklog,
                    consequence: "The mission remains visible but loses a specific day."
                )
            )
        }
        return MissionRecoveryProposal(
            missionID: mission.id,
            scheduleBlockID: block.id,
            missionTitle: mission.title,
            alternatives: alternatives
        )
    }
}
