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
        window.autorecalculatesKeyViewLoop = true
        window.setContentSize(NSSize(width: 720, height: 840))
        window.minSize = NSSize(width: 660, height: 700)
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func showConfiguration(
        mode: ConfigurationPresentationMode = .full
    ) {
        guard let window else {
            return
        }

        viewModel.prepareForPresentation(mode)
        showWindow(nil)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.recalculateKeyViewLoop()
    }
}
