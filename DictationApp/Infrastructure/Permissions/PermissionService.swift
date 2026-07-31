import AppKit
// ApplicationServices currently imports kAXTrustedCheckOptionPrompt as a
// mutable C global even though this code only reads the system-owned constant
// on MainActor. Remove @preconcurrency when the SDK annotates it safely.
@preconcurrency import ApplicationServices
import AVFoundation
import Speech

enum MicrophonePermissionStatus: Equatable {
    case notDetermined
    case granted
    case denied
    case restricted
}

enum AccessibilityPermissionStatus: Equatable {
    case granted
    case notGranted
}

enum SpeechRecognitionPermissionStatus: Equatable {
    case notDetermined
    case granted
    case denied
    case restricted
}

enum PermissionSettingsPane {
    case microphone
    case accessibility
    case speechRecognition
}

@MainActor
protocol MicrophonePermissionServicing {
    func microphoneStatus() -> MicrophonePermissionStatus
    func requestMicrophoneAccess() async -> MicrophonePermissionStatus
}

@MainActor
final class PermissionService: MicrophonePermissionServicing {
    func microphoneStatus() -> MicrophonePermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .granted
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }

    func requestMicrophoneAccess() async -> MicrophonePermissionStatus {
        guard microphoneStatus() == .notDetermined else {
            return microphoneStatus()
        }

        _ = await AVCaptureDevice.requestAccess(for: .audio)
        return microphoneStatus()
    }

    func speechRecognitionStatus()
        -> SpeechRecognitionPermissionStatus
    {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .granted
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }

    func requestSpeechRecognitionAccess() async
        -> SpeechRecognitionPermissionStatus
    {
        guard speechRecognitionStatus() == .notDetermined else {
            return speechRecognitionStatus()
        }

        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization {
                continuation.resume(returning: $0)
            }
        }

        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }

    func accessibilityStatus() -> AccessibilityPermissionStatus {
        AXIsProcessTrusted() ? .granted : .notGranted
    }

    func requestAccessibilityAccess() -> AccessibilityPermissionStatus {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary

        _ = AXIsProcessTrustedWithOptions(options)
        return accessibilityStatus()
    }

    func openSystemSettings(for pane: PermissionSettingsPane) {
        let paneURLString: String

        switch pane {
        case .microphone:
            paneURLString =
                "x-apple.systempreferences:com.apple.preference.security" +
                "?Privacy_Microphone"
        case .accessibility:
            paneURLString =
                "x-apple.systempreferences:com.apple.preference.security" +
                "?Privacy_Accessibility"
        case .speechRecognition:
            paneURLString =
                "x-apple.systempreferences:com.apple.preference.security" +
                "?Privacy_SpeechRecognition"
        }

        if
            let paneURL = URL(string: paneURLString),
            NSWorkspace.shared.open(paneURL)
        {
            return
        }

        if let settingsURL = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}
