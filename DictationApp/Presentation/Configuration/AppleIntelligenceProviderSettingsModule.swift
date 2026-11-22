import Combine
import SwiftUI

@MainActor
final class AppleIntelligenceProviderSettingsModule: ProviderSettingsModule {
    let descriptor = ProviderDescriptor(
        id: .appleIntelligence,
        displayName: ProviderID.appleIntelligence.displayName,
        systemImage: "wand.and.stars",
        capabilities: [
            .postProcessing: ProviderCapabilityDescriptor(
                capability: .postProcessing,
                processingLocation: .onDevice,
                dataFlowDescription: "Transcript cleanup runs on this Mac.",
                supportsCustomModels: false,
                defaultModelID: AppleIntelligencePostProcessingProvider.modelID
            ),
        ]
    )

    @Published private(set) var readiness: ProviderReadiness

    init() {
        readiness = Self.currentReadiness()
    }

    var savedReadiness: ProviderReadiness { readiness }
    var isDirty: Bool { false }
    var hasProvisionalConfiguration: Bool {
        readiness.state == .configured
    }

    func reload() {
        refreshSystemState()
    }

    func discard() {
        refreshSystemState()
    }

    func refreshSystemState() {
        let updatedReadiness = Self.currentReadiness()
        guard readiness != updatedReadiness else {
            return
        }
        readiness = updatedReadiness
    }

    func validate(
        configuration: AppConfiguration,
        stages: Set<ProviderCapability>
    ) async throws {
        guard
            stages.contains(.postProcessing),
            configuration.postProcessingMode == .enabled,
            configuration.postProcessingProvider == .appleIntelligence
        else {
            return
        }

        try Task.checkCancellation()
        refreshSystemState()
        if let message = readiness.message {
            throw ProviderSettingsValidationFailure(
                provider: .appleIntelligence,
                capability: .postProcessing,
                kind: .unavailable,
                message: message
            )
        }

        guard
            configuration.postProcessingModel
                == .curated(AppleIntelligencePostProcessingProvider.modelID)
        else {
            throw ProviderSettingsValidationFailure(
                provider: .appleIntelligence,
                capability: .postProcessing,
                kind: .model,
                message: "Apple Intelligence requires the system cleanup model."
            )
        }
    }

    func commit() -> ProviderCommitToken? { nil }
    func rollback(_: ProviderCommitToken) {}
    func didSave() {}

    func makeDetailView() -> some View {
        AppleIntelligenceProviderSettingsView(module: self)
    }

    private static func currentReadiness() -> ProviderReadiness {
        if let message = AppleIntelligencePostProcessingProvider.unavailabilityMessage {
            return .setupRequired(message)
        }
        return .configured
    }
}

private struct AppleIntelligenceProviderSettingsView: View {
    @ObservedObject var module: AppleIntelligenceProviderSettingsModule

    var body: some View {
        ConfigurationForm {
            ConfigurationSettingRow("Status") {
                if let message = module.readiness.message {
                    ConfigurationIssueLabel(message: message, warning: true)
                } else {
                    ConfigurationStatusLabel(
                        title: "Ready on this Mac",
                        systemImage: "checkmark.circle.fill",
                        style: .success,
                        font: .body
                    )
                }
            } detail: {
                Text("No API key is required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
