import MissionControlCore
import SwiftUI

@MainActor
@main
struct PersonalMissionControlApp: App {
    @StateObject private var appModel: AppModel

    init() {
        let notificationService = AppleNotificationService()
        let calendarService = AppleCalendarService()
        let healthService = HealthKitSleepService()
        let iCalService = URLSessionICalSubscriptionService()
        let secretStore = KeychainSecretStore()
        let imageRecognizer = VisionWorkShiftImageTextRecognizer()
        let aiProviderFactory:
            (AIIntegrationSettings) -> (any AICommandProvider)? = {
                settings in
                CustomJSONAIProvider(
                    settings: settings,
                    secretStore: secretStore
                )
            }
        let model: AppModel
        do {
            let repository = try SwiftDataMissionControlRepository()
            model = AppModel(
                repository: repository,
                notificationService: notificationService,
                calendarProvider: calendarService,
                healthProvider: healthService,
                iCalProvider: iCalService,
                shiftImageRecognizer: imageRecognizer,
                secretStore: secretStore,
                aiProviderFactory: aiProviderFactory
            )
        } catch {
            let repository = InMemoryMissionControlRepository()
            model = AppModel(
                repository: repository,
                startupNotice: "Local storage is unavailable. Changes will last for this session.",
                usesDurableStorage: false,
                notificationService: notificationService,
                calendarProvider: calendarService,
                healthProvider: healthService,
                iCalProvider: iCalService,
                shiftImageRecognizer: imageRecognizer,
                secretStore: secretStore,
                aiProviderFactory: aiProviderFactory
            )
        }
        _appModel = StateObject(wrappedValue: model)
        MissionControlIntentBridge.shared.configure(model: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: appModel)
        }
    }
}
