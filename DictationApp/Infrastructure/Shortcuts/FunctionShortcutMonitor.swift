import Carbon.HIToolbox
import CoreGraphics
import Foundation

@MainActor
final class FunctionShortcutMonitor {
    enum Action: Equatable {
        case holdPressed
        case holdReleased
        case holdCancelled
        case commandPressed
        case commandReleased
        case commandCancelled
        case togglePressed(replacesHold: Bool)
        case cancelSession
    }

    private enum FunctionPress {
        case idle
        case pending
        case holding
    }

    private enum SpacePress {
        case consumed
        case hold
        case command
    }

    private static let shortcutFlags: CGEventFlags = [
        .maskSecondaryFn, .maskCommand, .maskAlternate, .maskControl, .maskShift,
    ]

    var onAction: ((Action, ContinuousClock.Instant) -> Void)?
    var isCapturingShortcut = false {
        didSet {
            if isCapturingShortcut {
                cancelFunctionPress()
            }
        }
    }
    var capturesEscape = false
    var capturesCommandEscape = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var toggle: GlobalShortcut?
    private var hold: GlobalShortcut?
    private var command: GlobalShortcut?
    private var commandFlags: CGEventFlags = []
    private var bindingRevision = 0
    private var functionPress = FunctionPress.idle
    private var pendingHold: Task<Void, Never>?
    private var spacePress: SpacePress?
    private var isEscapeDown = false
    private var modifierFlags: CGEventFlags = []
    private var isModifierCommandDown = false

    func start() -> Bool {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return CGEvent.tapIsEnabled(tap: tap)
        }

        let eventTypes: [CGEventType] = [.flagsChanged, .keyDown, .keyUp]
        let mask = eventTypes.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            return false
        }

        self.tap = tap
        self.source = source
        modifierFlags = CGEventSource.flagsState(.combinedSessionState)
            .intersection(Self.shortcutFlags)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return true
    }

    func updateBindings(toggle: GlobalShortcut?, hold: GlobalShortcut?, command: GlobalShortcut?) {
        guard self.toggle != toggle || self.hold != hold || self.command != command else {
            return
        }
        self.toggle = toggle
        self.hold = hold
        self.command = command
        commandFlags = switch command {
        case .functionControl: [.maskSecondaryFn, .maskControl]
        case .commandControlOption: [.maskCommand, .maskControl, .maskAlternate]
        case .functionSpace: .maskSecondaryFn
        default: []
        }
        bindingRevision &+= 1
        resetFunctionPress()
        isModifierCommandDown = false
        if spacePress != nil {
            spacePress = .consumed
        }

        if toggle == nil, hold == nil, command == nil {
            stop()
        }
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        source = nil
        tap = nil
        toggle = nil
        hold = nil
        command = nil
        commandFlags = []
        bindingRevision &+= 1
        resetFunctionPress()
        spacePress = nil
        isEscapeDown = false
        modifierFlags = []
        isModifierCommandDown = false
    }

    private func handle(
        _ type: CGEventType,
        keyCode: UInt32,
        flags: CGEventFlags,
        isRepeat: Bool
    ) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if functionPress == .holding || spacePress == .hold {
                emit(.holdCancelled)
            }
            if isModifierCommandDown || spacePress == .command {
                emit(.commandCancelled)
            }
            resetFunctionPress()
            spacePress = nil
            isEscapeDown = false
            isModifierCommandDown = false
            modifierFlags = CGEventSource.flagsState(.combinedSessionState)
                .intersection(Self.shortcutFlags)
            if type == .tapDisabledByTimeout, let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }

        let eventModifiers = flags.intersection(Self.shortcutFlags)
        let previousModifiers = modifierFlags
        if type == .flagsChanged {
            modifierFlags = eventModifiers
            if isModifierCommandDown, !modifierFlags.contains(commandFlags) {
                isModifierCommandDown = false
                emit(.commandReleased)
            }
        }
        let isFnDown = eventModifiers.contains(.maskSecondaryFn)
        let hasStandardModifier = !eventModifiers.subtracting(.maskSecondaryFn).isEmpty

        // Consume the companion release even if the user has since released Fn.
        if keyCode == UInt32(kVK_Space), let spacePress {
            if type == .keyUp {
                self.spacePress = nil
                switch spacePress {
                case .hold: emit(.holdReleased)
                case .command: emit(.commandReleased)
                case .consumed: break
                }
            }
            return true
        }
        if keyCode == UInt32(kVK_Escape), isEscapeDown {
            if type == .keyUp {
                isEscapeDown = false
            }
            return true
        }

        guard !isCapturingShortcut else {
            return false
        }

        if type == .flagsChanged {
            if command?.isCommandModifierChord == true,
                modifierFlags == commandFlags,
                !previousModifiers.contains(commandFlags)
            {
                cancelFunctionPress()
                if spacePress == .hold {
                    spacePress = .consumed
                    emit(.holdCancelled)
                }
                isModifierCommandDown = true
                emit(.commandPressed)
                return false
            }
            if keyCode == GlobalShortcut.functionKeyCode {
                if !isFnDown {
                    if functionPress == .holding {
                        emit(.holdReleased)
                    }
                    resetFunctionPress()
                } else if hold?.isStandaloneFunctionKey == true && !hasStandardModifier {
                    beginFunctionPress()
                }
            } else if hasStandardModifier {
                cancelFunctionPress()
            }
            return false
        }

        guard type == .keyDown else {
            return false
        }

        let hasCommandModifiers = capturesCommandEscape && !eventModifiers.isEmpty
            && commandFlags.contains(eventModifiers)
        if keyCode == UInt32(kVK_Escape), capturesEscape,
            (isFnDown && !hasStandardModifier) || hasCommandModifiers
        {
            resetFunctionPress()
            isEscapeDown = true
            emit(.cancelSession)
            return true
        }

        if isFnDown && !hasStandardModifier {
            if keyCode == UInt32(kVK_Space),
                toggle == .functionSpace || hold == .functionSpace || command == .functionSpace
            {
                guard !isRepeat else {
                    return true
                }
                let replacesHold = functionPress == .holding
                resetFunctionPress()
                if toggle == .functionSpace {
                    spacePress = .consumed
                    emit(.togglePressed(replacesHold: replacesHold))
                } else if command == .functionSpace {
                    if replacesHold {
                        emit(.holdCancelled)
                    }
                    spacePress = .command
                    emit(.commandPressed)
                } else {
                    spacePress = .hold
                    emit(.holdPressed)
                }
                return true
            }
        }

        // Leave other Fn combinations to macOS and the frontmost app.
        cancelFunctionPress()
        return false
    }

    private func beginFunctionPress() {
        guard functionPress == .idle, spacePress == nil else {
            return
        }
        functionPress = .pending
        let receivedAt = ContinuousClock.now
        // Give a chord or another Fn combination time to arrive before recording.
        pendingHold = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
            guard let self, self.functionPress == .pending else {
                return
            }
            self.pendingHold = nil
            self.functionPress = .holding
            self.emit(.holdPressed, receivedAt: receivedAt)
        }
    }

    private func cancelFunctionPress() {
        if functionPress == .holding {
            emit(.holdCancelled)
        }
        resetFunctionPress()
    }

    private func resetFunctionPress() {
        pendingHold?.cancel()
        pendingHold = nil
        functionPress = .idle
    }

    private func emit(_ action: Action, receivedAt: ContinuousClock.Instant = .now) {
        let revision = bindingRevision
        // Return from the tap before starting work or changing global registrations.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.bindingRevision == revision else {
                return
            }
            switch action {
            case .holdPressed, .togglePressed, .commandPressed:
                guard !self.isCapturingShortcut else {
                    return
                }
            default:
                break
            }
            self.onAction?(action, receivedAt)
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, context in
        guard let context else {
            return Unmanaged.passUnretained(event)
        }
        let monitor = Unmanaged<FunctionShortcutMonitor>.fromOpaque(context)
            .takeUnretainedValue()
        let isKeyboardEvent = type == .keyDown || type == .keyUp || type == .flagsChanged
        let keyCode = isKeyboardEvent
            ? UInt32(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            : 0
        let flags = isKeyboardEvent ? event.flags : []
        let isRepeat = type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        // The source is attached exclusively to the main run loop in start().
        let consumed = MainActor.assumeIsolated {
            monitor.handle(type, keyCode: keyCode, flags: flags, isRepeat: isRepeat)
        }
        return consumed ? nil : Unmanaged.passUnretained(event)
    }
}
