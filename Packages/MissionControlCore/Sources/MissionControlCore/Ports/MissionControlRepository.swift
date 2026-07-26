@MainActor
public protocol MissionControlRepository: AnyObject {
    func loadSnapshot() throws -> MissionControlSnapshot?
    func saveSnapshot(_ snapshot: MissionControlSnapshot) throws
    func deleteSnapshot() throws
}

public extension MissionControlRepository {
    func deleteSnapshot() throws {
        throw MissionControlRepositoryError.deletionUnavailable
    }
}

public enum MissionControlRepositoryError: Error, Equatable {
    case deletionUnavailable
}

@MainActor
public final class InMemoryMissionControlRepository: MissionControlRepository {
    private var snapshot: MissionControlSnapshot?

    public init(snapshot: MissionControlSnapshot? = nil) {
        self.snapshot = snapshot
    }

    public func loadSnapshot() throws -> MissionControlSnapshot? {
        snapshot
    }

    public func saveSnapshot(_ snapshot: MissionControlSnapshot) throws {
        self.snapshot = snapshot
    }

    public func deleteSnapshot() throws {
        snapshot = nil
    }
}
