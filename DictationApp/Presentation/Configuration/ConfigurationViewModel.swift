import Combine
import Foundation
import Observation
import OSLog

enum SettingsDestination: String, Codable, CaseIterable, Identifiable {
    case general
    case transcription
    case postProcessing
    case providers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            "General"
        case .transcription:
            "Transcription"
        case .postProcessing:
            "Post-processing"
        case .providers:
            "Providers"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .transcription:
            "waveform"
        case .postProcessing:
            "wand.and.stars"
        case .providers:
            "server.rack"
        }
    }
}

enum ConfigurationPresentationMode: Equatable {
    case full
    case transcriptionRepair
}

enum ConfigurationSessionAccess: Equatable {
    case editable
    case readOnly
    case transcriptionRepair
}

enum ConfigurationRoute: Equatable {
    case ordinary
    case destination(SettingsDestination)
    case provider(ProviderID)
    case firstRun
    case transcriptionRepair
}

enum ConfigurationField: Hashable {
    case shortcut
    case provider(ProviderID)
    case credential(ProviderID)
    case transcriptionProvider
    case transcriptionModel
    case language
    case postProcessingProvider
    case postProcessingModel
}

struct ConfigurationIssue: Identifiable, Equatable {
    let id = UUID()
    let destination: SettingsDestination
    let provider: ProviderID?
    let field: ConfigurationField
    let message: String
}

enum ConfigurationSaveResult: Equatable {
    case saved
    case cancelled
    case failed
}

struct ConfigurationDraft: Equatable {
    var configuration: AppConfiguration
    var shortcut: GlobalShortcut
    var soundCuesEnabled: Bool
}

@MainActor
@Observable
final class ConfigurationViewModel {
    static let customModelChoice = "__custom__"

    var selectedDestination: SettingsDestination {
        didSet {
            guard selectedDestination != oldValue else {
                return
            }
            if selectedDestination != .providers {
                selectedProviderDetail = nil
            }
            if persistsTopLevelNavigation {
                settingsStore.saveLastSettingsDestination(
                    selectedDestination.rawValue
                )
            }
        }
    }
    var selectedProviderDetail: ProviderID?

    var transcriptionProviderChoice =
        AppConfiguration.default.transcriptionProvider
    var transcriptionModelChoice = ""
    var transcriptionCustomModel = ""
    var languageCode = "" {
        didSet {
            guard
                presentationMode == .full,
                languageCode != oldValue
            else {
                return
            }
            let language: LanguageSelection =
                languageCode.isEmpty
                ? .automatic
                : .explicit(languageCode)
            transcriptionLanguagesByProvider[
                transcriptionProviderChoice
            ] = language
            providerRegistry.settingsModule(
                for: transcriptionProviderChoice
            )?.stageTranscriptionLanguage(language)
        }
    }
    var postProcessingEnabled = false
    var postProcessingProviderChoice =
        AppConfiguration.default.postProcessingProvider
    var postProcessingModelChoice = ""
    var postProcessingCustomModel = ""
    var audioInputPreference = AudioInputPreference.default
    var soundCuesEnabled = true
    private(set) var globalShortcut =
        GlobalShortcut.defaultShortcut

    private(set) var microphoneStatus:
        MicrophonePermissionStatus = .notDetermined
    private(set) var accessibilityStatus:
        AccessibilityPermissionStatus = .notGranted
    private(set) var speechRecognitionStatus:
        SpeechRecognitionPermissionStatus = .notDetermined
    private(set) var shortcutErrorMessage: String?
    private(set) var successMessage: String?
    private(set) var issues: [ConfigurationIssue] = []
    private(set) var hasCompletedFirstRun = false
    private(set) var isValidating = false
    private(set) var presentationMode:
        ConfigurationPresentationMode = .full
    private(set) var sessionAccess:
        ConfigurationSessionAccess = .editable
    private(set) var repairContext:
        TranscriptionRepairContext?

    @ObservationIgnored
    var onConfigurationChanged: (() -> Void)?
    @ObservationIgnored
    var onTranscriptionRepairValidated:
        ((TranscriptionRepair) -> Void)?
    @ObservationIgnored
    var onRequestClose: (() -> Void)?

    @ObservationIgnored
    let providerRegistry: ProviderRegistry

    @ObservationIgnored
    private let settingsStore: SettingsStore
    @ObservationIgnored
    private let permissionService: PermissionService
    @ObservationIgnored
    private let shortcutService: GlobalShortcutService
    @ObservationIgnored
    private let audioInputDeviceService:
        CoreAudioInputDeviceService
    @ObservationIgnored
    private let providerRuntimeHealth:
        ProviderRuntimeHealthStore
    private var savedConfiguration: AppConfiguration = .default
    private var savedShortcut = GlobalShortcut.defaultShortcut
    private var savedSoundCuesEnabled = true
    private var transcriptionModelsByProvider:
        [ProviderID: ModelSelection] = [:]
    private var transcriptionLanguagesByProvider:
        [ProviderID: LanguageSelection] = [:]
    private var postProcessingModelsByProvider:
        [ProviderID: ModelSelection] = [:]
    private var postProcessingHealthRevision = 0
    private var providerSettingsRevision = 0
    @ObservationIgnored
    private var postProcessingHealthCancellable: AnyCancellable?
    @ObservationIgnored
    private var providerCancellables: [AnyCancellable] = []
    @ObservationIgnored
    private var validationTask:
        Task<ConfigurationSaveResult, Never>?
    @ObservationIgnored
    private var persistsTopLevelNavigation = true

    init(
        settingsStore: SettingsStore,
        permissionService: PermissionService,
        shortcutService: GlobalShortcutService,
        audioInputDeviceService: CoreAudioInputDeviceService,
        providerRegistry: ProviderRegistry,
        providerRuntimeHealth: ProviderRuntimeHealthStore
    ) {
        self.settingsStore = settingsStore
        self.permissionService = permissionService
        self.shortcutService = shortcutService
        self.audioInputDeviceService = audioInputDeviceService
        self.providerRegistry = providerRegistry
        self.providerRuntimeHealth = providerRuntimeHealth

        let rawDestination =
            settingsStore.load().lastSettingsDestination
        selectedDestination =
            SettingsDestination(rawValue: rawDestination)
            ?? .general

        postProcessingHealthCancellable =
            providerRuntimeHealth.$attentions.sink {
                [weak self] _ in
                self?.postProcessingHealthRevision &+= 1
            }
        providerCancellables =
            providerRegistry.settingsModules.map { module in
                module.objectWillChange.sink { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.issues.removeAll {
                        $0.provider == module.id
                            && $0.destination == .providers
                    }
                    if
                        let language =
                            module.provisionalTranscriptionLanguage
                    {
                        if
                            self.transcriptionLanguagesByProvider[
                                module.id
                            ] != language
                        {
                            self.transcriptionLanguagesByProvider[
                                module.id
                            ] = language
                        }
                        if
                            self.transcriptionProviderChoice
                                == module.id,
                            self.languageCode
                                != (
                                    language.providerIdentifier
                                    ?? ""
                                )
                        {
                            self.languageCode =
                                language.providerIdentifier ?? ""
                        }
                    }
                    if
                        self.isFirstRun,
                        module.id == .appleOnDevice,
                        module.hasResolvedFirstRunEligibility,
                        !module.isEligibleForFirstRunDefault,
                        self.selectedProviderDetail
                            == .appleOnDevice
                    {
                        self.selectTranscriptionProvider(.openAI)
                        self.selectedProviderDetail = .openAI
                    }
                    if
                        self.isFirstRun,
                        self.selectedProviderDetail
                            == .appleOnDevice,
                        module.id == .appleOnDevice,
                        module.hasProvisionalConfiguration
                    {
                        self.selectTranscriptionProvider(
                            .appleOnDevice
                        )
                    }
                    self.providerSettingsRevision &+= 1
                }
            }
        reload()
    }

    var isFirstRun: Bool {
        presentationMode == .full && !hasCompletedFirstRun
    }

    var saveButtonTitle: String {
        switch presentationMode {
        case .full:
            isFirstRun ? "Finish Setup" : "Save Changes"
        case .transcriptionRepair:
            "Validate Repair"
        }
    }

    var canSave: Bool {
        guard !isValidating, canEditPresentedSettings else {
            return false
        }
        if isFirstRun || presentationMode == .transcriptionRepair {
            return true
        }
        return hasUnsavedChanges
    }

    var hasUnsavedChanges: Bool {
        _ = providerSettingsRevision
        guard let draft = configurationDraft() else {
            return true
        }
        return draft != savedBaseline
            || providerRegistry.settingsModules.contains(where: \.isDirty)
    }

    var canEditPresentedSettings: Bool {
        switch (presentationMode, sessionAccess) {
        case (.full, .editable):
            true
        case (.transcriptionRepair, .transcriptionRepair):
            true
        case
            (.full, .readOnly),
            (.full, .transcriptionRepair),
            (.transcriptionRepair, .editable),
            (.transcriptionRepair, .readOnly):
            false
        }
    }

    var sessionAccessExplanation: String? {
        guard !canEditPresentedSettings else {
            return nil
        }
        switch sessionAccess {
        case .readOnly:
            return
                "Settings are read-only while the current dictation session is active. The session uses the last saved configuration."
        case .editable:
            return
                "This repair view is no longer active. Reopen Settings to make changes."
        case .transcriptionRepair:
            return
                "Only transcription and its provider configuration can be repaired for the retained recording."
        }
    }

    var availableTranscriptionProviders: [ProviderDescriptor] {
        availableProviders(for: .transcription)
    }

    var availableAudioInputDevices: [AudioInputDevice] {
        audioInputDeviceService.devices
    }

    var audioInputSelection: AudioInputPreference.Identity {
        get {
            audioInputPreference.identity
        }
        set {
            audioInputPreference = audioInputDeviceService.preference(
                for: newValue,
                retainingMetadataFrom: audioInputPreference
            )
        }
    }

    var isAudioInputPreferenceAvailable: Bool {
        audioInputDeviceService.isAvailable(audioInputPreference)
    }

    var audioInputPreferenceStatusMessage: String {
        if !isAudioInputPreferenceAvailable {
            let name = audioInputDeviceService.displayName(
                for: audioInputPreference
            )
            if audioInputPreference == .systemDefault {
                return
                    "No system default microphone is currently available."
            }
            return
                "\(name) is unavailable. Recordings will use System Default until it reconnects."
        }

        switch audioInputPreference {
        case .systemDefault:
            return
                "DictationApp uses the current macOS default input for each new recording."
        case .builtIn, .device:
            return
                "DictationApp uses this microphone without changing the macOS default input."
        }
    }

    func audioInputPreference(
        for device: AudioInputDevice
    ) -> AudioInputPreference {
        audioInputDeviceService.preference(for: device)
    }

    func audioInputDisplayName(
        for preference: AudioInputPreference
    ) -> String {
        audioInputDeviceService.displayName(for: preference)
    }

    var availablePostProcessingProviders: [ProviderDescriptor] {
        availableProviders(for: .postProcessing)
    }

    var availableLanguages: [ProviderLanguageDescriptor] {
        guard
            let descriptor =
                descriptor(for: transcriptionProviderChoice)?
                .capabilities[.transcription],
            case .catalog(let languages) = descriptor.languageSupport
        else {
            return []
        }
        return languages.sorted {
            $0.displayName.localizedStandardCompare($1.displayName)
                == .orderedAscending
        }
    }

    var hasUnsupportedLanguageSelection: Bool {
        !languageCode.isEmpty
            && !availableLanguages.contains { $0.id == languageCode }
    }

    var repairLanguageTitle: String {
        guard let language = repairContext?.language else {
            return "Saved session language"
        }
        switch language {
        case .automatic:
            return "Automatic (fixed for retained recording)"
        case .explicit(let identifier):
            let name =
                availableLanguages.first { $0.id == identifier }?
                    .displayName
                ?? identifier
            return "\(name) (fixed for retained recording)"
        }
    }

    func modelCatalog(
        for provider: ProviderID,
        capability: ProviderCapability
    ) -> [ProviderModelDescriptor] {
        descriptor(for: provider)?
            .capabilities[capability]?.modelCatalog ?? []
    }

    func supportsCustomModels(
        provider: ProviderID,
        capability: ProviderCapability
    ) -> Bool {
        descriptor(for: provider)?
            .capabilities[capability]?.supportsCustomModels ?? false
    }

    func hasModelSelection(
        provider: ProviderID,
        capability: ProviderCapability
    ) -> Bool {
        !modelCatalog(
            for: provider,
            capability: capability
        ).isEmpty
            || supportsCustomModels(
                provider: provider,
                capability: capability
            )
    }

    var allowsAutomaticTranscriptionLanguage: Bool {
        descriptor(for: transcriptionProviderChoice)?
            .capabilities[.transcription]?
            .supportsAutomaticLanguage ?? false
    }

    var postProcessingAttentionMessage: String? {
        _ = postProcessingHealthRevision
        guard savedConfiguration.postProcessingMode == .enabled else {
            return nil
        }
        return providerRuntimeHealth.message(
            for: PostProcessingConfiguration(
                appConfiguration: savedConfiguration
            )
        )
    }

    func providerReadiness(_ id: ProviderID) -> ProviderReadiness {
        _ = providerSettingsRevision
        return providerRegistry.settingsModule(for: id)?.readiness
            ?? .setupRequired("Provider setup is unavailable.")
    }

    func descriptor(for id: ProviderID) -> ProviderDescriptor? {
        providerRegistry.descriptor(for: id)
    }

    func issue(
        for field: ConfigurationField
    ) -> ConfigurationIssue? {
        issues.first { $0.field == field }
    }

    func clearIssue(for field: ConfigurationField) {
        issues.removeAll { $0.field == field }
    }

    func hasIssue(in destination: SettingsDestination) -> Bool {
        issues.contains { $0.destination == destination }
    }

    func isDirty(_ destination: SettingsDestination) -> Bool {
        switch destination {
        case .general:
            return globalShortcut != savedShortcut
                || audioInputPreference
                    != savedConfiguration.audioInputPreference
                || soundCuesEnabled != savedSoundCuesEnabled
        case .transcription:
            guard let draft = draftConfiguration() else {
                return true
            }
            return draft.transcription != savedConfiguration.transcription
                || draft.transcriptionLanguagesByProvider
                    != savedConfiguration
                        .transcriptionLanguagesByProvider
        case .postProcessing:
            guard let draft = draftConfiguration() else {
                return true
            }
            return draft.postProcessingMode
                    != savedConfiguration.postProcessingMode
                || draft.postProcessing
                    != savedConfiguration.postProcessing
        case .providers:
            _ = providerSettingsRevision
            return providerRegistry.settingsModules.contains(
                where: \.isDirty
            )
        }
    }

    func prepareForPresentation(_ route: ConfigurationRoute) {
        persistsTopLevelNavigation = route == .ordinary
        switch route {
        case .ordinary:
            presentationMode = .full
            let storedDestination =
                SettingsDestination(
                    rawValue:
                        settingsStore.load().lastSettingsDestination
                ) ?? .general
            selectedDestination = storedDestination
            selectedProviderDetail = nil
        case .destination(let destination):
            presentationMode = .full
            selectedDestination = destination
            selectedProviderDetail = nil
        case .provider(let provider):
            presentationMode = .full
            selectedDestination = .providers
            selectedProviderDetail = provider
        case .firstRun:
            presentationMode = .full
            selectedDestination = .providers
            selectedProviderDetail =
                providerRegistry.settingsModules.first?.id
        case .transcriptionRepair:
            guard sessionAccess == .transcriptionRepair else {
                presentationMode = .full
                return
            }
            presentationMode = .transcriptionRepair
            selectedDestination = .transcription
            selectedProviderDetail = nil
        }
        refreshSystemState()
    }

    func setRepairContext(_ context: TranscriptionRepairContext?) {
        repairContext = context
    }

    func prepareForPresentation(
        _ mode: ConfigurationPresentationMode
    ) {
        prepareForPresentation(
            mode == .transcriptionRepair
                ? .transcriptionRepair
                : .ordinary
        )
    }

    func setSessionAccess(_ access: ConfigurationSessionAccess) {
        guard sessionAccess != access else {
            return
        }
        sessionAccess = access
        switch access {
        case .transcriptionRepair:
            presentationMode = .transcriptionRepair
            selectedDestination = .transcription
        case .editable:
            if presentationMode == .transcriptionRepair {
                presentationMode = .full
            }
        case .readOnly:
            break
        }
    }

    func reload() {
        guard !isValidating else {
            return
        }
        let stored = settingsStore.load()
        savedConfiguration = stored.configuration
        savedShortcut = stored.globalShortcut
        savedSoundCuesEnabled = stored.soundCuesEnabled
        hasCompletedFirstRun = stored.hasCompletedFirstRun
        globalShortcut = stored.globalShortcut
        soundCuesEnabled = stored.soundCuesEnabled
        apply(stored.configuration)
        if
            !stored.hasCompletedFirstRun,
            audioInputPreference == .builtIn,
            !audioInputDeviceService.hasBuiltInInput
        {
            savedConfiguration.audioInputPreference = .systemDefault
            audioInputPreference = .systemDefault
        }
        providerRegistry.settingsModules.forEach { $0.reload() }
        issues = []
        successMessage = nil
        shortcutErrorMessage = nil
        refreshSystemState()
    }

    func discardChanges() {
        reload()
    }

    func refreshSystemState() {
        audioInputDeviceService.refresh()
        microphoneStatus = permissionService.microphoneStatus()
        accessibilityStatus = permissionService.accessibilityStatus()
        speechRecognitionStatus =
            permissionService.speechRecognitionStatus()
        providerRegistry.settingsModules.forEach {
            $0.refreshSystemState()
        }
    }

    func enableMicrophone() async {
        guard canEditPresentedSettings else {
            return
        }
        microphoneStatus =
            await permissionService.requestMicrophoneAccess()
    }

    func enableAccessibility() {
        guard canEditPresentedSettings else {
            return
        }
        accessibilityStatus =
            permissionService.requestAccessibilityAccess()
    }

    func enableSpeechRecognition() async {
        guard canEditPresentedSettings else {
            return
        }
        speechRecognitionStatus =
            await permissionService
                .requestSpeechRecognitionAccess()
        providerRegistry.settingsModule(
            for: .appleOnDevice
        )?.refreshSystemState()
    }

    func openMicrophoneSettings() {
        permissionService.openSystemSettings(for: .microphone)
    }

    func openAccessibilitySettings() {
        permissionService.openSystemSettings(for: .accessibility)
    }

    func openSpeechRecognitionSettings() {
        permissionService.openSystemSettings(
            for: .speechRecognition
        )
    }

    func updateGlobalShortcut(_ candidate: GlobalShortcut) {
        guard
            presentationMode == .full,
            sessionAccess == .editable
        else {
            return
        }
        do {
            try shortcutService.validateCandidate(candidate)
            globalShortcut = candidate
            shortcutErrorMessage = nil
            issues.removeAll { $0.field == .shortcut }
        } catch {
            shortcutErrorMessage = error.localizedDescription
            replaceIssue(
                ConfigurationIssue(
                    destination: .general,
                    provider: nil,
                    field: .shortcut,
                    message: error.localizedDescription
                )
            )
        }
    }

    func resetGlobalShortcut() {
        updateGlobalShortcut(.defaultShortcut)
    }

    func selectTranscriptionProvider(_ provider: ProviderID) {
        stashCurrentTranscriptionModel()
        stashCurrentTranscriptionLanguage()
        transcriptionProviderChoice = provider
        let model =
            transcriptionModelsByProvider[provider]
            ?? defaultModel(for: provider, capability: .transcription)
        applyTranscriptionModel(model)
        let language =
            transcriptionLanguagesByProvider[provider]
            ?? providerRegistry.settingsModule(for: provider)?
                .provisionalTranscriptionLanguage
            ?? (provider == .openAI ? .automatic : .explicit(""))
        transcriptionLanguagesByProvider[provider] = language
        languageCode = language.providerIdentifier ?? ""
    }

    func selectPostProcessingProvider(_ provider: ProviderID) {
        stashCurrentPostProcessingModel()
        postProcessingProviderChoice = provider
        let model =
            postProcessingModelsByProvider[provider]
            ?? defaultModel(for: provider, capability: .postProcessing)
        applyPostProcessingModel(model)
    }

    func showProvider(_ provider: ProviderID) {
        selectedDestination = .providers
        selectedProviderDetail = provider
    }

    func showProvidersList() {
        selectedProviderDetail = nil
    }

    func useOpenAIForTranscription() {
        selectTranscriptionProvider(.openAI)
        selectedDestination = .providers
        selectedProviderDetail = .openAI
    }

    func cancelValidation() {
        validationTask?.cancel()
    }

    func save() async -> ConfigurationSaveResult {
        guard canSave else {
            return .failed
        }
        let task = Task { [weak self] in
            guard let self else {
                return ConfigurationSaveResult.cancelled
            }
            return await self.performSave()
        }
        validationTask = task
        let result = await task.value
        validationTask = nil
        return result
    }

    private func performSave() async -> ConfigurationSaveResult {
        let wasFirstRun = isFirstRun
        issues = []
        successMessage = nil
        shortcutErrorMessage = nil

        guard let configuration = validatedDraftConfiguration() else {
            routeToFirstIssue()
            return .failed
        }

        isValidating = true
        defer { isValidating = false }

        var committedProviders:
            [(AnyProviderSettingsModule, ProviderCommitToken)] = []
        var shortcutWasChanged = false

        do {
            try Task.checkCancellation()

            let stages = validationStages(for: configuration)
            let affectedModules =
                presentationMode == .transcriptionRepair
                ? providerRegistry.settingsModules.filter {
                    $0.id == configuration.transcriptionProvider
                }
                : providerRegistry.settingsModules
            for module in affectedModules {
                let moduleStages = stages.filter {
                    selectedProvider(
                        for: $0,
                        configuration: configuration
                    ) == module.id
                }
                guard module.isDirty || !moduleStages.isEmpty else {
                    continue
                }
                try await module.validate(
                    configuration: configuration,
                    stages: moduleStages
                )
            }

            try Task.checkCancellation()

            if
                presentationMode == .full,
                globalShortcut != savedShortcut
            {
                try shortcutService.replaceShortcut(
                    with: globalShortcut
                )
                shortcutWasChanged = true
            }

            for module in affectedModules
            where module.isDirty {
                if let token = try module.commit() {
                    committedProviders.append((module, token))
                }
            }

            try Task.checkCancellation()

            if presentationMode == .transcriptionRepair {
                return try completeRepairSave(
                    configuration: configuration,
                    affectedModules: affectedModules
                )
            }

            try settingsStore.commit(
                configuration: configuration,
                hasCompletedFirstRun: true,
                soundCuesEnabled: soundCuesEnabled,
                globalShortcut: globalShortcut
            )

            providerRegistry.settingsModules.forEach { $0.didSave() }
            savedConfiguration = configuration
            audioInputPreference = configuration.audioInputPreference
            transcriptionModelsByProvider =
                configuration.transcription.modelsByProvider
            transcriptionLanguagesByProvider =
                configuration.transcriptionLanguagesByProvider
            postProcessingModelsByProvider =
                configuration.postProcessing.modelsByProvider
            savedShortcut = globalShortcut
            savedSoundCuesEnabled = soundCuesEnabled
            hasCompletedFirstRun = true

            if
                configuration.postProcessingMode == .enabled,
                stages.contains(.postProcessing)
            {
                providerRuntimeHealth.clearAfterValidation(
                    provider: configuration.postProcessingProvider,
                    capability: .postProcessing,
                    model: configuration.postProcessingModel
                )
            }
            if stages.contains(.transcription) {
                providerRuntimeHealth.clearAfterValidation(
                    provider: configuration.transcriptionProvider,
                    capability: .transcription,
                    model: configuration.transcriptionModel
                )
            }

            successMessage = stages.isEmpty
                ? "Configuration saved."
                : "Configuration saved and validated."
            onConfigurationChanged?()

            if wasFirstRun {
                onRequestClose?()
            }
            return .saved
        } catch is CancellationError {
            rollback(
                providers: committedProviders,
                shortcutWasChanged: shortcutWasChanged
            )
            successMessage = nil
            return .cancelled
        } catch {
            rollback(
                providers: committedProviders,
                shortcutWasChanged: shortcutWasChanged
            )
            mapSaveError(error)
            routeToFirstIssue()
            return .failed
        }
    }

    private func completeRepairSave(
        configuration: AppConfiguration,
        affectedModules: [AnyProviderSettingsModule]
    ) throws -> ConfigurationSaveResult {
        var repaired = savedConfiguration
        repaired.transcription.activeProvider =
            configuration.transcriptionProvider
        repaired.transcription.setModel(
            configuration.transcriptionModel,
            for: configuration.transcriptionProvider
        )
        repaired.setLanguage(
            configuration.language,
            for: configuration.transcriptionProvider
        )
        let repair = TranscriptionRepair(
            provider: repaired.transcriptionProvider,
            model: repaired.transcriptionModel,
            language: repaired.language
        )

        try settingsStore.commit(
            configuration: repaired,
            hasCompletedFirstRun: hasCompletedFirstRun,
            soundCuesEnabled: savedSoundCuesEnabled,
            globalShortcut: savedShortcut
        )

        affectedModules.forEach { $0.didSave() }
        savedConfiguration = repaired
        transcriptionModelsByProvider[
            repaired.transcriptionProvider
        ] = repaired.transcriptionModel
        transcriptionLanguagesByProvider[
            repaired.transcriptionProvider
        ] = repaired.language
        providerRuntimeHealth.clearAfterValidation(
            provider: repaired.transcriptionProvider,
            capability: .transcription,
            model: repaired.transcriptionModel
        )
        successMessage =
            "Transcription configuration repaired and validated."
        onConfigurationChanged?()
        onTranscriptionRepairValidated?(repair)
        onRequestClose?()
        return .saved
    }

    private func rollback(
        providers:
            [(AnyProviderSettingsModule, ProviderCommitToken)],
        shortcutWasChanged: Bool
    ) {
        for (module, token) in providers.reversed() {
            module.rollback(token)
        }
        if shortcutWasChanged {
            try? shortcutService.replaceShortcut(with: savedShortcut)
        }
    }

    private func validationStages(
        for configuration: AppConfiguration
    ) -> Set<ProviderCapability> {
        var result: Set<ProviderCapability> = []
        let transcriptionProviderSetupChanged =
            providerRegistry.settingsModule(
                for: configuration.transcriptionProvider
            )?.isDirty ?? false
        let transcriptionChanged =
            configuration.transcriptionProvider
                != savedConfiguration.transcriptionProvider
                || configuration.language
                    != savedConfiguration.language
                || (
                    configuration.transcriptionModel.isCustom
                        && configuration.transcriptionModel
                            != savedConfiguration.transcriptionModel
                )
        if
            transcriptionChanged
                || transcriptionProviderSetupChanged
        {
            result.insert(.transcription)
        }

        let postProcessingChanged =
            (
                configuration.postProcessingMode == .enabled
                    && savedConfiguration.postProcessingMode == .disabled
            )
                || configuration.postProcessingProvider
                    != savedConfiguration.postProcessingProvider
                || (
                    configuration.postProcessingModel.isCustom
                        && configuration.postProcessingModel
                            != savedConfiguration.postProcessingModel
                )
        let postProcessingProviderSetupChanged =
            providerRegistry.settingsModule(
                for: configuration.postProcessingProvider
            )?.isDirty ?? false
        if
            configuration.postProcessingMode == .enabled,
            postProcessingChanged
                || (
                    presentationMode == .full
                        && postProcessingProviderSetupChanged
                )
        {
            result.insert(.postProcessing)
        }
        return result
    }

    private func selectedProvider(
        for capability: ProviderCapability,
        configuration: AppConfiguration
    ) -> ProviderID {
        switch capability {
        case .transcription:
            configuration.transcriptionProvider
        case .postProcessing:
            configuration.postProcessingProvider
        }
    }

    private func validatedDraftConfiguration() -> AppConfiguration? {
        guard let configuration = draftConfiguration() else {
            return nil
        }

        if resolvedTranscriptionModel.isEmpty {
            replaceIssue(
                ConfigurationIssue(
                    destination: .transcription,
                    provider: nil,
                    field: .transcriptionModel,
                    message: "Enter a transcription model identifier."
                )
            )
        }

        if
            configuration.transcriptionProvider == .appleOnDevice,
            languageCode.isEmpty
        {
            replaceIssue(
                ConfigurationIssue(
                    destination: .transcription,
                    provider: .appleOnDevice,
                    field: .language,
                    message:
                        "Choose a language for Apple On-Device transcription."
                )
            )
        }

        if
            !languageCode.isEmpty,
            !availableLanguages.contains(where: { $0.id == languageCode })
        {
            replaceIssue(
                ConfigurationIssue(
                    destination: .transcription,
                    provider: nil,
                    field: .language,
                    message:
                        "Choose a language supported by the selected provider or Automatic."
                )
            )
        }

        if
            postProcessingEnabled,
            resolvedPostProcessingModel.isEmpty
        {
            replaceIssue(
                ConfigurationIssue(
                    destination: .postProcessing,
                    provider: nil,
                    field: .postProcessingModel,
                    message: "Enter a post-processing model identifier."
                )
            )
        }

        let transcriptionReadiness =
            providerRegistry.settingsModule(
                for: configuration.transcriptionProvider
            )?.readiness
            ?? .setupRequired("Configure a transcription provider.")
        if
            isFirstRun
                || presentationMode == .transcriptionRepair,
            !isUsable(transcriptionReadiness)
        {
            replaceIssue(
                ConfigurationIssue(
                    destination: .providers,
                    provider: configuration.transcriptionProvider,
                    field: .credential(
                        configuration.transcriptionProvider
                    ),
                    message:
                        transcriptionReadiness.message
                        ?? "Configure a transcription provider."
                )
            )
        }

        if postProcessingEnabled {
            let readiness = providerRegistry.readiness(
                for: configuration.postProcessingProvider,
                capability: .postProcessing
            )
            let draftReadiness =
                providerRegistry.settingsModule(
                    for: configuration.postProcessingProvider
                )?.readiness
                ?? readiness
            let newlyEnabled =
                savedConfiguration.postProcessingMode == .disabled
            if newlyEnabled, !isUsable(draftReadiness) {
                replaceIssue(
                    ConfigurationIssue(
                        destination: .providers,
                        provider: configuration.postProcessingProvider,
                        field: .credential(
                            configuration.postProcessingProvider
                        ),
                        message:
                            draftReadiness.message
                            ?? "Configure a post-processing provider."
                    )
                )
            }
        }

        return issues.isEmpty ? configuration : nil
    }

    private func draftConfiguration() -> AppConfiguration? {
        var configuration = savedConfiguration
        configuration.transcription.modelsByProvider =
            transcriptionModelsByProvider
        configuration.transcription.activeProvider =
            transcriptionProviderChoice
        configuration.transcription.setModel(
            transcriptionModelChoice == Self.customModelChoice
                ? .custom(resolvedTranscriptionModel)
                : .curated(resolvedTranscriptionModel),
            for: transcriptionProviderChoice
        )
        configuration.transcriptionLanguagesByProvider =
            transcriptionLanguagesByProvider
        configuration.setLanguage(
            presentationMode == .transcriptionRepair
                ? repairLanguage(
                    for: transcriptionProviderChoice
                )
                    ?? savedConfiguration.language
                : (
                    languageCode.isEmpty
                    ? .automatic
                    : .explicit(languageCode)
                ),
            for: transcriptionProviderChoice
        )
        configuration.postProcessingMode =
            postProcessingEnabled ? .enabled : .disabled
        configuration.postProcessing.modelsByProvider =
            postProcessingModelsByProvider
        configuration.postProcessing.activeProvider =
            postProcessingProviderChoice
        configuration.postProcessing.setModel(
            postProcessingModelChoice == Self.customModelChoice
                ? .custom(resolvedPostProcessingModel)
                : .curated(resolvedPostProcessingModel),
            for: postProcessingProviderChoice
        )
        configuration.audioInputPreference =
            audioInputDeviceService.refreshingPresentationMetadata(
                for: audioInputPreference
            )
        return configuration
    }

    private func configurationDraft() -> ConfigurationDraft? {
        guard let configuration = draftConfiguration() else {
            return nil
        }
        return ConfigurationDraft(
            configuration: configuration,
            shortcut: globalShortcut,
            soundCuesEnabled: soundCuesEnabled
        )
    }

    private var savedBaseline: ConfigurationDraft {
        ConfigurationDraft(
            configuration: savedConfiguration,
            shortcut: savedShortcut,
            soundCuesEnabled: savedSoundCuesEnabled
        )
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

    private func apply(_ configuration: AppConfiguration) {
        audioInputPreference = configuration.audioInputPreference
        transcriptionModelsByProvider =
            configuration.transcription.modelsByProvider
        transcriptionLanguagesByProvider =
            configuration.transcriptionLanguagesByProvider
        postProcessingModelsByProvider =
            configuration.postProcessing.modelsByProvider
        transcriptionProviderChoice =
            configuration.transcriptionProvider
        applyTranscriptionModel(configuration.transcriptionModel)
        languageCode = configuration.language.providerIdentifier ?? ""
        postProcessingEnabled =
            configuration.postProcessingMode == .enabled
        postProcessingProviderChoice =
            configuration.postProcessingProvider
        applyPostProcessingModel(configuration.postProcessingModel)
    }

    private func applyTranscriptionModel(_ model: ModelSelection) {
        if model.isCustom {
            transcriptionModelChoice = Self.customModelChoice
            transcriptionCustomModel = model.identifier
        } else {
            transcriptionModelChoice = model.identifier
            transcriptionCustomModel = ""
        }
    }

    private func applyPostProcessingModel(_ model: ModelSelection) {
        if model.isCustom {
            postProcessingModelChoice = Self.customModelChoice
            postProcessingCustomModel = model.identifier
        } else {
            postProcessingModelChoice = model.identifier
            postProcessingCustomModel = ""
        }
    }

    private func stashCurrentTranscriptionModel() {
        guard !resolvedTranscriptionModel.isEmpty else {
            return
        }
        transcriptionModelsByProvider[transcriptionProviderChoice] =
            transcriptionModelChoice == Self.customModelChoice
            ? .custom(resolvedTranscriptionModel)
            : .curated(resolvedTranscriptionModel)
    }

    private func stashCurrentTranscriptionLanguage() {
        transcriptionLanguagesByProvider[
            transcriptionProviderChoice
        ] =
            languageCode.isEmpty
            ? .automatic
            : .explicit(languageCode)
    }

    private func stashCurrentPostProcessingModel() {
        guard !resolvedPostProcessingModel.isEmpty else {
            return
        }
        postProcessingModelsByProvider[postProcessingProviderChoice] =
            postProcessingModelChoice == Self.customModelChoice
            ? .custom(resolvedPostProcessingModel)
            : .curated(resolvedPostProcessingModel)
    }

    private func defaultModel(
        for provider: ProviderID,
        capability: ProviderCapability
    ) -> ModelSelection {
        if
            let identifier =
                descriptor(for: provider)?
                .capabilities[capability]?.defaultModelID
        {
            return .curated(identifier)
        }
        return .custom("")
    }

    private func availableProviders(
        for capability: ProviderCapability
    ) -> [ProviderDescriptor] {
        _ = providerSettingsRevision
        let active = capability == .transcription
            ? transcriptionProviderChoice
            : postProcessingProviderChoice
        return providerRegistry.settingsModules.compactMap { module in
            guard
                module.descriptor.capabilities[capability] != nil,
                module.hasProvisionalConfiguration || module.id == active
            else {
                return nil
            }
            if
                presentationMode == .transcriptionRepair,
                capability == .transcription,
                let repairContext,
                let descriptor =
                    module.descriptor.capabilities[.transcription],
                !isCompatible(
                    descriptor,
                    with: repairContext
                )
            {
                return nil
            }
            return module.descriptor
        }
    }

    private func isCompatible(
        _ descriptor: ProviderCapabilityDescriptor,
        with context: TranscriptionRepairContext
    ) -> Bool {
        let accepted = descriptor.acceptedAudioFileExtensions
        if
            !accepted.isEmpty,
            !accepted.contains(
                context.recordingProfile.fileExtension.lowercased()
            )
        {
            return false
        }

        guard case .explicit(let language) = context.language else {
            return descriptor.supportsAutomaticLanguage
        }
        switch descriptor.languageSupport {
        case .notApplicable, .automaticOnly:
            return false
        case .catalog(let languages):
            return languages.contains {
                localeLanguageCode($0.id)
                    == localeLanguageCode(language)
            }
        }
    }

    private func repairLanguage(
        for provider: ProviderID
    ) -> LanguageSelection? {
        guard let original = repairContext?.language else {
            return nil
        }
        guard case .explicit(let identifier) = original else {
            return original
        }
        guard
            let capability =
                descriptor(for: provider)?
                    .capabilities[.transcription],
            case .catalog(let languages) =
                capability.languageSupport
        else {
            return original
        }
        let sourceCode = localeLanguageCode(identifier)
        guard
            let equivalent = languages.first(
                where: {
                    localeLanguageCode($0.id) == sourceCode
                }
            )
        else {
            return original
        }
        return .explicit(equivalent.id)
    }

    private func localeLanguageCode(_ identifier: String)
        -> Locale.LanguageCode?
    {
        Locale(identifier: identifier).language.languageCode
    }

    private func isUsable(_ readiness: ProviderReadiness) -> Bool {
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

    private func mapSaveError(_ error: Error) {
        if let failure = error as? ProviderSettingsValidationFailure {
            mapProviderValidationFailure(failure)
            return
        }
        let provider =
            selectedProviderDetail ?? transcriptionProviderChoice
        let issue = ConfigurationIssue(
            destination: selectedDestination,
            provider: provider,
            field: .provider(provider),
            message: error.localizedDescription
        )
        replaceIssue(issue)
    }

    private func mapProviderValidationFailure(
        _ failure: ProviderSettingsValidationFailure
    ) {
        switch failure.kind {
        case .authentication, .providerSetup:
            replaceIssue(
                ConfigurationIssue(
                    destination: .providers,
                    provider: failure.provider,
                    field: .credential(failure.provider),
                    message: failure.message
                )
            )
            if transcriptionProviderChoice == failure.provider {
                replaceIssue(
                    ConfigurationIssue(
                        destination: .transcription,
                        provider: failure.provider,
                        field: .transcriptionProvider,
                        message: failure.message
                    )
                )
            }
            if
                postProcessingEnabled,
                postProcessingProviderChoice == failure.provider
            {
                replaceIssue(
                    ConfigurationIssue(
                        destination: .postProcessing,
                        provider: failure.provider,
                        field: .postProcessingProvider,
                        message: failure.message
                    )
                )
            }
        case .model, .language, .unavailable, .unknown:
            let destination: SettingsDestination =
                failure.capability == .postProcessing
                ? .postProcessing
                : .transcription
            replaceIssue(
                ConfigurationIssue(
                    destination: destination,
                    provider: failure.provider,
                    field:
                        destination == .postProcessing
                        ? .postProcessingModel
                        : (
                            failure.kind == .language
                            ? .language
                            : .transcriptionModel
                        ),
                    message: failure.message
                )
            )
        }
    }

    private func replaceIssue(_ issue: ConfigurationIssue) {
        issues.removeAll { $0.field == issue.field }
        issues.append(issue)
    }

    private func routeToFirstIssue() {
        guard let issue = issues.first else {
            return
        }
        selectedDestination = issue.destination
        if issue.destination == .providers {
            selectedProviderDetail = issue.provider
        }
    }
}
