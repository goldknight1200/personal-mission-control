@MainActor
public protocol NotificationService: AnyObject {
    var actionHandler: ((MissionNotificationAction) -> Void)? { get set }

    func authorizationState() async -> NotificationAuthorizationState
    func requestAuthorization() async -> NotificationAuthorizationState
    func pendingMissionNotifications() async -> [MissionNotificationRequest]
    func reconcile(_ reconciliation: NotificationReconciliation) async throws
}

@MainActor
public final class UnavailableNotificationService: NotificationService {
    public var actionHandler: ((MissionNotificationAction) -> Void)?

    public init() {}

    public func authorizationState() async -> NotificationAuthorizationState {
        .unavailable
    }

    public func requestAuthorization() async -> NotificationAuthorizationState {
        .unavailable
    }

    public func pendingMissionNotifications() async -> [MissionNotificationRequest] {
        []
    }

    public func reconcile(_ reconciliation: NotificationReconciliation) async throws {}
}
