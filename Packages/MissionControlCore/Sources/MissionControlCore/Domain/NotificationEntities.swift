import Foundation

public enum MissionNotificationStage: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case preStart
    case start
    case late15
    case late30

    public var minuteOffset: Int {
        switch self {
        case .preStart: -15
        case .start: 0
        case .late15: 15
        case .late30: 30
        }
    }
}

public enum MissionNotificationActionKind: String, CaseIterable, Codable, Equatable, Sendable {
    case alreadyStarted
    case startNow
    case replan
    case skip
}

public struct MissionNotificationRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var missionID: EntityID
    public var scheduleBlockID: EntityID
    public var stage: MissionNotificationStage
    public var fireDate: Date
    public var title: String
    public var body: String

    public init(
        id: String,
        missionID: EntityID,
        scheduleBlockID: EntityID,
        stage: MissionNotificationStage,
        fireDate: Date,
        title: String,
        body: String
    ) {
        self.id = id
        self.missionID = missionID
        self.scheduleBlockID = scheduleBlockID
        self.stage = stage
        self.fireDate = fireDate
        self.title = title
        self.body = body
    }
}

public struct NotificationReconciliation: Equatable, Sendable {
    public var identifiersToCancel: [String]
    public var requestsToSchedule: [MissionNotificationRequest]

    public init(
        identifiersToCancel: [String],
        requestsToSchedule: [MissionNotificationRequest]
    ) {
        self.identifiersToCancel = identifiersToCancel
        self.requestsToSchedule = requestsToSchedule
    }
}

public struct MissionNotificationAction: Equatable, Sendable {
    public var kind: MissionNotificationActionKind
    public var missionID: EntityID
    public var scheduleBlockID: EntityID
    public var notificationStage: MissionNotificationStage
    public var receivedAt: Date

    public init(
        kind: MissionNotificationActionKind,
        missionID: EntityID,
        scheduleBlockID: EntityID,
        notificationStage: MissionNotificationStage,
        receivedAt: Date
    ) {
        self.kind = kind
        self.missionID = missionID
        self.scheduleBlockID = scheduleBlockID
        self.notificationStage = notificationStage
        self.receivedAt = receivedAt
    }
}

public enum NotificationAuthorizationState: String, Codable, Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case unavailable
}
