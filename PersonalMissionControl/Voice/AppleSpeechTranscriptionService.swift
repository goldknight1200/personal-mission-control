import AVFAudio
import Foundation
import MissionControlCore
import Speech

@MainActor
final class AppleSpeechTranscriptionService: NSObject, SpeechTranscriptionService {
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var interruptionObserver: NSObjectProtocol?
    private var stopContinuation: CheckedContinuation<SpeechTranscriptionResult, Error>?
    private var stopTimeoutTask: Task<Void, Never>?
    private var latestTranscript = ""
    private var latestConfidence = 0.0
    private var terminalError: SpeechTranscriptionServiceError?
    private var isTapInstalled = false
    private var hasFinalResult = false
    private var usedOnDeviceRecognition = false

    var authorizationState: SpeechAuthorizationState {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let microphoneStatus = AVAudioApplication.shared.recordPermission

        switch speechStatus {
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        case .authorized:
            break
        @unknown default:
            return .unavailable
        }

        switch microphoneStatus {
        case .granted:
            return .authorized
        case .denied:
            return .denied
        case .undetermined:
            return .notDetermined
        @unknown default:
            return .unavailable
        }
    }

    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? SFSpeechRecognizer(locale: .current)?.isAvailable ?? false
    }

    func requestAuthorization() async -> SpeechAuthorizationState {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            speechStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        } else {
            speechStatus = SFSpeechRecognizer.authorizationStatus()
        }

        guard speechStatus == .authorized else {
            switch speechStatus {
            case .denied:
                return .denied
            case .restricted:
                return .restricted
            case .notDetermined:
                return .notDetermined
            case .authorized:
                return .authorized
            @unknown default:
                return .unavailable
            }
        }

        if AVAudioApplication.shared.recordPermission == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
        }
        return authorizationState
    }

    func startTranscription(
        localeIdentifier: String,
        partialResultHandler: @escaping @MainActor (String) -> Void
    ) async throws {
        guard authorizationState == .authorized else {
            throw authorizationState == .restricted
                ? SpeechTranscriptionServiceError.restricted
                : SpeechTranscriptionServiceError.permissionDenied
        }

        cancelTranscription()
        latestTranscript = ""
        latestConfidence = 0
        terminalError = nil
        hasFinalResult = false

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
            ?? SFSpeechRecognizer(locale: .current)
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechTranscriptionServiceError.unavailable
        }
        speechRecognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        usedOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = usedOnDeviceRecognition
        recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true)
            observeAudioInterruptions(audioSession)
        } catch {
            cleanupSession()
            throw SpeechTranscriptionServiceError.recordingFailed(error.localizedDescription)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    latestTranscript = result.bestTranscription.formattedString
                    let confidences = result.bestTranscription.segments.map {
                        Double($0.confidence)
                    }
                    latestConfidence = confidences.isEmpty
                        ? 0
                        : confidences.reduce(0, +) / Double(confidences.count)
                    partialResultHandler(latestTranscript)
                    if result.isFinal {
                        hasFinalResult = true
                        finishPendingStopIfPossible()
                    }
                }
                if let error {
                    terminalError = .recognitionFailed(error.localizedDescription)
                    stopAudioCapture()
                    finishPendingStopIfPossible()
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            cleanupSession()
            throw SpeechTranscriptionServiceError.unavailable
        }
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: recordingFormat
        ) { buffer, _ in
            request.append(buffer)
        }
        isTapInstalled = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            cleanupSession()
            throw SpeechTranscriptionServiceError.recordingFailed(error.localizedDescription)
        }
    }

    func stopTranscription() async throws -> SpeechTranscriptionResult {
        stopAudioCapture()
        recognitionRequest?.endAudio()

        if let terminalError {
            cleanupSession()
            throw terminalError
        }
        if hasFinalResult {
            return try completedResult()
        }

        return try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation
            stopTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                self?.finishPendingStopIfPossible(force: true)
            }
        }
    }

    func cancelTranscription() {
        stopAudioCapture()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil
        if let continuation = stopContinuation {
            stopContinuation = nil
            continuation.resume(throwing: SpeechTranscriptionServiceError.cancelled)
        }
        cleanupSession()
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
    }

    private func finishPendingStopIfPossible(force: Bool = false) {
        guard let continuation = stopContinuation else { return }
        if !force && !hasFinalResult && terminalError == nil {
            return
        }
        stopContinuation = nil
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil

        if let terminalError {
            cleanupSession()
            continuation.resume(throwing: terminalError)
            return
        }
        do {
            continuation.resume(returning: try completedResult())
        } catch {
            continuation.resume(throwing: error)
        }
    }

    private func completedResult() throws -> SpeechTranscriptionResult {
        let transcript = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            cleanupSession()
            throw SpeechTranscriptionServiceError.noSpeechDetected
        }
        let result = SpeechTranscriptionResult(
            transcript: transcript,
            confidence: latestConfidence,
            usedOnDeviceRecognition: usedOnDeviceRecognition
        )
        cleanupSession()
        return result
    }

    private func cleanupSession() {
        stopAudioCapture()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func observeAudioInterruptions(_ audioSession: AVAudioSession) {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            guard
                let rawValue = notification.userInfo?[
                    AVAudioSessionInterruptionTypeKey
                ] as? UInt,
                AVAudioSession.InterruptionType(rawValue: rawValue) == .began
            else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                terminalError = .recordingFailed("Audio capture was interrupted.")
                stopAudioCapture()
                recognitionRequest?.endAudio()
                finishPendingStopIfPossible(force: true)
            }
        }
    }
}
