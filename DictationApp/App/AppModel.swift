import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var statusText = "Setup required"
    @Published private(set) var primaryActionTitle = "Start Dictation"
    @Published private(set) var isPrimaryActionEnabled = true
    @Published private(set) var canCancel = false

    private let settingsStore = SettingsStore()
    private let credentialStore = KeychainCredentialStore()
    private let validator = OpenAIConfigurationValidator()
    private let permissionService = PermissionService()
    private let shortcutService = GlobalShortcutService()
    private let recordingFileStore = RecordingFileStore()
    private var hasStarted = false
    private var sessionStateCancellable: AnyCancellable?

    private lazy var audioRecorder = AVFoundationAudioRecorder(
        fileStore: recordingFileStore
    )

    private lazy var dictationCoordinator = DictationCoordinator(
        recorder: audioRecorder,
        soundCuePlayer: SoundCuePlayer(),
        permissionService: permissionService,
        fileStore: recordingFileStore
    )

    private lazy var configurationViewModel: ConfigurationViewModel = {
        let viewModel = ConfigurationViewModel(
            settingsStore: settingsStore,
            credentialStore: credentialStore,
            validator: validator,
            permissionService: permissionService,
            shortcutService: shortcutService
        )
        viewModel.onConfigurationChanged = { [weak self] in
            self?.refreshStatus()
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
        configurationWindowController.showConfiguration()
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
            .tooShort,
            .cancelled,
            .failed:
            break
        }
    }

    func cancelDictation() {
        dictationCoordinator.cancel()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func startDictation() {
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

        guard hasCredential && configuration.isStructurallyValid else {
            statusText = "Setup required"
            return
        }

        statusText =
            hasStarted && shortcutService.activeShortcut == nil
                ? "Shortcut unavailable"
                : "Ready"
    }

    private func apply(_ state: DictationSessionState) {
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
}
