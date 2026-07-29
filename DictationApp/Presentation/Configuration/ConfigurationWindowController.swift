import AppKit
import SwiftUI

@MainActor
final class ConfigurationWindowController:
    NSWindowController,
    NSWindowDelegate
{
    private let viewModel: ConfigurationViewModel
    private var bypassCloseProtection = false
    private var isPresentingCloseAlert = false

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
        window.setContentSize(NSSize(width: 860, height: 720))
        window.minSize = NSSize(width: 760, height: 620)
        window.center()

        super.init(window: window)

        window.delegate = self
        viewModel.onRequestClose = { [weak self] in
            self?.closeWithoutPrompt()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func showConfiguration(route: ConfigurationRoute = .ordinary) {
        guard let window else {
            return
        }

        viewModel.prepareForPresentation(route)
        showWindow(nil)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.recalculateKeyViewLoop()
    }

    func showConfiguration(
        mode: ConfigurationPresentationMode = .full
    ) {
        showConfiguration(
            route:
                mode == .transcriptionRepair
                ? .transcriptionRepair
                : .ordinary
        )
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if bypassCloseProtection {
            bypassCloseProtection = false
            return true
        }

        guard !isPresentingCloseAlert else {
            return false
        }

        if viewModel.isValidating {
            presentValidationCloseAlert(on: sender)
            return false
        }

        if viewModel.hasUnsavedChanges {
            presentDirtyCloseAlert(on: sender)
            return false
        }

        return true
    }

    private func presentValidationCloseAlert(on window: NSWindow) {
        isPresentingCloseAlert = true
        let alert = NSAlert()
        alert.messageText = "Cancel configuration validation?"
        alert.informativeText =
            "No changes have been committed. The Settings draft will remain available."
        alert.addButton(withTitle: "Cancel Validation")
        alert.addButton(withTitle: "Keep Validating")

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else {
                return
            }
            self.isPresentingCloseAlert = false
            if response == .alertFirstButtonReturn {
                self.viewModel.cancelValidation()
            }
        }
    }

    private func presentDirtyCloseAlert(on window: NSWindow) {
        isPresentingCloseAlert = true
        let alert = NSAlert()
        alert.messageText = "Save changes before closing?"
        alert.informativeText =
            "Your changes apply together only after validation succeeds."
        alert.addButton(withTitle: viewModel.saveButtonTitle)
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else {
                return
            }
            self.isPresentingCloseAlert = false

            switch response {
            case .alertFirstButtonReturn:
                Task {
                    let result = await self.viewModel.save()
                    if result == .saved {
                        self.closeWithoutPrompt()
                    }
                }
            case .alertSecondButtonReturn:
                self.viewModel.discardChanges()
                self.closeWithoutPrompt()
            default:
                break
            }
        }
    }

    private func closeWithoutPrompt() {
        guard let window, window.isVisible else {
            return
        }
        bypassCloseProtection = true
        window.performClose(nil)
    }
}
