import Foundation

struct PostProcessingConfiguration: Equatable, Sendable {
    let provider: ProviderID
    let model: ModelSelection

    init(
        provider: ProviderID,
        model: ModelSelection
    ) {
        self.provider = provider
        self.model = model.normalized
    }

    init(sessionConfiguration: SessionConfiguration) {
        self.init(
            provider: sessionConfiguration.postProcessingProvider,
            model: sessionConfiguration.postProcessingModel
        )
    }

    init(appConfiguration: AppConfiguration) {
        self.init(
            provider: appConfiguration.postProcessingProvider,
            model: appConfiguration.postProcessingModel
        )
    }
}

struct PostProcessingRequest: Equatable, Sendable {
    let rawTranscript: String
    let model: ModelSelection
    let language: LanguageSelection
    let fastModeEnabled: Bool
    let deadline: ContinuousClock.Instant?
    let diagnosticSessionID: UUID?

    init(
        rawTranscript: String,
        model: ModelSelection,
        language: LanguageSelection,
        fastModeEnabled: Bool,
        deadline: ContinuousClock.Instant? = nil,
        diagnosticSessionID: UUID? = nil
    ) {
        self.rawTranscript = rawTranscript
        self.model = model
        self.language = language
        self.fastModeEnabled = fastModeEnabled
        self.deadline = deadline
        self.diagnosticSessionID = diagnosticSessionID
    }
}

protocol PostProcessingProvider {
    var providerID: ProviderID { get }

    func process(_ request: PostProcessingRequest) async throws -> String
    func process(_ request: TextCommandRequest) async throws -> String
}
