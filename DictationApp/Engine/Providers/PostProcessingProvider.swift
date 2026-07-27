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
}

protocol PostProcessingProvider {
    var providerID: ProviderID { get }

    func process(_ request: PostProcessingRequest) async throws -> String
}
