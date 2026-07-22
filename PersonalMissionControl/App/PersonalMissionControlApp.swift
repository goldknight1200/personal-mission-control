import MissionControlCore
import SwiftUI

@MainActor
@main
struct PersonalMissionControlApp: App {
    @StateObject private var appModel: AppModel

    init() {
        do {
            let repository = try SwiftDataMissionControlRepository()
            _appModel = StateObject(wrappedValue: AppModel(repository: repository))
        } catch {
            let repository = InMemoryMissionControlRepository()
            _appModel = StateObject(
                wrappedValue: AppModel(
                    repository: repository,
                    startupNotice: "Local storage is unavailable. Changes will last for this session.",
                    usesDurableStorage: false
                )
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: appModel)
        }
    }
}
