import Combine
import SwiftUI

@MainActor
final class OpenAIProviderSettingsModule:
    ObservableObject,
    ProviderSettingsModule
{
    @Published var candidateAPIKey = ""
    @Published private(set) var credentialIntent:
        ProviderCredentialIntent = .unchanged
    @Published private(set) var savedCredentialExists = false
    @Published private(set) var loadErrorMessage: String?

    let descriptor: ProviderDescriptor

    private let credentialStore: any CredentialStore
    private let validator: any OpenAIConfigurationValidating
    private let runtimeHealth: ProviderRuntimeHealthStore

    init(
        credentialStore: any CredentialStore,
        validator: any OpenAIConfigurationValidating,
        runtimeHealth: ProviderRuntimeHealthStore
    ) {
        self.credentialStore = credentialStore
        self.validator = validator
        self.runtimeHealth = runtimeHealth
        descriptor = ProviderDescriptor(
            id: .openAI,
            displayName: "OpenAI",
            systemImage: "cloud",
            capabilities: [
                .transcription: ProviderCapabilityDescriptor(
                    capability: .transcription,
                    processingLocation: .cloud,
                    dataFlowDescription:
                        "Completed audio is uploaded to OpenAI after recording stops.",
                    supportsCustomModels: true,
                    modelCatalog:
                        OpenAIModelCatalog.transcriptionModels.map {
                            ProviderModelDescriptor(
                                id: $0.id,
                                displayName: $0.displayName,
                                detail: $0.detail
                            )
                        },
                    defaultModelID: "gpt-4o-transcribe",
                    languageSupport: .catalog(
                        OpenAIModelCatalog.languages.map {
                            ProviderLanguageDescriptor(
                                id: $0.id,
                                displayName: $0.displayName
                            )
                        }
                    ),
                    acceptedAudioFileExtensions: ["m4a"]
                ),
                .postProcessing: ProviderCapabilityDescriptor(
                    capability: .postProcessing,
                    processingLocation: .cloud,
                    dataFlowDescription:
                        "Raw transcript text is uploaded to OpenAI when cleanup is enabled.",
                    supportsCustomModels: true,
                    modelCatalog:
                        OpenAIModelCatalog.postProcessingModels.map {
                            ProviderModelDescriptor(
                                id: $0.id,
                                displayName: $0.displayName,
                                detail: $0.detail
                            )
                        },
                    defaultModelID: "gpt-5-mini"
                ),
            ]
        )
        reload()
    }

    var readiness: ProviderReadiness {
        switch credentialIntent {
        case .replace where !trimmedCandidate.isEmpty:
            return ProviderReadiness(
                state: .pendingValidation,
                message: "API key pending validation."
            )
        case .remove:
            return ProviderReadiness(
                state: .willDisconnect,
                message: "The saved API key will be removed."
            )
        case .unchanged, .replace:
            return savedReadiness
        }
    }

    var savedReadiness: ProviderReadiness {
        if let loadErrorMessage {
            return .attentionRequired(loadErrorMessage)
        }
        if let message = runtimeHealth.providerMessage(for: .openAI) {
            return .attentionRequired(message)
        }
        return savedCredentialExists
            ? .configured
            : .setupRequired("Enter an OpenAI API key.")
    }

    var isDirty: Bool {
        credentialIntent != .unchanged
    }

    var hasProvisionalConfiguration: Bool {
        switch readiness.state {
        case .configured, .pendingValidation:
            true
        case
            .setupRequired,
            .attentionRequired,
            .willDisconnect:
            false
        }
    }

    func setCandidateAPIKey(_ value: String) {
        candidateAPIKey = value
        credentialIntent =
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .unchanged
            : .replace
    }

    func stageRemoval() {
        candidateAPIKey = ""
        credentialIntent = .remove
    }

    func reload() {
        candidateAPIKey = ""
        credentialIntent = .unchanged
        do {
            savedCredentialExists = try credentialStore.credentialExists()
            loadErrorMessage = nil
        } catch {
            savedCredentialExists = false
            loadErrorMessage = error.localizedDescription
        }
    }

    func discard() {
        reload()
    }

    func validate(
        configuration: AppConfiguration,
        stages: Set<ProviderCapability>
    ) async throws {
        guard credentialIntent != .remove else {
            return
        }

        let credential: String
        if credentialIntent == .replace {
            credential = trimmedCandidate
        } else if let saved = try credentialStore.readCredential() {
            credential = saved
        } else {
            throw ProviderSettingsValidationFailure(
                provider: .openAI,
                capability: nil,
                kind: .authentication,
                message: "Enter an OpenAI API key."
            )
        }

        guard !credential.isEmpty else {
            throw ProviderSettingsValidationFailure(
                provider: .openAI,
                capability: nil,
                kind: .authentication,
                message: "Enter an OpenAI API key."
            )
        }

        let effectiveStages = stages
        if credentialIntent == .replace && effectiveStages.isEmpty {
            do {
                try await validator.validateTranscription(
                    credential: credential,
                    model:
                        configuration.transcription.modelsByProvider[
                            .openAI
                        ]?.identifier
                        ?? "gpt-4o-transcribe"
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw validationFailure(
                    error,
                    capability: .transcription
                )
            }
            return
        }

        if effectiveStages.contains(.transcription) {
            do {
                try await validator.validateTranscription(
                    credential: credential,
                    model: configuration.transcriptionModel.identifier
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw validationFailure(
                    error,
                    capability: .transcription
                )
            }
        }

        if
            effectiveStages.contains(.postProcessing),
            configuration.postProcessingMode == .enabled
        {
            do {
                try await validator.validatePostProcessing(
                    credential: credential,
                    model: configuration.postProcessingModel.identifier
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw validationFailure(
                    error,
                    capability: .postProcessing
                )
            }
        }
    }

    func commit() throws -> ProviderCommitToken? {
        guard credentialIntent != .unchanged else {
            return nil
        }

        let previous = try credentialStore.readCredential()
        switch credentialIntent {
        case .unchanged:
            return nil
        case .replace:
            try credentialStore.replaceCredential(with: trimmedCandidate)
        case .remove:
            try credentialStore.deleteCredential()
        }
        return ProviderCommitToken(value: previous as Any)
    }

    func rollback(_ token: ProviderCommitToken) {
        let previous = token.value as? String
        if let previous {
            try? credentialStore.replaceCredential(with: previous)
        } else {
            try? credentialStore.deleteCredential()
        }
    }

    func didSave() {
        reload()
    }

    func makeDetailView() -> some View {
        OpenAIProviderSettingsView(module: self)
    }

    private var trimmedCandidate: String {
        candidateAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validationFailure(
        _ error: Error,
        capability: ProviderCapability
    ) -> ProviderSettingsValidationFailure {
        let kind: ProviderConfigurationIssueKind
        switch error {
        case OpenAIValidationError.invalidCredential:
            kind = .authentication
        case OpenAIValidationError.modelUnavailable:
            kind = .model
        default:
            kind = .providerSetup
        }
        return ProviderSettingsValidationFailure(
            provider: .openAI,
            capability: capability,
            kind: kind,
            message: error.localizedDescription
        )
    }
}

struct OpenAIProviderSettingsView: View {
    @ObservedObject var module: OpenAIProviderSettingsModule
    @State private var confirmsRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("Status") {
                Label(
                    readinessTitle,
                    systemImage: readinessSystemImage
                )
                .foregroundStyle(readinessColor)
            }

            SecureField(
                module.savedCredentialExists
                    ? "Enter a new key to replace the saved key"
                    : "Enter your OpenAI API key",
                text: Binding(
                    get: { module.candidateAPIKey },
                    set: { module.setCandidateAPIKey($0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("OpenAI API key")

            Text(
                "The key is stored in macOS Keychain and is never displayed again."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Label(
                "Saving may validate transcription with the bundled silent fixture and cleanup with fixed validation text. User recordings and transcripts are never used for Settings validation.",
                systemImage: "icloud.and.arrow.up"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if module.savedCredentialExists || module.credentialIntent == .remove {
                Button("Remove API Key", role: .destructive) {
                    confirmsRemoval = true
                }
            }
        }
        .confirmationDialog(
            "Remove the saved OpenAI API key?",
            isPresented: $confirmsRemoval
        ) {
            Button("Remove API Key", role: .destructive) {
                module.stageRemoval()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "OpenAI transcription and post-processing will require setup after Save Changes."
            )
        }
    }

    private var readinessTitle: String {
        switch module.readiness.state {
        case .configured:
            "Configured"
        case .setupRequired:
            "Setup required"
        case .attentionRequired:
            "Attention required"
        case .pendingValidation:
            "Pending validation"
        case .willDisconnect:
            "Will be disconnected"
        }
    }

    private var readinessSystemImage: String {
        switch module.readiness.state {
        case .configured:
            "checkmark.circle.fill"
        case .pendingValidation:
            "clock.fill"
        case .willDisconnect:
            "minus.circle.fill"
        case .setupRequired, .attentionRequired:
            "exclamationmark.triangle.fill"
        }
    }

    private var readinessColor: Color {
        switch module.readiness.state {
        case .configured:
            .green
        case .pendingValidation:
            .blue
        case .setupRequired, .attentionRequired, .willDisconnect:
            .orange
        }
    }
}
