public protocol ScheduleReplanning {
    func replan(
        snapshot: MissionControlSnapshot,
        requests: [ReplanRequest]
    ) throws -> MissionControlSnapshot
}

/// Test/fallback bridge that records requests without producing placements.
///
/// Production composition uses `ReplanningEngine`. This value remains useful
/// for isolated command-pipeline tests that intentionally exclude scheduling.
public struct PendingRequestScheduleReplanner: ScheduleReplanning {
    public init() {}

    public func replan(
        snapshot: MissionControlSnapshot,
        requests: [ReplanRequest]
    ) throws -> MissionControlSnapshot {
        snapshot
    }
}
