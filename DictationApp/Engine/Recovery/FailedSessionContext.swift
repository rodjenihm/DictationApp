import Foundation

struct FailedSessionContext: Equatable, Sendable {
    let identifier: UUID
    let originalConfiguration: SessionConfiguration
    let artifact: AudioArtifact
    let soundCuesEnabled: Bool
    private(set) var transcriptionRepair: TranscriptionRepair?

    var effectiveConfiguration: SessionConfiguration {
        guard let transcriptionRepair else {
            return originalConfiguration
        }
        return originalConfiguration.replacingTranscription(
            with: transcriptionRepair
        )
    }

    mutating func apply(_ repair: TranscriptionRepair) {
        transcriptionRepair = repair
    }
}
