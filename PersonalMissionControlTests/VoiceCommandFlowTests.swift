import Foundation
import MissionControlCore
import XCTest
@testable import PersonalMissionControl

final class VoiceCommandFlowTests: XCTestCase {
    @MainActor
    func testReleaseProducesReviewButDoesNotApplyACommand() async {
        let service = FakeSpeechTranscriptionService(
            result: SpeechTranscriptionResult(
                transcript: "Add passport to today.",
                confidence: 0.97,
                usedOnDeviceRecognition: true
            )
        )
        let capture = VoiceCaptureViewModel(service: service)

        capture.pressBegan(localeIdentifier: "en-GB")
        await capture.waitForCurrentOperation()
        XCTAssertEqual(capture.phase, .recording)

        capture.pressEnded()
        await capture.waitForCurrentOperation()

        XCTAssertEqual(service.startCount, 1)
        XCTAssertEqual(service.stopCount, 1)
        XCTAssertEqual(capture.phase, .review)
        XCTAssertTrue(capture.isReviewPresented)
        XCTAssertEqual(capture.rawTranscript, "Add passport to today.")
        XCTAssertEqual(capture.confirmedTranscript, "Add passport to today.")
        XCTAssertNil(capture.pendingCommand)
    }

    @MainActor
    func testDeniedPermissionFailsWithoutStartingRecording() async {
        let service = FakeSpeechTranscriptionService(
            authorizationState: .denied,
            requestedAuthorizationState: .denied
        )
        let capture = VoiceCaptureViewModel(service: service)

        capture.pressBegan(localeIdentifier: "en-GB")
        await capture.waitForCurrentOperation()

        XCTAssertEqual(capture.phase, .failed)
        XCTAssertEqual(service.startCount, 0)
        XCTAssertNotNil(capture.alertMessage)
        XCTAssertFalse(capture.isReviewPresented)
    }

    @MainActor
    func testRecognitionFailureNeverPresentsAReviewAndRetryResetsCapture() async {
        let service = FakeSpeechTranscriptionService(
            stopError: .recognitionFailed("interrupted")
        )
        let capture = VoiceCaptureViewModel(service: service)

        capture.pressBegan(localeIdentifier: "en-GB")
        await capture.waitForCurrentOperation()
        capture.pressEnded()
        await capture.waitForCurrentOperation()

        XCTAssertEqual(capture.phase, .failed)
        XCTAssertFalse(capture.isReviewPresented)
        XCTAssertTrue(capture.alertMessage?.contains("Transcription failed") == true)

        capture.retry()
        XCTAssertEqual(capture.phase, .idle)
        XCTAssertFalse(capture.isReviewPresented)
        XCTAssertEqual(capture.alertMessage, "Hold the microphone to try again.")
    }

    @MainActor
    func testTypedFallbackDoesNotStartSpeechCapture() {
        let service = FakeSpeechTranscriptionService(
            authorizationState: .denied,
            requestedAuthorizationState: .denied
        )
        let capture = VoiceCaptureViewModel(service: service)

        capture.presentTextEntry()

        XCTAssertEqual(capture.phase, .review)
        XCTAssertTrue(capture.isReviewPresented)
        XCTAssertEqual(capture.confirmedTranscript, "")
        XCTAssertEqual(service.startCount, 0)
        XCTAssertEqual(service.cancelCount, 1)
    }

    @MainActor
    func testLowRiskCommandAppliesOnlyAfterExplicitSubmit() {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let repository = InMemoryMissionControlRepository()
        let model = AppModel(repository: repository, referenceDate: referenceDate)

        let beforeCount = model.snapshot.checklist(ofKind: .today)?.items.count

        let result = model.submitVoiceCommand(
            rawTranscript: "Add passport to today.",
            confirmedTranscript: "Add passport to today.",
            at: referenceDate
        )

        guard case .applied = result else {
            return XCTFail("Expected a low-risk command to apply after Send")
        }
        XCTAssertEqual(
            model.snapshot.checklist(ofKind: .today)?.items.count,
            (beforeCount ?? 0) + 1
        )
    }

    @MainActor
    func testHighImpactCommandDoesNotMutateUntilConfirmation() {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let repository = InMemoryMissionControlRepository()
        let model = AppModel(repository: repository, referenceDate: referenceDate)
        let original = model.snapshot

        let submission = model.submitVoiceCommand(
            rawTranscript: "I woke up late; replan my day.",
            confirmedTranscript: "I woke up late; replan my day.",
            at: referenceDate
        )

        guard case let .confirmationRequired(command) = submission else {
            return XCTFail("Expected explicit confirmation")
        }
        XCTAssertEqual(model.snapshot, original)

        guard case .applied = model.confirmVoiceCommand(command) else {
            return XCTFail("Expected the confirmed command to apply")
        }
        XCTAssertEqual(model.snapshot.replanRequests.last?.reason, .lateStart)
        XCTAssertEqual(model.snapshot.commandHistory.last?.id, command.id)
    }

    @MainActor
    func testPersistenceFailureLeavesPublishedScheduleUnchanged() {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let repository = FailingSaveRepository(
            snapshot: MissionControlSeed.makeDemo(referenceDate: referenceDate)
        )
        let model = AppModel(repository: repository, referenceDate: referenceDate)
        let original = model.snapshot
        repository.shouldFailSave = true

        let submission = model.submitVoiceCommand(
            rawTranscript: "Add passport to today.",
            confirmedTranscript: "Add passport to today.",
            at: referenceDate
        )

        guard case .rejected = submission else {
            return XCTFail("Expected the failed durable write to reject the command")
        }
        XCTAssertEqual(model.snapshot, original)
        XCTAssertNotNil(model.persistenceNotice)
    }
}

@MainActor
private final class FakeSpeechTranscriptionService: SpeechTranscriptionService {
    var authorizationState: SpeechAuthorizationState
    var isAvailable = true
    var startCount = 0
    var stopCount = 0
    var cancelCount = 0

    private let requestedAuthorizationState: SpeechAuthorizationState
    private let result: SpeechTranscriptionResult
    private let stopError: SpeechTranscriptionServiceError?

    init(
        authorizationState: SpeechAuthorizationState = .authorized,
        requestedAuthorizationState: SpeechAuthorizationState = .authorized,
        result: SpeechTranscriptionResult = SpeechTranscriptionResult(
            transcript: "",
            confidence: 0,
            usedOnDeviceRecognition: false
        ),
        stopError: SpeechTranscriptionServiceError? = nil
    ) {
        self.authorizationState = authorizationState
        self.requestedAuthorizationState = requestedAuthorizationState
        self.result = result
        self.stopError = stopError
    }

    func requestAuthorization() async -> SpeechAuthorizationState {
        authorizationState = requestedAuthorizationState
        return authorizationState
    }

    func startTranscription(
        localeIdentifier: String,
        partialResultHandler: @escaping @MainActor (String) -> Void
    ) async throws {
        startCount += 1
        partialResultHandler(result.transcript)
    }

    func stopTranscription() async throws -> SpeechTranscriptionResult {
        stopCount += 1
        if let stopError {
            throw stopError
        }
        return result
    }

    func cancelTranscription() {
        cancelCount += 1
    }
}

@MainActor
private final class FailingSaveRepository: MissionControlRepository {
    var shouldFailSave = false
    private var snapshot: MissionControlSnapshot?

    init(snapshot: MissionControlSnapshot?) {
        self.snapshot = snapshot
    }

    func loadSnapshot() throws -> MissionControlSnapshot? {
        snapshot
    }

    func saveSnapshot(_ snapshot: MissionControlSnapshot) throws {
        if shouldFailSave {
            throw TestRepositoryError.saveFailed
        }
        self.snapshot = snapshot
    }
}

private enum TestRepositoryError: Error {
    case saveFailed
}
