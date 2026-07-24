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
        XCTAssertEqual(profile.planningPolicy.sleepTargetMinutes, 7 * 60 + 30)
        XCTAssertEqual(profile.planningPolicy.practicalSleepMinimumMinutes, 6 * 60 + 30)
        XCTAssertEqual(profile.planningPolicy.reconsiderDemandingWorkBelowMinutes, 6 * 60)
        XCTAssertEqual(profile.planningPolicy.generatedGridMinutes, 5)
    }

    func testHouseholdSeedCoversDocumentedCadences() {
        let titles = Set(MissionControlSeed.householdRoutines.map(\.title))

        XCTAssertEqual(
            titles,
            Set(["Light tidying", "Football laundry", "Groceries", "Meal preparation", "Take out trash", "Change bedsheets"])
        )
    }

    func testSeedInputsGenerateCurrentPlanAndSubduedTransitions() throws {
        let referenceDate = Date(timeIntervalSince1970: 7_000)
        var snapshot = MissionControlSeed.makeDemo(
            referenceDate: referenceDate
        )

        XCTAssertTrue(snapshot.scheduleBlocks.isEmpty)
        let result = SchedulingEngine().makePlan(
            input: PlanningInput(
                snapshot: snapshot,
                currentTime: referenceDate
            )
        )
        snapshot.applySchedulingResult(result)

        XCTAssertTrue(snapshot.scheduleBlocks.contains(where: { $0.kind == .preparation }))
        XCTAssertTrue(snapshot.scheduleBlocks.contains(where: { $0.kind == .travel }))
        XCTAssertNotNil(ScheduleTimeline.currentBlock(in: snapshot.scheduleBlocks, at: referenceDate))
        let football = try XCTUnwrap(
            snapshot.scheduleBlocks.first(where: {
                $0.category == .football && $0.kind == .mission
            })
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        XCTAssertEqual(calendar.component(.hour, from: football.start), 18)
        XCTAssertEqual(calendar.component(.minute, from: football.start), 30)
        let metadata = try XCTUnwrap(snapshot.schedulingPlanMetadata)
        XCTAssertEqual(
            metadata.horizonEnd.timeIntervalSince(metadata.horizonStart),
            7 * 86_400,
            accuracy: 1
        )
        let sorted = snapshot.scheduleBlocks.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.end < $1.end
        }
        for pair in zip(sorted, sorted.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                pair.1.start,
                pair.0.end,
                "\(pair.0.title) overlaps \(pair.1.title)"
            )
        }
    }
}
