import Foundation

struct TranscriptionRequest: Equatable, Sendable {
    let artifact: AudioArtifact
    let model: ModelSelection
    let language: LanguageSelection
}

protocol TranscriptionProvider {
    var providerID: ProviderID { get }

    func transcribe(_ request: TranscriptionRequest) async throws -> String
}
