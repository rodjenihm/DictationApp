import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appModel = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appModel.start()

        if appModel.shouldShowConfigurationOnLaunch {
            DispatchQueue.main.async { [appModel] in
                appModel.showConfiguration()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        appModel.applicationDidBecomeActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }
}
