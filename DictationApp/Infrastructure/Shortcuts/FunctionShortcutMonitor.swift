import Carbon.HIToolbox
import CoreGraphics
import Foundation

@MainActor
final class FunctionShortcutMonitor {
    enum Action: Equatable {
        case holdPressed
        case holdReleased
        case holdCancelled
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
    }

    var onAction: ((Action, ContinuousClock.Instant) -> Void)?
    var isCapturingShortcut = false {
        didSet {
            if isCapturingShortcut {
                cancelFunctionPress()
            }
        }
    }
    var capturesEscape = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var toggle: GlobalShortcut?
    private var hold: GlobalShortcut?
    private var bindingRevision = 0
    private var functionPress = FunctionPress.idle
    private var pendingHold: Task<Void, Never>?
    private var spacePress: SpacePress?
    private var isEscapeDown = false

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
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return true
    }

    func updateBindings(toggle: GlobalShortcut?, hold: GlobalShortcut?) {
        guard self.toggle != toggle || self.hold != hold else {
            return
        }
        self.toggle = toggle
        self.hold = hold
        bindingRevision &+= 1
        resetFunctionPress()
        if spacePress != nil {
            spacePress = .consumed
        }

        if toggle == nil, hold == nil {
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
        bindingRevision &+= 1
        resetFunctionPress()
        spacePress = nil
        isEscapeDown = false
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
            resetFunctionPress()
            spacePress = nil
            isEscapeDown = false
            if type == .tapDisabledByTimeout, let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }

        let isFnDown = flags.contains(.maskSecondaryFn)
        let hasStandardModifier = !flags.intersection(
            [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        ).isEmpty

        // Consume the companion release even if the user has since released Fn.
        if keyCode == UInt32(kVK_Space), let spacePress {
            if type == .keyUp {
                self.spacePress = nil
                if spacePress == .hold {
                    emit(.holdReleased)
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

        if isFnDown && !hasStandardModifier {
            if keyCode == UInt32(kVK_Escape) && capturesEscape {
                resetFunctionPress()
                isEscapeDown = true
                emit(.cancelSession)
                return true
            }
            if keyCode == UInt32(kVK_Space),
                toggle == .functionSpace || hold == .functionSpace
            {
                guard !isRepeat else {
                    return true
                }
                let replacesHold = functionPress == .holding
                resetFunctionPress()
                if toggle == .functionSpace {
                    spacePress = .consumed
                    emit(.togglePressed(replacesHold: replacesHold))
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
            case .holdPressed, .togglePressed:
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
