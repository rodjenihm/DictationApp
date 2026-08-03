import Foundation

struct PreparedRecording: Equatable, Sendable {
    let inputDeviceName: String
    let isUsingFallback: Bool
}

enum AudioRecorderError: Error, Equatable, Sendable {
    case noInputDevice
    case cannotConfigure
    case unsupportedFileType
    case cannotStart
    case cannotFinalize
    case invalidArtifact
}

enum UnexpectedCaptureOutcome: Sendable {
    case partial(AudioArtifact)
    case failed(AudioRecorderError)
}

@MainActor
protocol AudioRecorder: AnyObject {
    var onUnexpectedCaptureFailure:
        ((UUID, UnexpectedCaptureOutcome) -> Void)? { get set }
    var onCancellationTeardownCompleted:
        ((UUID) -> Void)? { get set }

    func prepare(
        profile: RecordingProfile,
        audioInputPreference: AudioInputPreference,
        sessionIdentifier: UUID
    ) async throws -> PreparedRecording
    func startPreparedRecording() async throws
    func stopRecording() async throws -> AudioArtifact
    func cancelRecording(sessionIdentifier: UUID) async
    func cancelImmediately(sessionIdentifier: UUID)
    func shutdownImmediately(sessionIdentifier: UUID)
}

extension AudioRecorder {
    func shutdownImmediately(sessionIdentifier: UUID) {
        cancelImmediately(sessionIdentifier: sessionIdentifier)
    }
}
