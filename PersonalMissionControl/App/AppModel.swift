import Foundation
import MissionControlCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: MissionControlSnapshot
    @Published private(set) var persistenceNotice: String?

    private let repository: any MissionControlRepository
    private let usesDurableStorage: Bool

    init(
        repository: any MissionControlRepository,
        referenceDate: Date = Date(),
        startupNotice: String? = nil,
        usesDurableStorage: Bool = true
    ) {
        self.repository = repository
        self.usesDurableStorage = usesDurableStorage
        persistenceNotice = startupNotice

        do {
            if let stored = try repository.loadSnapshot() {
                snapshot = stored
            } else {
                let seed = MissionControlSeed.makeDemo(referenceDate: referenceDate)
                snapshot = seed
                try repository.saveSnapshot(seed)
            }
        } catch {
            snapshot = MissionControlSeed.makeDemo(referenceDate: referenceDate)
            persistenceNotice = "Local persistence could not be opened. Changes will last for this session."
        }
    }

    func completeMission(_ id: EntityID, at date: Date = Date(), plannedDurationMinutes: Int) {
        guard snapshot.mission(withID: id)?.status != .completed else { return }
        snapshot.completeMission(
            id: id,
            at: date,
            actualDurationMinutes: max(plannedDurationMinutes, 1)
        )
        persist()
    }

    func updateActualDuration(for missionID: EntityID, minutes: Int) {
        snapshot.updateActualDuration(for: missionID, minutes: minutes)
        persist()
    }

    func toggleMissionStep(missionID: EntityID, stepID: EntityID) {
        snapshot.toggleMissionStep(missionID: missionID, stepID: stepID)
        persist()
    }

    func toggleChecklistItem(checklistID: EntityID, itemID: EntityID) {
        snapshot.toggleChecklistItem(checklistID: checklistID, itemID: itemID)
        persist()
    }

    func updateProfile(_ profile: UserProfile) {
        snapshot.profile = profile
        persist()
    }

    func updateProject(_ project: Project) {
        snapshot.updateProject(project)
        persist()
    }

    func updateRoutine(_ routine: Routine) {
        snapshot.updateRoutine(routine)
        persist()
    }

    private func persist() {
        do {
            try repository.saveSnapshot(snapshot)
            if usesDurableStorage {
                persistenceNotice = nil
            }
        } catch {
            persistenceNotice = "This change is visible now but could not be saved locally."
        }
    }
}
