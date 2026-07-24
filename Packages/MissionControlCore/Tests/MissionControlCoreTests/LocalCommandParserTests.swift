import Foundation
import XCTest
@testable import MissionControlCore

final class LocalCommandParserTests: XCTestCase {
    private let parser = LocalCommandParser()

    func testLateWakeRequestsConfirmedDayReplan() {
        let command = parse("I woke up late; replan my day.")

        XCTAssertEqual(command.detectedIntents.map(\.kind), [.replanDay])
        XCTAssertEqual(command.confidence, 0.99, accuracy: 0.001)
        XCTAssertEqual(command.proposedMutations.count, 1)
        XCTAssertTrue(command.confirmationRequirement.isRequired)
        XCTAssertNotNil(command.affectedScheduleRange.start)
        XCTAssertNotNil(command.affectedScheduleRange.end)
    }

    func testAlreadyStartedResolvesMissionAndMinutes() {
        let command = parse("I already started the gym 20 minutes ago.")

        XCTAssertEqual(command.detectedIntents.map(\.kind), [.markMissionStarted])
        guard case let .markMissionStarted(missionID, missionName, minutesAgo) = command.proposedMutations.first else {
            return XCTFail("Expected a mission-start mutation")
        }
        XCTAssertNotNil(missionID)
        XCTAssertEqual(missionName, "Approved gym session")
        XCTAssertEqual(minutesAgo, 20)
        XCTAssertFalse(command.confirmationRequirement.isRequired)
    }

    func testChecklistCommandsRemainLowRiskAndPreserveUserCasing() {
        let today = parse("Add Reply to the University Email to today.")
        let shopping = parse("Add Oat Milk to my shopping list.")

        XCTAssertEqual(today.detectedIntents.map(\.kind), [.addTodayItem])
        XCTAssertEqual(
            today.proposedMutations,
            [.addChecklistItem(kind: .today, title: "Reply to the University Email")]
        )
        XCTAssertFalse(today.confirmationRequirement.isRequired)

        XCTAssertEqual(shopping.detectedIntents.map(\.kind), [.addShoppingItem])
        XCTAssertEqual(
            shopping.proposedMutations,
            [.addChecklistItem(kind: .shopping, title: "Oat Milk")]
        )
        XCTAssertFalse(shopping.confirmationRequirement.isRequired)
    }

    func testInventoryDepletionProducesExplicitInventoryMutation() {
        let command = parse("I finished the last milk.")

        XCTAssertEqual(command.detectedIntents.map(\.kind), [.emptyInventoryItem])
        XCTAssertEqual(command.proposedMutations, [.markInventoryEmpty(name: "milk")])
    }

    func testMoveAndProtectedSkipRequireConsequentialConfirmation() {
        let move = parse("Move the gym.")
        let replan = parse("Replan the gym.")
        let skip = parse("I’m skipping the gym.")

        XCTAssertEqual(move.detectedIntents.map(\.kind), [.moveMission])
        XCTAssertTrue(move.confirmationRequirement.isRequired)
        XCTAssertEqual(replan.detectedIntents.map(\.kind), [.moveMission])
        XCTAssertTrue(replan.confirmationRequirement.isRequired)
        XCTAssertEqual(skip.detectedIntents.map(\.kind), [.skipMission])
        XCTAssertTrue(skip.confirmationRequirement.isRequired)
        XCTAssertTrue(skip.warnings.contains(where: { $0.severity == .consequence }))
    }

    func testExplicitWorkShiftParsesDateAndAlwaysRequiresConfirmation() throws {
        let command = parse("Work shift on 2026-07-28 from 12:00 to 20:00.")
        let mutation = try XCTUnwrap(command.proposedMutations.first)
        guard case let .addWorkShift(shift) = mutation else {
            return XCTFail("Expected work shift")
        }

        let calendar = berlinCalendar
        XCTAssertEqual(calendar.component(.year, from: shift.start), 2026)
        XCTAssertEqual(calendar.component(.month, from: shift.start), 7)
        XCTAssertEqual(calendar.component(.day, from: shift.start), 28)
        XCTAssertEqual(calendar.component(.hour, from: shift.start), 12)
        XCTAssertEqual(calendar.component(.hour, from: shift.end), 20)
        XCTAssertTrue(command.confirmationRequirement.isRequired)
    }

    func testMultipleShiftsProduceStructuredWarning() {
        let command = parse(
            "Work shift on 2026-07-28 from 12:00 to 20:00; "
                + "work shift on 2026-07-28 from 18:00 to 22:00."
        )

        XCTAssertEqual(command.proposedMutations.count, 2)
        XCTAssertTrue(command.confirmationRequirement.isRequired)
        XCTAssertTrue(command.warnings.contains(where: {
            $0.message.contains("Multiple shifts")
        }))
        XCTAssertTrue(command.warnings.contains(where: {
            $0.message.contains("overlap each other")
        }))
    }

    func testInferredShiftYearAndFixedCommitmentConflictAreExplicit() {
        let inferredYear = parse("Work shift on 28 July from 12:00 to 20:00.")
        let conflict = parse(
            "Work shift on 2026-07-25 from 10:00 to 12:00.",
            fixedCommitments: [
                FixedCommitment(
                    title: "Existing appointment",
                    category: .personal,
                    start: localDate(2026, 7, 25, 11),
                    end: localDate(2026, 7, 25, 13)
                )
            ]
        )

        XCTAssertTrue(inferredYear.confirmationRequirement.isRequired)
        XCTAssertTrue(inferredYear.warnings.contains(where: {
            $0.message.contains("current year was inferred")
        }))
        XCTAssertTrue(conflict.confirmationRequirement.isRequired)
        XCTAssertTrue(conflict.warnings.contains(where: {
            $0.message.contains("overlaps an existing fixed commitment")
        }))
    }

    func testPastWorkShiftIsRejectedInsteadOfMutatingHistory() {
        let command = parse(
            "Work shift on 2026-07-23 from 10:00 to 12:00."
        )

        XCTAssertTrue(command.proposedMutations.isEmpty)
        XCTAssertTrue(command.warnings.contains(where: {
            $0.message.contains("entirely in the past")
        }))
    }

    func testPainFlagIsStructuredAndConsequential() {
        let command = parse("My hamstring hurts.")

        XCTAssertEqual(command.detectedIntents.map(\.kind), [.reportPain])
        XCTAssertEqual(command.proposedMutations, [.addPainFlag(bodyArea: "hamstring")])
        XCTAssertTrue(command.confirmationRequirement.isRequired)
    }

    func testUnknownTextNeverCreatesMutation() {
        let command = parse("Maybe later, I am not sure.")

        XCTAssertEqual(command.detectedIntents.map(\.kind), [.unknown])
        XCTAssertTrue(command.proposedMutations.isEmpty)
    }

    func testRawAndEditedConfirmedTranscriptsRemainDistinct() {
        let command = parser.interpret(
            rawTranscript: "Add pass port to today.",
            confirmedTranscript: "Add passport to today.",
            context: CommandContext(
                snapshot: MissionControlSeed.makeDemo(referenceDate: referenceDate),
                referenceDate: referenceDate
            )
        )

        XCTAssertEqual(command.rawTranscript, "Add pass port to today.")
        XCTAssertEqual(command.confirmedTranscript, "Add passport to today.")
        XCTAssertEqual(
            command.proposedMutations,
            [.addChecklistItem(kind: .today, title: "passport")]
        )
    }

    private func parse(
        _ transcript: String,
        fixedCommitments: [FixedCommitment] = []
    ) -> StructuredCommand {
        var snapshot = MissionControlSeed.makeDemo(referenceDate: referenceDate)
        snapshot.fixedCommitments = fixedCommitments
        return parser.interpret(
            rawTranscript: transcript,
            confirmedTranscript: transcript,
            context: CommandContext(
                snapshot: snapshot,
                referenceDate: referenceDate
            )
        )
    }

    private func localDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int
    ) -> Date {
        berlinCalendar.date(
            from: DateComponents(
                timeZone: berlinCalendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }

    private var referenceDate: Date {
        berlinCalendar.date(
            from: DateComponents(
                timeZone: berlinCalendar.timeZone,
                year: 2026,
                month: 7,
                day: 24,
                hour: 10
            )
        )!
    }

    private var berlinCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }
}
