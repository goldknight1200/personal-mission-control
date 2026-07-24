/// Editable planning defaults shared by the app and deterministic core.
///
/// These values are seed configuration, not a hard-coded user identity. The
/// persistence adapter stores the user's edited copy and future planning use
/// cases receive that value through the domain snapshot.
public struct PlanningPolicy: Codable, Equatable, Sendable {
    public var timeZoneIdentifier: String
    public var planningHorizonDays: Int
    public var minimumFocusedBlockMinutes: Int
    public var sleepTargetMinutes: Int
    public var practicalSleepMinimumMinutes: Int
    public var reconsiderDemandingWorkBelowMinutes: Int
    public var preferredWakeMinute: Int
    public var generatedGridMinutes: Int

    public init(
        timeZoneIdentifier: String,
        planningHorizonDays: Int,
        minimumFocusedBlockMinutes: Int,
        sleepTargetMinutes: Int = 450,
        practicalSleepMinimumMinutes: Int = 390,
        reconsiderDemandingWorkBelowMinutes: Int = 360,
        preferredWakeMinute: Int = 450,
        generatedGridMinutes: Int = 5
    ) {
        precondition(!timeZoneIdentifier.isEmpty, "A time-zone identifier is required")
        precondition(planningHorizonDays > 0, "Planning horizon must be positive")
        precondition(minimumFocusedBlockMinutes > 0, "Minimum block must be positive")
        precondition(sleepTargetMinutes > 0, "Sleep target must be positive")
        precondition(
            practicalSleepMinimumMinutes <= sleepTargetMinutes,
            "Practical sleep minimum cannot exceed the target"
        )
        precondition(
            reconsiderDemandingWorkBelowMinutes <= practicalSleepMinimumMinutes,
            "Reconsideration threshold cannot exceed the practical minimum"
        )
        precondition((0..<24 * 60).contains(preferredWakeMinute))
        precondition(generatedGridMinutes > 0)

        self.timeZoneIdentifier = timeZoneIdentifier
        self.planningHorizonDays = planningHorizonDays
        self.minimumFocusedBlockMinutes = minimumFocusedBlockMinutes
        self.sleepTargetMinutes = sleepTargetMinutes
        self.practicalSleepMinimumMinutes = practicalSleepMinimumMinutes
        self.reconsiderDemandingWorkBelowMinutes = reconsiderDemandingWorkBelowMinutes
        self.preferredWakeMinute = preferredWakeMinute
        self.generatedGridMinutes = generatedGridMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case timeZoneIdentifier
        case planningHorizonDays
        case minimumFocusedBlockMinutes
        case sleepTargetMinutes
        case practicalSleepMinimumMinutes
        case reconsiderDemandingWorkBelowMinutes
        case preferredWakeMinute
        case generatedGridMinutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timeZoneIdentifier = try container.decode(
            String.self,
            forKey: .timeZoneIdentifier
        )
        planningHorizonDays = try container.decode(
            Int.self,
            forKey: .planningHorizonDays
        )
        minimumFocusedBlockMinutes = try container.decode(
            Int.self,
            forKey: .minimumFocusedBlockMinutes
        )
        sleepTargetMinutes = try container.decodeIfPresent(
            Int.self,
            forKey: .sleepTargetMinutes
        ) ?? 450
        practicalSleepMinimumMinutes = try container.decodeIfPresent(
            Int.self,
            forKey: .practicalSleepMinimumMinutes
        ) ?? 390
        reconsiderDemandingWorkBelowMinutes = try container.decodeIfPresent(
            Int.self,
            forKey: .reconsiderDemandingWorkBelowMinutes
        ) ?? 360
        preferredWakeMinute = try container.decodeIfPresent(
            Int.self,
            forKey: .preferredWakeMinute
        ) ?? 450
        generatedGridMinutes = try container.decodeIfPresent(
            Int.self,
            forKey: .generatedGridMinutes
        ) ?? 5
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try container.encode(planningHorizonDays, forKey: .planningHorizonDays)
        try container.encode(
            minimumFocusedBlockMinutes,
            forKey: .minimumFocusedBlockMinutes
        )
        try container.encode(sleepTargetMinutes, forKey: .sleepTargetMinutes)
        try container.encode(
            practicalSleepMinimumMinutes,
            forKey: .practicalSleepMinimumMinutes
        )
        try container.encode(
            reconsiderDemandingWorkBelowMinutes,
            forKey: .reconsiderDemandingWorkBelowMinutes
        )
        try container.encode(preferredWakeMinute, forKey: .preferredWakeMinute)
        try container.encode(generatedGridMinutes, forKey: .generatedGridMinutes)
    }

    public static let baseline = PlanningPolicy(
        timeZoneIdentifier: "Europe/Berlin",
        planningHorizonDays: 7,
        minimumFocusedBlockMinutes: 30,
        sleepTargetMinutes: 450,
        practicalSleepMinimumMinutes: 390,
        reconsiderDemandingWorkBelowMinutes: 360,
        preferredWakeMinute: 450,
        generatedGridMinutes: 5
    )
}
