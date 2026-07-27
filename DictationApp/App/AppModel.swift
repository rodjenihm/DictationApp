import AppKit
import Combine

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
    private let postProcessingRuntimeHealth =
        PostProcessingRuntimeHealth()
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

    private lazy var dictationCoordinator = DictationCoordinator(
        recorder: audioRecorder,
        soundCuePlayer: SoundCuePlayer(),
        permissionService: permissionService,
        fileStore: recordingFileStore,
        transcriptionProvider: transcriptionProvider,
        postProcessingProvider: postProcessingProvider,
        postProcessingRuntimeHealth:
            postProcessingRuntimeHealth,
        clipboardService: PasteboardClipboardService(),
        textInsertionService: AccessibilityTextInsertionService()
    )

    private lazy var configurationViewModel: ConfigurationViewModel = {
        let viewModel = ConfigurationViewModel(
            settingsStore: settingsStore,
            credentialStore: credentialStore,
            validator: validator,
            permissionService: permissionService,
            shortcutService: shortcutService,
            postProcessingRuntimeHealth:
                postProcessingRuntimeHealth
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
        recordingFileStore.removeOrphanedRecordings()
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
        } catch {
            // Settings exposes the actionable registration error.
        }

        refreshStatus()
    }

    func applicationDidBecomeActive() {
        configurationViewModel.refreshSystemState()
    }

    func showConfiguration() {
        let mode: ConfigurationPresentationMode
        if
            case .transcriptionFailed(let failure) =
                dictationCoordinator.state,
            failure.isConfigurationFailure
        {
            mode = .transcriptionRepair
        } else {
            mode = .full
        }
        configurationWindowController.showConfiguration(mode: mode)
    }

    func stop() {
        dictationCoordinator.cancelImmediately()
        overlayWindowController.dismiss()
        shortcutService.stop()
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
            statusText = "Finish Settings validation before starting"
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = true
            canCancel = false
            return
        }

        let storedSettings = settingsStore.load()
        let configuration = storedSettings.configuration
        let hasCredential = (try? credentialStore.credentialExists()) ?? false

        guard hasCredential && configuration.isStructurallyValid else {
            statusText = "Setup required"
            showConfiguration()
            return
        }

        do {
            try shortcutService.registerSessionCancellationShortcut()
        } catch {
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
    }

    private func refreshStatus(force: Bool = false) {
        guard force || dictationCoordinator.state == .idle else {
            return
        }

        let configuration = settingsStore.load().configuration
        let hasCredential = (try? credentialStore.credentialExists()) ?? false

        primaryActionTitle = "Start Dictation"
        isPrimaryActionEnabled = true
        canCancel = false
        canRetryTranscription = false
        canDiscardTranscription = false
        canRepairTranscription = false
        canTranscribePartial = false
        canDiscardPartial = false
        canDismissDeliveryStatus = false

        guard hasCredential && configuration.isStructurallyValid else {
            statusText = "Setup required"
            return
        }

        if hasStarted && shortcutService.activeShortcut == nil {
            statusText = "Shortcut unavailable"
        } else if
            configuration.postProcessingMode == .enabled,
            postProcessingRuntimeHealth.shouldSkip(
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
}
