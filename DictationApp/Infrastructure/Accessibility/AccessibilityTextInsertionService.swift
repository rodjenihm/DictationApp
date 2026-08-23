import ApplicationServices
import Carbon.HIToolbox
import Foundation
import OSLog

@MainActor
final class AccessibilityTextInsertionService: TextInsertionServicing {
    private let pasteConsumptionDelay = Duration.milliseconds(200)
    private let pasteVerificationRetryDelay = Duration.milliseconds(100)
    private let pasteVerificationAttemptCount = 3
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

        guard !Task.isCancelled else {
            return .failed
        }

        var isSettable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &isSettable
        )
        guard !Task.isCancelled else {
            return .failed
        }
        guard
            settableResult == .success,
            isSettable.boolValue
        else {
            AppLog.insertion.notice(
                "Insertion unavailable because focused text is not writable"
            )
            return .failed
        }

        let exposedTargetValue = stringAttribute(
            kAXValueAttribute,
            from: focusedElement
        )
        guard !Task.isCancelled else {
            return .failed
        }

        let placeholderValue = stringAttribute(
            kAXPlaceholderValueAttribute,
            from: focusedElement
        )
        guard !Task.isCancelled else {
            return .failed
        }

        let descriptionValue = stringAttribute(
            kAXDescriptionAttribute,
            from: focusedElement
        )
        guard !Task.isCancelled else {
            return .failed
        }

        let exposesDescriptionAsEmptyContent =
            descriptionValue.map {
                !$0.isEmpty
                    && exposedTargetValue != $0
                    && containsStaticText(
                        matching: $0,
                        in: focusedElement,
                        remainingDepth: 4
                    )
            }
            ?? false
        guard !Task.isCancelled else {
            return .failed
        }

        let targetValue: String?
        if
            (
                placeholderValue != nil
                    && exposedTargetValue == placeholderValue
            )
                || exposesDescriptionAsEmptyContent
        {
            targetValue = ""
            AppLog.insertion.info(
                "Focused editor exposed semantic placeholder content and was treated as empty"
            )
        } else {
            targetValue = exposedTargetValue
        }

        let selectedRange = selectedTextRange(from: focusedElement)
        guard !Task.isCancelled else {
            return .failed
        }

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
        let isConfirmed: Bool
        do {
            isConfirmed = try await confirmInsertion(
                expectedValue: expectedValue,
                selectedRange: selectedRange,
                insertedText: insertedText,
                in: focusedElement
            )
        } catch is CancellationError {
            AppLog.insertion.notice(
                "Insertion verification cancelled after paste dispatch"
            )
            return .failed
        } catch {
            return .failed
        }

        guard !Task.isCancelled else {
            return .failed
        }

        if insertedText != text {
            _ = clipboardTransaction.replaceOwnedContents(with: text)
        }

        guard expectedValue != nil else {
            AppLog.insertion.info(
                "Insertion completed without a verifiable target value"
            )
            return .unverified
        }

        if isConfirmed {
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

    private func confirmInsertion(
        expectedValue: String?,
        selectedRange: NSRange?,
        insertedText: String,
        in focusedElement: AXUIElement
    ) async throws -> Bool {
        try await Task.sleep(for: pasteConsumptionDelay)

        for attempt in 0..<pasteVerificationAttemptCount {
            try Task.checkCancellation()

            let actualValue = stringAttribute(
                kAXValueAttribute,
                from: focusedElement
            )
            if
                let expectedValue,
                valuesMatchForVerification(
                    actualValue,
                    expectedValue: expectedValue
                )
            {
                return true
            }

            if
                let insertedRange = insertedTextRange(
                    from: selectedRange,
                    insertedText: insertedText
                ),
                valuesMatchForVerification(
                    stringForRange(
                        insertedRange,
                        from: focusedElement
                    ),
                    expectedValue: insertedText
                )
            {
                AppLog.insertion.info(
                    "Insertion confirmed from inserted-range readback"
                )
                return true
            }

            let actualSelectedRange = selectedTextRange(
                from: focusedElement
            )
            if caretConfirmsInsertion(
                from: selectedRange,
                to: actualSelectedRange,
                insertedText: insertedText
            ) {
                AppLog.insertion.info(
                    "Insertion confirmed from caret advancement"
                )
                return true
            }

            guard attempt + 1 < pasteVerificationAttemptCount else {
                break
            }
            try await Task.sleep(for: pasteVerificationRetryDelay)
        }

        return false
    }

    private func insertedTextRange(
        from originalRange: NSRange?,
        insertedText: String
    ) -> NSRange? {
        guard
            let originalRange,
            originalRange.location >= 0,
            originalRange.location != NSNotFound,
            !insertedText.isEmpty,
            insertedText.utf16.count
                <= Int.max - originalRange.location
        else {
            return nil
        }

        return NSRange(
            location: originalRange.location,
            length: insertedText.utf16.count
        )
    }

    private func caretConfirmsInsertion(
        from originalRange: NSRange?,
        to actualRange: NSRange?,
        insertedText: String
    ) -> Bool {
        guard
            let originalRange,
            let actualRange,
            originalRange.location >= 0,
            originalRange.location != NSNotFound,
            actualRange.location >= 0,
            actualRange.length == 0,
            !insertedText.isEmpty,
            insertedText.utf16.count
                <= Int.max - originalRange.location
        else {
            return false
        }

        return actualRange.location
            == originalRange.location + insertedText.utf16.count
    }

    private func valuesMatchForVerification(
        _ actualValue: String?,
        expectedValue: String
    ) -> Bool {
        guard let actualValue else {
            return false
        }

        if actualValue == expectedValue {
            return true
        }

        return normalizeEditorSpaces(in: actualValue)
            == normalizeEditorSpaces(in: expectedValue)
    }

    private func normalizeEditorSpaces(in value: String) -> String {
        value.replacingOccurrences(of: "\u{00A0}", with: " ")
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

    private func containsStaticText(
        matching expectedValue: String,
        in element: AXUIElement,
        remainingDepth: Int
    ) -> Bool {
        guard !Task.isCancelled else {
            return false
        }

        if
            stringAttribute(
                kAXRoleAttribute,
                from: element
            ) == kAXStaticTextRole as String,
            stringAttribute(
                kAXValueAttribute,
                from: element
            ) == expectedValue
        {
            return true
        }

        guard remainingDepth > 0 else {
            return false
        }

        return elementArrayAttribute(
            kAXChildrenAttribute,
            from: element
        )
        .contains {
            containsStaticText(
                matching: expectedValue,
                in: $0,
                remainingDepth: remainingDepth - 1
            )
        }
    }

    private func elementArrayAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                attribute as CFString,
                &value
            ) == .success,
            let values = value as? [AnyObject]
        else {
            return []
        }

        return values.compactMap { value in
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeBitCast(value, to: AXUIElement.self)
        }
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

    private func stringForRange(
        _ range: NSRange,
        from element: AXUIElement
    ) -> String? {
        var cfRange = CFRange(
            location: range.location,
            length: range.length
        )
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return nil
        }

        var value: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForRangeParameterizedAttribute as CFString,
                rangeValue,
                &value
            ) == .success
        else {
            return nil
        }

        return value as? String
    }
}
