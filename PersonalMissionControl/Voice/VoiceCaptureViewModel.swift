import Foundation
import MissionControlCore
import SwiftUI

enum VoiceCapturePhase: Equatable {
    case idle
    case requestingPermission
    case recording
    case transcribing
    case review
    case confirmation
    case completed
    case failed
}

@MainActor
final class VoiceCaptureViewModel: ObservableObject {
    @Published private(set) var phase: VoiceCapturePhase = .idle
    @Published private(set) var authorizationState: SpeechAuthorizationState
    @Published private(set) var partialTranscript = ""
    @Published private(set) var usedOnDeviceRecognition: Bool?
    @Published var rawTranscript = ""
    @Published var confirmedTranscript = ""
    @Published var isReviewPresented = false
    @Published var pendingCommand: StructuredCommand?
    @Published var reviewError: String?
    @Published var successMessage: String?
    @Published var alertMessage: String?

    private let service: any SpeechTranscriptionService
    private var isPressing = false
    private var operationTask: Task<Void, Never>?

    init(service: any SpeechTranscriptionService) {
        self.service = service
        authorizationState = service.authorizationState
    }

    var isRecording: Bool {
        phase == .recording
    }

    var statusMessage: String? {
        switch phase {
        case .requestingPermission:
            "Requesting microphone and Speech access…"
        case .recording:
            partialTranscript.isEmpty
                ? "Listening… release to stop and review"
                : partialTranscript
        case .transcribing:
            "Finishing transcript…"
        case .idle, .review, .confirmation, .completed, .failed:
            nil
        }
    }

    func pressBegan(localeIdentifier: String) {
        guard !isPressing, phase != .transcribing else { return }
        isPressing = true
        alertMessage = nil
        reviewError = nil
        partialTranscript = ""
        usedOnDeviceRecognition = nil

        operationTask = Task { @MainActor [weak self] in
            await self?.requestPermissionAndStart(localeIdentifier: localeIdentifier)
        }
    }

    func pressEnded() {
        guard isPressing else { return }
        isPressing = false
        let startTask = operationTask
        operationTask = Task { @MainActor [weak self] in
            await startTask?.value
            await self?.finishCaptureIfNeeded()
        }
    }

    func waitForCurrentOperation() async {
        await operationTask?.value
    }

    func presentTextEntry() {
        service.cancelTranscription()
        operationTask?.cancel()
        isPressing = false
        rawTranscript = ""
        confirmedTranscript = ""
        partialTranscript = ""
        usedOnDeviceRecognition = nil
        pendingCommand = nil
        reviewError = nil
        successMessage = nil
        phase = .review
        isReviewPresented = true
    }

    func showConfirmation(_ command: StructuredCommand) {
        pendingCommand = command
        reviewError = nil
        phase = .confirmation
    }

    func showApplied(_ result: CommandApplicationResult) {
        pendingCommand = nil
        reviewError = nil
        successMessage = result.replanRequests.isEmpty
            ? "Change applied locally."
            : "\(result.appliedMutationCount) change(s) applied. "
                + "\(result.replanRequests.count) replanning request(s) queued."
        phase = .completed
    }

    func showReviewError(_ message: String) {
        reviewError = message
    }

    func editTranscript() {
        pendingCommand = nil
        successMessage = nil
        reviewError = nil
        phase = .review
    }

    func retry() {
        dismissReview()
        alertMessage = "Hold the microphone to try again."
    }

    func dismissReview() {
        service.cancelTranscription()
        operationTask?.cancel()
        operationTask = nil
        isPressing = false
        isReviewPresented = false
        rawTranscript = ""
        confirmedTranscript = ""
        partialTranscript = ""
        usedOnDeviceRecognition = nil
        pendingCommand = nil
        reviewError = nil
        successMessage = nil
        phase = .idle
    }

    func clearAlert() {
        alertMessage = nil
        if phase == .failed {
            phase = .idle
        }
    }

    private func requestPermissionAndStart(localeIdentifier: String) async {
        authorizationState = service.authorizationState
        if authorizationState != .authorized {
            phase = .requestingPermission
            authorizationState = .requesting
            authorizationState = await service.requestAuthorization()
        }

        guard isPressing else {
            phase = .idle
            return
        }
        guard authorizationState == .authorized else {
            fail(messageForAuthorization(authorizationState))
            return
        }
        guard service.isAvailable else {
            fail("Speech recognition is currently unavailable. You can type instead.")
            return
        }

        do {
            try await service.startTranscription(
                localeIdentifier: localeIdentifier
            ) { [weak self] transcript in
                self?.partialTranscript = transcript
            }
            phase = .recording
        } catch {
            fail(message(for: error))
        }
    }

    private func finishCaptureIfNeeded() async {
        guard phase == .recording else { return }
        phase = .transcribing
        do {
            let result = try await service.stopTranscription()
            rawTranscript = result.transcript
            confirmedTranscript = result.transcript
            partialTranscript = result.transcript
            usedOnDeviceRecognition = result.usedOnDeviceRecognition
            phase = .review
            isReviewPresented = true
        } catch {
            fail(message(for: error))
        }
    }

    private func fail(_ message: String) {
        service.cancelTranscription()
        isPressing = false
        phase = .failed
        alertMessage = message
    }

    private func messageForAuthorization(_ state: SpeechAuthorizationState) -> String {
        switch state {
        case .denied:
            "Microphone or Speech access was denied. Enable it in Settings or type instead."
        case .restricted:
            "Speech capture is restricted on this device. You can type instead."
        case .unavailable:
            "Speech recognition is unavailable. You can type instead."
        case .notDetermined, .requesting:
            "Speech permission was not completed. Try again or type instead."
        case .authorized:
            ""
        }
    }

    private func message(for error: Error) -> String {
        guard let error = error as? SpeechTranscriptionServiceError else {
            return "Voice capture failed. No command was applied."
        }
        switch error {
        case .permissionDenied:
            return "Microphone or Speech access was denied. You can type instead."
        case .restricted:
            return "Speech capture is restricted on this device. You can type instead."
        case .unavailable:
            return "Speech recognition is unavailable. You can type instead."
        case .noSpeechDetected:
            return "No speech was detected. Hold the microphone and try again."
        case let .recordingFailed(detail):
            return "Recording failed: \(detail)"
        case let .recognitionFailed(detail):
            return "Transcription failed: \(detail)"
        case .cancelled:
            return "Voice capture was cancelled."
        }
    }
}
