import Foundation

@MainActor
protocol ProviderRuntimeResolving {
    func transcriptionProvider(
        for id: ProviderID
    ) -> (any TranscriptionProvider)?
    func postProcessingProvider(
        for id: ProviderID
    ) -> (any PostProcessingProvider)?
}

@MainActor
final class ProviderRegistry: ProviderRuntimeResolving {
    struct Registration {
        let settings: AnyProviderSettingsModule
        let transcriptionProvider: (any TranscriptionProvider)?
        let postProcessingProvider: (any PostProcessingProvider)?
    }

    let registrations: [Registration]

    init(registrations: [Registration]) {
        self.registrations = registrations
    }

    var settingsModules: [AnyProviderSettingsModule] {
        registrations.map(\.settings)
    }

    func registration(for id: ProviderID) -> Registration? {
        registrations.first { $0.settings.id == id }
    }

    func settingsModule(
        for id: ProviderID
    ) -> AnyProviderSettingsModule? {
        registration(for: id)?.settings
    }

    func descriptor(for id: ProviderID) -> ProviderDescriptor? {
        settingsModule(for: id)?.descriptor
    }

    func readiness(
        for id: ProviderID,
        capability: ProviderCapability
    ) -> ProviderReadiness {
        guard
            let module = settingsModule(for: id),
            module.descriptor.capabilities[capability] != nil
        else {
            return .setupRequired(
                "The selected provider does not support this capability."
            )
        }
        return module.savedReadiness
    }

    func eligibleProviders(
        for capability: ProviderCapability
    ) -> [ProviderDescriptor] {
        settingsModules.compactMap { module in
            guard
                module.descriptor.capabilities[capability] != nil,
                module.hasProvisionalConfiguration
            else {
                return nil
            }
            return module.descriptor
        }
    }

    func transcriptionProvider(
        for id: ProviderID
    ) -> (any TranscriptionProvider)? {
        registration(for: id)?.transcriptionProvider
    }

    func postProcessingProvider(
        for id: ProviderID
    ) -> (any PostProcessingProvider)? {
        registration(for: id)?.postProcessingProvider
    }
}
