import Combine

struct PostProcessingAttention: Equatable, Sendable {
    let configuration: PostProcessingConfiguration
    let message: String
}

@MainActor
final class PostProcessingRuntimeHealth: ObservableObject {
    @Published private(set) var attention: PostProcessingAttention?

    func shouldSkip(
        _ configuration: PostProcessingConfiguration
    ) -> Bool {
        attention?.configuration == configuration
    }

    func message(
        for configuration: PostProcessingConfiguration
    ) -> String? {
        guard attention?.configuration == configuration else {
            return nil
        }
        return attention?.message
    }

    func markNeedsAttention(
        _ configuration: PostProcessingConfiguration,
        message: String
    ) {
        attention = PostProcessingAttention(
            configuration: configuration,
            message: message
        )
    }

    func clearAfterValidation(
        _ configuration: PostProcessingConfiguration
    ) {
        _ = configuration
        attention = nil
    }
}
