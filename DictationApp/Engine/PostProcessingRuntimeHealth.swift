import Combine

struct ProviderRuntimeAttention: Equatable, Sendable {
    let provider: ProviderID
    let capability: ProviderCapability?
    let model: ModelSelection?
    let kind: ProviderConfigurationIssueKind
    let message: String
}

@MainActor
final class ProviderRuntimeHealthStore: ObservableObject {
    @Published private(set) var attentions: [ProviderRuntimeAttention] = []

    func shouldSkip(
        _ configuration: PostProcessingConfiguration
    ) -> Bool {
        attentions.contains {
            $0.provider == configuration.provider
                && ($0.capability == nil || $0.capability == .postProcessing)
                && ($0.model == nil || $0.model == configuration.model)
        }
    }

    func message(
        for configuration: PostProcessingConfiguration
    ) -> String? {
        attentions.first {
            $0.provider == configuration.provider
                && ($0.capability == nil || $0.capability == .postProcessing)
                && ($0.model == nil || $0.model == configuration.model)
        }?.message
    }

    func markNeedsAttention(
        _ configuration: PostProcessingConfiguration,
        kind: ProviderConfigurationIssueKind = .unknown,
        message: String
    ) {
        markNeedsAttention(
            provider: configuration.provider,
            capability: .postProcessing,
            model: configuration.model,
            kind: kind,
            message: message
        )
    }

    func markNeedsAttention(
        provider: ProviderID,
        capability: ProviderCapability,
        model: ModelSelection?,
        kind: ProviderConfigurationIssueKind,
        message: String
    ) {
        let providerWide = kind == .authentication || kind == .providerSetup
        let attention = ProviderRuntimeAttention(
            provider: provider,
            capability: providerWide ? nil : capability,
            model: providerWide ? nil : model,
            kind: kind,
            message: message
        )
        attentions.removeAll {
            $0.provider == attention.provider
                && $0.capability == attention.capability
                && $0.model == attention.model
        }
        attentions.append(attention)
    }

    func providerMessage(for provider: ProviderID) -> String? {
        attentions.first {
            $0.provider == provider && $0.capability == nil
        }?.message
    }

    func clearAfterValidation(
        provider: ProviderID,
        capability: ProviderCapability,
        model: ModelSelection
    ) {
        attentions.removeAll {
            $0.provider == provider
                && (
                    $0.capability == nil
                        || (
                            $0.capability == capability
                                && ($0.model == nil || $0.model == model)
                        )
                )
        }
    }
}
