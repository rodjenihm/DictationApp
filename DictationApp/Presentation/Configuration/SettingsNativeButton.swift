import AppKit

class SettingsNativeButton: NSButton {
    private var requestedEnabled = true
    private var isEnabledUpdateScheduled = false

    var isButtonActionEnabled: Bool {
        requestedEnabled && super.isEnabled
    }

    override var isEnabled: Bool {
        get { super.isEnabled }
        set {
            requestedEnabled = newValue
            guard super.isEnabled != newValue else {
                return
            }

            if window == nil {
                super.isEnabled = newValue
                return
            }

            guard !isEnabledUpdateScheduled else {
                return
            }
            isEnabledUpdateScheduled = true

            // Disabling a focused button can synchronously ask SwiftUI for
            // the next responder. Apply it after SwiftUI's current update.
            DispatchQueue.main.async { [weak self] in
                self?.applyRequestedEnabledState()
            }
        }
    }

    private func applyRequestedEnabledState() {
        isEnabledUpdateScheduled = false
        if super.isEnabled != requestedEnabled {
            super.isEnabled = requestedEnabled
        }
    }
}
