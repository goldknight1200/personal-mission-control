import Foundation

public protocol CalendarProviding: AnyObject {
    var changeHandler: (() -> Void)? { get set }

    func authorizationState(
        for accessLevel: CalendarAccessLevel
    ) async -> PlatformAuthorizationState

    func requestAccess(
        _ accessLevel: CalendarAccessLevel
    ) async -> PlatformAuthorizationState

    func calendars() async -> [CalendarDescriptor]

    func events(
        in interval: DateInterval,
        calendarIDs: [String]
    ) async throws -> [ExternalCalendarEvent]

    func upsertAppOwnedEvents(
        _ events: [CalendarEventWrite]
    ) async throws -> [CalendarEventWriteResult]

    func deleteAppOwnedEvent(
        externalIdentifier: String
    ) async throws
}

public protocol HealthContextProviding: AnyObject {
    func availabilityState() async -> PlatformAuthorizationState
    func requestSleepReadAccess() async -> PlatformAuthorizationState
    func sleepRecoverySample(
        endingAt date: Date
    ) async throws -> SleepRecoverySample?
}

public protocol ICalSubscriptionProviding: AnyObject {
    func events(
        for subscription: ICalSubscription,
        in interval: DateInterval,
        fetchedAt: Date,
        timeZoneIdentifier: String
    ) async throws -> ExternalEventBatch
}

public final class UnavailableCalendarProvider: CalendarProviding {
    public var changeHandler: (() -> Void)?

    public init() {}

    public func authorizationState(
        for accessLevel: CalendarAccessLevel
    ) async -> PlatformAuthorizationState {
        .unavailable
    }

    public func requestAccess(
        _ accessLevel: CalendarAccessLevel
    ) async -> PlatformAuthorizationState {
        .unavailable
    }

    public func calendars() async -> [CalendarDescriptor] { [] }

    public func events(
        in interval: DateInterval,
        calendarIDs: [String]
    ) async throws -> [ExternalCalendarEvent] {
        []
    }

    public func upsertAppOwnedEvents(
        _ events: [CalendarEventWrite]
    ) async throws -> [CalendarEventWriteResult] {
        []
    }

    public func deleteAppOwnedEvent(
        externalIdentifier: String
    ) async throws {}
}

public final class UnavailableHealthContextProvider: HealthContextProviding {
    public init() {}

    public func availabilityState() async -> PlatformAuthorizationState {
        .unavailable
    }

    public func requestSleepReadAccess() async -> PlatformAuthorizationState {
        .unavailable
    }

    public func sleepRecoverySample(
        endingAt date: Date
    ) async throws -> SleepRecoverySample? {
        nil
    }
}

public final class UnavailableICalSubscriptionProvider:
    ICalSubscriptionProviding
{
    public init() {}

    public func events(
        for subscription: ICalSubscription,
        in interval: DateInterval,
        fetchedAt: Date,
        timeZoneIdentifier: String
    ) async throws -> ExternalEventBatch {
        throw PlatformIntegrationError.unavailable
    }
}
