import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: GlobalShortcut
    let isEnabled: Bool
    let onCandidate: (GlobalShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl()
        control.onCandidate = onCandidate
        control.shortcut = shortcut
        control.isEnabled = isEnabled
        return control
    }

    func updateNSView(
        _ control: ShortcutRecorderControl,
        context: Context
    ) {
        control.onCandidate = onCandidate
        control.shortcut = shortcut
        control.isEnabled = isEnabled
        control.refreshTitle()
    }
}

final class ShortcutRecorderControl: NSButton {
    var shortcut = GlobalShortcut.defaultShortcut
    var onCandidate: ((GlobalShortcut) -> Void)?

    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        focusRingType = .exterior
        toolTip = "Click, then press the new shortcut. Press Escape to cancel."
        target = self
        action = #selector(beginRecording)
        refreshTitle()
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
        guard isEnabled else {
            return
        }

        window?.makeFirstResponder(self)
        isRecording = true
        refreshTitle()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording, !event.isARepeat else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            finishRecording()
            return
        }

        let modifiers = Self.carbonModifiers(
            from: event.modifierFlags
        )
        guard modifiers != 0 else {
            NSSound.beep()
            title = "Include a modifier"
            return
        }

        let candidate = GlobalShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers
        )

        finishRecording()
        onCandidate?(candidate)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            finishRecording()
        }
        return resigned
    }

    func refreshTitle() {
        title = isRecording
            ? "Press shortcut…"
            : shortcut.displayName
    }

    private func finishRecording() {
        isRecording = false
        refreshTitle()
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
