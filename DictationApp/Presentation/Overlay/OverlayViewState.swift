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
    case transcribedToClipboard
    case noSpeech
    case transcriptionFailed(message: String)
    case tooShort
    case cancelled
    case failed(message: String)
}
