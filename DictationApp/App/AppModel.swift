import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var statusText = "Setup required"

    private let settingsStore = SettingsStore()
    private let credentialStore = KeychainCredentialStore()
    private let validator = OpenAIConfigurationValidator()
    private let permissionService = PermissionService()
    private let shortcutService = GlobalShortcutService()
    private var hasStarted = false

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
        shortcutService.onShortcutPressed = { [weak self] in
            self?.handleGlobalShortcut()
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
        shortcutService.stop()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func handleGlobalShortcut() {
        let configuration = settingsStore.load().configuration
        let hasCredential = (try? credentialStore.credentialExists()) ?? false

        guard hasCredential && configuration.isStructurallyValid else {
            statusText = "Setup required"
            showConfiguration()
            return
        }

        statusText = "Recording engine not available yet"
    }

    private func refreshStatus() {
        let configuration = settingsStore.load().configuration
        let hasCredential = (try? credentialStore.credentialExists()) ?? false

        guard hasCredential && configuration.isStructurallyValid else {
            statusText = "Setup required"
            return
        }

        statusText =
            hasStarted && shortcutService.activeShortcut == nil
                ? "Shortcut unavailable"
                : "Ready"
    }
}
