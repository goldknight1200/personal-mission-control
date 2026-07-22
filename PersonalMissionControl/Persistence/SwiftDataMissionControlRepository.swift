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
        return try decoder.decode(MissionControlSnapshot.self, from: record.payload)
    }

    func saveSnapshot(_ snapshot: MissionControlSnapshot) throws {
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
        try context.save()
    }
}
