import AppKit
import SwiftUI

struct AccessibleActionButton: NSViewRepresentable {
    @Environment(\.isEnabled) private var environmentIsEnabled

    let title: String
    let accessibilityLabel: String
    let accessibilityHelp: String?
    var isDefault = false
    let action: () -> Void

    func makeNSView(context: Context) -> AccessibleButtonControl {
        let control = AccessibleButtonControl()
        update(control)
        return control
    }

    func updateNSView(
        _ control: AccessibleButtonControl,
        context: Context
    ) {
        update(control)
    }

    private func update(_ control: AccessibleButtonControl) {
        control.title = title
        control.onAction = action
        control.isEnabled = environmentIsEnabled
        control.isDefaultAction = isDefault
        control.keyEquivalent = isDefault ? "\r" : ""
        control.keyEquivalentModifierMask = []
        control.bezelColor =
            isDefault && environmentIsEnabled
            ? .controlAccentColor
            : nil
        control.contentTintColor =
            isDefault && environmentIsEnabled
            ? .white
            : nil
        control.setAccessibilityLabel(accessibilityLabel)
        control.setAccessibilityHelp(accessibilityHelp)
    }
}

final class AccessibleButtonControl: NSButton {
    var onAction: (() -> Void)?
    var isDefaultAction = false {
        didSet {
            updateDefaultButton()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        focusRingType = .exterior
        target = self
        action = #selector(performAction)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDefaultButton()
    }

    @objc
    private func performAction() {
        onAction?()
    }

    private func updateDefaultButton() {
        guard let window, let buttonCell = cell as? NSButtonCell else {
            return
        }

        if isDefaultAction {
            window.defaultButtonCell = buttonCell
        } else if window.defaultButtonCell === buttonCell {
            window.defaultButtonCell = nil
        }
    }
}
