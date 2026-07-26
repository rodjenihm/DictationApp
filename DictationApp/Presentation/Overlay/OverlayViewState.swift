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
    case tooShort
    case cancelled
    case failed(message: String)
}
