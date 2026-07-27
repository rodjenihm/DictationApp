import Combine
import Foundation

@MainActor
final class DictationCoordinator: ObservableObject {
    @Published private(set) var state: DictationSessionState = .idle

    private let recorder: any AudioRecorder
    private let soundCuePlayer: SoundCuePlayer
    private let permissionService: any MicrophonePermissionServicing
    private let fileStore: RecordingFileStore
    private let transcriptionProvider: any TranscriptionProvider
    private let postProcessingProvider: any PostProcessingProvider
    private let postProcessingRuntimeHealth:
        PostProcessingRuntimeHealth
    private let clipboardService: any TranscriptClipboardServicing
    private let textInsertionService: any TextInsertionServicing
    private let clock = ContinuousClock()

    private var sessionID: UUID?
    private var sessionSoundCuesEnabled = true
    private var activeSession: ActiveSession?
    private var startTask: Task<Void, Never>?
    private var finalizationTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var ownedArtifactURL: URL?
    private var failedSessionContext: FailedSessionContext?
    private var activeClipboardTransaction:
        (any ClipboardTransactionHandling)?

    init(
        recorder: any AudioRecorder,
        soundCuePlayer: SoundCuePlayer,
        permissionService: any MicrophonePermissionServicing,
        fileStore: RecordingFileStore,
        transcriptionProvider: any TranscriptionProvider,
        postProcessingProvider: any PostProcessingProvider,
        postProcessingRuntimeHealth: PostProcessingRuntimeHealth,
        clipboardService: any TranscriptClipboardServicing,
        textInsertionService: any TextInsertionServicing
    ) {
        self.recorder = recorder
        self.soundCuePlayer = soundCuePlayer
        self.permissionService = permissionService
        self.fileStore = fileStore
        self.transcriptionProvider = transcriptionProvider
        self.postProcessingProvider = postProcessingProvider
        self.postProcessingRuntimeHealth =
            postProcessingRuntimeHealth
        self.clipboardService = clipboardService
        self.textInsertionService = textInsertionService

        self.recorder.onUnexpectedCaptureFailure = { [weak self] outcome in
            self?.handleUnexpectedCaptureFailure(outcome)
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
            .transcribing,
            .postProcessing,
            .inserting,
            .inserted,
            .insertionUnverified,
            .clipboardFallback,
            .rawTranscriptFallback,
            .noSpeech,
            .transcriptionFailed,
            .captureFailed,
            .tooShort,
            .cancelled,
            .failed:
            false
        }
    }

    var canCancel: Bool {
        switch state {
        case
            .idle,
            .inserted,
            .insertionUnverified,
            .clipboardFallback,
            .rawTranscriptFallback,
            .noSpeech:
            false
        case
            .preparing,
            .recording,
            .finalizing,
            .completed,
            .transcribing,
            .postProcessing,
            .inserting,
            .transcriptionFailed,
            .captureFailed,
            .tooShort,
            .cancelled,
            .failed:
            true
        }
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
        failedSessionContext = nil
        activeClipboardTransaction = nil
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

    func retryTranscription() {
        guard
            case .transcriptionFailed = state,
            let failedSessionContext,
            sessionID == failedSessionContext.identifier
        else {
            return
        }

        state = .transcribing(
            failedSessionContext.effectiveConfiguration
                .transcriptionProvider
        )
        finalizationTask = Task { [weak self] in
            guard let self else {
                return
            }

            await transcribe(failedSessionContext)
        }
    }

    func applyTranscriptionRepair(_ repair: TranscriptionRepair) {
        guard
            case .transcriptionFailed(let failure) = state,
            failure.isConfigurationFailure,
            var failedSessionContext
        else {
            return
        }

        failedSessionContext.apply(repair)
        self.failedSessionContext = failedSessionContext
        state = .transcriptionFailed(
            TranscriptionFailureState(
                message:
                    "Transcription configuration repaired. Retry the retained recording.",
                isConfigurationFailure: true
            )
        )
    }

    func transcribePartial() {
        guard
            case .captureFailed = state,
            let failedSessionContext,
            sessionID == failedSessionContext.identifier
        else {
            return
        }

        state = .transcribing(
            failedSessionContext.effectiveConfiguration
                .transcriptionProvider
        )
        finalizationTask = Task { [weak self] in
            guard let self else {
                return
            }

            await transcribe(failedSessionContext)
        }
    }

    func discardPartial() {
        guard case .captureFailed = state else {
            return
        }
        cancel()
    }

    func discardTranscription() {
        guard case .transcriptionFailed = state else {
            return
        }
        cancel()
    }

    func dismissDeliveryStatus() {
        switch state {
        case .insertionUnverified, .clipboardFallback:
            break
        default:
            return
        }

        finalizationTask?.cancel()
        finalizationTask = nil
        activeClipboardTransaction?.abandon()
        activeClipboardTransaction = nil
        sessionID = nil
        sessionSoundCuesEnabled = true
        activeSession = nil
        failedSessionContext = nil
        ownedArtifactURL = nil
        state = .idle
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
        failedSessionContext = nil
        activeClipboardTransaction?.restoreIfOwned()
        activeClipboardTransaction = nil
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
        failedSessionContext = nil
        activeClipboardTransaction?.restoreIfOwned()
        activeClipboardTransaction = nil
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

                await transcribe(
                    FailedSessionContext(
                        identifier: activeSession.identifier,
                        originalConfiguration:
                            activeSession.configuration,
                        artifact: artifact,
                        soundCuesEnabled:
                            activeSession.soundCuesEnabled,
                        transcriptionRepair: nil
                    )
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

    private func transcribe(
        _ session: FailedSessionContext
    ) async {
        guard
            sessionID == session.identifier,
            ownedArtifactURL == session.artifact.url
        else {
            return
        }

        state = .transcribing(
            session.effectiveConfiguration.transcriptionProvider
        )

        do {
            guard
                session.effectiveConfiguration.transcriptionProvider
                    == transcriptionProvider.providerID
            else {
                throw ProviderOperationFailure.configuration(
                    message:
                        "The configured transcription provider is unavailable."
                )
            }

            let transcript = try await transcriptionProvider.transcribe(
                TranscriptionRequest(
                    artifact: session.artifact,
                    model:
                        session.effectiveConfiguration.transcriptionModel,
                    language:
                        session.effectiveConfiguration.language
                )
            )

            guard sessionID == session.identifier else {
                return
            }

            fileStore.delete(session.artifact.url)
            if ownedArtifactURL == session.artifact.url {
                ownedArtifactURL = nil
            }
            failedSessionContext = nil

            let normalizedTranscript = transcript.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            if normalizedTranscript.isEmpty {
                state = .noSpeech
                await returnToIdle(
                    after: 2,
                    sessionIdentifier: session.identifier
                )
            } else {
                await deliverTranscript(
                    normalizedTranscript,
                    configuration:
                        session.effectiveConfiguration,
                    sessionIdentifier: session.identifier
                )
            }
        } catch let failure as ProviderOperationFailure {
            if
                failure == .cancelled,
                sessionID != session.identifier
            {
                return
            }

            await presentTranscriptionFailure(
                failure == .cancelled
                    ? .operation(
                        message:
                            "The transcription request was interrupted."
                    )
                    : failure,
                session: session
            )
        } catch is CancellationError {
            if sessionID == session.identifier {
                await presentTranscriptionFailure(
                    .operation(
                        message:
                            "The transcription request was interrupted."
                    ),
                    session: session
                )
            }
        } catch {
            await presentTranscriptionFailure(
                .operation(
                    message: "The recording could not be transcribed."
                ),
                session: session
            )
        }
    }

    private func deliverTranscript(
        _ rawTranscript: String,
        configuration: SessionConfiguration,
        sessionIdentifier: UUID
    ) async {
        guard sessionID == sessionIdentifier else {
            return
        }

        guard configuration.postProcessingMode == .enabled else {
            await insertTranscript(
                rawTranscript,
                rawFallbackMessage: nil,
                sessionIdentifier: sessionIdentifier
            )
            return
        }

        let postProcessingConfiguration =
            PostProcessingConfiguration(
                sessionConfiguration: configuration
            )

        if postProcessingRuntimeHealth.shouldSkip(
            postProcessingConfiguration
        ) {
            await insertTranscript(
                rawTranscript,
                rawFallbackMessage:
                    "Cleanup needs attention.",
                sessionIdentifier: sessionIdentifier
            )
            return
        }

        guard
            configuration.postProcessingProvider
                == postProcessingProvider.providerID
        else {
            let message =
                "The configured post-processing provider is unavailable."
            postProcessingRuntimeHealth.markNeedsAttention(
                postProcessingConfiguration,
                message: message
            )
            await insertTranscript(
                rawTranscript,
                rawFallbackMessage:
                    "Cleanup was unavailable.",
                sessionIdentifier: sessionIdentifier
            )
            return
        }

        state = .postProcessing(
            configuration.postProcessingProvider
        )

        do {
            let output = try await postProcessingProvider.process(
                PostProcessingRequest(
                    rawTranscript: rawTranscript,
                    model: configuration.postProcessingModel
                )
            )

            guard sessionID == sessionIdentifier else {
                return
            }

            let validatedOutput =
                try PostProcessingOutputPolicy.validatedOutput(
                    output,
                    rawTranscript: rawTranscript
                )

            await insertTranscript(
                validatedOutput,
                rawFallbackMessage: nil,
                sessionIdentifier: sessionIdentifier
            )
        } catch let failure as ProviderOperationFailure {
            guard sessionID == sessionIdentifier else {
                return
            }

            if failure.isConfigurationFailure {
                postProcessingRuntimeHealth.markNeedsAttention(
                    postProcessingConfiguration,
                    message:
                        failure.errorDescription
                        ?? "Post-processing configuration needs attention."
                )
            }

            await insertTranscript(
                rawTranscript,
                rawFallbackMessage:
                    "Cleanup was unavailable.",
                sessionIdentifier: sessionIdentifier
            )
        } catch is CancellationError {
            guard sessionID == sessionIdentifier else {
                return
            }

            await insertTranscript(
                rawTranscript,
                rawFallbackMessage:
                    "Cleanup was unavailable.",
                sessionIdentifier: sessionIdentifier
            )
        } catch {
            guard sessionID == sessionIdentifier else {
                return
            }

            await insertTranscript(
                rawTranscript,
                rawFallbackMessage:
                    "Cleanup was unavailable.",
                sessionIdentifier: sessionIdentifier
            )
        }
    }

    private func insertTranscript(
        _ transcript: String,
        rawFallbackMessage: String?,
        sessionIdentifier: UUID
    ) async {
        guard sessionID == sessionIdentifier else {
            return
        }

        state = .inserting
        let transaction = clipboardService.beginTransaction(
            replacingContentsWith: transcript
        )
        activeClipboardTransaction = transaction

        await Task.yield()

        guard
            sessionID == sessionIdentifier,
            activeClipboardTransaction != nil
        else {
            return
        }

        let outcome = await textInsertionService.insert(
            transcript,
            using: transaction
        )

        guard sessionID == sessionIdentifier else {
            return
        }

        activeClipboardTransaction = nil

        switch outcome {
        case .confirmed:
            _ = transaction.restoreIfOwned()

            if let rawFallbackMessage {
                state = .rawTranscriptFallback(
                    rawFallbackMessage
                        + " The raw transcript was inserted."
                )
                await returnToIdle(
                    after: 2.5,
                    sessionIdentifier: sessionIdentifier
                )
            } else {
                state = .inserted
                await returnToIdle(
                    after: 1.2,
                    sessionIdentifier: sessionIdentifier
                )
            }
        case .unverified:
            let message = deliveryFallbackMessage(
                outcome: .unverified,
                rawFallbackMessage: rawFallbackMessage,
                transcriptRemainsOnClipboard:
                    transaction.isStillOwned
            )
            transaction.abandon()
            state = .insertionUnverified(message)
            await returnToIdle(
                after: 6,
                sessionIdentifier: sessionIdentifier
            )
        case .failed:
            let message = deliveryFallbackMessage(
                outcome: .failed,
                rawFallbackMessage: rawFallbackMessage,
                transcriptRemainsOnClipboard:
                    transaction.isStillOwned
            )
            transaction.abandon()
            state = .clipboardFallback(message)
            await returnToIdle(
                after: 6,
                sessionIdentifier: sessionIdentifier
            )
        }
    }

    private func deliveryFallbackMessage(
        outcome: TextInsertionOutcome,
        rawFallbackMessage: String?,
        transcriptRemainsOnClipboard: Bool
    ) -> String {
        let cleanupPrefix = rawFallbackMessage.map { $0 + " " } ?? ""

        guard transcriptRemainsOnClipboard else {
            return cleanupPrefix
                + "The clipboard changed, so its newer contents were preserved."
        }

        switch outcome {
        case .unverified:
            return cleanupPrefix
                + "Insertion could not be verified. The transcript remains on the clipboard."
        case .failed:
            return cleanupPrefix
                + "Automatic insertion was unavailable. The transcript is ready to paste."
        case .confirmed:
            return cleanupPrefix
        }
    }

    private func presentTranscriptionFailure(
        _ failure: ProviderOperationFailure,
        session: FailedSessionContext
    ) async {
        await soundCuePlayer.play(
            .attentionRequired,
            enabled: session.soundCuesEnabled
        )

        guard
            sessionID == session.identifier,
            ownedArtifactURL == session.artifact.url
        else {
            return
        }

        failedSessionContext = session
        finalizationTask = nil
        state = .transcriptionFailed(
            TranscriptionFailureState(
                message:
                    failure.errorDescription
                    ?? "The recording could not be transcribed.",
                isConfigurationFailure:
                    failure.isConfigurationFailure
            )
        )
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

    private func handleUnexpectedCaptureFailure(
        _ outcome: UnexpectedCaptureOutcome
    ) {
        guard
            case .recording = state,
            let activeSession,
            sessionID == activeSession.identifier
        else {
            if case .partial(let artifact) = outcome {
                fileStore.delete(artifact.url)
            }
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

            switch outcome {
            case .partial(let artifact):
                guard sessionID == activeSession.identifier else {
                    fileStore.delete(artifact.url)
                    return
                }

                ownedArtifactURL = artifact.url

                guard
                    artifact.duration
                        >= activeSession.configuration.recordingProfile
                            .minimumDuration
                else {
                    fileStore.delete(artifact.url)
                    ownedArtifactURL = nil
                    await presentFailure(
                        .partialRecordingTooShort,
                        identifier: activeSession.identifier,
                        soundCuesEnabled:
                            activeSession.soundCuesEnabled
                    )
                    return
                }

                let failedContext = FailedSessionContext(
                    identifier: activeSession.identifier,
                    originalConfiguration:
                        activeSession.configuration,
                    artifact: artifact,
                    soundCuesEnabled:
                        activeSession.soundCuesEnabled,
                    transcriptionRepair: nil
                )
                failedSessionContext = failedContext

                await soundCuePlayer.play(
                    .attentionRequired,
                    enabled: activeSession.soundCuesEnabled
                )

                guard
                    sessionID == activeSession.identifier,
                    ownedArtifactURL == artifact.url
                else {
                    return
                }

                finalizationTask = nil
                state = .captureFailed(
                    RecoverableCaptureFailureState(
                        message:
                            "The microphone became unavailable. A partial recording can be transcribed or discarded.",
                        artifact: artifact
                    )
                )
            case .failed(let recorderError):
                await presentFailure(
                    map(recorderError),
                    identifier: activeSession.identifier,
                    soundCuesEnabled:
                        activeSession.soundCuesEnabled
                )
            }
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
        failedSessionContext = nil
        activeClipboardTransaction?.abandon()
        activeClipboardTransaction = nil
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
