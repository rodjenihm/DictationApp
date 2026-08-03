import Foundation

enum ProviderID:
    String,
    Codable,
    CaseIterable,
    Hashable,
    Identifiable,
    Sendable
{
    case appleOnDevice
    case openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleOnDevice:
            "Apple On-Device"
        case .openAI:
            "OpenAI"
        }
    }
}

enum ModelSelection: Codable, Equatable, Sendable {
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

enum LanguageSelection: Codable, Equatable, Sendable {
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

enum PostProcessingMode:
    String,
    Codable,
    CaseIterable,
    Identifiable,
    Sendable
{
    case disabled
    case enabled

    var id: String { rawValue }
}

struct AppConfiguration: Codable, Equatable, Sendable {
    var audioInputPreference: AudioInputPreference
    var transcription: StageConfiguration
    var transcriptionLanguagesByProvider:
        [ProviderID: LanguageSelection]
    var postProcessingMode: PostProcessingMode
    var postProcessing: StageConfiguration

    static let `default` = AppConfiguration(
        audioInputPreference: .default,
        transcription: StageConfiguration(
            activeProvider: .openAI,
            modelsByProvider: [
                .appleOnDevice:
                    .curated("apple-speech-transcriber"),
                .openAI: .curated("gpt-4o-transcribe"),
            ]
        ),
        transcriptionLanguagesByProvider: [
            .openAI: .automatic,
        ],
        postProcessingMode: .disabled,
        postProcessing: StageConfiguration(
            activeProvider: .openAI,
            modelsByProvider: [
                .openAI: .curated("gpt-5-mini"),
            ]
        )
    )

    init(
        audioInputPreference: AudioInputPreference = .default,
        transcription: StageConfiguration,
        transcriptionLanguagesByProvider:
            [ProviderID: LanguageSelection],
        postProcessingMode: PostProcessingMode,
        postProcessing: StageConfiguration
    ) {
        self.audioInputPreference = audioInputPreference
        self.transcription = transcription
        self.transcriptionLanguagesByProvider =
            transcriptionLanguagesByProvider
        self.postProcessingMode = postProcessingMode
        self.postProcessing = postProcessing
    }

    init(
        audioInputPreference: AudioInputPreference = .default,
        transcriptionProvider: ProviderID,
        transcriptionModel: ModelSelection,
        language: LanguageSelection,
        postProcessingMode: PostProcessingMode,
        postProcessingProvider: ProviderID,
        postProcessingModel: ModelSelection
    ) {
        self.audioInputPreference = audioInputPreference
        transcription = StageConfiguration(
            activeProvider: transcriptionProvider,
            modelsByProvider: [
                transcriptionProvider: transcriptionModel,
            ]
        )
        transcriptionLanguagesByProvider = [
            transcriptionProvider: language,
        ]
        self.postProcessingMode = postProcessingMode
        postProcessing = StageConfiguration(
            activeProvider: postProcessingProvider,
            modelsByProvider: [
                postProcessingProvider: postProcessingModel,
            ]
        )
    }

    var transcriptionProvider: ProviderID {
        get { transcription.activeProvider }
        set { transcription.activeProvider = newValue }
    }

    var transcriptionModel: ModelSelection {
        get { transcription.activeModel }
        set { transcription.setModel(newValue, for: transcriptionProvider) }
    }

    var language: LanguageSelection {
        get {
            language(for: transcriptionProvider)
        }
        set {
            setLanguage(newValue, for: transcriptionProvider)
        }
    }

    func language(for provider: ProviderID) -> LanguageSelection {
        transcriptionLanguagesByProvider[provider]
            ?? (provider == .openAI ? .automatic : .explicit(""))
    }

    mutating func setLanguage(
        _ language: LanguageSelection,
        for provider: ProviderID
    ) {
        transcriptionLanguagesByProvider[provider] = language
    }

    var postProcessingProvider: ProviderID {
        get { postProcessing.activeProvider }
        set { postProcessing.activeProvider = newValue }
    }

    var postProcessingModel: ModelSelection {
        get { postProcessing.activeModel }
        set { postProcessing.setModel(newValue, for: postProcessingProvider) }
    }

    var isStructurallyValid: Bool {
        !transcriptionModel.identifier.isEmpty
            && (
                transcriptionProvider != .appleOnDevice
                    || language.providerIdentifier?.isEmpty == false
            )
            && (
                postProcessingMode == .disabled
                    || !postProcessingModel.identifier.isEmpty
            )
    }
}

struct StageConfiguration: Codable, Equatable, Sendable {
    var activeProvider: ProviderID
    var modelsByProvider: [ProviderID: ModelSelection]

    var activeModel: ModelSelection {
        modelsByProvider[activeProvider] ?? .custom("")
    }

    mutating func setModel(
        _ model: ModelSelection,
        for provider: ProviderID
    ) {
        modelsByProvider[provider] = model
    }
}
