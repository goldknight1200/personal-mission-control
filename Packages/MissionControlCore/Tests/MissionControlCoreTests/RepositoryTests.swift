import Foundation
import XCTest
@testable import MissionControlCore

final class RepositoryTests: XCTestCase {
    @MainActor
    func testInMemoryRepositoryRoundTrip() throws {
        let repository = InMemoryMissionControlRepository()
        let snapshot = MissionControlSeed.makeDemo(referenceDate: Date(timeIntervalSince1970: 5_000))

        XCTAssertNil(try repository.loadSnapshot())
        try repository.saveSnapshot(snapshot)

        XCTAssertEqual(try repository.loadSnapshot(), snapshot)
    }
}
