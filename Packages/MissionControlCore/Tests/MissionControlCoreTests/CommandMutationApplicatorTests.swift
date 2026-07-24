import Foundation
import XCTest
@testable import MissionControlCore

final class CommandMutationApplicatorTests: XCTestCase {
    func testLowRiskMutationsApplyAndPersistCommandHistory() throws {
        let snapshot = MissionControlSeed.makeDemo(referenceDate: referenceDate)
        let command = makeCommand(
            mutations: [
                .addChecklistItem(kind: .today, title: "Submit form"),
                .markInventoryEmpty(name: "Milk")
            ]
        )
        let replanner = RecordingReplanner()
        let applicator = CommandMutationApplicator(replanner: replanner)

        let result = try applicator.apply(
            command,
            to: snapshot,
            finalConfirmationProvided: true
        )

        XCTAssertEqual(
            result.snapshot.checklist(ofKind: .today)?.items.last?.title,
            "Submit form"
        )
        XCTAssertEqual(
            result.snapshot.inventoryItems.first(where: { $0.name == "Milk" })?.state,
            .empty
        )
        XCTAssertEqual(result.snapshot.commandHistory.last, command)
        XCTAssertEqual(replanner.invocationCount, 1)
        XCTAssertTrue(replanner.receivedRequests.isEmpty)
    }

    func testMissionStartUsesCorrectedActualStart() throws {
        let snapshot = MissionControlSeed.makeDemo(referenceDate: referenceDate)
        let mission = try XCTUnwrap(snapshot.missions.first(where: { $0.category == .gym }))
        let command = makeCommand(
            mutations: [
                .markMissionStarted(
                    missionID: mission.id,
                    missionName: mission.title,
                    minutesAgo: 20
                )
            ]
        )

        let result = try CommandMutationApplicator(
            replanner: RecordingReplanner()
        ).apply(command, to: snapshot, finalConfirmationProvided: true)

        XCTAssertEqual(result.snapshot.mission(withID: mission.id)?.status, .inProgress)
        XCTAssertEqual(
            result.snapshot.missionStartRecords.first?.actualStart,
            referenceDate.addingTimeInterval(-20 * 60)
        )
        XCTAssertEqual(result.replanRequests.map(\.reason), [.actualStartCorrected])
    }

    func testHighImpactCommandCannotApplyWithoutFinalConfirmation() {
        let snapshot = MissionControlSeed.makeDemo(referenceDate: referenceDate)
        let command = makeCommand(
            mutations: [.requestDayReplan(availableFrom: referenceDate)],
            confirmation: .explicit(reasons: ["Large schedule change"])
        )

        XCTAssertThrowsError(
            try CommandMutationApplicator(
                replanner: RecordingReplanner()
            ).apply(command, to: snapshot, finalConfirmationProvided: false)
        ) { error in
            XCTAssertEqual(error as? CommandApplicationError, .confirmationRequired)
        }
        XCTAssertTrue(snapshot.replanRequests.isEmpty)
        XCTAssertTrue(snapshot.commandHistory.isEmpty)
    }

    func testShiftPainAndSkipCreateTypedReplanRequests() throws {
        let snapshot = MissionControlSeed.makeDemo(referenceDate: referenceDate)
        let mission = try XCTUnwrap(snapshot.missions.first(where: { $0.category == .gym }))
        let shiftStart = referenceDate.addingTimeInterval(24 * 60 * 60)
        let shiftEnd = shiftStart.addingTimeInterval(8 * 60 * 60)
        let command = makeCommand(
            mutations: [
                .skipMission(missionID: mission.id, missionName: mission.title),
                .addWorkShift(WorkShiftPayload(start: shiftStart, end: shiftEnd)),
                .addPainFlag(bodyArea: "hamstring")
            ],
            confirmation: .explicit(reasons: ["Consequential"])
        )
        let replanner = RecordingReplanner()

        let result = try CommandMutationApplicator(replanner: replanner).apply(
            command,
            to: snapshot,
            finalConfirmationProvided: true
        )

        XCTAssertEqual(result.snapshot.mission(withID: mission.id)?.status, .skipped)
        XCTAssertEqual(
            result.snapshot.completions.last(where: {
                $0.missionID == mission.id
            })?.status,
            .skipped
        )
        XCTAssertEqual(result.snapshot.fixedCommitments.last?.start, shiftStart)
        XCTAssertEqual(result.snapshot.painFlags.last?.bodyArea, "hamstring")
        XCTAssertEqual(
            Set(result.replanRequests.map(\.reason)),
            Set([.missionSkipped, .fixedCommitmentAdded, .painReported])
        )
        XCTAssertEqual(replanner.receivedRequests, result.replanRequests)
    }

    func testFailureIsAtomicAndDoesNotExposePartiallyMutatedSnapshot() {
        let snapshot = MissionControlSeed.makeDemo(referenceDate: referenceDate)
        let command = makeCommand(
            mutations: [
                .addChecklistItem(kind: .today, title: "Should not escape"),
                .skipMission(missionID: nil, missionName: "Unknown")
            ]
        )

        XCTAssertThrowsError(
            try CommandMutationApplicator(
                replanner: RecordingReplanner()
            ).apply(command, to: snapshot, finalConfirmationProvided: true)
        )
        XCTAssertFalse(
            snapshot.checklist(ofKind: .today)?.items.contains(where: {
                $0.title == "Should not escape"
            }) ?? true
        )
    }

    func testApplyingTheSamePreparedCommandTwiceIsIdempotent() throws {
        let snapshot = MissionControlSeed.makeDemo(
            referenceDate: referenceDate
        )
        let command = makeCommand(
            mutations: [
                .addChecklistItem(
                    kind: .today,
                    title: "Only add this once"
                )
            ]
        )
        let replanner = RecordingReplanner()
        let applicator = CommandMutationApplicator(replanner: replanner)

        let first = try applicator.apply(
            command,
            to: snapshot,
            finalConfirmationProvided: true
        )
        let second = try applicator.apply(
            command,
            to: first.snapshot,
            finalConfirmationProvided: true
        )

        XCTAssertEqual(
            second.snapshot.checklist(ofKind: .today)?.items.filter {
                $0.title == "Only add this once"
            }.count,
            1
        )
        XCTAssertEqual(second.appliedMutationCount, 0)
        XCTAssertTrue(second.replanRequests.isEmpty)
        XCTAssertEqual(replanner.invocationCount, 1)
    }

    func testPastShiftCannotBypassInterpreterValidation() {
        let snapshot = MissionControlSeed.makeDemo(
            referenceDate: referenceDate
        )
        let command = makeCommand(
            mutations: [
                .addWorkShift(
                    WorkShiftPayload(
                        start: referenceDate.addingTimeInterval(-7_200),
                        end: referenceDate.addingTimeInterval(-3_600)
                    )
                )
            ],
            confirmation: .explicit(reasons: ["Fixed commitment"])
        )

        XCTAssertThrowsError(
            try CommandMutationApplicator(
                replanner: RecordingReplanner()
            ).apply(
                command,
                to: snapshot,
                finalConfirmationProvided: true
            )
        ) { error in
            XCTAssertEqual(
                error as? CommandApplicationError,
                .invalidDate
            )
        }
    }

    private func makeCommand(
        mutations: [ProposedMutation],
        confirmation: ConfirmationRequirement = .none
    ) -> StructuredCommand {
        StructuredCommand(
            rawTranscript: "raw",
            confirmedTranscript: "confirmed",
            detectedIntents: [DetectedIntent(kind: .addTodayItem, confidence: 1)],
            extractedEntities: [],
            proposedMutations: mutations,
            confirmationRequirement: confirmation,
            createdAt: referenceDate
        )
    }

    private var referenceDate: Date {
        Date(timeIntervalSince1970: 1_800_000_000)
    }
}

private final class RecordingReplanner: ScheduleReplanning {
    private(set) var invocationCount = 0
    private(set) var receivedRequests: [ReplanRequest] = []

    func replan(
        snapshot: MissionControlSnapshot,
        requests: [ReplanRequest]
    ) throws -> MissionControlSnapshot {
        invocationCount += 1
        receivedRequests = requests
        return snapshot
    }
}
