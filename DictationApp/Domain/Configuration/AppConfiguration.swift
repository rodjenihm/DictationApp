import Foundation

enum ProviderID: String, Codable, CaseIterable, Identifiable {
    case openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        }
    }
}

enum ModelSelection: Codable, Equatable {
    case curated(String)
    case custom(String)

    var identifier: String {
        switch self {
        case .curated(let identifier), .custom(let identifier):
            identifier
        }
    }

    var normalized: ModelSelection {
        switch self {
        case .curated:
            self
        case .custom(let identifier):
            .custom(identifier.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    var isCustom: Bool {
        if case .custom = self {
            return true
        }
        return false
    }
}

enum LanguageSelection: Codable, Equatable {
    case automatic
    case explicit(String)

    var providerIdentifier: String? {
        switch self {
        case .automatic:
            nil
        case .explicit(let identifier):
            identifier
        }
    }
}

enum PostProcessingMode: String, Codable, CaseIterable, Identifiable {
    case disabled
    case enabled

    var id: String { rawValue }
}

struct AppConfiguration: Codable, Equatable {
    var transcriptionProvider: ProviderID
    var transcriptionModel: ModelSelection
    var language: LanguageSelection
    var postProcessingMode: PostProcessingMode
    var postProcessingProvider: ProviderID
    var postProcessingModel: ModelSelection

    static let `default` = AppConfiguration(
        transcriptionProvider: .openAI,
        transcriptionModel: .curated("gpt-4o-transcribe"),
        language: .automatic,
        postProcessingMode: .disabled,
        postProcessingProvider: .openAI,
        postProcessingModel: .curated("gpt-5-mini")
    )

    var isStructurallyValid: Bool {
        !transcriptionModel.identifier.isEmpty
            && (
                postProcessingMode == .disabled
                    || !postProcessingModel.identifier.isEmpty
            )
    }
}
