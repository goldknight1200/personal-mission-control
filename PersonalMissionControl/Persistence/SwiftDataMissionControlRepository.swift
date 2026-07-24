import Foundation
import MissionControlCore
import SwiftData

@Model
final class MissionControlStateRecord {
    @Attribute(.unique) var key: String
    var schemaVersion: Int
    var payload: Data

    init(
        key: String = "primary",
        schemaVersion: Int = MissionControlSnapshot.currentSchemaVersion,
        payload: Data
    ) {
        self.key = key
        self.schemaVersion = schemaVersion
        self.payload = payload
    }
}

enum MissionControlPersistenceError: Error, Equatable {
    case unsupportedSchema(found: Int, supported: Int)
    case invalidSnapshot(String)
}

@MainActor
final class SwiftDataMissionControlRepository: MissionControlRepository {
    private let container: ModelContainer
    private let context: ModelContext
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(container: ModelContainer) {
        self.container = container
        context = ModelContext(container)
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    convenience init(isStoredInMemoryOnly: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: isStoredInMemoryOnly)
        let container = try ModelContainer(
            for: MissionControlStateRecord.self,
            configurations: configuration
        )
        self.init(container: container)
    }

    func loadSnapshot() throws -> MissionControlSnapshot? {
        var descriptor = FetchDescriptor<MissionControlStateRecord>(
            predicate: #Predicate { $0.key == "primary" }
        )
        descriptor.fetchLimit = 1

        guard let record = try context.fetch(descriptor).first else {
            return nil
        }
        guard record.schemaVersion <= MissionControlSnapshot.currentSchemaVersion else {
            throw MissionControlPersistenceError.unsupportedSchema(
                found: record.schemaVersion,
                supported: MissionControlSnapshot.currentSchemaVersion
            )
        }
        var snapshot = try decoder.decode(MissionControlSnapshot.self, from: record.payload)
        try validate(snapshot)
        if record.schemaVersion < MissionControlSnapshot.currentSchemaVersion {
            snapshot.schemaVersion = MissionControlSnapshot.currentSchemaVersion
            record.schemaVersion = MissionControlSnapshot.currentSchemaVersion
            record.payload = try encoder.encode(snapshot)
            try saveContextOrRollback()
        }
        return snapshot
    }

    func saveSnapshot(_ snapshot: MissionControlSnapshot) throws {
        try validate(snapshot)
        let payload = try encoder.encode(snapshot)
        var descriptor = FetchDescriptor<MissionControlStateRecord>(
            predicate: #Predicate { $0.key == "primary" }
        )
        descriptor.fetchLimit = 1

        if let record = try context.fetch(descriptor).first {
            record.schemaVersion = snapshot.schemaVersion
            record.payload = payload
        } else {
            context.insert(
                MissionControlStateRecord(
                    schemaVersion: snapshot.schemaVersion,
                    payload: payload
                )
            )
        }
        try saveContextOrRollback()
    }

    private func validate(_ snapshot: MissionControlSnapshot) throws {
        guard
            snapshot.schemaVersion > 0,
            snapshot.schemaVersion
                <= MissionControlSnapshot.currentSchemaVersion
        else {
            throw MissionControlPersistenceError.invalidSnapshot(
                "Snapshot schema version is outside the supported range."
            )
        }
        guard TimeZone(identifier: snapshot.profile.timeZoneIdentifier) != nil
        else {
            throw MissionControlPersistenceError.invalidSnapshot(
                "Profile timezone is invalid."
            )
        }
        guard snapshot.missions.allSatisfy({
            $0.estimatedDurationMinutes > 0
                && $0.minimumUsefulBlockMinutes > 0
                && ($0.actualDurationMinutes ?? 0) >= 0
                && $0.preparationMinutes >= 0
                && $0.travelBeforeMinutes >= 0
                && $0.travelAfterMinutes >= 0
                && valid($0.dueWindow)
        }) else {
            throw MissionControlPersistenceError.invalidSnapshot(
                "A mission contains an invalid duration or due window."
            )
        }
        guard snapshot.scheduleBlocks.allSatisfy({
            $0.end > $0.start
        }) else {
            throw MissionControlPersistenceError.invalidSnapshot(
                "A schedule block has a non-positive duration."
            )
        }
        guard snapshot.fixedCommitments.allSatisfy({
            $0.end > $0.start
        }) else {
            throw MissionControlPersistenceError.invalidSnapshot(
                "A fixed commitment has a non-positive duration."
            )
        }
        guard snapshot.routines.allSatisfy({
            $0.recurrence.interval > 0
                && $0.estimatedDurationMinutes > 0
                && $0.dueWindowMinutes >= 0
        }) else {
            throw MissionControlPersistenceError.invalidSnapshot(
                "A routine contains an invalid duration or recurrence."
            )
        }
        guard snapshot.completions.allSatisfy({
            $0.plannedDurationMinutes > 0
                && $0.actualDurationMinutes >= 0
        }) else {
            throw MissionControlPersistenceError.invalidSnapshot(
                "Completion history contains an invalid duration."
            )
        }
        guard
            Set(snapshot.missions.map(\.id)).count
                == snapshot.missions.count,
            Set(snapshot.scheduleBlocks.map(\.id)).count
                == snapshot.scheduleBlocks.count
        else {
            throw MissionControlPersistenceError.invalidSnapshot(
                "Authoritative entity identifiers are duplicated."
            )
        }
        if let metadata = snapshot.schedulingPlanMetadata {
            guard
                metadata.horizonEnd > metadata.horizonStart,
                metadata.gridMinutes > 0
            else {
                throw MissionControlPersistenceError.invalidSnapshot(
                    "Scheduling metadata is invalid."
                )
            }
        }
    }

    private func valid(_ dueWindow: DueWindow?) -> Bool {
        guard
            let earliest = dueWindow?.earliest,
            let latest = dueWindow?.latest
        else {
            return true
        }
        return earliest <= latest
    }

    private func saveContextOrRollback() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
