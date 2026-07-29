import AppKit
import Combine
import OSLog

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var statusText = "Setup required"
    @Published private(set) var primaryActionTitle = "Start Dictation"
    @Published private(set) var isPrimaryActionEnabled = true
    @Published private(set) var canCancel = false
    @Published private(set) var canRetryTranscription = false
    @Published private(set) var canDiscardTranscription = false
    @Published private(set) var canRepairTranscription = false
    @Published private(set) var canTranscribePartial = false
    @Published private(set) var canDiscardPartial = false
    @Published private(set) var canDismissDeliveryStatus = false

    private let settingsStore = SettingsStore()
    private let credentialStore = KeychainCredentialStore()
    private let validator = OpenAIConfigurationValidator()
    private let permissionService = PermissionService()
    private let shortcutService = GlobalShortcutService()
    private let recordingFileStore = RecordingFileStore()
    private let providerRuntimeHealth =
        ProviderRuntimeHealthStore()
    private var hasStarted = false
    private var sessionStateCancellable: AnyCancellable?

    private lazy var audioRecorder = AVFoundationAudioRecorder(
        fileStore: recordingFileStore
    )

    private lazy var transcriptionProvider = OpenAITranscriptionProvider(
        credentialStore: credentialStore
    )

    private lazy var postProcessingProvider =
        OpenAIPostProcessingProvider(
            credentialStore: credentialStore
        )

    private lazy var openAISettingsModule =
        OpenAIProviderSettingsModule(
            credentialStore: credentialStore,
            validator: validator,
            runtimeHealth: providerRuntimeHealth
        )

    private lazy var providerRegistry = ProviderRegistry(
        registrations: [
            ProviderRegistry.Registration(
                settings: AnyProviderSettingsModule(
                    openAISettingsModule
                ),
                transcriptionProvider: transcriptionProvider,
                postProcessingProvider: postProcessingProvider
            ),
        ]
    )

    private lazy var dictationCoordinator = DictationCoordinator(
        recorder: audioRecorder,
        soundCuePlayer: SoundCuePlayer(),
        permissionService: permissionService,
        fileStore: recordingFileStore,
        providerResolver: providerRegistry,
        providerRuntimeHealth: providerRuntimeHealth,
        clipboardService: PasteboardClipboardService(),
        textInsertionService: AccessibilityTextInsertionService()
    )

    private lazy var configurationViewModel: ConfigurationViewModel = {
        let viewModel = ConfigurationViewModel(
            settingsStore: settingsStore,
            permissionService: permissionService,
            shortcutService: shortcutService,
            providerRegistry: providerRegistry,
            providerRuntimeHealth: providerRuntimeHealth
        )
        viewModel.onConfigurationChanged = { [weak self] in
            self?.refreshStatus()
        }
        viewModel.onTranscriptionRepairValidated = { [weak self] repair in
            self?.dictationCoordinator.applyTranscriptionRepair(repair)
        }
        return viewModel
    }()

    private lazy var configurationWindowController =
        ConfigurationWindowController(viewModel: configurationViewModel)

    private lazy var overlayWindowController = OverlayWindowController(
        onStop: { [weak self] in
            self?.dictationCoordinator.stop()
        },
        onCancel: { [weak self] in
            self?.cancelDictation()
        },
        onRetry: { [weak self] in
            self?.retryTranscription()
        },
        onDiscard: { [weak self] in
            self?.discardTranscription()
        },
        onTranscribePartial: { [weak self] in
            self?.transcribePartial()
        },
        onRepairTranscription: { [weak self] in
            self?.showConfiguration()
        },
        onDismiss: { [weak self] in
            self?.dismissDeliveryStatus()
        }
    )

    init() {
        refreshStatus()
    }

    var shouldShowConfigurationOnLaunch: Bool {
        !settingsStore.load().hasCompletedFirstRun
    }

    func start() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        AppLog.lifecycle.info("Application services starting")
        let orphanCount =
            recordingFileStore.removeOrphanedRecordings()
        AppLog.lifecycle.info(
            "Startup cleanup removed \(orphanCount, privacy: .public) recording item(s)"
        )
        sessionStateCancellable = dictationCoordinator.$state.sink {
            [weak self] state in
            self?.apply(state)
        }
        shortcutService.onShortcutPressed = { [weak self] in
            self?.performPrimaryAction()
        }
        shortcutService.onSessionCancellationShortcutPressed = {
            [weak self] in
            self?.cancelDictation()
        }

        do {
            try shortcutService.start(
                with: settingsStore.load().globalShortcut
            )
            AppLog.lifecycle.info("Global shortcut service started")
        } catch {
            AppLog.lifecycle.error(
                "Global shortcut service failed to start"
            )
            // Settings exposes the actionable registration error.
        }

        refreshStatus()
    }

    func applicationDidBecomeActive() {
        configurationViewModel.refreshSystemState()
    }

    func showConfiguration() {
        let route: ConfigurationRoute
        if
            case .transcriptionFailed(let failure) =
                dictationCoordinator.state,
            failure.isConfigurationFailure
        {
            configurationViewModel.setRepairContext(
                dictationCoordinator.transcriptionRepairContext
            )
            route = .transcriptionRepair
        } else if !settingsStore.load().hasCompletedFirstRun {
            configurationViewModel.setRepairContext(nil)
            route = .firstRun
        } else if
            providerRuntimeHealth.message(
                for: PostProcessingConfiguration(
                    appConfiguration:
                        settingsStore.load().configuration
                )
            ) != nil
        {
            configurationViewModel.setRepairContext(nil)
            route = .destination(.postProcessing)
        } else {
            configurationViewModel.setRepairContext(nil)
            route = .ordinary
        }
        configurationWindowController.showConfiguration(route: route)
    }

    func showConfiguration(route: ConfigurationRoute) {
        configurationWindowController.showConfiguration(route: route)
    }

    func stop() {
        AppLog.lifecycle.notice("Bounded application shutdown started")
        dictationCoordinator.shutdownImmediately()
        overlayWindowController.dismiss()
        shortcutService.stop()
        AppLog.lifecycle.notice("Application shutdown cleanup finished")
    }

    func performPrimaryAction() {
        switch dictationCoordinator.state {
        case .idle:
            startDictation()
        case .recording:
            dictationCoordinator.stop()
        case
            .preparing,
            .finalizing,
            .completed,
            .transcribing,
            .postProcessing,
            .inserting,
            .inserted,
            .insertionUnverified,
            .clipboardFallback,
            .rawTranscriptFallback,
            .noSpeech,
            .transcriptionFailed,
            .captureFailed,
            .tooShort,
            .cancelled,
            .failed:
            break
        }
    }

    func cancelDictation() {
        dictationCoordinator.cancel()
    }

    func retryTranscription() {
        dictationCoordinator.retryTranscription()
    }

    func discardTranscription() {
        dictationCoordinator.discardTranscription()
    }

    func transcribePartial() {
        dictationCoordinator.transcribePartial()
    }

    func discardPartial() {
        dictationCoordinator.discardPartial()
    }

    func dismissDeliveryStatus() {
        dictationCoordinator.dismissDeliveryStatus()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func startDictation() {
        guard !configurationViewModel.isValidating else {
            AppLog.session.notice(
                "Dictation start blocked by configuration validation"
            )
            statusText = "Finish Settings validation before starting"
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = true
            canCancel = false
            return
        }

        let storedSettings = settingsStore.load()
        let configuration = storedSettings.configuration
        let readiness = providerRegistry.readiness(
            for: configuration.transcriptionProvider,
            capability: .transcription
        )

        guard isUsable(readiness) else {
            AppLog.session.notice(
                "Dictation start redirected to required setup"
            )
            statusText = "Setup required"
            showConfiguration(
                route: .provider(configuration.transcriptionProvider)
            )
            return
        }
        guard configuration.isStructurallyValid else {
            AppLog.session.notice(
                "Dictation start redirected to transcription settings"
            )
            statusText = "Transcription configuration needs attention"
            showConfiguration(route: .destination(.transcription))
            return
        }

        do {
            try shortcutService.registerSessionCancellationShortcut()
        } catch {
            AppLog.session.error(
                "Dictation start blocked by cancellation shortcut conflict"
            )
            statusText =
                (error as? LocalizedError)?.errorDescription
                ?? "Escape could not be reserved for cancellation. Recording did not start."
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = true
            canCancel = false
            return
        }

        dictationCoordinator.start(
            configuration: SessionConfiguration(
                configuration: configuration,
                recordingProfile: .openAI
            ),
            soundCuesEnabled: storedSettings.soundCuesEnabled
        )
        AppLog.session.info("Dictation start accepted")
    }

    private func refreshStatus(force: Bool = false) {
        guard force || dictationCoordinator.state == .idle else {
            return
        }

        let configuration = settingsStore.load().configuration
        primaryActionTitle = "Start Dictation"
        isPrimaryActionEnabled = true
        canCancel = false
        canRetryTranscription = false
        canDiscardTranscription = false
        canRepairTranscription = false
        canTranscribePartial = false
        canDiscardPartial = false
        canDismissDeliveryStatus = false

        let readiness = providerRegistry.readiness(
            for: configuration.transcriptionProvider,
            capability: .transcription
        )

        guard
            isUsable(readiness),
            configuration.isStructurallyValid
        else {
            statusText = "Setup required"
            return
        }

        if hasStarted && shortcutService.activeShortcut == nil {
            statusText = "Shortcut unavailable"
        } else if
            configuration.postProcessingMode == .enabled,
            providerRuntimeHealth.shouldSkip(
                PostProcessingConfiguration(
                    appConfiguration: configuration
                )
            )
        {
            statusText = "Ready — cleanup needs attention"
        } else {
            statusText = "Ready"
        }
    }

    private func apply(_ state: DictationSessionState) {
        configurationViewModel.setSessionAccess(
            configurationAccess(for: state)
        )

        canRetryTranscription = false
        canDiscardTranscription = false
        canRepairTranscription = false
        canTranscribePartial = false
        canDiscardPartial = false
        canDismissDeliveryStatus = false

        switch state {
        case .idle:
            shortcutService.unregisterSessionCancellationShortcut()
            overlayWindowController.dismiss()
            refreshStatus(force: true)
        case .preparing:
            statusText = "Preparing recording…"
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = true
            overlayWindowController.present(.preparing)
        case .recording(let recording):
            let elapsed = formatDuration(recording.elapsed)
            statusText =
                recording.isNearDurationLimit
                ? "Recording \(elapsed) — \(recording.inputDeviceName) — limit soon"
                : "Recording \(elapsed) — \(recording.inputDeviceName)"
            primaryActionTitle = "Stop Dictation"
            isPrimaryActionEnabled = true
            canCancel = true
            overlayWindowController.present(
                .recording(
                    elapsed: recording.elapsed,
                    inputDeviceName: recording.inputDeviceName,
                    isNearDurationLimit: recording.isNearDurationLimit
                )
            )
        case .finalizing(let reason):
            switch reason {
            case .stopped:
                statusText = "Finalizing recording…"
            case .automaticLimit:
                statusText = "Maximum duration reached — finalizing…"
            case .cancelled:
                statusText = "Cancelling recording…"
            }
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = true
            overlayWindowController.present(.finalizing(reason))
        case .completed(let artifact):
            statusText =
                "Captured locally (\(formatDuration(artifact.duration)))"
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = true
            overlayWindowController.present(
                .completed(duration: artifact.duration)
            )
        case .transcribing(let provider):
            statusText =
                "Uploading completed audio to \(provider.displayName)…"
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = true
            overlayWindowController.present(
                .transcribing(providerName: provider.displayName)
            )
        case .postProcessing(let provider):
            statusText =
                "Cleaning up transcript with \(provider.displayName)…"
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = true
            overlayWindowController.present(
                .postProcessing(
                    providerName: provider.displayName
                )
            )
        case .inserting:
            statusText = "Inserting transcript…"
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = true
            overlayWindowController.present(.inserting)
        case .inserted:
            shortcutService.unregisterSessionCancellationShortcut()
            statusText = "Transcript inserted"
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = false
            overlayWindowController.present(.inserted)
        case .insertionUnverified(let message):
            shortcutService.unregisterSessionCancellationShortcut()
            statusText = message
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = false
            canDismissDeliveryStatus = true
            overlayWindowController.present(
                .insertionUnverified(message: message)
            )
        case .clipboardFallback(let message):
            shortcutService.unregisterSessionCancellationShortcut()
            statusText = message
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = false
            canDismissDeliveryStatus = true
            overlayWindowController.present(
                .clipboardFallback(message: message)
            )
        case .rawTranscriptFallback(let message):
            shortcutService.unregisterSessionCancellationShortcut()
            statusText = message
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = false
            overlayWindowController.present(
                .rawTranscriptFallback(message: message)
            )
        case .noSpeech:
            shortcutService.unregisterSessionCancellationShortcut()
            statusText = "No speech detected"
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = false
            overlayWindowController.present(.noSpeech)
        case .transcriptionFailed(let failure):
            statusText = failure.message
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = true
            canRetryTranscription = true
            canDiscardTranscription = true
            canRepairTranscription =
                failure.isConfigurationFailure
            overlayWindowController.present(
                .transcriptionFailed(
                    message: failure.message,
                    canRepair: failure.isConfigurationFailure
                )
            )
        case .captureFailed(let failure):
            statusText = failure.message
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = true
            canTranscribePartial = true
            canDiscardPartial = true
            overlayWindowController.present(
                .captureFailed(
                    message: failure.message,
                    duration: failure.artifact.duration
                )
            )
        case .tooShort:
            statusText = "Recording too short — discarded"
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = true
            overlayWindowController.present(.tooShort)
        case .cancelled:
            statusText = "Recording cancelled"
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = true
            overlayWindowController.present(.cancelled)
        case .failed(let error):
            statusText = error.localizedDescription
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = true
            overlayWindowController.present(
                .failed(message: error.localizedDescription)
            )
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        return String(
            format: "%d:%02d",
            totalSeconds / 60,
            totalSeconds % 60
        )
    }

    private func configurationAccess(
        for state: DictationSessionState
    ) -> ConfigurationSessionAccess {
        switch state {
        case
            .idle,
            .inserted,
            .insertionUnverified,
            .clipboardFallback,
            .rawTranscriptFallback,
            .noSpeech:
            return .editable
        case .transcriptionFailed(let failure)
            where failure.isConfigurationFailure:
            return .transcriptionRepair
        case
            .preparing,
            .recording,
            .finalizing,
            .completed,
            .transcribing,
            .postProcessing,
            .inserting,
            .transcriptionFailed,
            .captureFailed,
            .tooShort,
            .cancelled,
            .failed:
            return .readOnly
        }
    }

    private func isUsable(_ readiness: ProviderReadiness) -> Bool {
        switch readiness.state {
        case .configured:
            true
        case
            .setupRequired,
            .attentionRequired,
            .pendingValidation,
            .willDisconnect:
            false
        }
    }
}
