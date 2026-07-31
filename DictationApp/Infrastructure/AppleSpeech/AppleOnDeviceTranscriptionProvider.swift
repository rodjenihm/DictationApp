import Foundation

@MainActor
final class AppleOnDeviceTranscriptionProvider:
    TranscriptionProvider
{
    let providerID = ProviderID.appleOnDevice

    private let speechService: AppleSpeechService

    init(speechService: AppleSpeechService) {
        self.speechService = speechService
    }

    func transcribe(_ request: TranscriptionRequest) async throws
        -> String
    {
        guard case .explicit(let localeIdentifier) = request.language,
              !localeIdentifier.isEmpty
        else {
            throw ProviderOperationFailure.scopedConfiguration(
                kind: .language,
                message:
                    "Choose a language for Apple On-Device transcription."
            )
        }

        do {
            return try await speechService.transcribe(
                fileURL: request.artifact.url,
                localeIdentifier: localeIdentifier
            )
        } catch is CancellationError {
            throw ProviderOperationFailure.cancelled
        } catch let error as AppleSpeechServiceError {
            throw map(error)
        } catch {
            throw ProviderOperationFailure.operation(
                message:
                    "Apple On-Device could not transcribe the recording."
            )
        }
    }

    private func map(
        _ error: AppleSpeechServiceError
    ) -> ProviderOperationFailure {
        switch error {
        case .unavailable:
            return .scopedConfiguration(
                kind: .unavailable,
                message:
                    "Apple On-Device transcription is unavailable on this Mac."
            )
        case .unsupportedLocale:
            return .scopedConfiguration(
                kind: .language,
                message:
                    "The selected language is not supported by Apple On-Device transcription."
            )
        case
            .reservationUnavailable,
            .assetMissing,
            .installationFailed:
            return .scopedConfiguration(
                kind: .providerSetup,
                message:
                    "The selected Apple transcription language asset needs setup."
            )
        case .invalidAudio:
            return .operation(
                message:
                    "The completed recording could not be opened for Apple transcription."
            )
        case .temporarilyUnavailable:
            return .transient(
                message:
                    "Apple On-Device transcription is temporarily unavailable.",
                retryAfter: nil
            )
        case .analysisFailed:
            return .operation(
                message:
                    "Apple On-Device could not transcribe the recording."
            )
        }
    }
}
