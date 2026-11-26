import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Environment(\.isEnabled) private var environmentIsEnabled

    let shortcut: GlobalShortcut?
    let accessibilityLabel: String
    let onCandidate: (GlobalShortcut) -> Void
    let onCaptureChanged: (ObjectIdentifier, ((GlobalShortcut) -> Void)?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl()
        configure(control)
        return control
    }

    func updateNSView(
        _ control: ShortcutRecorderControl,
        context: Context
    ) {
        configure(control)
    }

    static func dismantleNSView(_ control: ShortcutRecorderControl, coordinator: ()) {
        control.cancelCapture()
    }

    private func configure(_ control: ShortcutRecorderControl) {
        if control.shortcut != shortcut || !environmentIsEnabled {
            control.cancelCapture()
        }
        control.onCandidate = onCandidate
        control.onCaptureChanged = onCaptureChanged
        control.shortcut = shortcut
        control.shortcutAccessibilityLabel = accessibilityLabel
        control.isEnabled = environmentIsEnabled
        control.refreshTitle()
        control.refreshAccessibility()
    }
}

final class ShortcutRecorderControl: SettingsNativeButton {
    var shortcut: GlobalShortcut?
    var shortcutAccessibilityLabel = "Dictation shortcut"
    var onCandidate: ((GlobalShortcut) -> Void)?
    var onCaptureChanged: ((ObjectIdentifier, ((GlobalShortcut) -> Void)?) -> Void)?

    private var isRecording = false
    private var isStandaloneFunctionCandidate = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        focusRingType = .exterior
        toolTip = "Click, then press the new shortcut. Press Escape to cancel."
        target = self
        action = #selector(beginRecording)
        refreshTitle()
        refreshAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }

    @objc
    private func beginRecording() {
        guard isButtonActionEnabled, window?.isKeyWindow == true,
            window?.makeFirstResponder(self) == true
        else {
            return
        }

        isRecording = true
        isStandaloneFunctionCandidate = false
        onCaptureChanged?(ObjectIdentifier(self)) { [weak self] candidate in
            self?.acceptCandidate(candidate)
        }
        refreshTitle()
        refreshAccessibility()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        isStandaloneFunctionCandidate = false
        guard !event.isARepeat else {
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            cancelCapture()
            return
        }

        let modifiers = Self.carbonModifiers(
            from: event.modifierFlags
        )
        if event.keyCode == UInt16(kVK_Space), modifiers == 0,
            event.modifierFlags.contains(.function)
        {
            acceptCandidate(.functionSpace)
            return
        }

        guard modifiers != 0 else {
            NSSound.beep()
            title = "Include a modifier"
            refreshAccessibility()
            return
        }

        let candidate = GlobalShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers
        )

        acceptCandidate(candidate)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        guard UInt32(event.keyCode) == GlobalShortcut.functionKeyCode else {
            isStandaloneFunctionCandidate = false
            super.flagsChanged(with: event)
            return
        }

        if event.modifierFlags.contains(.function) {
            isStandaloneFunctionCandidate = Self.carbonModifiers(from: event.modifierFlags) == 0
        } else if isStandaloneFunctionCandidate {
            acceptCandidate(.standaloneFunctionKey)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow {
            cancelCapture()
            let notifications = NotificationCenter.default
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                if let window {
                    notifications.removeObserver(self, name: name, object: window)
                }
                if let newWindow {
                    notifications.addObserver(
                        self,
                        selector: #selector(windowDidEndCapture(_:)),
                        name: name,
                        object: newWindow
                    )
                }
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            cancelCapture()
        }
        return resigned
    }

    func refreshTitle() {
        title = isRecording
            ? "Press shortcut…"
            : shortcut?.displayName ?? "Set Shortcut"
    }

    func refreshAccessibility() {
        setAccessibilityLabel(shortcutAccessibilityLabel)
        setAccessibilityValue(
            isRecording
                ? "Waiting for a shortcut"
                : shortcut?.displayName ?? "Disabled"
        )
        setAccessibilityHelp(
            isRecording
                ? "Press a shortcut, or Escape to cancel."
                : "Press Space or Return to record a new shortcut."
        )
    }

    func cancelCapture() {
        guard isRecording else {
            return
        }
        isRecording = false
        isStandaloneFunctionCandidate = false
        onCaptureChanged?(ObjectIdentifier(self), nil)
        refreshTitle()
        refreshAccessibility()
    }

    private func acceptCandidate(_ candidate: GlobalShortcut) {
        guard isRecording, isButtonActionEnabled, window?.isKeyWindow == true else {
            cancelCapture()
            return
        }
        cancelCapture()
        onCandidate?(candidate)
    }

    @objc
    private func windowDidEndCapture(_: Notification) {
        cancelCapture()
    }

    private static func carbonModifiers(
        from flags: NSEvent.ModifierFlags
    ) -> UInt32 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: UInt32 = 0

        if flags.contains(.command) {
            result |= UInt32(cmdKey)
        }
        if flags.contains(.option) {
            result |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            result |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            result |= UInt32(shiftKey)
        }

        return result
    }
}
