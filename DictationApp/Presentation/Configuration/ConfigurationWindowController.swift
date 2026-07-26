import AppKit
import SwiftUI

@MainActor
final class ConfigurationWindowController: NSWindowController {
    private let viewModel: ConfigurationViewModel

    init(viewModel: ConfigurationViewModel) {
        self.viewModel = viewModel
        let hostingController = NSHostingController(
            rootView: ConfigurationView(viewModel: viewModel)
        )
        let window = NSWindow(contentViewController: hostingController)

        window.title = "DictationApp Settings"
        window.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
        ]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 700, height: 760))
        window.minSize = NSSize(width: 640, height: 660)
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

        viewModel.reload()
        showWindow(nil)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
