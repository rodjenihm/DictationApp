import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let onStop: () -> Void
    private let onCancel: () -> Void
    private let onRetry: () -> Void
    private let onDiscard: () -> Void
    private let onTranscribePartial: () -> Void
    private let onRepairTranscription: () -> Void
    private let onDismiss: () -> Void
    private let onCopyCommandResult: () -> Void

    private var panel: OverlayPanel?
    private var hostingController: NSHostingController<OverlayView>?
    private var sessionScreen: NSScreen?

    init(
        onStop: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onDiscard: @escaping () -> Void,
        onTranscribePartial: @escaping () -> Void,
        onRepairTranscription: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onCopyCommandResult: @escaping () -> Void
    ) {
        self.onStop = onStop
        self.onCancel = onCancel
        self.onRetry = onRetry
        self.onDiscard = onDiscard
        self.onTranscribePartial = onTranscribePartial
        self.onRepairTranscription = onRepairTranscription
        self.onDismiss = onDismiss
        self.onCopyCommandResult = onCopyCommandResult
    }

    func prewarm() {
        guard panel == nil else {
            return
        }
        preparePanel(for: .preparing)
    }

    func present(_ state: OverlayViewState) {
        if sessionScreen == nil {
            sessionScreen = screenContainingPointer()
        }
        preparePanel(for: state)
        guard let panel else {
            return
        }
        position(panel, on: sessionScreen)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        }
        sessionScreen = nil
    }

    private func preparePanel(for state: OverlayViewState) {
        let reusesPreparingView =
            state == .preparing && hostingController?.rootView.state == .preparing
        if !reusesPreparingView {
            let view = OverlayView(
                state: state,
                onStop: onStop,
                onCancel: onCancel,
                onRetry: onRetry,
                onDiscard: onDiscard,
                onTranscribePartial: onTranscribePartial,
                onRepairTranscription: onRepairTranscription,
                onDismiss: onDismiss,
                onCopyCommandResult: onCopyCommandResult
            )

            if let hostingController {
                hostingController.rootView = view
            } else {
                let hostingController = NSHostingController(rootView: view)
                let panel = makePanel()
                panel.contentViewController = hostingController
                self.hostingController = hostingController
                self.panel = panel
            }
        }

        guard let panel, let view = hostingController?.view else {
            return
        }
        guard
            !reusesPreparingView || view.needsLayout
                || view.needsUpdateConstraints
        else {
            return
        }
        view.layoutSubtreeIfNeeded()
        let fittingSize = view.fittingSize
        panel.setContentSize(
            NSSize(
                width: ceil(max(1, fittingSize.width)),
                height: ceil(max(1, fittingSize.height))
            )
        )
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
