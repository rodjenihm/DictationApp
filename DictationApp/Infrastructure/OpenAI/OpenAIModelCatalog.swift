import Foundation

struct ProviderModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let detail: String?
}

struct ProviderLanguage: Identifiable, Hashable {
    let id: String
    let fallbackName: String

    var displayName: String {
        Locale.current.localizedString(forLanguageCode: id)
            ?? fallbackName
    }
}

enum OpenAIModelCatalog {
    static let transcriptionModels = [
        ProviderModel(
            id: "gpt-4o-transcribe",
            displayName: "GPT-4o Transcribe",
            detail: "Higher accuracy"
        ),
        ProviderModel(
            id: "gpt-4o-mini-transcribe",
            displayName: "GPT-4o Mini Transcribe",
            detail: "Faster and lower cost"
        ),
    ]

    static let postProcessingModels = [
        ProviderModel(
            id: "gpt-5-mini",
            displayName: "GPT-5 mini",
            detail: "Recommended"
        ),
        ProviderModel(
            id: "gpt-5-nano",
            displayName: "GPT-5 nano",
            detail: "Faster and lower cost"
        ),
    ]

    static let languages: [ProviderLanguage] = [
        ("af", "Afrikaans"),
        ("ar", "Arabic"),
        ("hy", "Armenian"),
        ("az", "Azerbaijani"),
        ("be", "Belarusian"),
        ("bs", "Bosnian"),
        ("bg", "Bulgarian"),
        ("ca", "Catalan"),
        ("zh", "Chinese"),
        ("hr", "Croatian"),
        ("cs", "Czech"),
        ("da", "Danish"),
        ("nl", "Dutch"),
        ("en", "English"),
        ("et", "Estonian"),
        ("fi", "Finnish"),
        ("fr", "French"),
        ("gl", "Galician"),
        ("de", "German"),
        ("el", "Greek"),
        ("he", "Hebrew"),
        ("hi", "Hindi"),
        ("hu", "Hungarian"),
        ("is", "Icelandic"),
        ("id", "Indonesian"),
        ("it", "Italian"),
        ("ja", "Japanese"),
        ("kn", "Kannada"),
        ("kk", "Kazakh"),
        ("ko", "Korean"),
        ("lv", "Latvian"),
        ("lt", "Lithuanian"),
        ("mk", "Macedonian"),
        ("ms", "Malay"),
        ("mr", "Marathi"),
        ("mi", "Maori"),
        ("ne", "Nepali"),
        ("no", "Norwegian"),
        ("fa", "Persian"),
        ("pl", "Polish"),
        ("pt", "Portuguese"),
        ("ro", "Romanian"),
        ("ru", "Russian"),
        ("sr", "Serbian"),
        ("sk", "Slovak"),
        ("sl", "Slovenian"),
        ("es", "Spanish"),
        ("sw", "Swahili"),
        ("sv", "Swedish"),
        ("tl", "Tagalog"),
        ("ta", "Tamil"),
        ("th", "Thai"),
        ("tr", "Turkish"),
        ("uk", "Ukrainian"),
        ("ur", "Urdu"),
        ("vi", "Vietnamese"),
        ("cy", "Welsh"),
    ]
    .map(ProviderLanguage.init)
    .sorted {
        $0.displayName.localizedStandardCompare($1.displayName)
            == .orderedAscending
    }

    static func isCuratedTranscriptionModel(_ identifier: String) -> Bool {
        transcriptionModels.contains { $0.id == identifier }
    }

    static func isCuratedPostProcessingModel(_ identifier: String) -> Bool {
        postProcessingModels.contains { $0.id == identifier }
    }

    static func transcriptionAPIIdentifier(
        for selection: ModelSelection
    ) -> String? {
        switch selection.normalized {
        case .curated(let identifier):
            transcriptionModels.first { $0.id == identifier }?.id
        case .custom(let identifier):
            identifier.isEmpty ? nil : identifier
        }
    }

    static func transcriptionLanguageAPIIdentifier(
        for selection: LanguageSelection
    ) -> String? {
        switch selection {
        case .automatic:
            nil
        case .explicit(let identifier):
            languages.first { $0.id == identifier }?.id
        }
    }
}
