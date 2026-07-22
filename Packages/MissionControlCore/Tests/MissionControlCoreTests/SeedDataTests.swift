import Foundation
import XCTest
@testable import MissionControlCore

final class SeedDataTests: XCTestCase {
    func testSeedMatchesEditablePersonalBaseline() {
        let snapshot = MissionControlSeed.makeDemo(referenceDate: Date(timeIntervalSince1970: 6_000))
        let profile = snapshot.profile

        XCTAssertEqual(profile.timeZoneIdentifier, "Europe/Berlin")
        XCTAssertTrue(profile.uses24HourTime)
        XCTAssertFalse(profile.hasRegularUniversityLectures)
        XCTAssertEqual(profile.workPattern.typicalWeekdays, [.monday, .wednesday, .friday, .saturday])
        XCTAssertEqual(profile.footballPattern.trainingWeekdays, [.tuesday, .thursday])
        XCTAssertEqual(profile.footballPattern.historicalTrainingStartMinute, 18 * 60 + 30)
        XCTAssertTrue(profile.footballPattern.historicalTimeIsConfigurable)
        XCTAssertEqual(profile.gymWeeklyTarget, WeeklyTarget(minimum: 4, preferred: 5))
        XCTAssertEqual(profile.transitions.gymTravelEachWayMinutes, 16)
        XCTAssertEqual(profile.nutritionTargets.approximateCalories, 3_400)
        XCTAssertEqual(profile.nutritionTargets.approximateProteinGrams, 180)
        XCTAssertEqual(profile.nutritionTargets.substantialMeals, 3)
    }

    func testHouseholdSeedCoversDocumentedCadences() {
        let titles = Set(MissionControlSeed.householdRoutines.map(\.title))

        XCTAssertEqual(
            titles,
            Set(["Light tidying", "Football laundry", "Groceries", "Meal preparation", "Take out trash", "Change bedsheets"])
        )
    }

    func testDemoScheduleIncludesSubduedTransitionKinds() {
        let referenceDate = Date(timeIntervalSince1970: 7_000)
        let snapshot = MissionControlSeed.makeDemo(referenceDate: referenceDate)

        XCTAssertTrue(snapshot.scheduleBlocks.contains(where: { $0.kind == .preparation }))
        XCTAssertTrue(snapshot.scheduleBlocks.contains(where: { $0.kind == .travel }))
        XCTAssertNotNil(ScheduleTimeline.currentBlock(in: snapshot.scheduleBlocks, at: referenceDate))
    }
}
