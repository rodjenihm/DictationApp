import AppKit

@MainActor
final class AppModel {
    private lazy var configurationWindowController =
        ConfigurationWindowController()

    let statusText = "Setup required"

    func showConfiguration() {
        configurationWindowController.showConfiguration()
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
