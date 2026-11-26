import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum GlobalShortcutRegistrationError: LocalizedError {
    case missingModifier
    case standaloneFunctionKeyRequiresHold
    case functionKeyPermissionRequired
    case functionKeyEventTapUnavailable
    case duplicateBindings
    case reservedBySystem
    case conflict
    case eventHandlerRegistrationFailed(OSStatus)
    case hotKeyRegistrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingModifier:
            "Choose Fn–Space or a shortcut that includes Command, Option, Control, or Shift."
        case .standaloneFunctionKeyRequiresHold:
            "Use Fn–Space for toggle dictation. Fn alone is available for hold to dictate."
        case .functionKeyPermissionRequired:
            "Allow DictationApp in Accessibility settings to use global Fn shortcuts, then try again."
        case .functionKeyEventTapUnavailable:
            "The global Fn shortcut listener could not start. Try again or choose another shortcut."
        case .duplicateBindings:
            "Choose different shortcuts for toggle dictation and hold to dictate."
        case .reservedBySystem:
            "That shortcut is reserved by macOS. Choose another combination."
        case .conflict:
            "Another application already uses that shortcut. The previous shortcut is still active."
        case .eventHandlerRegistrationFailed(let status):
            "The global shortcut handler could not start (error \(status))."
        case .hotKeyRegistrationFailed(let status):
            "The shortcut could not be registered (error \(status)). The previous shortcut is still active."
        }
    }
}

enum SessionCancellationShortcutRegistrationError: LocalizedError {
    case conflict
    case eventHandlerUnavailable
    case hotKeyRegistrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .conflict:
            "Escape is already reserved by another application. Recording did not start."
        case .eventHandlerUnavailable:
            "The cancellation shortcut handler is unavailable. Recording did not start."
        case .hotKeyRegistrationFailed(let status):
            "Escape could not be reserved for cancellation (error \(status)). Recording did not start."
        }
    }
}

@MainActor
final class GlobalShortcutService {
    var onShortcutPressed: ((ContinuousClock.Instant, _ replacesHold: Bool) -> Void)?
    var onHoldShortcutPressed: ((ContinuousClock.Instant) -> Void)?
    var onHoldShortcutReleased: ((ContinuousClock.Instant) -> Void)?
    var onHoldShortcutCancelled: (() -> Void)?
    var onSessionCancellationShortcutPressed: (() -> Void)?
    var onShortcutCaptured: ((GlobalShortcut) -> Void)? {
        didSet { functionMonitor.isCapturingShortcut = onShortcutCaptured != nil }
    }

    var activeShortcut: GlobalShortcut? { toggleRegistration?.shortcut }
    var activeHoldShortcut: GlobalShortcut? { holdRegistration?.shortcut }
    private(set) var registrationError: GlobalShortcutRegistrationError?
    private(set) var holdRegistrationError: GlobalShortcutRegistrationError?

    private struct Registration {
        let shortcut: GlobalShortcut
        let id: UInt32
        let ref: EventHotKeyRef?
    }

    private static let signature: OSType = 0x44494354

    private var eventHandlerRef: EventHandlerRef?
    private var toggleRegistration: Registration?
    private var holdRegistration: Registration?
    private var isHoldKeyDown = false
    private var cancellationRegistration: Registration?
    private var holdCancellationRegistration: Registration?
    private var nextHotKeyID: UInt32 = 1
    private let functionMonitor = FunctionShortcutMonitor()

    func start(toggle: GlobalShortcut, hold: GlobalShortcut?) throws {
        guard eventHandlerRef == nil else {
            return
        }

        let eventTypes = [kEventHotKeyPressed, kEventHotKeyReleased].map {
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32($0)
            )
        }
        var installedHandler: EventHandlerRef?

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            eventTypes.count,
            eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &installedHandler
        )

        guard status == noErr, let installedHandler else {
            let error = GlobalShortcutRegistrationError
                .eventHandlerRegistrationFailed(status)
            registrationError = error
            holdRegistrationError = hold == nil ? nil : error
            throw error
        }

        eventHandlerRef = installedHandler
        functionMonitor.onAction = { [weak self] action, receivedAt in
            self?.handleFunctionAction(action, receivedAt: receivedAt)
        }
        defer { updateFunctionBindings() }

        do throws(GlobalShortcutRegistrationError) {
            guard !toggle.isStandaloneFunctionKey else {
                throw .standaloneFunctionKeyRequiresHold
            }
            try validateCandidate(toggle)
            toggleRegistration = try register(toggle)
            registrationError = nil
        } catch {
            registrationError = error
        }

        if let hold {
            do {
                try validateDistinctShortcuts(toggle: toggle, hold: hold)
                try validateCandidate(hold)
                holdRegistration = try register(hold)
                holdRegistrationError = nil
            } catch {
                holdRegistrationError = error
            }
        }

        if let error = registrationError ?? holdRegistrationError {
            throw error
        }
    }

    func replaceShortcuts(
        toggle: GlobalShortcut,
        hold: GlobalShortcut?,
        updateToggle: Bool,
        updateHold: Bool,
        committing: () throws -> Void
    ) throws {
        guard updateToggle || updateHold else {
            try committing()
            return
        }
        defer { updateFunctionBindings() }

        try validateDistinctShortcuts(toggle: toggle, hold: hold)
        if updateToggle {
            guard !toggle.isStandaloneFunctionKey else {
                throw GlobalShortcutRegistrationError.standaloneFunctionKeyRequiresHold
            }
            try validateCandidate(toggle)
        }
        if updateHold, let hold {
            try validateCandidate(hold)
        }

        let existing = [toggleRegistration, holdRegistration].compactMap { $0 }
        var additions: [Registration] = []

        func candidate(for shortcut: GlobalShortcut) throws -> Registration {
            if let registered = existing.first(where: { $0.shortcut == shortcut }) {
                return registered
            }

            let registered = try register(shortcut)
            additions.append(registered)
            return registered
        }

        let newToggle: Registration?
        let newHold: Registration?
        do {
            newToggle = updateToggle
                ? try candidate(for: toggle)
                : toggleRegistration
            newHold = updateHold
                ? try hold.map { try candidate(for: $0) }
                : holdRegistration
            // Keep current bindings active until provider and settings writes succeed.
            try committing()
        } catch {
            for registration in additions {
                unregister(registration)
            }
            throw error
        }

        for registration in existing
        where registration.id != newToggle?.id && registration.id != newHold?.id {
            unregister(registration)
        }

        if holdRegistration?.id != newHold?.id {
            isHoldKeyDown = false
        }
        toggleRegistration = newToggle
        holdRegistration = newHold
        if updateToggle {
            registrationError = nil
        }
        if updateHold {
            holdRegistrationError = nil
        }
    }

    func validateDistinctShortcuts(
        toggle: GlobalShortcut,
        hold: GlobalShortcut?
    ) throws(GlobalShortcutRegistrationError) {
        guard hold != toggle else {
            throw .duplicateBindings
        }
    }

    func validateCandidate(
        _ shortcut: GlobalShortcut
    ) throws(GlobalShortcutRegistrationError) {
        guard shortcut.isConfigurable else {
            throw GlobalShortcutRegistrationError.missingModifier
        }

        guard !isReservedBySystem(shortcut) else {
            throw GlobalShortcutRegistrationError.reservedBySystem
        }
    }

    func registerSessionCancellationShortcut(forHold: Bool) throws {
        guard cancellationRegistration == nil else {
            return
        }

        let escapeCode = UInt32(kVK_Escape)
        do {
            cancellationRegistration = try register(
                GlobalShortcut(keyCode: escapeCode, modifiers: 0)
            )
        } catch {
            switch error {
            case .conflict:
                throw SessionCancellationShortcutRegistrationError.conflict
            case .eventHandlerRegistrationFailed:
                throw SessionCancellationShortcutRegistrationError.eventHandlerUnavailable
            case .hotKeyRegistrationFailed(let status):
                throw SessionCancellationShortcutRegistrationError.hotKeyRegistrationFailed(status)
            default:
                throw error
            }
        }

        functionMonitor.capturesEscape = true
        if forHold, let hold = activeHoldShortcut, !hold.usesFunctionModifier {
            // Escape can also be pressed before releasing the hold modifiers.
            let modifiedEscape = GlobalShortcut(
                keyCode: escapeCode,
                modifiers: hold.modifiers
            )
            if !isReservedBySystem(modifiedEscape) {
                holdCancellationRegistration = try? register(modifiedEscape)
            }
        }
    }

    func unregisterSessionCancellationShortcut() {
        if let cancellationRegistration {
            unregister(cancellationRegistration)
        }
        cancellationRegistration = nil
        functionMonitor.capturesEscape = false
        unregisterHoldCancellationShortcut()
    }

    func stop() {
        unregisterSessionCancellationShortcut()

        if let toggleRegistration {
            unregister(toggleRegistration)
        }
        if let holdRegistration {
            unregister(holdRegistration)
        }
        functionMonitor.stop()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }

        toggleRegistration = nil
        holdRegistration = nil
        eventHandlerRef = nil
        isHoldKeyDown = false
        onShortcutCaptured = nil
    }

    private func register(
        _ shortcut: GlobalShortcut
    ) throws(GlobalShortcutRegistrationError) -> Registration {
        guard eventHandlerRef != nil else {
            throw .eventHandlerRegistrationFailed(OSStatus(paramErr))
        }

        let candidateID = nextHotKeyID
        nextHotKeyID &+= 1

        if shortcut.usesFunctionModifier {
            guard CGPreflightPostEventAccess() else {
                throw .functionKeyPermissionRequired
            }
            guard functionMonitor.start() else {
                throw .functionKeyEventTapUnavailable
            }
            return Registration(shortcut: shortcut, id: candidateID, ref: nil)
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: candidateID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            UInt32(kEventHotKeyExclusive),
            &ref
        )

        guard status == noErr, let ref else {
            throw status == eventHotKeyExistsErr
                ? .conflict
                : .hotKeyRegistrationFailed(status)
        }

        return Registration(shortcut: shortcut, id: candidateID, ref: ref)
    }

    private func unregisterHoldCancellationShortcut() {
        if let holdCancellationRegistration {
            unregister(holdCancellationRegistration)
            self.holdCancellationRegistration = nil
        }
    }

    private func unregister(_ registration: Registration) {
        if let ref = registration.ref {
            UnregisterEventHotKey(ref)
        }
    }

    private func updateFunctionBindings() {
        let toggle = activeShortcut.flatMap { $0.usesFunctionModifier ? $0 : nil }
        let hold = activeHoldShortcut.flatMap { $0.usesFunctionModifier ? $0 : nil }
        if toggle == nil, hold == nil {
            functionMonitor.stop()
        } else {
            functionMonitor.updateBindings(toggle: toggle, hold: hold)
        }
    }

    private func isReservedBySystem(_ shortcut: GlobalShortcut) -> Bool {
        var unmanagedHotKeys: Unmanaged<CFArray>?
        guard
            CopySymbolicHotKeys(&unmanagedHotKeys) == noErr,
            let hotKeys = unmanagedHotKeys?.takeRetainedValue()
                as? [[String: Any]]
        else {
            return false
        }

        return hotKeys.contains { item in
            guard
                let enabled = item[kHISymbolicHotKeyEnabled] as? Bool,
                enabled,
                let keyCode = item[kHISymbolicHotKeyCode] as? NSNumber,
                let modifiers =
                    item[kHISymbolicHotKeyModifiers] as? NSNumber
            else {
                return false
            }

            return keyCode.uint32Value == shortcut.keyCode
                && (
                    modifiers.uint32Value
                        & (GlobalShortcut.carbonModifierMask | GlobalShortcut.functionModifier)
                ) == shortcut.modifiers
        }
    }

    private func handleFunctionAction(
        _ action: FunctionShortcutMonitor.Action,
        receivedAt: ContinuousClock.Instant
    ) {
        switch action {
        case .holdPressed, .holdReleased:
            if let holdRegistration {
                handleHotKey(
                    id: holdRegistration.id,
                    isPressed: action == .holdPressed,
                    receivedAt: receivedAt
                )
            }
        case .holdCancelled:
            if isHoldKeyDown {
                isHoldKeyDown = false
                onHoldShortcutCancelled?()
            }
        case .togglePressed(let replacesHold):
            if replacesHold {
                isHoldKeyDown = false
            }
            onShortcutPressed?(receivedAt, replacesHold)
        case .cancelSession:
            isHoldKeyDown = false
            onSessionCancellationShortcutPressed?()
        }
    }

    private func handleHotKey(
        id: UInt32,
        isPressed: Bool,
        receivedAt: ContinuousClock.Instant
    ) {
        if id == cancellationRegistration?.id || id == holdCancellationRegistration?.id {
            if isPressed {
                onSessionCancellationShortcutPressed?()
            }
        } else if let hold = holdRegistration, id == hold.id {
            guard isPressed != isHoldKeyDown else {
                return
            }
            isHoldKeyDown = isPressed

            if !isPressed {
                unregisterHoldCancellationShortcut()
                onHoldShortcutReleased?(receivedAt)
            } else if let onShortcutCaptured {
                onShortcutCaptured(hold.shortcut)
            } else {
                onHoldShortcutPressed?(receivedAt)
            }
        } else if let toggle = toggleRegistration, id == toggle.id, isPressed {
            if let onShortcutCaptured {
                onShortcutCaptured(toggle.shortcut)
            } else {
                onShortcutPressed?(receivedAt, false)
            }
        }
    }

    private static let eventHandler: EventHandlerUPP = {
        _, event, userData in
        guard let event, let userData else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard
            status == noErr,
            hotKeyID.signature == GlobalShortcutService.signature
        else {
            return OSStatus(eventNotHandledErr)
        }

        let service = Unmanaged<GlobalShortcutService>
            .fromOpaque(userData)
            .takeUnretainedValue()
        let identifier = hotKeyID.id
        let isPressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
        let receivedAt = ContinuousClock.now

        // Deliver both edges in Carbon's order, including rapid press-release.
        DispatchQueue.main.async {
            service.handleHotKey(
                id: identifier,
                isPressed: isPressed,
                receivedAt: receivedAt
            )
        }

        return noErr
    }
}
