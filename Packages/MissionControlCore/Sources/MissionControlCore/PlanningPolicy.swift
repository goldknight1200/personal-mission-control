/// Editable planning defaults shared by the app and deterministic core.
///
/// These values are seed configuration, not a hard-coded user identity. The
/// persistence adapter stores the user's edited copy and future planning use
/// cases receive that value through the domain snapshot.
public struct PlanningPolicy: Codable, Equatable, Sendable {
    public var timeZoneIdentifier: String
    public var planningHorizonDays: Int
    public var minimumFocusedBlockMinutes: Int

    public init(
        timeZoneIdentifier: String,
        planningHorizonDays: Int,
        minimumFocusedBlockMinutes: Int
    ) {
        precondition(!timeZoneIdentifier.isEmpty, "A time-zone identifier is required")
        precondition(planningHorizonDays > 0, "Planning horizon must be positive")
        precondition(minimumFocusedBlockMinutes > 0, "Minimum block must be positive")

        self.timeZoneIdentifier = timeZoneIdentifier
        self.planningHorizonDays = planningHorizonDays
        self.minimumFocusedBlockMinutes = minimumFocusedBlockMinutes
    }

    public static let baseline = PlanningPolicy(
        timeZoneIdentifier: "Europe/Berlin",
        planningHorizonDays: 7,
        minimumFocusedBlockMinutes: 30
    )
}
