import Combine
import SwiftUI

private struct AppleProviderCommitState {
    let savedLocaleIdentifier: String?
    let candidateLocaleIdentifier: String?
    let draftReservedLocaleIDs: Set<String>
}

@MainActor
final class AppleOnDeviceProviderSettingsModule:
    ObservableObject,
    ProviderSettingsModule
{
    @Published private(set) var supportSnapshot =
        AppleSpeechSupportSnapshot.requiresMacOS26
    @Published private(set) var permissionStatus:
        SpeechRecognitionPermissionStatus = .notDetermined
    @Published private(set) var candidateAssetState:
        AppleSpeechAssetState = .unsupported
    @Published private(set) var savedAssetState:
        AppleSpeechAssetState = .unsupported
    @Published private(set) var isInstalling = false
    @Published private(set) var installationProgress = 0.0
    @Published private(set) var installationErrorMessage: String?
    @Published private(set) var hasLoadedSupport = false
    @Published var candidateLocaleIdentifier = ""

    private(set) var savedLocaleIdentifier: String?

    private let speechService: AppleSpeechService
    private let permissionService: PermissionService
    private let settingsStore: SettingsStore
    private var pendingCommit: AppleProviderCommitState?
    private var candidateWasStaged = false
    private var draftReservedLocaleIDs: Set<String> = []

    init(
        speechService: AppleSpeechService,
        permissionService: PermissionService,
        settingsStore: SettingsStore
    ) {
        self.speechService = speechService
        self.permissionService = permissionService
        self.settingsStore = settingsStore
        reload()
    }

    var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: .appleOnDevice,
            displayName: "Apple On-Device",
            systemImage: "apple.logo",
            capabilities: [
                .transcription: ProviderCapabilityDescriptor(
                    capability: .transcription,
                    processingLocation: .onDevice,
                    dataFlowDescription:
                        "Completed audio is transcribed on this Mac. Language assets may be downloaded from Apple during setup.",
                    supportsCustomModels: false,
                    defaultModelID: "apple-speech-transcriber",
                    languageSupport: .catalog(
                        supportSnapshot.supportedLocales.map {
                            ProviderLanguageDescriptor(
                                id: $0.id,
                                displayName: $0.displayName
                            )
                        }
                    ),
                    acceptedAudioFileExtensions: ["m4a"]
                ),
            ]
        )
    }

    var readiness: ProviderReadiness {
        readiness(
            localeIdentifier:
                candidateLocaleIdentifier.nilIfEmpty,
            assetState: candidateAssetState,
            pendingWhenConfigured: isDirty
        )
    }

    var savedReadiness: ProviderReadiness {
        readiness(
            localeIdentifier: savedLocaleIdentifier,
            assetState: savedAssetState,
            pendingWhenConfigured: false
        )
    }

    var isDirty: Bool {
        candidateWasStaged
            && candidateLocaleIdentifier.nilIfEmpty
                != savedLocaleIdentifier
    }

    var hasProvisionalConfiguration: Bool {
        supportSnapshot.availability == .available
            && permissionStatus == .granted
            && (candidateWasStaged || savedLocaleIdentifier != nil)
            && candidateLocaleIdentifier.nilIfEmpty != nil
            && candidateAssetState == .installed
    }

    var provisionalTranscriptionLanguage: LanguageSelection? {
        guard candidateWasStaged || savedLocaleIdentifier != nil else {
            return nil
        }
        guard
            let identifier =
                candidateLocaleIdentifier.nilIfEmpty
        else {
            return nil
        }
        return .explicit(identifier)
    }

    var requiresInstalledLanguageConfirmation: Bool {
        candidateAssetState == .installed
            && savedLocaleIdentifier == nil
            && !candidateWasStaged
    }

    var hasResolvedFirstRunEligibility: Bool {
        hasLoadedSupport
    }

    var isEligibleForFirstRunDefault: Bool {
        supportSnapshot.availability == .available
            && supportSnapshot.suggestedLocaleID != nil
    }

    func reload() {
        releaseDraftReservations(except: savedLocaleIdentifier)
        let configured =
            settingsStore.load().configuration.language(
                for: .appleOnDevice
            ).providerIdentifier?.nilIfEmpty
        savedLocaleIdentifier = configured
        candidateLocaleIdentifier = configured ?? ""
        pendingCommit = nil
        candidateWasStaged = false
        draftReservedLocaleIDs = []
        installationErrorMessage = nil
        installationProgress = 0
        refreshSystemState()
    }

    func discard() {
        releaseDraftReservations(except: savedLocaleIdentifier)
        draftReservedLocaleIDs = []
        candidateLocaleIdentifier = savedLocaleIdentifier ?? ""
        candidateWasStaged = false
        installationErrorMessage = nil
        installationProgress = 0
        refreshSystemState()
    }

    func refreshSystemState() {
        permissionStatus =
            permissionService.speechRecognitionStatus()
        Task {
            await refreshSupport()
        }
    }

    func stageTranscriptionLanguage(
        _ language: LanguageSelection
    ) {
        guard case .explicit(let identifier) = language else {
            candidateLocaleIdentifier = ""
            candidateAssetState = .unsupported
            return
        }
        setCandidateLocale(identifier)
    }

    func setCandidateLocale(_ identifier: String) {
        guard candidateLocaleIdentifier != identifier else {
            guard !candidateWasStaged else {
                return
            }
            candidateWasStaged = true
            objectWillChange.send()
            return
        }
        candidateWasStaged = true
        candidateLocaleIdentifier = identifier
        candidateAssetState = .supported
        installationErrorMessage = nil
        installationProgress = 0
        Task {
            await refreshAssetStates()
        }
    }

    func installSelectedLocale() async {
        guard !isInstalling else {
            return
        }
        installationErrorMessage = nil

        if permissionStatus == .notDetermined {
            permissionStatus =
                await permissionService
                    .requestSpeechRecognitionAccess()
        }
        guard permissionStatus == .granted else {
            installationErrorMessage =
                "Allow Speech Recognition before installing an Apple transcription language."
            return
        }
        guard
            let localeIdentifier =
                candidateLocaleIdentifier.nilIfEmpty
        else {
            installationErrorMessage =
                "Choose a transcription language."
            return
        }
        candidateWasStaged = true
        if localeIdentifier != savedLocaleIdentifier {
            draftReservedLocaleIDs.insert(localeIdentifier)
        }

        isInstalling = true
        installationProgress = 0
        candidateAssetState = .downloading
        defer {
            isInstalling = false
        }

        do {
            try await speechService.installAsset(
                for: localeIdentifier
            ) { [weak self] progress in
                self?.installationProgress = progress
            }
            await refreshSupport()
            candidateAssetState = .installed
        } catch is CancellationError {
            installationErrorMessage =
                "Language installation was cancelled."
            await refreshAssetStates()
        } catch {
            installationErrorMessage = error.localizedDescription
            await refreshAssetStates()
        }
    }

    func requestSpeechRecognitionPermission() async {
        guard permissionStatus == .notDetermined else {
            return
        }
        permissionStatus =
            await permissionService.requestSpeechRecognitionAccess()
        await refreshAssetStates()
    }

    func confirmInstalledLocale() {
        guard
            candidateAssetState == .installed,
            candidateLocaleIdentifier.nilIfEmpty != nil
        else {
            return
        }
        candidateWasStaged = true
        objectWillChange.send()
    }

    func openSpeechRecognitionSettings() {
        permissionService.openSystemSettings(
            for: .speechRecognition
        )
    }

    func validate(
        configuration: AppConfiguration,
        stages: Set<ProviderCapability>
    ) async throws {
        guard
            stages.contains(.transcription)
                || configuration.transcriptionProvider
                    == .appleOnDevice
        else {
            return
        }
        guard supportSnapshot.availability == .available else {
            throw validationFailure(
                kind: .unavailable,
                message:
                    supportSnapshot.availability
                        == .requiresMacOS26
                    ? "Apple On-Device requires macOS 26 or later."
                    : "Apple On-Device transcription is unavailable on this Mac."
            )
        }
        guard permissionStatus == .granted else {
            throw validationFailure(
                kind: .providerSetup,
                message:
                    "Allow Speech Recognition for Apple On-Device transcription."
            )
        }
        guard
            case .explicit(let localeIdentifier) =
                configuration.language(for: .appleOnDevice),
            !localeIdentifier.isEmpty,
            supportSnapshot.supportedLocales.contains(
                where: { $0.id == localeIdentifier }
            )
        else {
            throw validationFailure(
                kind: .language,
                message:
                    "Choose a language supported by Apple On-Device transcription."
            )
        }
        guard
            await speechService.assetState(
                for: localeIdentifier
            ) == .installed
        else {
            throw validationFailure(
                kind: .providerSetup,
                message:
                    "Install the selected Apple transcription language before saving."
            )
        }
    }

    func commit() throws -> ProviderCommitToken? {
        guard isDirty else {
            return nil
        }
        let state = AppleProviderCommitState(
            savedLocaleIdentifier: savedLocaleIdentifier,
            candidateLocaleIdentifier:
                candidateLocaleIdentifier.nilIfEmpty,
            draftReservedLocaleIDs: draftReservedLocaleIDs
        )
        pendingCommit = state
        return ProviderCommitToken(value: state)
    }

    func rollback(_ token: ProviderCommitToken) {
        guard let state = token.value as? AppleProviderCommitState else {
            return
        }
        releaseReservations(
            state.draftReservedLocaleIDs,
            except: state.savedLocaleIdentifier
        )
        candidateLocaleIdentifier =
            state.savedLocaleIdentifier ?? ""
        candidateWasStaged = false
        draftReservedLocaleIDs = []
        pendingCommit = nil
        refreshSystemState()
    }

    func didSave() {
        guard let pendingCommit else {
            releaseDraftReservations(except: savedLocaleIdentifier)
            draftReservedLocaleIDs = []
            refreshSystemState()
            return
        }
        let previous = pendingCommit.savedLocaleIdentifier
        let current = pendingCommit.candidateLocaleIdentifier
        savedLocaleIdentifier = current
        candidateWasStaged = false
        self.pendingCommit = nil
        releaseReservations(
            draftReservedLocaleIDs,
            except: current
        )
        draftReservedLocaleIDs = []
        if let previous, previous != current {
            Task {
                await speechService.releaseAssetReservation(
                    for: previous
                )
            }
        }
        refreshSystemState()
    }

    func makeDetailView() -> some View {
        AppleOnDeviceProviderSettingsView(module: self)
    }

    private func refreshSupport() async {
        supportSnapshot = await speechService.supportSnapshot()
        hasLoadedSupport = true
        if
            candidateLocaleIdentifier.isEmpty,
            let suggested = supportSnapshot.suggestedLocaleID
        {
            candidateLocaleIdentifier = suggested
            candidateWasStaged =
                !settingsStore.load().hasCompletedFirstRun
        }
        await refreshAssetStates()
    }

    private func refreshAssetStates() async {
        if let candidate = candidateLocaleIdentifier.nilIfEmpty {
            candidateAssetState =
                await speechService.assetState(for: candidate)
        } else {
            candidateAssetState = .unsupported
        }
        if let savedLocaleIdentifier {
            savedAssetState =
                await speechService.assetState(
                    for: savedLocaleIdentifier
                )
        } else {
            savedAssetState = .unsupported
        }
    }

    private func readiness(
        localeIdentifier: String?,
        assetState: AppleSpeechAssetState,
        pendingWhenConfigured: Bool
    ) -> ProviderReadiness {
        switch supportSnapshot.availability {
        case .requiresMacOS26:
            return .setupRequired(
                "Requires macOS 26 or later."
            )
        case .unavailableOnDevice:
            return .setupRequired(
                "Apple On-Device transcription is unavailable on this Mac."
            )
        case .available:
            break
        }

        switch permissionStatus {
        case .notDetermined:
            return .setupRequired(
                "Allow Speech Recognition and install a language."
            )
        case .denied, .restricted:
            return .attentionRequired(
                "Speech Recognition permission is required."
            )
        case .granted:
            break
        }

        guard localeIdentifier != nil else {
            return .setupRequired(
                "Choose and install a transcription language."
            )
        }
        guard assetState == .installed else {
            return .setupRequired(
                assetState == .downloading
                    ? "The transcription language is downloading."
                    : "Install the selected transcription language."
            )
        }
        if pendingWhenConfigured {
            return ProviderReadiness(
                state: .pendingValidation,
                message: "Apple language pending Save Changes."
            )
        }
        return .configured
    }

    private func validationFailure(
        kind: ProviderConfigurationIssueKind,
        message: String
    ) -> ProviderSettingsValidationFailure {
        ProviderSettingsValidationFailure(
            provider: .appleOnDevice,
            capability: .transcription,
            kind: kind,
            message: message
        )
    }

    private func releaseDraftReservations(except locale: String?) {
        releaseReservations(draftReservedLocaleIDs, except: locale)
    }

    private func releaseReservations(
        _ identifiers: Set<String>,
        except retainedIdentifier: String?
    ) {
        for identifier in identifiers
        where identifier != retainedIdentifier {
            Task {
                await speechService.releaseAssetReservation(
                    for: identifier
                )
            }
        }
    }
}

private struct AppleOnDeviceProviderSettingsView: View {
    @ObservedObject var module:
        AppleOnDeviceProviderSettingsModule

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("Status") {
                Label(
                    statusTitle,
                    systemImage: statusSystemImage
                )
                .foregroundStyle(statusColor)
            }

            Text(availabilityMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            if module.supportSnapshot.availability == .available {
                LabeledContent("Speech Recognition") {
                    Text(permissionTitle)
                }

                if
                    module.permissionStatus == .denied
                        || module.permissionStatus == .restricted
                {
                    Button("Open Speech Recognition Settings") {
                        module.openSpeechRecognitionSettings()
                    }
                }

                LabeledContent("Language") {
                    Picker(
                        "Apple transcription language",
                        selection: Binding(
                            get: {
                                module.candidateLocaleIdentifier
                            },
                            set: {
                                module.setCandidateLocale($0)
                            }
                        )
                    ) {
                        Text(
                            module.supportSnapshot.supportedLocales
                                .isEmpty
                                ? "Loading languages…"
                                : "Choose a language"
                        )
                        .tag("")
                        ForEach(
                            module.supportSnapshot.supportedLocales
                        ) { locale in
                            Text(locale.displayName).tag(locale.id)
                        }
                        if
                            !module.candidateLocaleIdentifier.isEmpty,
                            !module.supportSnapshot.supportedLocales
                                .contains(
                                    where: {
                                        $0.id
                                            == module
                                                .candidateLocaleIdentifier
                                    }
                                )
                        {
                            Text(
                                "\(module.candidateLocaleIdentifier) — Unavailable"
                            )
                            .tag(module.candidateLocaleIdentifier)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)
                    .disabled(
                        module.supportSnapshot.supportedLocales
                            .isEmpty
                    )
                }

                LabeledContent("Language asset") {
                    Text(assetTitle)
                }

                if module.isInstalling {
                    ProgressView(
                        value: module.installationProgress,
                        total: 1
                    ) {
                        Text("Installing language")
                    }
                    .accessibilityValue(
                        "\(Int(module.installationProgress * 100)) percent"
                    )
                } else if
                    module.permissionStatus == .notDetermined,
                    module.candidateAssetState == .installed
                {
                    Button("Allow Speech Recognition") {
                        Task {
                            await module
                                .requestSpeechRecognitionPermission()
                        }
                    }
                } else if
                    module.requiresInstalledLanguageConfirmation
                {
                    Button("Use Installed Language") {
                        module.confirmInstalledLocale()
                    }
                } else if module.candidateAssetState != .installed {
                    Button(
                        module.permissionStatus == .notDetermined
                            ? "Allow and Install Language"
                            : "Install Language"
                    ) {
                        Task {
                            await module.installSelectedLocale()
                        }
                    }
                    .disabled(
                        module.candidateLocaleIdentifier.isEmpty
                    )
                }
            }

            if let message = module.installationErrorMessage {
                ConfigurationIssueLabel(message: message)
            }

            Label(
                "Completed recording audio is processed on this Mac. Apple may be contacted only to install system-managed language assets.",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var statusTitle: String {
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

    private var statusSystemImage: String {
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

    private var statusColor: Color {
        switch module.readiness.state {
        case .configured:
            .green
        case .pendingValidation:
            .blue
        case .setupRequired, .attentionRequired, .willDisconnect:
            .orange
        }
    }

    private var availabilityMessage: String {
        switch module.supportSnapshot.availability {
        case .requiresMacOS26:
            "Apple On-Device requires macOS 26 or later. OpenAI remains available for transcription."
        case .unavailableOnDevice:
            "The SpeechTranscriber model is unavailable on this Mac. OpenAI remains available for transcription."
        case .available:
            "Apple SpeechTranscriber processes completed recordings locally using a concrete installed language."
        }
    }

    private var permissionTitle: String {
        switch module.permissionStatus {
        case .notDetermined:
            "Not requested"
        case .granted:
            "Allowed"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        }
    }

    private var assetTitle: String {
        switch module.candidateAssetState {
        case .unsupported:
            "Unsupported"
        case .supported:
            "Not installed"
        case .downloading:
            "Installing"
        case .installed:
            "Installed"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
