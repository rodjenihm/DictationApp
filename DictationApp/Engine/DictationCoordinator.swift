import Combine
import Foundation
import OSLog

@MainActor
final class DictationCoordinator: ObservableObject {
    @Published private(set) var state: DictationSessionState = .idle

    private let recorder: any AudioRecorder
    private let soundCuePlayer: SoundCuePlayer
    private let permissionService: any MicrophonePermissionServicing
    private let fileStore: RecordingFileStore
    private let providerResolver: any ProviderRuntimeResolving
    private let providerRuntimeHealth:
        ProviderRuntimeHealthStore
    private let clipboardService: any TranscriptClipboardServicing
    private let textInsertionService: any TextInsertionServicing
    private let clock = ContinuousClock()

    private var currentToken: SessionToken?
    private var pipelineTask: Task<Void, Never>?
    private var pipelineEvents:
        AsyncStream<PipelineEvent>.Continuation?
    private var sessionSoundCuesEnabled = true
    private var ownedArtifactURL: URL?
    private var failedSessionContext: FailedSessionContext?
    private var activeClipboardTransaction:
        (any ClipboardTransactionHandling)?
    private var activeTextPayload: SessionTextPayload?
    private var pendingCancellationCue:
        (sessionIdentifier: UUID, enabled: Bool)?

    init(
        recorder: any AudioRecorder,
        soundCuePlayer: SoundCuePlayer,
        permissionService: any MicrophonePermissionServicing,
        fileStore: RecordingFileStore,
        providerResolver: any ProviderRuntimeResolving,
        providerRuntimeHealth: ProviderRuntimeHealthStore,
        clipboardService: any TranscriptClipboardServicing,
        textInsertionService: any TextInsertionServicing
    ) {
        self.recorder = recorder
        self.soundCuePlayer = soundCuePlayer
        self.permissionService = permissionService
        self.fileStore = fileStore
        self.providerResolver = providerResolver
        self.providerRuntimeHealth = providerRuntimeHealth
        self.clipboardService = clipboardService
        self.textInsertionService = textInsertionService

        self.recorder.onUnexpectedCaptureFailure = {
            [weak self] identifier, outcome in
            self?.submit(
                .unexpectedCapture(outcome),
                sessionIdentifier: identifier
            )
        }
        self.recorder.onCancellationTeardownCompleted = {
            [weak self] identifier in
            self?.playCancellationCueAfterTeardown(
                sessionIdentifier: identifier
            )
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

    var transcriptionRepairContext: TranscriptionRepairContext? {
        guard let failedSessionContext else {
            return nil
        }
        return TranscriptionRepairContext(
            recordingProfile:
                failedSessionContext.effectiveConfiguration.recordingProfile,
            language:
                failedSessionContext.effectiveConfiguration.language
        )
    }

    func start(
        configuration: SessionConfiguration,
        soundCuesEnabled: Bool
    ) {
        guard state == .idle, currentToken == nil else {
            return
        }

        pendingCancellationCue = nil
        let token = SessionToken()
        let (events, continuation) = AsyncStream.makeStream(
            of: PipelineEvent.self,
            bufferingPolicy: .unbounded
        )

        currentToken = token
        pipelineEvents = continuation
        sessionSoundCuesEnabled = soundCuesEnabled
        ownedArtifactURL = nil
        failedSessionContext = nil
        activeClipboardTransaction = nil
        activeTextPayload = SessionTextPayload()

        guard transition(to: .preparing(configuration), token: token)
        else {
            resetSessionWithoutCue()
            return
        }

        pipelineTask = Task { [weak self] in
            guard let self else {
                return
            }

            await runPipeline(
                token: token,
                configuration: configuration,
                soundCuesEnabled: soundCuesEnabled,
                events: events,
                eventContinuation: continuation
            )
        }
    }

    func stop() {
        guard case .recording = state else {
            return
        }
        submit(.stop(.stopped))
    }

    func retryTranscription() {
        guard case .transcriptionFailed = state else {
            return
        }
        submit(.retryTranscription)
    }

    func applyTranscriptionRepair(_ repair: TranscriptionRepair) {
        guard
            case .transcriptionFailed(let failure) = state,
            failure.isConfigurationFailure
        else {
            return
        }
        submit(.applyTranscriptionRepair(repair))
    }

    func transcribePartial() {
        guard case .captureFailed = state else {
            return
        }
        submit(.transcribePartial)
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
            completeCurrentSessionWithoutCue()
        default:
            return
        }
    }

    func cancel() {
        guard canCancel else {
            return
        }
        cancelCurrentSession(playCue: true)
    }

    func cancelImmediately() {
        cancelCurrentSession(playCue: false)
    }

    func shutdownImmediately() {
        cancelCurrentSession(
            playCue: false,
            isTerminating: true
        )
    }

    private func runPipeline(
        token: SessionToken,
        configuration: SessionConfiguration,
        soundCuesEnabled: Bool,
        events: AsyncStream<PipelineEvent>,
        eventContinuation:
            AsyncStream<PipelineEvent>.Continuation
    ) async {
        do {
            try await ensureMicrophonePermission()
            try requireCurrent(token)

            let prepared = try await recorder.prepare(
                profile: configuration.recordingProfile,
                sessionIdentifier: token.id
            )
            try requireCurrent(token)

            await soundCuePlayer.play(
                .recordingStarted,
                enabled: soundCuesEnabled
            )
            try requireCurrent(token)

            try await recorder.startPreparedRecording()
            try requireCurrent(token)

            let activeSession = ActiveSession(
                token: token,
                configuration: configuration,
                inputDeviceName: prepared.inputDeviceName,
                startedAt: clock.now,
                soundCuesEnabled: soundCuesEnabled
            )

            guard transition(
                to: recordingState(for: activeSession),
                token: token
            ) else {
                throw CancellationError()
            }

            let recordingEvent = try await waitForRecordingEvent(
                events,
                eventContinuation: eventContinuation,
                activeSession: activeSession
            )
            try requireCurrent(token)

            let capturedSession: CapturedSessionResult
            switch recordingEvent {
            case .stop(let reason):
                capturedSession = try await finalizeRecording(
                    activeSession,
                    reason: reason
                )
            case .unexpectedCapture(let outcome):
                capturedSession = try await handleUnexpectedCapture(
                    outcome,
                    activeSession: activeSession
                )
            case
                .elapsed,
                .retryTranscription,
                .transcribePartial,
                .applyTranscriptionRepair:
                throw CancellationError()
            }

            switch capturedSession {
            case .terminal:
                completeCurrentSession(token: token)
                return
            case .recoverablePartial(let session):
                let sessionToTranscribe =
                    try await waitForPartialTranscription(
                        session,
                        events: events
                    )
                try await runTranscriptionLoop(
                    sessionToTranscribe,
                    events: events
                )
            case .ready(let session):
                try await runTranscriptionLoop(
                    session,
                    events: events
                )
            }

            completeCurrentSession(token: token)
        } catch is CancellationError {
            // Explicit cancellation invalidates the token and owns cleanup.
        } catch {
            guard isCurrent(token) else {
                return
            }

            await recorder.cancelRecording(
                sessionIdentifier: token.id
            )
            guard isCurrent(token) else {
                return
            }

            await presentCaptureFailure(
                map(error),
                token: token,
                soundCuesEnabled: soundCuesEnabled
            )
            completeCurrentSession(token: token)
        }
    }

    private func waitForRecordingEvent(
        _ events: AsyncStream<PipelineEvent>,
        eventContinuation:
            AsyncStream<PipelineEvent>.Continuation,
        activeSession: ActiveSession
    ) async throws -> PipelineEvent {
        let result = await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let timerClock = ContinuousClock()
                while !Task.isCancelled {
                    do {
                        try await timerClock.sleep(
                            for: .milliseconds(100)
                        )
                    } catch {
                        return
                    }

                    guard !Task.isCancelled else {
                        return
                    }

                    let elapsed = Self.timeInterval(
                        timerClock.now
                            - activeSession.startedAt
                    )
                    eventContinuation.yield(.elapsed(elapsed))
                }
            }

            var recordingResult: PipelineEvent?
            for await event in events {
                switch event {
                case .elapsed(let elapsed):
                    guard
                        isCurrent(activeSession.token),
                        case .recording = state
                    else {
                        recordingResult = nil
                        break
                    }

                    let profile =
                        activeSession.configuration.recordingProfile
                    if elapsed >= profile.maximumDuration {
                        recordingResult = .stop(.automaticLimit)
                        break
                    }

                    _ = transition(
                        to: recordingState(
                            for: activeSession,
                            elapsed: elapsed
                        ),
                        token: activeSession.token
                    )
                case .stop, .unexpectedCapture:
                    recordingResult = event
                case
                    .retryTranscription,
                    .transcribePartial,
                    .applyTranscriptionRepair:
                    continue
                }

                if recordingResult != nil
                    || !isCurrent(activeSession.token)
                {
                    break
                }
            }

            group.cancelAll()
            return recordingResult
        }

        guard let result else {
            throw CancellationError()
        }
        return result
    }

    private func finalizeRecording(
        _ activeSession: ActiveSession,
        reason: RecordingFinalizationReason
    ) async throws -> CapturedSessionResult {
        guard transition(
            to: .finalizing(reason),
            token: activeSession.token
        ) else {
            throw CancellationError()
        }

        let artifact = try await recorder.stopRecording()
        guard isCurrent(activeSession.token) else {
            fileStore.delete(artifact.url)
            throw CancellationError()
        }
        try Task.checkCancellation()
        ownedArtifactURL = artifact.url

        await soundCuePlayer.play(
            .recordingStopped,
            enabled: activeSession.soundCuesEnabled
        )
        try requireCurrent(activeSession.token)

        guard
            artifact.duration
                >= activeSession.configuration.recordingProfile
                    .minimumDuration
        else {
            deleteOwnedArtifact(artifact.url)
            guard transition(
                to: .tooShort,
                token: activeSession.token
            ) else {
                throw CancellationError()
            }
            try await sleep(
                for: 1.2,
                token: activeSession.token
            )
            return .terminal
        }

        return .ready(
            failedContext(
                for: artifact,
                activeSession: activeSession
            )
        )
    }

    private func handleUnexpectedCapture(
        _ outcome: UnexpectedCaptureOutcome,
        activeSession: ActiveSession
    ) async throws -> CapturedSessionResult {
        guard transition(
            to: .finalizing(.stopped),
            token: activeSession.token
        ) else {
            if case .partial(let artifact) = outcome {
                fileStore.delete(artifact.url)
            }
            throw CancellationError()
        }

        switch outcome {
        case .partial(let artifact):
            try requireCurrent(activeSession.token)
            ownedArtifactURL = artifact.url

            guard
                artifact.duration
                    >= activeSession.configuration.recordingProfile
                        .minimumDuration
            else {
                deleteOwnedArtifact(artifact.url)
                await presentCaptureFailure(
                    .partialRecordingTooShort,
                    token: activeSession.token,
                    soundCuesEnabled:
                        activeSession.soundCuesEnabled
                )
                return .terminal
            }

            let session = failedContext(
                for: artifact,
                activeSession: activeSession
            )
            failedSessionContext = session

            await soundCuePlayer.play(
                .attentionRequired,
                enabled: activeSession.soundCuesEnabled
            )
            try requireCurrent(activeSession.token)

            guard transition(
                to: .captureFailed(
                    RecoverableCaptureFailureState(
                        message:
                            "The microphone became unavailable. A partial recording can be transcribed or discarded.",
                        artifact: artifact
                    )
                ),
                token: activeSession.token
            ) else {
                throw CancellationError()
            }
            return .recoverablePartial(session)

        case .failed(let recorderError):
            await presentCaptureFailure(
                map(recorderError),
                token: activeSession.token,
                soundCuesEnabled:
                    activeSession.soundCuesEnabled
            )
            return .terminal
        }
    }

    private func waitForPartialTranscription(
        _ session: FailedSessionContext,
        events: AsyncStream<PipelineEvent>
    ) async throws -> FailedSessionContext {
        for await event in events {
            try requireCurrent(SessionToken(id: session.identifier))

            switch event {
            case .transcribePartial:
                return session
            case
                .elapsed,
                .stop,
                .unexpectedCapture,
                .retryTranscription,
                .applyTranscriptionRepair:
                continue
            }
        }
        throw CancellationError()
    }

    private func runTranscriptionLoop(
        _ initialSession: FailedSessionContext,
        events: AsyncStream<PipelineEvent>
    ) async throws {
        var session = initialSession
        let token = SessionToken(id: session.identifier)

        while true {
            try requireCurrent(token)

            do {
                try await transcribeAndDeliver(session, token: token)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch let failure as ProviderOperationFailure {
                let presentedFailure: ProviderOperationFailure =
                    failure == .cancelled
                    ? .operation(
                        message:
                            "The transcription request was interrupted."
                    )
                    : failure

                try await presentTranscriptionFailure(
                    presentedFailure,
                    session: session,
                    token: token
                )

                session = try await waitForTranscriptionRecovery(
                    session,
                    failure: presentedFailure,
                    events: events,
                    token: token
                )
            } catch {
                let failure = ProviderOperationFailure.operation(
                    message:
                        "The recording could not be transcribed."
                )
                try await presentTranscriptionFailure(
                    failure,
                    session: session,
                    token: token
                )
                session = try await waitForTranscriptionRecovery(
                    session,
                    failure: failure,
                    events: events,
                    token: token
                )
            }
        }
    }

    private func transcribeAndDeliver(
        _ session: FailedSessionContext,
        token: SessionToken
    ) async throws {
        guard transition(
            to: .transcribing(
                session.effectiveConfiguration
                    .transcriptionProvider
            ),
            token: token
        ) else {
            throw CancellationError()
        }

        guard let transcriptionProvider =
            providerResolver.transcriptionProvider(
                for: session.effectiveConfiguration.transcriptionProvider
            )
        else {
            throw ProviderOperationFailure.scopedConfiguration(
                kind: .unavailable,
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
        AppLog.providers.info("Transcription operation succeeded")
        try requireCurrent(token)

        deleteOwnedArtifact(session.artifact.url)
        failedSessionContext = nil

        let normalizedTranscript = transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        activeTextPayload?.rawTranscript = normalizedTranscript

        if normalizedTranscript.isEmpty {
            AppLog.session.info("Transcription produced no speech")
            guard transition(to: .noSpeech, token: token) else {
                throw CancellationError()
            }
            try await sleep(
                for: TerminalDisplayDuration.noSpeech,
                token: token
            )
            return
        }

        try await deliverTranscript(
            normalizedTranscript,
            configuration: session.effectiveConfiguration,
            token: token
        )
    }

    private func presentTranscriptionFailure(
        _ failure: ProviderOperationFailure,
        session: FailedSessionContext,
        token: SessionToken
    ) async throws {
        AppLog.providers.error(
            "Transcription stopped with classification \(failure.logClassification, privacy: .public)"
        )
        await soundCuePlayer.play(
            .attentionRequired,
            enabled: session.soundCuesEnabled
        )
        try requireCurrent(token)

        guard ownedArtifactURL == session.artifact.url else {
            throw CancellationError()
        }

        failedSessionContext = session
        if
            let kind = failure.configurationIssueKind
        {
            providerRuntimeHealth.markNeedsAttention(
                provider:
                    session.effectiveConfiguration.transcriptionProvider,
                capability: .transcription,
                model:
                    session.effectiveConfiguration.transcriptionModel,
                kind: kind,
                message:
                    failure.errorDescription
                    ?? "Transcription configuration needs attention."
            )
        }
        guard transition(
            to: .transcriptionFailed(
                TranscriptionFailureState(
                    message:
                        failure.errorDescription
                        ?? "The recording could not be transcribed.",
                    isConfigurationFailure:
                        failure.isConfigurationFailure,
                    configurationIssueKind:
                        failure.configurationIssueKind
                )
            ),
            token: token
        ) else {
            throw CancellationError()
        }
    }

    private func waitForTranscriptionRecovery(
        _ initialSession: FailedSessionContext,
        failure: ProviderOperationFailure,
        events: AsyncStream<PipelineEvent>,
        token: SessionToken
    ) async throws -> FailedSessionContext {
        var session = initialSession

        for await event in events {
            try requireCurrent(token)

            switch event {
            case .applyTranscriptionRepair(let repair):
                guard failure.isConfigurationFailure else {
                    continue
                }
                session.apply(repair)
                failedSessionContext = session
                _ = transition(
                    to: .transcriptionFailed(
                        TranscriptionFailureState(
                            message:
                                "Transcription configuration repaired. Retry the retained recording.",
                            isConfigurationFailure: true
                        )
                    ),
                    token: token
                )
            case .retryTranscription:
                return session
            case
                .elapsed,
                .stop,
                .unexpectedCapture,
                .transcribePartial:
                continue
            }
        }

        throw CancellationError()
    }

    private func deliverTranscript(
        _ rawTranscript: String,
        configuration: SessionConfiguration,
        token: SessionToken
    ) async throws {
        try requireCurrent(token)

        guard configuration.postProcessingMode == .enabled else {
            try await insertTranscript(
                rawTranscript,
                rawFallbackMessage: nil,
                token: token
            )
            return
        }

        let postProcessingConfiguration =
            PostProcessingConfiguration(
                sessionConfiguration: configuration
            )

        if providerRuntimeHealth.shouldSkip(
            postProcessingConfiguration
        ) {
            AppLog.providers.notice(
                "Post-processing skipped because configuration needs attention"
            )
            try await insertTranscript(
                rawTranscript,
                rawFallbackMessage:
                    "Cleanup needs attention.",
                token: token
            )
            return
        }

        guard let postProcessingProvider =
            providerResolver.postProcessingProvider(
                for: configuration.postProcessingProvider
            )
        else {
            let message =
                "The configured post-processing provider is unavailable."
            providerRuntimeHealth.markNeedsAttention(
                postProcessingConfiguration,
                kind: .unavailable,
                message: message
            )
            try await insertTranscript(
                rawTranscript,
                rawFallbackMessage:
                    "Cleanup was unavailable.",
                token: token
            )
            return
        }

        guard transition(
            to: .postProcessing(
                configuration.postProcessingProvider
            ),
            token: token
        ) else {
            throw CancellationError()
        }
        AppLog.providers.info("Post-processing operation started")

        do {
            let output = try await postProcessingProvider.process(
                PostProcessingRequest(
                    rawTranscript: rawTranscript,
                    model: configuration.postProcessingModel
                )
            )
            AppLog.providers.info(
                "Post-processing operation succeeded"
            )
            try requireCurrent(token)

            let validatedOutput =
                try PostProcessingOutputPolicy.validatedOutput(
                    output,
                    rawTranscript: rawTranscript
                )
            activeTextPayload?.finalTranscript = validatedOutput

            try await insertTranscript(
                validatedOutput,
                rawFallbackMessage: nil,
                token: token
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ProviderOperationFailure {
            AppLog.providers.error(
                "Post-processing stopped with classification \(failure.logClassification, privacy: .public)"
            )
            try requireCurrent(token)

            if failure.isConfigurationFailure {
                providerRuntimeHealth.markNeedsAttention(
                    postProcessingConfiguration,
                    kind: failure.configurationIssueKind ?? .unknown,
                    message:
                        failure.errorDescription
                        ?? "Post-processing configuration needs attention."
                )
            }

            try await insertTranscript(
                rawTranscript,
                rawFallbackMessage:
                    "Cleanup was unavailable.",
                token: token
            )
        } catch {
            AppLog.providers.error(
                "Post-processing stopped with unclassified failure"
            )
            try requireCurrent(token)
            try await insertTranscript(
                rawTranscript,
                rawFallbackMessage:
                    "Cleanup was unavailable.",
                token: token
            )
        }
    }

    private func insertTranscript(
        _ transcript: String,
        rawFallbackMessage: String?,
        token: SessionToken
    ) async throws {
        try requireCurrent(token)
        activeTextPayload?.finalTranscript = transcript

        guard transition(to: .inserting, token: token) else {
            throw CancellationError()
        }

        let transaction = clipboardService.beginTransaction(
            replacingContentsWith: transcript
        )
        activeClipboardTransaction = transaction

        await Task.yield()
        try requireCurrent(token)
        guard activeClipboardTransaction != nil else {
            throw CancellationError()
        }

        let outcome = await textInsertionService.insert(
            transcript,
            using: transaction
        )
        AppLog.insertion.info(
            "Insertion completed with outcome \(outcome.logClassification, privacy: .public)"
        )
        try requireCurrent(token)
        activeClipboardTransaction = nil

        switch outcome {
        case .confirmed:
            _ = transaction.restoreIfOwned()

            if let rawFallbackMessage {
                guard transition(
                    to: .rawTranscriptFallback(
                        rawFallbackMessage
                            + " The raw transcript was inserted."
                    ),
                    token: token
                ) else {
                    throw CancellationError()
                }
                try await sleep(
                    for: TerminalDisplayDuration.rawFallback,
                    token: token
                )
            } else {
                guard transition(to: .inserted, token: token)
                else {
                    throw CancellationError()
                }
                try await sleep(
                    for: TerminalDisplayDuration.success,
                    token: token
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
            guard transition(
                to: .insertionUnverified(message),
                token: token
            ) else {
                throw CancellationError()
            }
            try await sleep(
                for: TerminalDisplayDuration.clipboardFallback,
                token: token
            )

        case .failed:
            let message = deliveryFallbackMessage(
                outcome: .failed,
                rawFallbackMessage: rawFallbackMessage,
                transcriptRemainsOnClipboard:
                    transaction.isStillOwned
            )
            transaction.abandon()
            guard transition(
                to: .clipboardFallback(message),
                token: token
            ) else {
                throw CancellationError()
            }
            try await sleep(
                for: TerminalDisplayDuration.clipboardFallback,
                token: token
            )
        }
    }

    private func presentCaptureFailure(
        _ error: DictationCaptureError,
        token: SessionToken,
        soundCuesEnabled: Bool
    ) async {
        AppLog.capture.error(
            "Capture failed with classification \(error.logClassification, privacy: .public)"
        )
        await soundCuePlayer.play(
            .attentionRequired,
            enabled: soundCuesEnabled
        )

        guard isCurrent(token) else {
            return
        }

        guard transition(to: .failed(error), token: token)
        else {
            return
        }
        try? await sleep(for: 3, token: token)
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

    private func transition(
        to newState: DictationSessionState,
        token: SessionToken
    ) -> Bool {
        let currentKind = state.kind
        let nextKind = newState.kind
        guard
            isCurrent(token),
            isLegalTransition(
                from: currentKind,
                to: nextKind
            )
        else {
            AppLog.session.error(
                "Rejected stale or illegal session transition"
            )
            return false
        }

        state = newState
        if currentKind != nextKind {
            AppLog.session.info(
                "Session transition \(currentKind.logName, privacy: .public) -> \(nextKind.logName, privacy: .public)"
            )
        }
        return true
    }

    private func isLegalTransition(
        from current: SessionStateKind,
        to next: SessionStateKind
    ) -> Bool {
        if next == .idle {
            return true
        }

        return switch (current, next) {
        case
            (.idle, .preparing),
            (.preparing, .recording),
            (.preparing, .failed),
            (.recording, .recording),
            (.recording, .finalizing),
            (.finalizing, .tooShort),
            (.finalizing, .captureFailed),
            (.finalizing, .transcribing),
            (.finalizing, .failed),
            (.captureFailed, .transcribing),
            (.transcribing, .transcribing),
            (.transcribing, .transcriptionFailed),
            (.transcribing, .postProcessing),
            (.transcribing, .inserting),
            (.transcribing, .noSpeech),
            (.transcriptionFailed, .transcriptionFailed),
            (.transcriptionFailed, .transcribing),
            (.postProcessing, .inserting),
            (.inserting, .inserted),
            (.inserting, .insertionUnverified),
            (.inserting, .clipboardFallback),
            (.inserting, .rawTranscriptFallback):
            true
        default:
            false
        }
    }

    private func submit(
        _ event: PipelineEvent,
        sessionIdentifier: UUID? = nil
    ) {
        guard
            let currentToken,
            sessionIdentifier == nil
                || sessionIdentifier == currentToken.id
        else {
            deletePartialArtifact(in: event)
            return
        }

        guard let pipelineEvents else {
            deletePartialArtifact(in: event)
            return
        }

        switch pipelineEvents.yield(event) {
        case .enqueued:
            break
        case .dropped(let droppedEvent):
            deletePartialArtifact(in: droppedEvent)
        case .terminated:
            deletePartialArtifact(in: event)
        @unknown default:
            deletePartialArtifact(in: event)
        }
    }

    private func deletePartialArtifact(in event: PipelineEvent) {
        guard
            case .unexpectedCapture(let outcome) = event,
            case .partial(let artifact) = outcome
        else {
            return
        }
        fileStore.delete(artifact.url)
    }

    private func requireCurrent(_ token: SessionToken) throws {
        try Task.checkCancellation()
        guard isCurrent(token) else {
            throw CancellationError()
        }
    }

    private func isCurrent(_ token: SessionToken) -> Bool {
        currentToken == token
    }

    private func completeCurrentSession(token: SessionToken) {
        guard isCurrent(token) else {
            return
        }

        _ = transition(to: .idle, token: token)
        pipelineEvents?.finish()
        pipelineEvents = nil
        currentToken = nil
        pipelineTask = nil
        sessionSoundCuesEnabled = true
        failedSessionContext = nil
        activeClipboardTransaction?.abandon()
        activeClipboardTransaction = nil
        activeTextPayload?.clear()
        activeTextPayload = nil

        if let ownedArtifactURL {
            fileStore.delete(ownedArtifactURL)
        }
        ownedArtifactURL = nil
        AppLog.session.info("Session resources released")
    }

    private func completeCurrentSessionWithoutCue() {
        guard currentToken != nil else {
            return
        }

        currentToken = nil
        pipelineEvents?.finish()
        pipelineEvents = nil
        pipelineTask?.cancel()
        pipelineTask = nil
        sessionSoundCuesEnabled = true
        failedSessionContext = nil
        activeClipboardTransaction?.abandon()
        activeClipboardTransaction = nil
        activeTextPayload?.clear()
        activeTextPayload = nil

        if let ownedArtifactURL {
            fileStore.delete(ownedArtifactURL)
        }
        ownedArtifactURL = nil
        state = .idle
        AppLog.session.info(
            "Delivery status dismissed and session resources released"
        )
    }

    private func cancelCurrentSession(
        playCue: Bool,
        isTerminating: Bool = false
    ) {
        guard
            let token = currentToken,
            state != .idle
        else {
            return
        }

        let cuesEnabled = sessionSoundCuesEnabled
        pendingCancellationCue =
            playCue && cuesEnabled
            ? (token.id, true)
            : nil

        // Invalidate ownership before cancelling work so no suspended callback
        // can publish or perform a late side effect.
        currentToken = nil
        pipelineEvents?.finish()
        pipelineEvents = nil
        pipelineTask?.cancel()
        pipelineTask = nil

        activeTextPayload?.clear()
        activeTextPayload = nil
        failedSessionContext = nil
        let restoredClipboard =
            activeClipboardTransaction?.cancelAndRestoreIfOwned()
            ?? false
        activeClipboardTransaction = nil

        if isTerminating {
            recorder.shutdownImmediately(
                sessionIdentifier: token.id
            )
        } else {
            recorder.cancelImmediately(
                sessionIdentifier: token.id
            )
        }
        if let ownedArtifactURL {
            fileStore.delete(ownedArtifactURL)
        }
        ownedArtifactURL = nil
        sessionSoundCuesEnabled = true
        state = .idle
        AppLog.session.notice(
            "Session cancelled; clipboard restoration owned=\(restoredClipboard, privacy: .public)"
        )

    }

    private func playCancellationCueAfterTeardown(
        sessionIdentifier: UUID
    ) {
        guard
            let pendingCancellationCue,
            pendingCancellationCue.sessionIdentifier == sessionIdentifier
        else {
            return
        }
        self.pendingCancellationCue = nil
        guard currentToken == nil else {
            return
        }
        soundCuePlayer.enqueue(
            .sessionCancelled,
            enabled: pendingCancellationCue.enabled
        )
    }

    private func resetSessionWithoutCue() {
        currentToken = nil
        pipelineEvents?.finish()
        pipelineEvents = nil
        pipelineTask?.cancel()
        pipelineTask = nil
        sessionSoundCuesEnabled = true
        failedSessionContext = nil
        activeClipboardTransaction?.abandon()
        activeClipboardTransaction = nil
        activeTextPayload?.clear()
        activeTextPayload = nil
        ownedArtifactURL = nil
        state = .idle
    }

    private func sleep(
        for delay: TimeInterval,
        token: SessionToken
    ) async throws {
        try await Task.sleep(for: .seconds(delay))
        try requireCurrent(token)
    }

    private func recordingState(
        for activeSession: ActiveSession,
        elapsed: TimeInterval = 0
    ) -> DictationSessionState {
        let profile = activeSession.configuration.recordingProfile
        return .recording(
            RecordingSessionState(
                configuration: activeSession.configuration,
                inputDeviceName: activeSession.inputDeviceName,
                elapsed: elapsed,
                isNearDurationLimit:
                    elapsed >= profile.warningDuration
            )
        )
    }

    private func failedContext(
        for artifact: AudioArtifact,
        activeSession: ActiveSession
    ) -> FailedSessionContext {
        FailedSessionContext(
            identifier: activeSession.token.id,
            originalConfiguration:
                activeSession.configuration,
            artifact: artifact,
            soundCuesEnabled:
                activeSession.soundCuesEnabled,
            transcriptionRepair: nil
        )
    }

    private func deleteOwnedArtifact(_ url: URL) {
        fileStore.delete(url)
        if ownedArtifactURL == url {
            ownedArtifactURL = nil
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

    private func map(_ error: any Error) -> DictationCaptureError {
        if let captureError = error as? DictationCaptureError {
            return captureError
        }

        guard let recorderError = error as? AudioRecorderError else {
            return .cannotConfigureCapture
        }

        return map(recorderError)
    }

    private func map(
        _ recorderError: AudioRecorderError
    ) -> DictationCaptureError {
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

    private nonisolated static func timeInterval(
        _ duration: Duration
    ) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds)
                / 1_000_000_000_000_000_000
    }
}

private struct SessionToken: Equatable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

private enum PipelineEvent: Sendable {
    case elapsed(TimeInterval)
    case stop(RecordingFinalizationReason)
    case unexpectedCapture(UnexpectedCaptureOutcome)
    case retryTranscription
    case transcribePartial
    case applyTranscriptionRepair(TranscriptionRepair)
}

private enum CapturedSessionResult {
    case ready(FailedSessionContext)
    case recoverablePartial(FailedSessionContext)
    case terminal
}

private final class SessionTextPayload {
    var rawTranscript: String?
    var finalTranscript: String?

    func clear() {
        rawTranscript = nil
        finalTranscript = nil
    }
}

private struct ActiveSession {
    let token: SessionToken
    let configuration: SessionConfiguration
    let inputDeviceName: String
    let startedAt: ContinuousClock.Instant
    let soundCuesEnabled: Bool
}

private enum SessionStateKind: Equatable {
    case idle
    case preparing
    case recording
    case finalizing
    case completed
    case transcribing
    case postProcessing
    case inserting
    case inserted
    case insertionUnverified
    case clipboardFallback
    case rawTranscriptFallback
    case noSpeech
    case transcriptionFailed
    case captureFailed
    case tooShort
    case cancelled
    case failed
}

private extension DictationSessionState {
    var kind: SessionStateKind {
        switch self {
        case .idle:
            .idle
        case .preparing:
            .preparing
        case .recording:
            .recording
        case .finalizing:
            .finalizing
        case .completed:
            .completed
        case .transcribing:
            .transcribing
        case .postProcessing:
            .postProcessing
        case .inserting:
            .inserting
        case .inserted:
            .inserted
        case .insertionUnverified:
            .insertionUnverified
        case .clipboardFallback:
            .clipboardFallback
        case .rawTranscriptFallback:
            .rawTranscriptFallback
        case .noSpeech:
            .noSpeech
        case .transcriptionFailed:
            .transcriptionFailed
        case .captureFailed:
            .captureFailed
        case .tooShort:
            .tooShort
        case .cancelled:
            .cancelled
        case .failed:
            .failed
        }
    }
}

private extension SessionStateKind {
    var logName: String {
        switch self {
        case .idle: "idle"
        case .preparing: "preparing"
        case .recording: "recording"
        case .finalizing: "finalizing"
        case .completed: "completed"
        case .transcribing: "transcribing"
        case .postProcessing: "post_processing"
        case .inserting: "inserting"
        case .inserted: "inserted"
        case .insertionUnverified: "insertion_unverified"
        case .clipboardFallback: "clipboard_fallback"
        case .rawTranscriptFallback: "raw_fallback"
        case .noSpeech: "no_speech"
        case .transcriptionFailed: "transcription_failed"
        case .captureFailed: "capture_failed"
        case .tooShort: "too_short"
        case .cancelled: "cancelled"
        case .failed: "failed"
        }
    }
}

private enum TerminalDisplayDuration {
    static let success: TimeInterval = 1.2
    static let noSpeech: TimeInterval = 2
    static let rawFallback: TimeInterval = 2.5
    static let clipboardFallback: TimeInterval = 6
}
