import Foundation

public protocol AICommandProvider: Sendable {
    func requestCommand(
        _ request: AIProviderRequest
    ) async throws -> AIProviderResponse
}

public protocol SecretStoring: AnyObject {
    func containsSecret(for key: String) -> Bool
    func secret(for key: String) throws -> String?
    func setSecret(_ secret: String, for key: String) throws
    func removeSecret(for key: String) throws
}

public final class UnavailableSecretStore: SecretStoring {
    public init() {}

    public func containsSecret(for key: String) -> Bool {
        false
    }

    public func secret(for key: String) throws -> String? {
        nil
    }

    public func setSecret(_ secret: String, for key: String) throws {
        throw AICommandPipelineError.providerUnavailable
    }

    public func removeSecret(for key: String) throws {}
}

public protocol WorkShiftImageTextRecognizing: Sendable {
    func recognizeText(in imageData: Data) async throws
        -> WorkShiftImageRecognition
}

public struct UnavailableWorkShiftImageTextRecognizer:
    WorkShiftImageTextRecognizing
{
    public init() {}

    public func recognizeText(in imageData: Data) async throws
        -> WorkShiftImageRecognition {
        throw WorkShiftImageRecognitionError.unavailable
    }
}

public enum WorkShiftImageRecognitionError:
    Error,
    Equatable,
    Sendable
{
    case unavailable
    case unreadableImage
    case noTextFound
}
