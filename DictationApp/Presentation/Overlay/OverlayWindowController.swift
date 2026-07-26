import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let onStop: () -> Void
    private let onCancel: () -> Void
    private let onRetry: () -> Void
    private let onDiscard: () -> Void

    private var panel: OverlayPanel?
    private var hostingController: NSHostingController<OverlayView>?
    private var sessionScreen: NSScreen?

    init(
        onStop: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.onStop = onStop
        self.onCancel = onCancel
        self.onRetry = onRetry
        self.onDiscard = onDiscard
    }

    func present(_ state: OverlayViewState) {
        if sessionScreen == nil {
            sessionScreen = screenContainingPointer()
        }

        let view = OverlayView(
            state: state,
            onStop: onStop,
            onCancel: onCancel,
            onRetry: onRetry,
            onDiscard: onDiscard
        )

        if let hostingController {
            hostingController.rootView = view
        } else {
            let hostingController = NSHostingController(rootView: view)
            self.hostingController = hostingController

            let panel = makePanel()
            panel.contentViewController = hostingController
            self.panel = panel
        }

        guard let panel, let hostingController else {
            return
        }

        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        panel.setContentSize(
            NSSize(
                width: max(500, fittingSize.width),
                height: max(64, fittingSize.height)
            )
        )
        position(panel, on: sessionScreen)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
        sessionScreen = nil
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: .zero,
            styleMask: [
                .borderless,
                .nonactivatingPanel,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
        ]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.worksWhenModal = true
        panel.animationBehavior = .none
        return panel
    }

    private func screenContainingPointer() -> NSScreen? {
        let pointerLocation = NSEvent.mouseLocation
        return NSScreen.screens.first {
            NSMouseInRect(pointerLocation, $0.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func position(_ panel: NSPanel, on screen: NSScreen?) {
        guard let screen else {
            panel.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let panelFrame = panel.frame
        let origin = NSPoint(
            x: visibleFrame.midX - panelFrame.width / 2,
            y: visibleFrame.minY + 28
        )
        panel.setFrameOrigin(origin)
    }
}
