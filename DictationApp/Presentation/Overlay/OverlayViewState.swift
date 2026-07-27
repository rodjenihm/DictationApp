import Foundation

enum OverlayViewState: Equatable {
    case preparing
    case recording(
        elapsed: TimeInterval,
        inputDeviceName: String,
        isNearDurationLimit: Bool
    )
    case finalizing(RecordingFinalizationReason)
    case completed(duration: TimeInterval)
    case transcribing(providerName: String)
    case postProcessing(providerName: String)
    case transcribedToClipboard
    case rawTranscriptFallback(message: String)
    case noSpeech
    case transcriptionFailed(message: String, canRepair: Bool)
    case captureFailed(message: String, duration: TimeInterval)
    case tooShort
    case cancelled
    case failed(message: String)
}
