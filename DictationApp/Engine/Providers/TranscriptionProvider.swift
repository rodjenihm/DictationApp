import Foundation

struct TranscriptionRequest: Equatable, Sendable {
    let artifact: AudioArtifact
    let model: ModelSelection
    let language: LanguageSelection
    let diagnosticSessionID: UUID?

    init(
        artifact: AudioArtifact,
        model: ModelSelection,
        language: LanguageSelection,
        diagnosticSessionID: UUID? = nil
    ) {
        self.artifact = artifact
        self.model = model
        self.language = language
        self.diagnosticSessionID = diagnosticSessionID
    }
}

protocol TranscriptionProvider {
    var providerID: ProviderID { get }

    func transcribe(_ request: TranscriptionRequest) async throws -> String
}
