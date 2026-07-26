import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var statusText = "Setup required"

    private let settingsStore = SettingsStore()
    private let credentialStore = KeychainCredentialStore()
    private let validator = OpenAIConfigurationValidator()

    private lazy var configurationViewModel: ConfigurationViewModel = {
        let viewModel = ConfigurationViewModel(
            settingsStore: settingsStore,
            credentialStore: credentialStore,
            validator: validator
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

    func showConfiguration() {
        configurationWindowController.showConfiguration()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func refreshStatus() {
        let configuration = settingsStore.load().configuration
        let hasCredential = (try? credentialStore.credentialExists()) ?? false

        statusText = hasCredential && configuration.isStructurallyValid
            ? "Ready"
            : "Setup required"
    }
}
