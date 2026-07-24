import Foundation

public enum NotificationSchedulePlanner {
    public static let identifierPrefix = "missioncontrol.mission."

    public static func desiredRequests(
        snapshot: MissionControlSnapshot,
        now: Date
    ) -> [MissionNotificationRequest] {
        snapshot.scheduleBlocks.compactMap { block -> [MissionNotificationRequest]? in
            guard
                let missionID = block.missionID,
                let mission = snapshot.mission(withID: missionID),
                !snapshot.completions.contains(where: {
                    $0.scheduleBlockID == block.id
                }),
                !snapshot.unresolvedDispositions.contains(where: {
                    $0.scheduleBlockID == block.id
                })
            else {
                return nil
            }
            let blockAwareStarts = snapshot.missionStartRecords.filter {
                $0.missionID == missionID && $0.scheduleBlockID != nil
            }
            let isThisBlockInProgress = mission.status == .inProgress
                && (
                    blockAwareStarts.isEmpty
                        || blockAwareStarts.contains(where: {
                            $0.scheduleBlockID == block.id
                        })
                )
            guard mission.status == .planned
                || (mission.status == .inProgress && !isThisBlockInProgress)
            else {
                return nil
            }
            return MissionNotificationStage.allCases.compactMap { stage in
                let fireDate = block.start.addingTimeInterval(
                    TimeInterval(stage.minuteOffset * 60)
                )
                guard fireDate > now else { return nil }
                return MissionNotificationRequest(
                    id: identifier(
                        missionID: missionID,
                        scheduleBlockID: block.id,
                        stage: stage
                    ),
                    missionID: missionID,
                    scheduleBlockID: block.id,
                    stage: stage,
                    fireDate: fireDate,
                    title: title(for: stage, missionTitle: mission.title),
                    body: body(for: stage, missionTitle: mission.title)
                )
            }
        }
        .flatMap { $0 }
        .sorted {
            if $0.fireDate == $1.fireDate { return $0.id < $1.id }
            return $0.fireDate < $1.fireDate
        }
    }

    public static func reconciliation(
        snapshot: MissionControlSnapshot,
        existing: [MissionNotificationRequest],
        now: Date
    ) -> NotificationReconciliation {
        let desired = desiredRequests(snapshot: snapshot, now: now)
        let desiredByID = Dictionary(uniqueKeysWithValues: desired.map { ($0.id, $0) })
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        let cancellations = existing.filter { existingRequest in
            desiredByID[existingRequest.id] != existingRequest
        }
        .map(\.id)
        .sorted()

        let additions = desired.filter { desiredRequest in
            existingByID[desiredRequest.id] != desiredRequest
        }

        return NotificationReconciliation(
            identifiersToCancel: cancellations,
            requestsToSchedule: additions
        )
    }

    public static func identifier(
        missionID: EntityID,
        scheduleBlockID: EntityID,
        stage: MissionNotificationStage
    ) -> String {
        identifierPrefix
            + missionID.rawValue.uuidString.lowercased()
            + "."
            + scheduleBlockID.rawValue.uuidString.lowercased()
            + "."
            + stage.rawValue
    }

    private static func title(
        for stage: MissionNotificationStage,
        missionTitle: String
    ) -> String {
        switch stage {
        case .preStart: "\(missionTitle) starts in 15 minutes"
        case .start: "Start \(missionTitle)"
        case .late15: "\(missionTitle) is unresolved"
        case .late30: "Reality check: \(missionTitle)"
        }
    }

    private static func body(
        for stage: MissionNotificationStage,
        missionTitle: String
    ) -> String {
        switch stage {
        case .preStart:
            "Prepare now so the start stays realistic."
        case .start:
            "Start now, or choose an explicit recovery action."
        case .late15:
            "Already started, start now, replan, or skip."
        case .late30:
            "Choose what happens next so stale work does not linger."
        }
    }
}
