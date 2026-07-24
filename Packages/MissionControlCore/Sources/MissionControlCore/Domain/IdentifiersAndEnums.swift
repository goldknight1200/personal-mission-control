import Foundation

public struct EntityID: Codable, Comparable, Hashable, RawRepresentable, Sendable {
    public var rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        rawValue = UUID()
    }

    public static func < (lhs: EntityID, rhs: EntityID) -> Bool {
        lhs.rawValue.uuidString < rhs.rawValue.uuidString
    }
}

public enum Weekday: Int, CaseIterable, Codable, Identifiable, Sendable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    public var id: Int { rawValue }

    public var shortName: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }
}

public enum MissionCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case work
    case football
    case gym
    case project
    case nutrition
    case household
    case personal
    case recovery
    case travel
    case preparation
    case freeTime

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .freeTime: "Free time"
        default: rawValue.capitalized
        }
    }
}

public enum MissionRigidity: String, CaseIterable, Codable, Identifiable, Sendable {
    case fixed
    case protected
    case flexible
    case deferrable
    case droppable

    public var id: String { rawValue }
}

public enum ProjectStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case activePriority
    case maintained
    case backlog

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .activePriority: "Active priority"
        case .maintained: "Maintained"
        case .backlog: "Backlog"
        }
    }
}

public enum PriorityLevel: Int, CaseIterable, Codable, Comparable, Sendable {
    case low = 1
    case normal
    case high
    case critical

    public static func < (lhs: PriorityLevel, rhs: PriorityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum EnergyDemand: String, Codable, Sendable {
    case low
    case moderate
    case high
}

public enum PhysicalLoad: String, Codable, Sendable {
    case none
    case light
    case moderate
    case heavy
}

public enum MissionStatus: String, Codable, Sendable {
    case planned
    case inProgress
    case completed
    case skipped
    case partial
}

public enum ScheduleBlockKind: String, Codable, Sendable {
    case mission
    case preparation
    case travel
    case meal
    case sleep
    case fixedCommitment
    case freeTime

    public var isTransition: Bool {
        self == .preparation || self == .travel
    }
}

public enum ChecklistKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case today
    case shopping
    case routines

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .today: "Today"
        case .shopping: "Shopping"
        case .routines: "Routines"
        }
    }
}

public enum RecurrenceFrequency: String, CaseIterable, Codable, Identifiable, Sendable {
    case daily
    case weekly
    case monthly
    case afterEvent

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .daily: "Daily cadence"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .afterEvent: "After an event"
        }
    }
}

public enum AccentName: String, CaseIterable, Codable, Identifiable, Sendable {
    case blue
    case indigo
    case orange
    case green
    case red
    case teal
    case purple
    case gray

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public struct CategoryAccentPreference: Codable, Equatable, Identifiable, Sendable {
    public var category: MissionCategory
    public var accent: AccentName

    public var id: MissionCategory { category }

    public init(category: MissionCategory, accent: AccentName) {
        self.category = category
        self.accent = accent
    }
}
