import Foundation

enum ProviderCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case transcription
    case postProcessing

    var displayName: String {
        switch self {
        case .transcription:
            "Transcription"
        case .postProcessing:
            "Post-processing"
        }
    }
}

enum ProviderProcessingLocation: String, Codable, Hashable, Sendable {
    case cloud
    case onDevice
    case mixed

    var displayName: String {
        switch self {
        case .cloud:
            "Cloud"
        case .onDevice:
            "On-device"
        case .mixed:
            "Mixed"
        }
    }
}

struct ProviderCapabilityDescriptor: Hashable, Sendable {
    let capability: ProviderCapability
    let processingLocation: ProviderProcessingLocation
    let dataFlowDescription: String
    let supportsCustomModels: Bool
    let modelCatalog: [ProviderModelDescriptor]
    let defaultModelID: String?
    let languageSupport: ProviderLanguageSupport
    let acceptedAudioFileExtensions: Set<String>

    init(
        capability: ProviderCapability,
        processingLocation: ProviderProcessingLocation,
        dataFlowDescription: String,
        supportsCustomModels: Bool,
        modelCatalog: [ProviderModelDescriptor] = [],
        defaultModelID: String? = nil,
        languageSupport: ProviderLanguageSupport = .notApplicable,
        acceptedAudioFileExtensions: Set<String> = []
    ) {
        self.capability = capability
        self.processingLocation = processingLocation
        self.dataFlowDescription = dataFlowDescription
        self.supportsCustomModels = supportsCustomModels
        self.modelCatalog = modelCatalog
        self.defaultModelID = defaultModelID ?? modelCatalog.first?.id
        self.languageSupport = languageSupport
        self.acceptedAudioFileExtensions = acceptedAudioFileExtensions
    }
}

struct ProviderModelDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let detail: String?
}

enum ProviderLanguageSupport: Hashable, Sendable {
    case notApplicable
    case automaticOnly
    case catalog([ProviderLanguageDescriptor])
}

struct ProviderLanguageDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
}

struct ProviderDescriptor: Identifiable, Hashable, Sendable {
    let id: ProviderID
    let displayName: String
    let systemImage: String
    let capabilities: [ProviderCapability: ProviderCapabilityDescriptor]
}

enum ProviderReadinessState: Equatable, Sendable {
    case configured
    case setupRequired
    case attentionRequired
    case pendingValidation
    case willDisconnect
}

struct ProviderReadiness: Equatable, Sendable {
    let state: ProviderReadinessState
    let message: String?

    static let configured = ProviderReadiness(
        state: .configured,
        message: nil
    )

    static func setupRequired(_ message: String) -> ProviderReadiness {
        ProviderReadiness(state: .setupRequired, message: message)
    }

    static func attentionRequired(_ message: String) -> ProviderReadiness {
        ProviderReadiness(state: .attentionRequired, message: message)
    }
}

nonisolated enum ProviderConfigurationIssueKind: Equatable, Sendable {
    case authentication
    case providerSetup
    case model
    case language
    case unavailable
    case unknown
}
