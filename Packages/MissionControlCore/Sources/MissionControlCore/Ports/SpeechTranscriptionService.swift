public enum SpeechAuthorizationState: String, Codable, Equatable, Sendable {
    case notDetermined
    case requesting
    case authorized
    case denied
    case restricted
    case unavailable
}

public struct SpeechTranscriptionResult: Equatable, Sendable {
    public var transcript: String
    public var confidence: Double
    public var usedOnDeviceRecognition: Bool

    public init(transcript: String, confidence: Double, usedOnDeviceRecognition: Bool) {
        self.transcript = transcript
        self.confidence = min(max(confidence, 0), 1)
        self.usedOnDeviceRecognition = usedOnDeviceRecognition
    }
}

public enum SpeechTranscriptionServiceError: Error, Equatable, Sendable {
    case permissionDenied
    case restricted
    case unavailable
    case noSpeechDetected
    case recordingFailed(String)
    case recognitionFailed(String)
    case cancelled
}

@MainActor
public protocol SpeechTranscriptionService: AnyObject {
    var authorizationState: SpeechAuthorizationState { get }
    var isAvailable: Bool { get }

    func requestAuthorization() async -> SpeechAuthorizationState
    func startTranscription(
        localeIdentifier: String,
        partialResultHandler: @escaping @MainActor (String) -> Void
    ) async throws
    func stopTranscription() async throws -> SpeechTranscriptionResult
    func cancelTranscription()
}
