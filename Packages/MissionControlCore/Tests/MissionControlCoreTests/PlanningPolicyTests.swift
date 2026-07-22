import XCTest
@testable import MissionControlCore

final class PlanningPolicyTests: XCTestCase {
    func testBaselineMatchesEditableProductSeed() {
        let policy = PlanningPolicy.baseline

        XCTAssertEqual(policy.timeZoneIdentifier, "Europe/Berlin")
        XCTAssertEqual(policy.planningHorizonDays, 7)
        XCTAssertEqual(policy.minimumFocusedBlockMinutes, 30)
    }

    func testCustomPolicyIsNotCoupledToBaseline() {
        let policy = PlanningPolicy(
            timeZoneIdentifier: "America/New_York",
            planningHorizonDays: 5,
            minimumFocusedBlockMinutes: 45
        )

        XCTAssertNotEqual(policy, .baseline)
        XCTAssertEqual(policy.planningHorizonDays, 5)
    }
}
