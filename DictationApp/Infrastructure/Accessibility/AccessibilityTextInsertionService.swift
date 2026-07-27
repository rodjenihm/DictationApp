import ApplicationServices
import Carbon.HIToolbox
import Foundation
import OSLog

@MainActor
final class AccessibilityTextInsertionService: TextInsertionServicing {
    private let pasteConsumptionDelay = Duration.milliseconds(200)
    private let clipboardRestorationDelay = Duration.milliseconds(250)

    func insert(
        _ text: String,
        using clipboardTransaction: any ClipboardTransactionHandling
    ) async -> TextInsertionOutcome {
        guard !Task.isCancelled else {
            AppLog.insertion.notice(
                "Insertion skipped because the task was cancelled"
            )
            return .failed
        }

        guard AXIsProcessTrusted() else {
            AppLog.insertion.notice(
                "Insertion unavailable because Accessibility is not trusted"
            )
            return .failed
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        guard let focusedElement = focusedElement(from: systemWideElement)
        else {
            AppLog.insertion.notice(
                "Insertion unavailable because no focused element exists"
            )
            return .failed
        }

        var isSettable = DarwinBoolean(false)
        guard
            AXUIElementIsAttributeSettable(
                focusedElement,
                kAXSelectedTextAttribute as CFString,
                &isSettable
            ) == .success,
            isSettable.boolValue
        else {
            AppLog.insertion.notice(
                "Insertion unavailable because focused text is not writable"
            )
            return .failed
        }

        let targetValue = stringAttribute(
            kAXValueAttribute,
            from: focusedElement
        )
        let selectedRange = selectedTextRange(from: focusedElement)
        let insertedText = TextInsertionBoundaryPolicy.preparedText(
            text,
            targetValue: targetValue,
            selectedRange: selectedRange
        )
        let expectedValue = TextInsertionBoundaryPolicy.expectedValue(
            replacing: selectedRange,
            in: targetValue,
            with: insertedText
        )

        guard clipboardTransaction.isStillOwned else {
            AppLog.insertion.notice(
                "Insertion stopped because clipboard ownership was lost"
            )
            return .failed
        }

        if
            insertedText != text,
            !clipboardTransaction.replaceOwnedContents(with: insertedText)
        {
            AppLog.insertion.notice(
                "Insertion stopped while preparing boundary spacing"
            )
            return .failed
        }

        guard
            !Task.isCancelled,
            postPasteShortcut(to: focusedElement)
        else {
            if insertedText != text {
                _ = clipboardTransaction.replaceOwnedContents(with: text)
            }
            AppLog.insertion.notice(
                "Insertion could not post the paste command"
            )
            return .failed
        }

        clipboardTransaction.holdRestoration(
            for: clipboardRestorationDelay
        )
        await waitForPasteConsumption()

        let actualValue = stringAttribute(
            kAXValueAttribute,
            from: focusedElement
        )

        if insertedText != text {
            _ = clipboardTransaction.replaceOwnedContents(with: text)
        }

        guard let expectedValue else {
            AppLog.insertion.info(
                "Insertion completed without a verifiable target value"
            )
            return .unverified
        }

        if actualValue == expectedValue {
            AppLog.insertion.info("Insertion confirmed")
            return .confirmed
        }

        AppLog.insertion.info("Insertion remained unverified")
        return .unverified
    }

    private func postPasteShortcut(
        to focusedElement: AXUIElement
    ) -> Bool {
        var processIdentifier: pid_t = 0
        guard
            CGPreflightPostEventAccess(),
            AXUIElementGetPid(
                focusedElement,
                &processIdentifier
            ) == .success,
            processIdentifier > 0,
            let source = CGEventSource(
                stateID: .hidSystemState
            ),
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
            )
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        return true
    }

    private func waitForPasteConsumption() async {
        try? await Task.sleep(for: pasteConsumptionDelay)
    }

    private func focusedElement(
        from systemWideElement: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                systemWideElement,
                kAXFocusedUIElementAttribute as CFString,
                &value
            ) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func stringAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                attribute as CFString,
                &value
            ) == .success
        else {
            return nil
        }

        return value as? String
    }

    private func selectedTextRange(
        from element: AXUIElement
    ) -> NSRange? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &value
            ) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        return NSRange(location: range.location, length: range.length)
    }
}
