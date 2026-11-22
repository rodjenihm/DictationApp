import ApplicationServices
import Carbon.HIToolbox
import Foundation
import OSLog

@MainActor
final class AccessibilityTextInsertionService: TextInsertionServicing {
    private let clock = ContinuousClock()
    private let messagingTimeout: Float = 1
    private let pasteConsumptionDelay = Duration.milliseconds(200)
    private let pasteVerificationRetryDelay = Duration.milliseconds(100)
    private let pasteVerificationAttemptCount = 3
    private let clipboardHoldDuration = Duration.milliseconds(250)
    private let placeholderInspectionDuration = Duration.milliseconds(100)
    private let placeholderInspectionDepth = 4
    private let placeholderInspectionNodeLimit = 24

    private struct Target {
        let element: AXUIElement
        let value: String?
        let selectedRange: NSRange?
    }

    private enum TargetProbeFailure: Error {
        case unavailable
        case messagingFailed
    }

    func insert(
        _ text: String,
        using clipboardTransaction: any ClipboardTransactionHandling,
        sessionID: UUID,
        onPasteDispatched: (ContinuousClock.Instant) -> Void
    ) async -> TextInsertionOutcome {
        let target: Target
        do {
            let startedAt = clock.now
            defer {
                AppLog.recordLatency(
                    "accessibility_preparation",
                    since: startedAt,
                    sessionID: sessionID
                )
            }
            target = try prepareTarget()
        } catch TargetProbeFailure.messagingFailed {
            AppLog.insertion.notice(
                "Accessibility messaging failed before paste dispatch"
            )
            return .failed
        } catch {
            return .failed
        }

        let insertedText = TextInsertionBoundaryPolicy.preparedText(
            text,
            targetValue: target.value,
            selectedRange: target.selectedRange
        )

        guard !Task.isCancelled else {
            return .failed
        }
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
            if !Task.isCancelled {
                _ = clipboardTransaction.replaceOwnedContents(with: text)
            }
            AppLog.insertion.notice(
                "Insertion stopped while preparing boundary spacing"
            )
            return .failed
        }

        guard !Task.isCancelled else {
            return .failed
        }
        guard postPasteShortcut(to: target.element) else {
            if insertedText != text {
                _ = clipboardTransaction.replaceOwnedContents(with: text)
            }
            AppLog.insertion.notice(
                "Insertion could not post the paste command"
            )
            return .failed
        }

        let pasteDispatchedAt = clock.now
        clipboardTransaction.holdRestoration(for: clipboardHoldDuration)
        onPasteDispatched(pasteDispatchedAt)

        let isConfirmed: Bool
        do {
            defer {
                AppLog.recordLatency(
                    "accessibility_verification",
                    since: pasteDispatchedAt,
                    sessionID: sessionID
                )
            }
            isConfirmed = try await confirmInsertion(
                target: target,
                insertedText: insertedText
            )
        } catch is CancellationError {
            AppLog.insertion.notice(
                "Insertion verification cancelled after paste dispatch"
            )
            return .failed
        } catch TargetProbeFailure.messagingFailed {
            AppLog.insertion.notice(
                "Accessibility messaging failed after paste dispatch"
            )
            isConfirmed = false
        } catch {
            isConfirmed = false
        }

        guard !Task.isCancelled else {
            return .failed
        }

        if isConfirmed {
            AppLog.insertion.info("Insertion confirmed")
            return .confirmed
        }

        if insertedText != text {
            let consumptionDeadline = pasteDispatchedAt.advanced(
                by: clipboardHoldDuration
            )
            do {
                try await clock.sleep(until: consumptionDeadline)
                try Task.checkCancellation()
            } catch {
                return .failed
            }
            _ = clipboardTransaction.replaceOwnedContents(with: text)
        }

        AppLog.insertion.info("Insertion remained unverified")
        return .unverified
    }

    private func prepareTarget() throws -> Target {
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else {
            AppLog.insertion.notice(
                "Insertion unavailable because Accessibility is not trusted"
            )
            throw TargetProbeFailure.unavailable
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        // The system-wide element applies this limit to all AX messaging
        // from this process, including requests to focused elements and children.
        guard AXUIElementSetMessagingTimeout(
            systemWideElement,
            messagingTimeout
        ) == .success else {
            throw TargetProbeFailure.messagingFailed
        }

        guard
            let focusedElement = try attributeValue(
                kAXFocusedUIElementAttribute,
                from: systemWideElement
            ),
            CFGetTypeID(focusedElement) == AXUIElementGetTypeID()
        else {
            AppLog.insertion.notice(
                "Insertion unavailable because no focused element exists"
            )
            throw TargetProbeFailure.unavailable
        }
        let element = unsafeBitCast(focusedElement, to: AXUIElement.self)

        try Task.checkCancellation()
        var isSettable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &isSettable
        )
        guard try isSuccessful(settableResult), isSettable.boolValue else {
            AppLog.insertion.notice(
                "Insertion unavailable because focused text is not writable"
            )
            throw TargetProbeFailure.unavailable
        }

        guard let selectedRange = try selectedTextRange(from: element) else {
            return Target(element: element, value: nil, selectedRange: nil)
        }
        return Target(
            element: element,
            value: try targetValue(from: element),
            selectedRange: selectedRange
        )
    }

    private func targetValue(from element: AXUIElement) throws -> String? {
        let value = try stringAttribute(kAXValueAttribute, from: element)
        if value == "" {
            return value
        }

        if
            let placeholder = try stringAttribute(
                kAXPlaceholderValueAttribute,
                from: element
            ),
            value == placeholder
        {
            return ""
        }

        if
            let description = try stringAttribute(
                kAXDescriptionAttribute,
                from: element
            ),
            !description.isEmpty,
            value != description
        {
            var remainingNodes = placeholderInspectionNodeLimit
            if try containsStaticText(
                matching: description,
                in: element,
                remainingDepth: placeholderInspectionDepth,
                remainingNodes: &remainingNodes,
                deadline: clock.now.advanced(by: placeholderInspectionDuration)
            ) {
                return ""
            }
        }

        return value
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
        target: Target,
        insertedText: String
    ) async throws -> Bool {
        guard let selectedRange = target.selectedRange else {
            return false
        }

        try await Task.sleep(for: pasteConsumptionDelay)

        let expectedValue = TextInsertionBoundaryPolicy.expectedValue(
            replacing: selectedRange,
            in: target.value,
            with: insertedText
        )
        let insertedRange = insertedTextRange(
            from: selectedRange,
            insertedText: insertedText
        )

        for attempt in 0..<pasteVerificationAttemptCount {
            if
                let expectedValue,
                valuesMatchForVerification(
                    try stringAttribute(
                        kAXValueAttribute,
                        from: target.element
                    ),
                    expectedValue: expectedValue
                )
            {
                return true
            }

            if let insertedRange {
                if valuesMatchForVerification(
                    try stringForRange(insertedRange, from: target.element),
                    expectedValue: insertedText
                ) {
                    AppLog.insertion.info(
                        "Insertion confirmed from inserted-range readback"
                    )
                    return true
                }

                if
                    let actualRange = try selectedTextRange(from: target.element),
                    actualRange.length == 0,
                    actualRange.location == NSMaxRange(insertedRange)
                {
                    AppLog.insertion.info(
                        "Insertion confirmed from caret advancement"
                    )
                    return true
                }
            }

            guard attempt + 1 < pasteVerificationAttemptCount else {
                break
            }
            try await Task.sleep(for: pasteVerificationRetryDelay)
        }

        return false
    }

    private func insertedTextRange(
        from originalRange: NSRange,
        insertedText: String
    ) -> NSRange? {
        let insertedLength = insertedText.utf16.count
        guard
            insertedLength > 0,
            insertedLength <= Int.max - originalRange.location
        else {
            return nil
        }

        return NSRange(
            location: originalRange.location,
            length: insertedLength
        )
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

    private func attributeValue(
        _ attribute: String,
        from element: AXUIElement
    ) throws -> CFTypeRef? {
        try Task.checkCancellation()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )
        return try isSuccessful(result) ? value : nil
    }

    private func stringAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) throws -> String? {
        try attributeValue(attribute, from: element) as? String
    }

    private func containsStaticText(
        matching expectedValue: String,
        in element: AXUIElement,
        remainingDepth: Int,
        remainingNodes: inout Int,
        deadline: ContinuousClock.Instant
    ) throws -> Bool {
        guard remainingNodes > 0, clock.now < deadline else {
            return false
        }
        remainingNodes -= 1

        if
            try stringAttribute(kAXRoleAttribute, from: element)
                == kAXStaticTextRole as String,
            clock.now < deadline,
            try stringAttribute(kAXValueAttribute, from: element) == expectedValue
        {
            return true
        }

        guard remainingDepth > 0, remainingNodes > 0, clock.now < deadline else {
            return false
        }

        let children = try childElements(of: element, limit: remainingNodes)
        return try children.contains { child in
            try containsStaticText(
                matching: expectedValue,
                in: child,
                remainingDepth: remainingDepth - 1,
                remainingNodes: &remainingNodes,
                deadline: deadline
            )
        }
    }

    private func childElements(
        of element: AXUIElement,
        limit: Int
    ) throws -> [AXUIElement] {
        try Task.checkCancellation()
        var value: CFArray?
        let result = AXUIElementCopyAttributeValues(
            element,
            kAXChildrenAttribute as CFString,
            0,
            limit,
            &value
        )
        guard try isSuccessful(result), let values = value as? [AnyObject] else {
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
    ) throws -> NSRange? {
        guard
            let value = try attributeValue(
                kAXSelectedTextRangeAttribute,
                from: element
            ),
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard
            AXValueGetValue(axValue, .cfRange, &range),
            range.location >= 0,
            range.location != NSNotFound,
            range.length >= 0
        else {
            return nil
        }

        return NSRange(location: range.location, length: range.length)
    }

    private func stringForRange(
        _ range: NSRange,
        from element: AXUIElement
    ) throws -> String? {
        var cfRange = CFRange(
            location: range.location,
            length: range.length
        )
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return nil
        }

        try Task.checkCancellation()
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )
        return try isSuccessful(result) ? value as? String : nil
    }

    private func isSuccessful(_ result: AXError) throws -> Bool {
        try Task.checkCancellation()
        switch result {
        case .success:
            return true
        case .cannotComplete, .invalidUIElement, .apiDisabled, .failure:
            throw TargetProbeFailure.messagingFailed
        default:
            return false
        }
    }
}
