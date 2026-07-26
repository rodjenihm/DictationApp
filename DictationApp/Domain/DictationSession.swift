import Foundation

struct RecordingProfile: Equatable, Sendable {
    let fileExtension: String
    let sampleRate: Double
    let channelCount: Int
    let targetBitRate: Int
    let minimumDuration: TimeInterval
    let warningDuration: TimeInterval
    let maximumDuration: TimeInterval

    static let openAI = RecordingProfile(
        fileExtension: "m4a",
        sampleRate: 16_000,
        channelCount: 1,
        targetBitRate: 64_000,
        minimumDuration: 0.5,
        warningDuration: 9 * 60 + 30,
        maximumDuration: 10 * 60
    )
}

struct SessionConfiguration: Equatable, Sendable {
    let transcriptionProvider: ProviderID
    let transcriptionModel: ModelSelection
    let language: LanguageSelection
    let postProcessingMode: PostProcessingMode
    let postProcessingProvider: ProviderID
    let postProcessingModel: ModelSelection
    let recordingProfile: RecordingProfile

    init(
        configuration: AppConfiguration,
        recordingProfile: RecordingProfile
    ) {
        transcriptionProvider = configuration.transcriptionProvider
        transcriptionModel = configuration.transcriptionModel
        language = configuration.language
        postProcessingMode = configuration.postProcessingMode
        postProcessingProvider = configuration.postProcessingProvider
        postProcessingModel = configuration.postProcessingModel
        self.recordingProfile = recordingProfile
    }
}

struct AudioArtifact: Equatable, Sendable {
    let url: URL
    let duration: TimeInterval
    let fileSize: Int64
    let inputDeviceName: String
}

struct RecordingSessionState: Equatable, Sendable {
    let configuration: SessionConfiguration
    let inputDeviceName: String
    let elapsed: TimeInterval
    let isNearDurationLimit: Bool
}

enum RecordingFinalizationReason: Equatable, Sendable {
    case stopped
    case automaticLimit
    case cancelled
}

enum DictationCaptureError: Equatable, LocalizedError, Sendable {
    case microphoneDenied
    case microphoneRestricted
    case noInputDevice
    case cannotConfigureCapture
    case cannotStartCapture
    case cannotFinalizeRecording
    case invalidRecording

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is denied. Enable DictationApp in System Settings."
        case .microphoneRestricted:
            "Microphone access is restricted on this Mac."
        case .noInputDevice:
            "No default microphone input is available."
        case .cannotConfigureCapture:
            "The default microphone could not be configured for recording."
        case .cannotStartCapture:
            "Audio recording could not start."
        case .cannotFinalizeRecording:
            "The recording could not be finalized."
        case .invalidRecording:
            "The finalized recording did not contain valid audio."
        }
    }
}

enum DictationSessionState: Equatable, Sendable {
    case idle
    case preparing(SessionConfiguration)
    case recording(RecordingSessionState)
    case finalizing(RecordingFinalizationReason)
    case completed(AudioArtifact)
    case tooShort
    case cancelled
    case failed(DictationCaptureError)
}
