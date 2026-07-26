import AppKit
import SwiftUI

@MainActor
final class ConfigurationWindowController: NSWindowController {
    init() {
        let hostingController = NSHostingController(
            rootView: ConfigurationView()
        )
        let window = NSWindow(contentViewController: hostingController)

        window.title = "DictationApp Settings"
        window.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
        ]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 370))
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func showConfiguration() {
        guard let window else {
            return
        }

        showWindow(nil)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
