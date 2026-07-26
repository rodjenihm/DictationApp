import Combine
import Foundation

@MainActor
final class ConfigurationViewModel: ObservableObject {
    static let customModelChoice = "__custom__"

    @Published var candidateAPIKey = ""
    @Published var transcriptionModelChoice = ""
    @Published var transcriptionCustomModel = ""
    @Published var languageCode = ""
    @Published var postProcessingEnabled = false
    @Published var postProcessingModelChoice = ""
    @Published var postProcessingCustomModel = ""
    @Published var soundCuesEnabled = true

    @Published private(set) var microphoneStatus:
        MicrophonePermissionStatus = .notDetermined
    @Published private(set) var accessibilityStatus:
        AccessibilityPermissionStatus = .notGranted
    @Published private(set) var globalShortcut =
        GlobalShortcut.defaultShortcut
    @Published private(set) var shortcutErrorMessage: String?
    @Published private(set) var shortcutSuccessMessage: String?

    @Published private(set) var credentialExists = false
    @Published private(set) var hasCompletedFirstRun = false
    @Published private(set) var isValidating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?

    var onConfigurationChanged: (() -> Void)?

    private let settingsStore: SettingsStore
    private let credentialStore: any CredentialStore
    private let validator: any OpenAIConfigurationValidating
    private let permissionService: PermissionService
    private let shortcutService: GlobalShortcutService
    private var savedConfiguration: AppConfiguration = .default

    init(
        settingsStore: SettingsStore,
        credentialStore: any CredentialStore,
        validator: any OpenAIConfigurationValidating,
        permissionService: PermissionService,
        shortcutService: GlobalShortcutService
    ) {
        self.settingsStore = settingsStore
        self.credentialStore = credentialStore
        self.validator = validator
        self.permissionService = permissionService
        self.shortcutService = shortcutService
        reload()
    }

    var isFirstRun: Bool {
        !hasCompletedFirstRun
    }

    var saveButtonTitle: String {
        isFirstRun ? "Finish Setup" : "Save Changes"
    }

    var canSave: Bool {
        guard !isValidating else {
            return false
        }

        guard credentialExists || !trimmedCandidateKey.isEmpty else {
            return false
        }

        guard !resolvedTranscriptionModel.isEmpty else {
            return false
        }

        return !postProcessingEnabled || !resolvedPostProcessingModel.isEmpty
    }

    func reload() {
        guard !isValidating else {
            return
        }

        let stored = settingsStore.load()
        savedConfiguration = stored.configuration
        hasCompletedFirstRun = stored.hasCompletedFirstRun
        globalShortcut = stored.globalShortcut
        soundCuesEnabled = stored.soundCuesEnabled
        apply(stored.configuration)
        candidateAPIKey = ""
        successMessage = nil
        shortcutSuccessMessage = nil
        shortcutErrorMessage =
            shortcutService.registrationError?.localizedDescription
        refreshSystemState()

        do {
            credentialExists = try credentialStore.credentialExists()
            errorMessage = nil
        } catch {
            credentialExists = false
            errorMessage = error.localizedDescription
        }
    }

    func refreshSystemState() {
        microphoneStatus = permissionService.microphoneStatus()
        accessibilityStatus = permissionService.accessibilityStatus()
    }

    func enableMicrophone() async {
        microphoneStatus =
            await permissionService.requestMicrophoneAccess()
    }

    func enableAccessibility() {
        accessibilityStatus =
            permissionService.requestAccessibilityAccess()
    }

    func openMicrophoneSettings() {
        permissionService.openSystemSettings(for: .microphone)
    }

    func openAccessibilitySettings() {
        permissionService.openSystemSettings(for: .accessibility)
    }

    func updateGlobalShortcut(_ candidate: GlobalShortcut) {
        let previousShortcut = globalShortcut
        shortcutErrorMessage = nil
        shortcutSuccessMessage = nil

        do {
            try shortcutService.replaceShortcut(with: candidate)

            do {
                try settingsStore.commit(globalShortcut: candidate)
            } catch {
                try? shortcutService.replaceShortcut(
                    with: previousShortcut
                )
                throw error
            }

            globalShortcut = candidate
            shortcutSuccessMessage =
                "Global shortcut updated to \(candidate.displayName)."
            onConfigurationChanged?()
        } catch {
            shortcutErrorMessage = error.localizedDescription
        }
    }

    func resetGlobalShortcut() {
        updateGlobalShortcut(.defaultShortcut)
    }

    func save() async {
        guard canSave else {
            return
        }

        errorMessage = nil
        successMessage = nil
        isValidating = true
        defer { isValidating = false }

        do {
            let candidateCredential = trimmedCandidateKey
            let isReplacingCredential = !candidateCredential.isEmpty
            let credential: String

            if isReplacingCredential {
                credential = candidateCredential
            } else if let savedCredential = try credentialStore.readCredential() {
                credential = savedCredential
            } else {
                throw ConfigurationInputError.missingCredential
            }

            let configuration = try makeConfiguration()
            var performedValidation = false

            let transcriptionCustomChanged =
                configuration.transcriptionModel.isCustom
                && configuration.transcriptionModel
                    != savedConfiguration.transcriptionModel

            if
                isReplacingCredential
                    || !credentialExists
                    || transcriptionCustomChanged
            {
                try await validator.validateTranscription(
                    credential: credential,
                    model: configuration.transcriptionModel.identifier
                )
                performedValidation = true
            }

            let postProcessingCustomChanged =
                configuration.postProcessingModel.isCustom
                && configuration.postProcessingModel
                    != savedConfiguration.postProcessingModel

            if
                configuration.postProcessingMode == .enabled
                    && (
                        isReplacingCredential
                            || !credentialExists
                            || savedConfiguration.postProcessingMode == .disabled
                            || postProcessingCustomChanged
                    )
            {
                try await validator.validatePostProcessing(
                    credential: credential,
                    model: configuration.postProcessingModel.identifier
                )
                performedValidation = true
            }

            if isReplacingCredential {
                try credentialStore.replaceCredential(with: credential)
            }

            try settingsStore.commit(
                configuration: configuration,
                hasCompletedFirstRun: true,
                soundCuesEnabled: soundCuesEnabled
            )

            savedConfiguration = configuration
            hasCompletedFirstRun = true
            credentialExists = true
            candidateAPIKey = ""
            apply(configuration)
            successMessage = performedValidation
                ? "Configuration saved and validated."
                : "Configuration saved."
            onConfigurationChanged?()
        } catch is CancellationError {
            errorMessage = "Validation was cancelled."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCredential() {
        guard !isValidating else {
            return
        }

        errorMessage = nil
        successMessage = nil

        do {
            try credentialStore.deleteCredential()
            credentialExists = false
            candidateAPIKey = ""
            successMessage = "The saved OpenAI API key was deleted."
            onConfigurationChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var trimmedCandidateKey: String {
        candidateAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedTranscriptionModel: String {
        if transcriptionModelChoice == Self.customModelChoice {
            return transcriptionCustomModel.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }
        return transcriptionModelChoice
    }

    private var resolvedPostProcessingModel: String {
        if postProcessingModelChoice == Self.customModelChoice {
            return postProcessingCustomModel.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }
        return postProcessingModelChoice
    }

    private func makeConfiguration() throws -> AppConfiguration {
        let transcriptionModel = resolvedTranscriptionModel
        guard !transcriptionModel.isEmpty else {
            throw ConfigurationInputError.missingTranscriptionModel
        }

        let postProcessingModel = resolvedPostProcessingModel
        if postProcessingEnabled && postProcessingModel.isEmpty {
            throw ConfigurationInputError.missingPostProcessingModel
        }

        return AppConfiguration(
            transcriptionProvider: .openAI,
            transcriptionModel: transcriptionModelChoice
                == Self.customModelChoice
                ? .custom(transcriptionModel)
                : .curated(transcriptionModel),
            language: languageCode.isEmpty
                ? .automatic
                : .explicit(languageCode),
            postProcessingMode: postProcessingEnabled ? .enabled : .disabled,
            postProcessingProvider: .openAI,
            postProcessingModel: postProcessingModelChoice
                == Self.customModelChoice
                ? .custom(postProcessingModel)
                : .curated(postProcessingModel)
        )
    }

    private func apply(_ configuration: AppConfiguration) {
        if configuration.transcriptionModel.isCustom {
            transcriptionModelChoice = Self.customModelChoice
            transcriptionCustomModel =
                configuration.transcriptionModel.identifier
        } else {
            transcriptionModelChoice =
                configuration.transcriptionModel.identifier
            transcriptionCustomModel = ""
        }

        languageCode = configuration.language.providerIdentifier ?? ""
        postProcessingEnabled =
            configuration.postProcessingMode == .enabled

        if configuration.postProcessingModel.isCustom {
            postProcessingModelChoice = Self.customModelChoice
            postProcessingCustomModel =
                configuration.postProcessingModel.identifier
        } else {
            postProcessingModelChoice =
                configuration.postProcessingModel.identifier
            postProcessingCustomModel = ""
        }
    }
}

private enum ConfigurationInputError: LocalizedError {
    case missingCredential
    case missingTranscriptionModel
    case missingPostProcessingModel

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            "Enter an OpenAI API key."
        case .missingTranscriptionModel:
            "Enter a custom transcription model identifier."
        case .missingPostProcessingModel:
            "Enter a custom post-processing model identifier."
        }
    }
}
