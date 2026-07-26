import Foundation
import XCTest
@testable import MissionControlCore

final class PhaseNineHardeningTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_001_000_000)

    func testAIContextIsBoundedAndDoesNotIncludeCalendarOrHealthDetails()
        throws {
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        snapshot.recoveryContext = RecoveryContext(
            recordedAt: now,
            sleepDurationMinutes: 300,
            note: "Private health note"
        )
        snapshot.fixedCommitments.append(
            FixedCommitment(
                title: "Private appointment title",
                category: .personal,
                start: now.addingTimeInterval(3_600),
                end: now.addingTimeInterval(7_200),
                isExternallyManaged: true
            )
        )
        let settings = AIIntegrationSettings(
            isEnabled: true,
            provider: .customJSON,
            endpointURLString: "https://example.test/interpret",
            modelIdentifier: "configured-model",
            sharesRelevantMissionTitles: true,
            sharesWorkShiftTimesWhenRelevant: false
        )

        let request = AICommandContextMinimizer.request(
            confirmedText: "Move the approved gym session",
            context: CommandContext(snapshot: snapshot, referenceDate: now),
            settings: settings
        )
        let encoded = String(
            decoding: try JSONEncoder().encode(request),
            as: UTF8.self
        )

        XCTAssertLessThanOrEqual(request.relevantMissions.count, 6)
        XCTAssertTrue(request.relevantWorkShifts.isEmpty)
        XCTAssertFalse(encoded.contains("Private appointment title"))
        XCTAssertFalse(encoded.contains("Private health note"))
    }

    func testAIConfigurationRejectsEmbeddedOrQueryCredentials() {
        var settings = enabledAISettings
        settings.endpointURLString =
            "https://user:password@example.test/interpret"
        XCTAssertFalse(settings.isConfigured)

        settings.endpointURLString =
            "https://example.test/interpret?api_key=secret"
        XCTAssertFalse(settings.isConfigured)
    }

    func testValidAIOutputBecomesConfirmationOnlyStructuredProposal()
        async throws {
        let snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        let response = AIProviderResponse(
            detectedIntents: [
                DetectedIntent(kind: .addShoppingItem, confidence: 0.94)
            ],
            confidence: 0.94,
            extractedEntities: [
                ExtractedEntity(kind: .checklistItem, value: "Bananas")
            ],
            mutations: [
                AIProviderMutation(
                    kind: .addChecklistItem,
                    checklistKind: .shopping,
                    title: "Bananas"
                )
            ]
        )
        let interpreter = ProviderBackedAICommandInterpreter(
            provider: FakeAIProvider(response: response),
            settings: enabledAISettings
        )

        let command = try await interpreter.interpret(
            rawTranscript: "add bananas",
            confirmedTranscript: "Add bananas to shopping",
            context: CommandContext(snapshot: snapshot, referenceDate: now)
        )

        XCTAssertEqual(command.interpretationSource, .aiProvider)
        XCTAssertTrue(command.confirmationRequirement.isRequired)
        XCTAssertEqual(
            command.proposedMutations,
            [.addChecklistItem(kind: .shopping, title: "Bananas")]
        )
        XCTAssertEqual(snapshot.checklist(ofKind: .shopping)?.items.count, 3)
    }

    func testInvalidProviderOutputFallsBackToSupportedLocalCommand()
        async throws {
        let snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        let invalid = AIProviderResponse(
            schemaVersion: 99,
            detectedIntents: [
                DetectedIntent(kind: .addShoppingItem, confidence: 1)
            ],
            confidence: 1,
            mutations: [
                AIProviderMutation(
                    kind: .addChecklistItem,
                    checklistKind: .shopping,
                    title: "Milk"
                )
            ]
        )
        let interpreter = ProviderBackedAICommandInterpreter(
            provider: FakeAIProvider(response: invalid),
            settings: enabledAISettings
        )

        let command = try await interpreter.interpret(
            rawTranscript: "add bananas to shopping list",
            confirmedTranscript: "add bananas to shopping list",
            context: CommandContext(snapshot: snapshot, referenceDate: now)
        )

        XCTAssertEqual(command.interpretationSource, .aiFallback)
        XCTAssertFalse(command.proposedMutations.isEmpty)
        XCTAssertTrue(
            command.warnings.contains(where: {
                $0.message.contains("interpreted locally")
            })
        )
    }

    func testAIValidatorRejectsUnknownMissionIdentifier() throws {
        let snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        let response = AIProviderResponse(
            detectedIntents: [
                DetectedIntent(kind: .skipMission, confidence: 0.92)
            ],
            confidence: 0.92,
            mutations: [
                AIProviderMutation(
                    kind: .skipMission,
                    missionID: EntityID().rawValue.uuidString,
                    missionName: "Approved gym session"
                )
            ]
        )

        XCTAssertThrowsError(
            try AICommandOutputValidator.command(
                response: response,
                rawTranscript: "skip gym",
                confirmedTranscript: "skip gym",
                context: CommandContext(
                    snapshot: snapshot,
                    referenceDate: now
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? AICommandPipelineError,
                .invalidMissionReference
            )
        }
    }

    func testCommandContextRevisionChangesAfterScheduleEdit() throws {
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        snapshot.fixedCommitments = [
            FixedCommitment(
                title: "Work shift",
                category: .work,
                start: now.addingTimeInterval(3_600),
                end: now.addingTimeInterval(7_200)
            )
        ]
        let before = CommandContext(
            snapshot: snapshot,
            referenceDate: now
        ).revisionToken
        snapshot.fixedCommitments[0].end =
            snapshot.fixedCommitments[0].end.addingTimeInterval(1_800)
        let after = CommandContext(
            snapshot: snapshot,
            referenceDate: now
        ).revisionToken

        XCTAssertNotEqual(before, after)
    }

    func testStrictResponseDecoderRejectsUnexpectedMutationFields()
        throws {
        let data = Data(
            """
            {
              "schemaVersion": 1,
              "detectedIntents": [
                {"kind": "addShoppingItem", "confidence": 0.9}
              ],
              "confidence": 0.9,
              "extractedEntities": [],
              "mutations": [
                {
                  "kind": "addChecklistItem",
                  "checklistKind": "shopping",
                  "title": "Milk",
                  "directDatabaseWrite": true
                }
              ],
              "affectedScheduleRange": {},
              "warnings": []
            }
            """.utf8
        )

        XCTAssertThrowsError(try AIProviderResponseDecoder.decode(data)) {
            error in
            XCTAssertEqual(
                error as? AICommandPipelineError,
                .invalidJSONStructure
            )
        }
    }

    func testImageImportExcludesLowConfidenceTextAndFlagsAmbiguity()
        throws {
        let existing = FixedCommitment(
            title: "Work shift",
            category: .work,
            start: localDate(2026, 8, 3, 8, 0),
            end: localDate(2026, 8, 3, 16, 0)
        )
        let review = WorkShiftImageImportCoordinator.review(
            recognition: WorkShiftImageRecognition(
                lines: [
                    RecognizedTextLine(
                        text: "3 Aug 09:00-17:00",
                        confidence: 0.99
                    ),
                    RecognizedTextLine(
                        text: "5 Aug 1?:00-18:00",
                        confidence: 0.41
                    )
                ]
            ),
            title: "Work shift",
            location: nil,
            referenceDate: localDate(2026, 7, 26, 12, 0),
            timeZoneIdentifier: "Europe/Berlin",
            existingCommitments: [existing]
        )

        XCTAssertEqual(review.parseResult.entries.count, 1)
        XCTAssertTrue(try XCTUnwrap(review.parseResult.entries.first).isChange)
        XCTAssertTrue(
            review.ambiguities.contains(where: {
                $0.contains("Low-confidence")
            })
        )
        XCTAssertFalse(review.recognizedText.contains("1?:00"))
    }

    func testBackupRoundTripAndSchemaNineDefaults() throws {
        let snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        let data = try MissionControlBackupService.encode(
            snapshot: snapshot,
            exportedAt: now
        )
        let restored = try MissionControlBackupService.decode(data)
        XCTAssertEqual(restored.snapshot, snapshot)

        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["schemaVersion"] = 9
        object.removeValue(forKey: "aiIntegrationSettings")
        object.removeValue(forKey: "privacySettings")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(
            MissionControlSnapshot.self,
            from: legacy
        )

        XCTAssertFalse(decoded.aiIntegrationSettings.isEnabled)
        XCTAssertTrue(decoded.privacySettings.retainsCommandTranscripts)
        XCTAssertEqual(
            decoded.privacySettings.timeZoneBehavior,
            .fixedProfile
        )
    }

    func testIntegrityValidatorRejectsDuplicateIdentifiers() {
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        snapshot.goals.append(snapshot.goals[0])

        XCTAssertTrue(
            SnapshotIntegrityValidator.issues(in: snapshot).contains(
                where: { $0.kind == .duplicateIdentifier }
            )
        )
    }

    func testNotificationEditProducesCancellationAndReplacement()
        throws {
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        snapshot.applySchedulingResult(
            SchedulingEngine().makePlan(
                input: PlanningInput(
                    snapshot: snapshot,
                    currentTime: now
                )
            )
        )
        let existing = NotificationSchedulePlanner.desiredRequests(
            snapshot: snapshot,
            now: now
        )
        let request = try XCTUnwrap(existing.first)
        let blockIndex = try XCTUnwrap(
            snapshot.scheduleBlocks.firstIndex(where: {
                $0.id == request.scheduleBlockID
            })
        )
        snapshot.scheduleBlocks[blockIndex].start =
            snapshot.scheduleBlocks[blockIndex].start.addingTimeInterval(
                30 * 60
            )
        snapshot.scheduleBlocks[blockIndex].end =
            snapshot.scheduleBlocks[blockIndex].end.addingTimeInterval(
                30 * 60
            )

        let reconciliation = NotificationSchedulePlanner.reconciliation(
            snapshot: snapshot,
            existing: existing,
            now: now
        )

        XCTAssertTrue(
            reconciliation.identifiersToCancel.contains(request.id)
        )
        XCTAssertTrue(
            reconciliation.requestsToSchedule.contains(where: {
                $0.id == request.id
                    && $0.fireDate
                        == request.fireDate.addingTimeInterval(30 * 60)
            })
        )
    }

    func testDSTBoundaryPreservesExactFixedCommitmentInstants() throws {
        let reference = localDate(2026, 3, 28, 9, 0)
        let commitment = FixedCommitment(
            title: "DST boundary commitment",
            category: .personal,
            start: localDate(2026, 3, 29, 1, 30),
            end: localDate(2026, 3, 29, 3, 30),
            isExternallyManaged: true
        )
        var snapshot = MissionControlSeed.makeFresh(
            referenceDate: reference
        )
        snapshot.fixedCommitments = [commitment]
        let result = SchedulingEngine().makePlan(
            input: PlanningInput(
                snapshot: snapshot,
                currentTime: reference
            )
        )

        let block = try XCTUnwrap(
            result.scheduleBlocks.first(where: {
                $0.fixedCommitmentID == commitment.id
            })
        )
        XCTAssertEqual(block.start, commitment.start)
        XCTAssertEqual(block.end, commitment.end)
        XCTAssertEqual(
            block.end.timeIntervalSince(block.start),
            60 * 60
        )
        XCTAssertTrue(block.isImmutable)
    }

    func testLargeHistoryProfilingIsCompleteAndDeterministic() throws {
        var snapshot = MissionControlSeed.makeDemo(referenceDate: now)
        let missionID = try XCTUnwrap(snapshot.missions.first?.id)
        snapshot.completions = (0..<10_000).map { offset in
            CompletionRecord(
                missionID: missionID,
                completedAt: now.addingTimeInterval(Double(offset)),
                plannedDurationMinutes: 30,
                actualDurationMinutes: 25
            )
        }

        let first = SnapshotDatasetProfiler.profile(snapshot)
        let second = SnapshotDatasetProfiler.profile(snapshot)

        XCTAssertEqual(first, second)
        XCTAssertGreaterThanOrEqual(first.historyRecordCount, 10_000)
    }

    private var enabledAISettings: AIIntegrationSettings {
        AIIntegrationSettings(
            isEnabled: true,
            provider: .customJSON,
            endpointURLString: "https://example.test/interpret",
            modelIdentifier: "configured-model"
        )
    }

    private func localDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone =
            TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}

private struct FakeAIProvider: AICommandProvider {
    var response: AIProviderResponse

    func requestCommand(
        _ request: AIProviderRequest
    ) async throws -> AIProviderResponse {
        response
    }
}
