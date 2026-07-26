import Foundation

public enum PlatformAuthorizationState:
    String,
    Codable,
    Equatable,
    Sendable
{
    case disabled
    case notDetermined
    case requested
    case authorized
    case limited
    case denied
    case restricted
    case unavailable
}

public enum CalendarIntegrationMode:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case disabled
    case createOnly
    case importAndSync

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .disabled: "Off"
        case .createOnly: "Add new app events only"
        case .importAndSync: "Import and sync"
        }
    }
}

public enum CalendarAccessLevel: String, Codable, Equatable, Sendable {
    case writeOnly
    case full
}

public struct CalendarDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var sourceTitle: String
    public var colorHex: String?
    public var allowsContentModifications: Bool

    public init(
        id: String,
        title: String,
        sourceTitle: String,
        colorHex: String? = nil,
        allowsContentModifications: Bool
    ) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        self.colorHex = colorHex
        self.allowsContentModifications = allowsContentModifications
    }
}

public struct CalendarIntegrationSettings: Codable, Equatable, Sendable {
    public var mode: CalendarIntegrationMode
    public var importsCalendarIDs: [String]
    public var exportsLocalCommitments: Bool
    public var destinationCalendarID: String?
    public var lastSyncAt: Date?
    public var lastError: String?

    public init(
        mode: CalendarIntegrationMode = .disabled,
        importsCalendarIDs: [String] = [],
        exportsLocalCommitments: Bool = false,
        destinationCalendarID: String? = nil,
        lastSyncAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.mode = mode
        self.importsCalendarIDs = importsCalendarIDs
        self.exportsLocalCommitments = exportsLocalCommitments
        self.destinationCalendarID = destinationCalendarID
        self.lastSyncAt = lastSyncAt
        self.lastError = lastError
    }
}

public struct HealthIntegrationSettings: Codable, Equatable, Sendable {
    public var sleepReadEnabled: Bool
    public var lastRefreshAt: Date?
    public var lastError: String?

    public init(
        sleepReadEnabled: Bool = false,
        lastRefreshAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.sleepReadEnabled = sleepReadEnabled
        self.lastRefreshAt = lastRefreshAt
        self.lastError = lastError
    }
}

public enum ExternalScheduleSourceKind:
    String,
    Codable,
    Equatable,
    Sendable
{
    case eventKit
    case iCal
}

public struct ExternalCalendarItem:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public var id: EntityID
    public var sourceKind: ExternalScheduleSourceKind
    public var sourceIdentifier: String
    public var externalIdentifier: String
    public var linkedFixedCommitmentID: EntityID?
    public var isAppOwned: Bool
    public var lastSeenAt: Date
    public var lastModifiedAt: Date?

    public init(
        id: EntityID = EntityID(),
        sourceKind: ExternalScheduleSourceKind,
        sourceIdentifier: String,
        externalIdentifier: String,
        linkedFixedCommitmentID: EntityID? = nil,
        isAppOwned: Bool = false,
        lastSeenAt: Date,
        lastModifiedAt: Date? = nil
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.sourceIdentifier = sourceIdentifier
        self.externalIdentifier = externalIdentifier
        self.linkedFixedCommitmentID = linkedFixedCommitmentID
        self.isAppOwned = isAppOwned
        self.lastSeenAt = lastSeenAt
        self.lastModifiedAt = lastModifiedAt
    }

    public var reconciliationKey: String {
        "\(sourceKind.rawValue)|\(sourceIdentifier)|\(externalIdentifier)"
    }
}

public struct ICalSubscription:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public var id: EntityID
    public var title: String
    public var urlString: String
    public var isEnabled: Bool
    public var isFootballFixtures: Bool
    public var lastSyncAt: Date?
    public var lastError: String?

    public init(
        id: EntityID = EntityID(),
        title: String,
        urlString: String,
        isEnabled: Bool = true,
        isFootballFixtures: Bool = false,
        lastSyncAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.isEnabled = isEnabled
        self.isFootballFixtures = isFootballFixtures
        self.lastSyncAt = lastSyncAt
        self.lastError = lastError
    }
}

public struct ExternalCalendarEvent: Equatable, Sendable {
    public var sourceKind: ExternalScheduleSourceKind
    public var sourceIdentifier: String
    public var externalIdentifier: String
    public var title: String
    public var category: MissionCategory
    public var start: Date
    public var end: Date
    public var location: String?
    public var isAllDay: Bool
    public var isFootballMatch: Bool
    public var isAppOwned: Bool
    public var isCancelled: Bool
    public var lastModifiedAt: Date?

    public init(
        sourceKind: ExternalScheduleSourceKind,
        sourceIdentifier: String,
        externalIdentifier: String,
        title: String,
        category: MissionCategory = .personal,
        start: Date,
        end: Date,
        location: String? = nil,
        isAllDay: Bool = false,
        isFootballMatch: Bool = false,
        isAppOwned: Bool = false,
        isCancelled: Bool = false,
        lastModifiedAt: Date? = nil
    ) {
        self.sourceKind = sourceKind
        self.sourceIdentifier = sourceIdentifier
        self.externalIdentifier = externalIdentifier
        self.title = title
        self.category = category
        self.start = start
        self.end = end
        self.location = location
        self.isAllDay = isAllDay
        self.isFootballMatch = isFootballMatch
        self.isAppOwned = isAppOwned
        self.isCancelled = isCancelled
        self.lastModifiedAt = lastModifiedAt
    }

    public var reconciliationKey: String {
        "\(sourceKind.rawValue)|\(sourceIdentifier)|\(externalIdentifier)"
    }
}

public struct ExternalEventBatch: Equatable, Sendable {
    public var sourceKind: ExternalScheduleSourceKind
    public var sourceIdentifier: String
    public var coveredInterval: DateInterval
    public var events: [ExternalCalendarEvent]
    public var fetchedAt: Date

    public init(
        sourceKind: ExternalScheduleSourceKind,
        sourceIdentifier: String,
        coveredInterval: DateInterval,
        events: [ExternalCalendarEvent],
        fetchedAt: Date
    ) {
        self.sourceKind = sourceKind
        self.sourceIdentifier = sourceIdentifier
        self.coveredInterval = coveredInterval
        self.events = events
        self.fetchedAt = fetchedAt
    }
}

public struct CalendarEventWrite: Equatable, Sendable {
    public var localFixedCommitmentID: EntityID
    public var externalIdentifier: String?
    public var title: String
    public var start: Date
    public var end: Date
    public var location: String?
    public var destinationCalendarID: String?

    public init(
        localFixedCommitmentID: EntityID,
        externalIdentifier: String? = nil,
        title: String,
        start: Date,
        end: Date,
        location: String? = nil,
        destinationCalendarID: String? = nil
    ) {
        self.localFixedCommitmentID = localFixedCommitmentID
        self.externalIdentifier = externalIdentifier
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.destinationCalendarID = destinationCalendarID
    }
}

public struct CalendarEventWriteResult: Equatable, Sendable {
    public var localFixedCommitmentID: EntityID
    public var sourceIdentifier: String
    public var externalIdentifier: String
    public var lastModifiedAt: Date?

    public init(
        localFixedCommitmentID: EntityID,
        sourceIdentifier: String,
        externalIdentifier: String,
        lastModifiedAt: Date? = nil
    ) {
        self.localFixedCommitmentID = localFixedCommitmentID
        self.sourceIdentifier = sourceIdentifier
        self.externalIdentifier = externalIdentifier
        self.lastModifiedAt = lastModifiedAt
    }
}

public struct SleepRecoverySample: Equatable, Sendable {
    public var sleepWindowStart: Date
    public var sleepWindowEnd: Date
    public var asleepMinutes: Int

    public init(
        sleepWindowStart: Date,
        sleepWindowEnd: Date,
        asleepMinutes: Int
    ) {
        self.sleepWindowStart = sleepWindowStart
        self.sleepWindowEnd = sleepWindowEnd
        self.asleepMinutes = asleepMinutes
    }
}
