import Foundation

enum OverlayViewState: Equatable {
    case preparing
    case recording(
        elapsed: TimeInterval,
        inputDeviceName: String,
        isUsingFallback: Bool,
        isNearDurationLimit: Bool
    )
    case finalizing(RecordingFinalizationReason)
    case completed(duration: TimeInterval)
    case transcribing(providerName: String)
    case postProcessing(providerName: String)
    case inserting
    case inserted
    case insertionUnverified(message: String)
    case clipboardFallback(message: String)
    case rawTranscriptFallback(message: String)
    case noSpeech
    case transcriptionFailed(message: String, canRepair: Bool)
    case captureFailed(message: String, duration: TimeInterval)
    case tooShort
    case cancelled
    case failed(message: String)
}
