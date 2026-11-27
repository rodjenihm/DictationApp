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
    @Published private(set) var canCopyCommandResult = false

    private let settingsStore = SettingsStore()
    private let credentialStore = KeychainCredentialStore()
    private let validator = OpenAIConfigurationValidator()
    private let permissionService = PermissionService()
    private let shortcutService = GlobalShortcutService()
    private let audioInputDeviceService =
        CoreAudioInputDeviceService()
    private let recordingFileStore = RecordingFileStore()
    private let providerRuntimeHealth =
        ProviderRuntimeHealthStore()
    private let clipboardService = PasteboardClipboardService()
    private let textInsertionService = AccessibilityTextInsertionService()
    private var hasStarted = false
    private var hasStopped = false
    private var holdOwnsCapture = false
    private var sessionStateCancellable: AnyCancellable?
    private var providerSettingsCancellables: [AnyCancellable] = []

    private lazy var audioRecorder = CoreAudioRecorder(
        fileStore: recordingFileStore,
        audioInputDeviceService: audioInputDeviceService
    )

    private lazy var transcriptionProvider = OpenAITranscriptionProvider(
        credentialStore: credentialStore
    )

    private lazy var appleSpeechService = AppleSpeechService()

    private lazy var appleTranscriptionProvider =
        AppleOnDeviceTranscriptionProvider(
            speechService: appleSpeechService
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

    private lazy var appleSettingsModule =
        AppleOnDeviceProviderSettingsModule(
            speechService: appleSpeechService,
            permissionService: permissionService,
            settingsStore: settingsStore
        )

    private lazy var appleIntelligenceSettingsModule =
        AppleIntelligenceProviderSettingsModule()

    private lazy var providerRegistry = ProviderRegistry(
        registrations: [
            ProviderRegistry.Registration(
                settings: AnyProviderSettingsModule(
                    appleSettingsModule
                ),
                transcriptionProvider:
                    appleTranscriptionProvider,
                postProcessingProvider: nil
            ),
            ProviderRegistry.Registration(
                settings: AnyProviderSettingsModule(appleIntelligenceSettingsModule),
                transcriptionProvider: nil,
                postProcessingProvider: AppleIntelligencePostProcessingProvider()
            ),
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
        clipboardService: clipboardService,
        textInsertionService: textInsertionService,
        selectionReplacer: textInsertionService
    )

    private lazy var configurationViewModel: ConfigurationViewModel = {
        let viewModel = ConfigurationViewModel(
            settingsStore: settingsStore,
            permissionService: permissionService,
            shortcutService: shortcutService,
            audioInputDeviceService: audioInputDeviceService,
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
        },
        onCopyCommandResult: { [weak self] in
            self?.copyCommandResult()
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
        providerSettingsCancellables =
            providerRegistry.settingsModules.map { module in
                module.objectWillChange.sink { [weak self] _ in
                    self?.refreshStatus()
                }
            }
        shortcutService.onShortcutPressed = { [weak self] receivedAt, replacesHold in
            guard let self else {
                return
            }
            if replacesHold && self.holdOwnsCapture && !self.dictationCoordinator.isCommandSession {
                self.holdOwnsCapture = false
                return
            }
            self.performPrimaryAction(receivedAt: receivedAt)
        }
        shortcutService.onHoldShortcutPressed = { [weak self] receivedAt in
            self?.performPrimaryAction(receivedAt: receivedAt, fromHold: true)
        }
        shortcutService.onHoldShortcutReleased = { [weak self] receivedAt in
            self?.endHold(receivedAt: receivedAt)
        }
        shortcutService.onHoldShortcutCancelled = { [weak self] in
            self?.cancelHold(forCommand: false)
        }
        shortcutService.onCommandShortcutPressed = { [weak self] receivedAt in
            self?.startCommand(receivedAt: receivedAt)
        }
        shortcutService.onCommandShortcutReleased = { [weak self] receivedAt in
            self?.endHold(receivedAt: receivedAt, forCommand: true)
        }
        shortcutService.onCommandShortcutCancelled = { [weak self] in
            self?.cancelHold(forCommand: true)
        }
        shortcutService.onSessionCancellationShortcutPressed = {
            [weak self] in
            self?.cancelDictation()
        }

        let settings = settingsStore.load()
        do {
            try shortcutService.start(
                toggle: settings.globalShortcut,
                hold: settings.holdShortcut,
                command: settings.commandShortcut
            )
            AppLog.lifecycle.info("Global shortcut service started")
        } catch {
            AppLog.lifecycle.error(
                "One or more global shortcuts could not be registered"
            )
            // Settings exposes the actionable registration error.
        }

        refreshStatus()
        Task { @MainActor [weak self] in
            self?.overlayWindowController.prewarm()
        }
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
        guard !hasStopped else {
            return
        }
        hasStopped = true
        AppLog.lifecycle.notice("Bounded application shutdown started")
        dictationCoordinator.shutdownImmediately()
        overlayWindowController.dismiss()
        shortcutService.stop()
        AppLog.lifecycle.notice("Application shutdown cleanup finished")
    }

    var hasPendingClipboardRestoration: Bool {
        clipboardService.hasPendingRestoration
    }

    func finishPendingClipboardRestoration() async {
        await clipboardService.finishPendingRestoration()
    }

    func performPrimaryAction(
        receivedAt: ContinuousClock.Instant = .now,
        fromHold: Bool = false
    ) {
        switch dictationCoordinator.state {
        case .idle:
            startDictation(receivedAt: receivedAt, fromHold: fromHold)
        case .rawTranscriptFallback, .commandFeedback:
            dictationCoordinator.dismissDeliveryStatus()
            startDictation(receivedAt: receivedAt, fromHold: fromHold)
        case .recording where !fromHold && !dictationCoordinator.isCommandSession:
            dictationCoordinator.stop(receivedAt: receivedAt)
        case
            .preparing,
            .recording,
            .finalizing,
            .completed,
            .transcribing,
            .postProcessing,
            .inserting,
            .inserted,
            .insertionUnverified,
            .clipboardFallback,
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

    func copyCommandResult() {
        guard let result = dictationCoordinator.copyableCommandResult() else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(result, forType: .string) {
            dismissDeliveryStatus()
        }
    }

    var cancelActionTitle: String {
        dictationCoordinator.isCommandSession ? "Cancel Command" : "Cancel Dictation"
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func endHold(
        receivedAt: ContinuousClock.Instant,
        forCommand: Bool = false
    ) {
        guard holdOwnsCapture, dictationCoordinator.isCommandSession == forCommand else {
            return
        }
        holdOwnsCapture = false

        switch dictationCoordinator.state {
        case .preparing:
            dictationCoordinator.cancelImmediately()
        case .recording:
            dictationCoordinator.stop(receivedAt: receivedAt)
        default:
            break
        }
    }

    private func cancelHold(forCommand: Bool) {
        guard holdOwnsCapture, dictationCoordinator.isCommandSession == forCommand else {
            return
        }
        holdOwnsCapture = false
        dictationCoordinator.cancelImmediately()
    }

    private func startCommand(receivedAt: ContinuousClock.Instant) {
        if case .commandFeedback = dictationCoordinator.state {
            dismissDeliveryStatus()
        }
        guard dictationCoordinator.state == .idle else {
            return
        }
        guard !configurationViewModel.isValidating else {
            dictationCoordinator.showCommandRejection(
                "Finish Settings validation before running a command."
            )
            return
        }

        let selection: EditableSelection
        do {
            selection = try textInsertionService.captureEditableSelection()
        } catch {
            dictationCoordinator.showCommandRejection(error.localizedDescription)
            return
        }
        guard selection.text.utf8.count <= TextCommandRequest.maximumSelectionUTF8Count else {
            dictationCoordinator.showCommandRejection("Select a shorter passage to run a command.")
            return
        }

        let settings = settingsStore.load()
        let configuration = settings.configuration
        let transcriptionReadiness = providerRegistry.readiness(
            for: configuration.transcriptionProvider,
            capability: .transcription
        )
        guard isUsable(transcriptionReadiness), configuration.isStructurallyValid else {
            dictationCoordinator.showCommandRejection(
                "Check the transcription and cleanup settings before running a command."
            )
            return
        }
        providerRegistry.settingsModule(for: configuration.postProcessingProvider)?
            .refreshSystemState()
        let cleanupReadiness = providerRegistry.readiness(
            for: configuration.postProcessingProvider,
            capability: .postProcessing
        )
        guard
            isUsable(cleanupReadiness),
            !configuration.postProcessingModel.normalized.identifier.isEmpty,
            !providerRuntimeHealth.shouldSkip(
                PostProcessingConfiguration(appConfiguration: configuration)
            )
        else {
            dictationCoordinator.showCommandRejection(
                "Check the Command Mode provider in Post-processing settings."
            )
            return
        }
        startCapture(
            settings: settings,
            receivedAt: receivedAt,
            fromHold: true,
            commandSelection: selection
        )
    }

    private func startDictation(
        receivedAt: ContinuousClock.Instant,
        fromHold: Bool
    ) {
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

        startCapture(
            settings: storedSettings,
            receivedAt: receivedAt,
            fromHold: fromHold
        )
    }

    private func startCapture(
        settings: StoredSettings,
        receivedAt: ContinuousClock.Instant,
        fromHold: Bool,
        commandSelection: EditableSelection? = nil
    ) {
        let isCommand = commandSelection != nil
        do {
            try shortcutService.registerSessionCancellationShortcut(
                forHold: fromHold && !isCommand,
                forCommand: isCommand
            )
        } catch {
            AppLog.session.error(
                "Recording start blocked by cancellation shortcut conflict"
            )
            let message =
                (error as? LocalizedError)?.errorDescription
                ?? "Escape could not be reserved for cancellation. Recording did not start."
            if isCommand {
                dictationCoordinator.showCommandRejection(message)
                return
            }
            statusText = message
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = true
            canCancel = false
            return
        }

        holdOwnsCapture = fromHold
        dictationCoordinator.start(
            configuration: SessionConfiguration(
                configuration: settings.configuration,
                recordingProfile: .completedM4A
            ),
            soundCuesEnabled: settings.soundCuesEnabled,
            commandSelection: commandSelection,
            receivedAt: receivedAt
        )
        AppLog.session.info("Recording start accepted")
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
        canCopyCommandResult = false

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
        switch state {
        case .preparing, .recording:
            break
        default:
            holdOwnsCapture = false
        }

        configurationViewModel.setSessionAccess(
            configurationAccess(for: state)
        )

        canRetryTranscription = false
        canDiscardTranscription = false
        canRepairTranscription = false
        canTranscribePartial = false
        canDiscardPartial = false
        canDismissDeliveryStatus = false
        canCopyCommandResult = false

        if dictationCoordinator.isCommandSession, applyCommandProgress(state) {
            return
        }

        switch state {
        case .idle:
            shortcutService.unregisterSessionCancellationShortcut()
            overlayWindowController.dismiss()
            refreshStatus(force: true)
        case .preparing:
            statusText = "Activating microphone…"
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = false
            canCancel = true
            overlayWindowController.present(.preparing)
        case .recording(let recording):
            let elapsed = formatDuration(recording.elapsed)
            statusText =
                recordingStatusText(
                    elapsed: elapsed,
                    recording: recording
                )
            primaryActionTitle = "Stop Dictation"
            isPrimaryActionEnabled = true
            canCancel = true
            overlayWindowController.present(
                .recording(
                    elapsed: recording.elapsed,
                    inputDeviceName: recording.inputDeviceName,
                    isUsingFallback: recording.isUsingFallback,
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
                provider == .appleOnDevice
                ? "Transcribing on this Mac…"
                : "Uploading completed audio to \(provider.displayName)…"
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
            overlayWindowController.dismiss()
            refreshStatus(force: true)
            announceAccessibility(
                dictationCoordinator.isCommandSession ? "Command applied" : "Transcript inserted"
            )
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
        case .rawTranscriptFallback(let fallback):
            shortcutService.unregisterSessionCancellationShortcut()
            statusText = "\(fallback.message) Original text pasted."
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = true
            canCancel = false
            overlayWindowController.present(
                .rawTranscriptFallback(message: "\(fallback.title) · Original text pasted")
            )
            announceAccessibility(statusText)
        case .commandFeedback(let message, let canCopyResult):
            shortcutService.unregisterSessionCancellationShortcut()
            statusText = message
            primaryActionTitle = "Start Dictation"
            isPrimaryActionEnabled = true
            canCancel = false
            canDismissDeliveryStatus = true
            canCopyCommandResult = canCopyResult
            overlayWindowController.present(
                .commandFeedback(message: message, canCopyResult: canCopyResult)
            )
            announceAccessibility(message)
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

    private func applyCommandProgress(_ state: DictationSessionState) -> Bool {
        let overlay: OverlayViewState
        switch state {
        case .preparing:
            statusText = "Starting command…"
            overlay = .commandWorking(message: statusText)
        case .recording(let recording):
            statusText = "Listening for command…"
            overlay = .commandListening(elapsed: recording.elapsed)
        case .finalizing, .completed, .transcribing:
            statusText = "Transcribing command…"
            overlay = .commandWorking(message: statusText)
        case .postProcessing, .inserting:
            statusText = "Applying command…"
            overlay = .commandWorking(message: statusText)
        default:
            return false
        }
        primaryActionTitle = "Start Dictation"
        isPrimaryActionEnabled = false
        canCancel = true
        overlayWindowController.present(overlay)
        return true
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        return String(
            format: "%d:%02d",
            totalSeconds / 60,
            totalSeconds % 60
        )
    }

    private func announceAccessibility(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }

    private func recordingStatusText(
        elapsed: String,
        recording: RecordingSessionState
    ) -> String {
        var components = [
            "Recording \(elapsed)",
            recording.inputDeviceName,
        ]
        if recording.isUsingFallback {
            components.append("preferred microphone unavailable")
        }
        if recording.isNearDurationLimit {
            components.append("limit soon")
        }
        return components.joined(separator: " — ")
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
            .commandFeedback,
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
