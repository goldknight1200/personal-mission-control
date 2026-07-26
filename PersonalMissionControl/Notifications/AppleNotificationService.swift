import Foundation
import MissionControlCore
import UserNotifications

private enum NotificationIdentifier {
    static let category = "MISSION_EXECUTION"
    static let alreadyStarted = "MISSION_ALREADY_STARTED"
    static let startNow = "MISSION_START_NOW"
    static let replan = "MISSION_REPLAN"
    static let skip = "MISSION_SKIP"
    static let missionID = "missionID"
    static let scheduleBlockID = "scheduleBlockID"
    static let stage = "stage"
}

@MainActor
final class AppleNotificationService: NSObject, NotificationService,
    UNUserNotificationCenterDelegate {
    var actionHandler: ((MissionNotificationAction) -> Void)? {
        didSet {
            deliverBufferedActions()
        }
    }

    private let center: UNUserNotificationCenter
    private var bufferedActions: [MissionNotificationAction] = []

    override convenience init() {
        self.init(center: .current())
    }

    init(center: UNUserNotificationCenter) {
        self.center = center
        super.init()
        center.delegate = self
        registerCategories()
    }

    func authorizationState() async -> NotificationAuthorizationState {
        let settings = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
        return Self.map(settings.authorizationStatus)
    }

    func requestAuthorization() async -> NotificationAuthorizationState {
        do {
            let _: Bool = try await withCheckedThrowingContinuation { continuation in
                center.requestAuthorization(options: [.alert, .sound, .badge]) {
                    granted,
                    error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        } catch {
            return .unavailable
        }
        return await authorizationState()
    }

    func pendingMissionNotifications() async -> [MissionNotificationRequest] {
        let pending = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
        return pending.compactMap(Self.domainRequest(from:))
    }

    func reconcile(_ reconciliation: NotificationReconciliation) async throws {
        if !reconciliation.identifiersToCancel.isEmpty {
            center.removePendingNotificationRequests(
                withIdentifiers: reconciliation.identifiersToCancel
            )
            center.removeDeliveredNotifications(
                withIdentifiers: reconciliation.identifiersToCancel
            )
        }

        for request in reconciliation.requestsToSchedule {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            content.categoryIdentifier = NotificationIdentifier.category
            content.userInfo = [
                NotificationIdentifier.missionID: request.missionID.rawValue.uuidString,
                NotificationIdentifier.scheduleBlockID: request.scheduleBlockID.rawValue.uuidString,
                NotificationIdentifier.stage: request.stage.rawValue
            ]

            let interval = max(request.fireDate.timeIntervalSinceNow, 1)
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: interval,
                repeats: false
            )
            let systemRequest = UNNotificationRequest(
                identifier: request.id,
                content: content,
                trigger: trigger
            )
            let _: Void = try await withCheckedThrowingContinuation { continuation in
                center.add(systemRequest) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func registerCategories() {
        let actions = [
            UNNotificationAction(
                identifier: NotificationIdentifier.alreadyStarted,
                title: "Already Started",
                options: [.foreground]
            ),
            UNNotificationAction(
                identifier: NotificationIdentifier.startNow,
                title: "Start Now",
                options: [.foreground]
            ),
            UNNotificationAction(
                identifier: NotificationIdentifier.replan,
                title: "Replan",
                options: [.foreground]
            ),
            UNNotificationAction(
                identifier: NotificationIdentifier.skip,
                title: "Skip",
                options: [.foreground]
            )
        ]
        let category = UNNotificationCategory(
            identifier: NotificationIdentifier.category,
            actions: actions,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    private func receive(_ action: MissionNotificationAction) {
        guard let actionHandler else {
            bufferedActions.append(action)
            return
        }
        actionHandler(action)
    }

    private func deliverBufferedActions() {
        guard let actionHandler, !bufferedActions.isEmpty else { return }
        let actions = bufferedActions
        bufferedActions.removeAll()
        actions.forEach(actionHandler)
    }

    nonisolated private static func domainRequest(
        from request: UNNotificationRequest
    ) -> MissionNotificationRequest? {
        guard
            request.identifier.hasPrefix(NotificationSchedulePlanner.identifierPrefix),
            let missionID = entityID(
                request.content.userInfo[NotificationIdentifier.missionID] as? String
            ),
            let blockID = entityID(
                request.content.userInfo[NotificationIdentifier.scheduleBlockID] as? String
            ),
            let stageValue = request.content.userInfo[NotificationIdentifier.stage] as? String,
            let stage = MissionNotificationStage(rawValue: stageValue),
            let fireDate = nextTriggerDate(for: request.trigger)
        else {
            return nil
        }
        return MissionNotificationRequest(
            id: request.identifier,
            missionID: missionID,
            scheduleBlockID: blockID,
            stage: stage,
            fireDate: fireDate,
            title: request.content.title,
            body: request.content.body
        )
    }

    nonisolated private static func nextTriggerDate(
        for trigger: UNNotificationTrigger?
    ) -> Date? {
        if let trigger = trigger as? UNTimeIntervalNotificationTrigger {
            return trigger.nextTriggerDate()
        }
        if let trigger = trigger as? UNCalendarNotificationTrigger {
            return trigger.nextTriggerDate()
        }
        return nil
    }

    nonisolated private static func action(
        from response: UNNotificationResponse,
        receivedAt: Date
    ) -> MissionNotificationAction? {
        let kind: MissionNotificationActionKind
        switch response.actionIdentifier {
        case NotificationIdentifier.alreadyStarted:
            kind = .alreadyStarted
        case NotificationIdentifier.startNow:
            kind = .startNow
        case NotificationIdentifier.replan:
            kind = .replan
        case NotificationIdentifier.skip:
            kind = .skip
        default:
            return nil
        }

        let userInfo = response.notification.request.content.userInfo
        guard
            let missionID = entityID(userInfo[NotificationIdentifier.missionID] as? String),
            let blockID = entityID(userInfo[NotificationIdentifier.scheduleBlockID] as? String),
            let stageValue = userInfo[NotificationIdentifier.stage] as? String,
            let stage = MissionNotificationStage(rawValue: stageValue)
        else {
            return nil
        }
        return MissionNotificationAction(
            kind: kind,
            missionID: missionID,
            scheduleBlockID: blockID,
            notificationStage: stage,
            receivedAt: receivedAt
        )
    }

    nonisolated private static func entityID(_ value: String?) -> EntityID? {
        guard let value, let uuid = UUID(uuidString: value) else { return nil }
        return EntityID(rawValue: uuid)
    }

    nonisolated private static func map(
        _ status: UNAuthorizationStatus
    ) -> NotificationAuthorizationState {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional, .ephemeral: .provisional
        @unknown default: .unavailable
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = Self.action(from: response, receivedAt: Date())
        Task { @MainActor [weak self] in
            if let action {
                self?.receive(action)
            }
            completionHandler()
        }
    }
}
