import Combine
import Foundation

@MainActor
final class DictationCoordinator: ObservableObject {
    @Published private(set) var state: DictationSessionState = .idle

    private let recorder: any AudioRecorder
    private let soundCuePlayer: SoundCuePlayer
    private let permissionService: PermissionService
    private let fileStore: RecordingFileStore
    private let clock = ContinuousClock()

    private var sessionID: UUID?
    private var sessionSoundCuesEnabled = true
    private var activeSession: ActiveSession?
    private var startTask: Task<Void, Never>?
    private var finalizationTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var ownedArtifactURL: URL?

    init(
        recorder: any AudioRecorder,
        soundCuePlayer: SoundCuePlayer,
        permissionService: PermissionService,
        fileStore: RecordingFileStore
    ) {
        self.recorder = recorder
        self.soundCuePlayer = soundCuePlayer
        self.permissionService = permissionService
        self.fileStore = fileStore

        self.recorder.onUnexpectedCaptureFailure = { [weak self] in
            self?.handleUnexpectedCaptureFailure()
        }
    }

    var acceptsToggle: Bool {
        switch state {
        case .idle, .recording:
            true
        case
            .preparing,
            .finalizing,
            .completed,
            .tooShort,
            .cancelled,
            .failed:
            false
        }
    }

    var canCancel: Bool {
        state != .idle
    }

    func start(
        configuration: SessionConfiguration,
        soundCuesEnabled: Bool
    ) {
        guard state == .idle else {
            return
        }

        let identifier = UUID()
        sessionID = identifier
        sessionSoundCuesEnabled = soundCuesEnabled
        ownedArtifactURL = nil
        state = .preparing(configuration)

        startTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await ensureMicrophonePermission()
                try Task.checkCancellation()

                let prepared = try await recorder.prepare(
                    profile: configuration.recordingProfile
                )
                try Task.checkCancellation()

                await soundCuePlayer.play(
                    .recordingStarted,
                    enabled: soundCuesEnabled
                )
                try Task.checkCancellation()

                try await recorder.startPreparedRecording()
                try Task.checkCancellation()

                guard sessionID == identifier else {
                    await recorder.cancelRecording()
                    return
                }

                let startedAt = clock.now
                activeSession = ActiveSession(
                    identifier: identifier,
                    configuration: configuration,
                    inputDeviceName: prepared.inputDeviceName,
                    startedAt: startedAt,
                    soundCuesEnabled: soundCuesEnabled
                )
                state = .recording(
                    RecordingSessionState(
                        configuration: configuration,
                        inputDeviceName: prepared.inputDeviceName,
                        elapsed: 0,
                        isNearDurationLimit: false
                    )
                )
                startElapsedUpdates(for: identifier)
            } catch is CancellationError {
                // Explicit cancellation owns the cleanup and state transition.
            } catch {
                await handleStartFailure(
                    map(error),
                    identifier: identifier,
                    soundCuesEnabled: soundCuesEnabled
                )
            }

            if sessionID == identifier {
                startTask = nil
            }
        }
    }

    func stop() {
        guard case .recording = state, let activeSession else {
            return
        }

        beginFinalization(
            activeSession: activeSession,
            reason: .stopped
        )
    }

    func cancel() {
        guard canCancel else {
            return
        }

        let soundCuesEnabled = sessionSoundCuesEnabled
        startTask?.cancel()
        finalizationTask?.cancel()
        startTask = nil
        finalizationTask = nil
        elapsedTask?.cancel()
        elapsedTask = nil
        activeSession = nil
        sessionID = nil
        sessionSoundCuesEnabled = true

        recorder.cancelImmediately()
        if let ownedArtifactURL {
            fileStore.delete(ownedArtifactURL)
        }
        ownedArtifactURL = nil
        state = .idle

        soundCuePlayer.enqueue(
            .sessionCancelled,
            enabled: soundCuesEnabled
        )
    }

    func cancelImmediately() {
        startTask?.cancel()
        finalizationTask?.cancel()
        elapsedTask?.cancel()
        startTask = nil
        finalizationTask = nil
        elapsedTask = nil
        activeSession = nil
        sessionID = nil
        sessionSoundCuesEnabled = true
        recorder.cancelImmediately()
        if let ownedArtifactURL {
            fileStore.delete(ownedArtifactURL)
        }
        ownedArtifactURL = nil
        state = .idle
    }

    private func ensureMicrophonePermission() async throws {
        var status = permissionService.microphoneStatus()

        if status == .notDetermined {
            status = await permissionService.requestMicrophoneAccess()
        }

        switch status {
        case .granted:
            return
        case .denied, .notDetermined:
            throw DictationCaptureError.microphoneDenied
        case .restricted:
            throw DictationCaptureError.microphoneRestricted
        }
    }

    private func startElapsedUpdates(for identifier: UUID) {
        elapsedTask?.cancel()
        elapsedTask = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                try? await clock.sleep(for: .milliseconds(100))
                guard
                    !Task.isCancelled,
                    sessionID == identifier,
                    let activeSession,
                    activeSession.identifier == identifier,
                    case .recording = state
                else {
                    return
                }

                let elapsed = timeInterval(
                    clock.now - activeSession.startedAt
                )
                let profile =
                    activeSession.configuration.recordingProfile

                if elapsed >= profile.maximumDuration {
                    beginFinalization(
                        activeSession: activeSession,
                        reason: .automaticLimit
                    )
                    return
                }

                state = .recording(
                    RecordingSessionState(
                        configuration: activeSession.configuration,
                        inputDeviceName: activeSession.inputDeviceName,
                        elapsed: elapsed,
                        isNearDurationLimit:
                            elapsed >= profile.warningDuration
                    )
                )
            }
        }
    }

    private func beginFinalization(
        activeSession: ActiveSession,
        reason: RecordingFinalizationReason
    ) {
        guard
            sessionID == activeSession.identifier,
            case .recording = state
        else {
            return
        }

        elapsedTask?.cancel()
        elapsedTask = nil
        self.activeSession = nil
        state = .finalizing(reason)

        finalizationTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let artifact = try await recorder.stopRecording()
                guard sessionID == activeSession.identifier else {
                    fileStore.delete(artifact.url)
                    return
                }

                ownedArtifactURL = artifact.url
                await soundCuePlayer.play(
                    .recordingStopped,
                    enabled: activeSession.soundCuesEnabled
                )

                guard sessionID == activeSession.identifier else {
                    fileStore.delete(artifact.url)
                    if ownedArtifactURL == artifact.url {
                        ownedArtifactURL = nil
                    }
                    return
                }

                if
                    artifact.duration
                        < activeSession.configuration.recordingProfile
                            .minimumDuration
                {
                    fileStore.delete(artifact.url)
                    ownedArtifactURL = nil
                    state = .tooShort
                    await returnToIdle(
                        after: 1.2,
                        sessionIdentifier: activeSession.identifier
                    )
                    return
                }

                state = .completed(artifact)
                await returnToIdle(
                    after: 1.2,
                    sessionIdentifier: activeSession.identifier,
                    deleting: artifact.url
                )
            } catch is CancellationError {
                // Immediate application termination owns cleanup.
            } catch {
                await presentFailure(
                    map(error),
                    identifier: activeSession.identifier,
                    soundCuesEnabled: activeSession.soundCuesEnabled
                )
            }
        }
    }

    private func handleStartFailure(
        _ error: DictationCaptureError,
        identifier: UUID,
        soundCuesEnabled: Bool
    ) async {
        await recorder.cancelRecording()
        await presentFailure(
            error,
            identifier: identifier,
            soundCuesEnabled: soundCuesEnabled
        )
    }

    private func handleUnexpectedCaptureFailure() {
        guard
            case .recording = state,
            let activeSession,
            sessionID == activeSession.identifier
        else {
            return
        }

        elapsedTask?.cancel()
        elapsedTask = nil
        self.activeSession = nil
        state = .finalizing(.stopped)

        finalizationTask = Task { [weak self] in
            guard let self else {
                return
            }

            await presentFailure(
                .cannotFinalizeRecording,
                identifier: activeSession.identifier,
                soundCuesEnabled: activeSession.soundCuesEnabled
            )
        }
    }

    private func presentFailure(
        _ error: DictationCaptureError,
        identifier: UUID,
        soundCuesEnabled: Bool
    ) async {
        await soundCuePlayer.play(
            .attentionRequired,
            enabled: soundCuesEnabled
        )

        guard sessionID == identifier else {
            return
        }

        state = .failed(error)
        await returnToIdle(
            after: 3,
            sessionIdentifier: identifier
        )
    }

    private func returnToIdle(
        after delay: TimeInterval,
        sessionIdentifier: UUID,
        deleting artifactURL: URL? = nil
    ) async {
        try? await Task.sleep(
            for: .seconds(delay)
        )

        if let artifactURL {
            fileStore.delete(artifactURL)
            if ownedArtifactURL == artifactURL {
                ownedArtifactURL = nil
            }
        }

        guard sessionID == sessionIdentifier else {
            return
        }

        sessionID = nil
        sessionSoundCuesEnabled = true
        activeSession = nil
        finalizationTask = nil
        ownedArtifactURL = nil
        state = .idle
    }

    private func map(_ error: any Error) -> DictationCaptureError {
        if let captureError = error as? DictationCaptureError {
            return captureError
        }

        guard let recorderError = error as? AudioRecorderError else {
            return .cannotConfigureCapture
        }

        switch recorderError {
        case .noInputDevice:
            return .noInputDevice
        case .cannotConfigure, .unsupportedFileType:
            return .cannotConfigureCapture
        case .cannotStart:
            return .cannotStartCapture
        case .cannotFinalize:
            return .cannotFinalizeRecording
        case .invalidArtifact:
            return .invalidRecording
        }
    }

    private func timeInterval(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

private struct ActiveSession {
    let identifier: UUID
    let configuration: SessionConfiguration
    let inputDeviceName: String
    let startedAt: ContinuousClock.Instant
    let soundCuesEnabled: Bool
}
