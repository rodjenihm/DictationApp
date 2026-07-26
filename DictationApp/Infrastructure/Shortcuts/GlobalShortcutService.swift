import Carbon.HIToolbox
import Foundation

enum GlobalShortcutRegistrationError: LocalizedError {
    case missingModifier
    case reservedBySystem
    case conflict
    case eventHandlerRegistrationFailed(OSStatus)
    case hotKeyRegistrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingModifier:
            "Choose a shortcut that includes Command, Option, Control, or Shift."
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

@MainActor
final class GlobalShortcutService {
    var onShortcutPressed: (() -> Void)?

    private(set) var activeShortcut: GlobalShortcut?
    private(set) var registrationError: GlobalShortcutRegistrationError?

    private static let signature: OSType = 0x44494354

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var activeHotKeyID: UInt32?
    private var nextHotKeyID: UInt32 = 1

    func start(with shortcut: GlobalShortcut) throws {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installedHandler: EventHandlerRef?

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &installedHandler
        )

        guard status == noErr, let installedHandler else {
            let error = GlobalShortcutRegistrationError
                .eventHandlerRegistrationFailed(status)
            registrationError = error
            throw error
        }

        eventHandlerRef = installedHandler

        do {
            try replaceShortcut(with: shortcut)
        } catch {
            registrationError =
                error as? GlobalShortcutRegistrationError
            throw error
        }
    }

    func replaceShortcut(with shortcut: GlobalShortcut) throws {
        guard shortcut.hasStandardModifier else {
            let error = GlobalShortcutRegistrationError.missingModifier
            registrationError = error
            throw error
        }

        guard !isReservedBySystem(shortcut) else {
            let error = GlobalShortcutRegistrationError.reservedBySystem
            registrationError = error
            throw error
        }

        if activeShortcut == shortcut {
            registrationError = nil
            return
        }

        guard eventHandlerRef != nil else {
            let error = GlobalShortcutRegistrationError
                .eventHandlerRegistrationFailed(OSStatus(paramErr))
            registrationError = error
            throw error
        }

        let candidateID = nextHotKeyID
        nextHotKeyID &+= 1

        var candidateRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: candidateID
        )

        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            UInt32(kEventHotKeyExclusive),
            &candidateRef
        )

        guard status == noErr, let candidateRef else {
            let error: GlobalShortcutRegistrationError =
                status == eventHotKeyExistsErr
                    ? .conflict
                    : .hotKeyRegistrationFailed(status)
            registrationError = error
            throw error
        }

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        hotKeyRef = candidateRef
        activeShortcut = shortcut
        activeHotKeyID = candidateID
        registrationError = nil
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }

        hotKeyRef = nil
        eventHandlerRef = nil
        activeShortcut = nil
        activeHotKeyID = nil
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
                        & GlobalShortcut.supportedModifierMask
                ) == shortcut.modifiers
        }
    }

    private func handleHotKeyPressed(id: UInt32) {
        guard id == activeHotKeyID else {
            return
        }

        onShortcutPressed?()
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

        Task { @MainActor in
            service.handleHotKeyPressed(id: identifier)
        }

        return noErr
    }
}
