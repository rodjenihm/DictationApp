@preconcurrency import AVFoundation
@preconcurrency import AudioToolbox
import Foundation
import OSLog

@MainActor
final class CoreAudioRecorder: AudioRecorder {
    var onUnexpectedCaptureFailure:
        ((UUID, UnexpectedCaptureOutcome) -> Void)?
    var onCancellationTeardownCompleted:
        ((UUID) -> Void)?

    private let fileStore: RecordingFileStore
    private let audioInputDeviceService:
        CoreAudioInputDeviceService
    private let runtime = AudioUnitRuntime()

    private var context: CoreAudioCaptureContext?
    private var startContinuation:
        CheckedContinuation<ContinuousClock.Instant, any Error>?
    private var startTimeoutTask: Task<Void, Never>?
    private var preparingSessionIdentifiers: Set<UUID> = []
    private var cancelledSessionIdentifiers: Set<UUID> = []
    private var isExpectedFinish = false
    private var hasAcceptedAudio = false
    private var engineStartBeganAt: ContinuousClock.Instant?
    private var terminationContext: CoreAudioCaptureContext?

    init(
        fileStore: RecordingFileStore,
        audioInputDeviceService: CoreAudioInputDeviceService
    ) {
        self.fileStore = fileStore
        self.audioInputDeviceService = audioInputDeviceService
    }

    func prepare(
        profile: RecordingProfile,
        audioInputPreference: AudioInputPreference,
        sessionIdentifier: UUID,
        includeLiveAudio: Bool
    ) async throws -> PreparedRecording {
        let preparationBeganAt = ContinuousClock.now
        AppLog.capture.info("Streaming capture preparation started")
        guard context == nil else {
            AppLog.capture.error(
                "Streaming capture preparation rejected because a context exists"
            )
            throw AudioRecorderError.cannotConfigure
        }
        guard
            !preparingSessionIdentifiers.contains(sessionIdentifier),
            !cancelledSessionIdentifiers.contains(sessionIdentifier)
        else {
            throw CancellationError()
        }

        preparingSessionIdentifiers.insert(sessionIdentifier)
        defer {
            preparingSessionIdentifiers.remove(sessionIdentifier)
        }

        let discoveryBeganAt = ContinuousClock.now
        let candidates = audioInputDeviceService.captureCandidates(
            for: audioInputPreference
        )
        AppLog.recordLatency(
            "capture_input_discovery",
            since: discoveryBeganAt,
            sessionID: sessionIdentifier
        )
        guard !candidates.isEmpty else {
            throw AudioRecorderError.noInputDevice
        }

        let outputSetupBeganAt = ContinuousClock.now
        let outputURL: URL
        do {
            outputURL = try fileStore.makeRecordingURL(
                fileExtension: profile.fileExtension
            )
        } catch {
            throw AudioRecorderError.cannotConfigure
        }
        AppLog.recordLatency(
            "capture_output_setup",
            since: outputSetupBeganAt,
            sessionID: sessionIdentifier
        )

        do {
            var preparedContext: CoreAudioCaptureContext?
            var lastError: (any Error)?

            for candidate in candidates {
                try Task.checkCancellation()
                do {
                    preparedContext = try await configureCapture(
                        profile: profile,
                        outputURL: outputURL,
                        candidate: candidate,
                        sessionIdentifier: sessionIdentifier,
                        includeLiveAudio: includeLiveAudio
                    )
                    break
                } catch {
                    lastError = error
                    fileStore.delete(outputURL)
                    if !candidate.isFallback,
                        candidates.contains(where: \.isFallback)
                    {
                        AppLog.capture.notice(
                            "Preferred audio input preparation failed; trying system default"
                        )
                    }
                }
            }

            guard let preparedContext else {
                throw lastError ?? AudioRecorderError.cannotConfigure
            }

            guard
                cancelledSessionIdentifiers.remove(
                    sessionIdentifier
                ) == nil
            else {
                await tearDownCapture(preparedContext)
                fileStore.delete(outputURL)
                onCancellationTeardownCompleted?(sessionIdentifier)
                throw CancellationError()
            }

            guard context == nil else {
                await tearDownCapture(preparedContext)
                fileStore.delete(outputURL)
                throw AudioRecorderError.cannotConfigure
            }

            context = preparedContext
            let observersBeganAt = ContinuousClock.now
            installFailureObservers(for: preparedContext)
            AppLog.recordLatency(
                "capture_observer_installation",
                since: observersBeganAt,
                sessionID: sessionIdentifier
            )
            AppLog.recordLatency(
                "capture_preparation",
                since: preparationBeganAt,
                sessionID: sessionIdentifier
            )
            return PreparedRecording(
                inputDeviceName: preparedContext.inputDeviceName,
                isUsingFallback: preparedContext.isUsingFallback,
                liveAudio: preparedContext.liveAudio
            )
        } catch {
            let wasCancelled =
                cancelledSessionIdentifiers.remove(sessionIdentifier)
                != nil
            fileStore.delete(outputURL)
            if wasCancelled {
                onCancellationTeardownCompleted?(sessionIdentifier)
            }
            AppLog.capture.error("Streaming capture preparation failed")
            throw error
        }
    }

    func startPreparedRecording() async throws -> ContinuousClock.Instant {
        guard let context else {
            throw AudioRecorderError.cannotStart
        }

        engineStartBeganAt = ContinuousClock.now
        startTimeoutTask?.cancel()
        startTimeoutTask = Task {
            @concurrent [weak self, sessionIdentifier =
                context.sessionIdentifier] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await self?.handleAudioUnitStartFailure(
                sessionIdentifier: sessionIdentifier
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation

            runtime.queue.async { [weak self, context] in
                guard context.start() == noErr else {
                    Task { @MainActor [weak self] in
                        self?.handleAudioUnitStartFailure(
                            sessionIdentifier: context.sessionIdentifier
                        )
                    }
                    return
                }
            }
        }
    }

    func stopRecording() async throws -> AudioArtifact {
        guard let context, hasAcceptedAudio else {
            throw AudioRecorderError.cannotFinalize
        }

        isExpectedFinish = true
        let outputURL: URL
        do {
            outputURL = try await finishCapture(context)
        } catch {
            fileStore.delete(context.outputURL)
            clearContext(ifMatching: context)
            AppLog.capture.error("Streaming capture finalization failed")
            throw error
        }

        removeFailureObservers(from: context)
        clearContext(ifMatching: context)

        do {
            let validationBeganAt = ContinuousClock.now
            let artifact = try await validateArtifact(
                at: outputURL,
                context: context
            )
            AppLog.recordLatency(
                "capture_artifact_validation",
                since: validationBeganAt,
                sessionID: context.sessionIdentifier
            )
            return artifact
        } catch {
            fileStore.delete(outputURL)
            AppLog.capture.error("Streaming capture validation failed")
            throw error
        }
    }

    func cancelRecording(sessionIdentifier: UUID) async {
        guard
            let context,
            context.sessionIdentifier == sessionIdentifier
        else {
            return
        }

        context.liveAudio?.abort()
        startContinuation?.resume(throwing: CancellationError())
        startContinuation = nil
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        removeFailureObservers(from: context)
        clearContext(ifMatching: context)
        await tearDownCapture(context)
        fileStore.delete(context.outputURL)
    }

    func cancelImmediately(sessionIdentifier: UUID) {
        guard
            let context,
            context.sessionIdentifier == sessionIdentifier
        else {
            if preparingSessionIdentifiers.contains(sessionIdentifier) {
                cancelledSessionIdentifiers.insert(sessionIdentifier)
            } else {
                onCancellationTeardownCompleted?(sessionIdentifier)
            }
            return
        }

        context.liveAudio?.abort()
        self.context = nil
        removeFailureObservers(from: context)
        startContinuation?.resume(throwing: CancellationError())
        startContinuation = nil
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        hasAcceptedAudio = false
        isExpectedFinish = false
        engineStartBeganAt = nil

        runtime.queue.async { [weak self, context] in
            _ = context.stopAndDisposeWriter()
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                fileStore.delete(context.outputURL)
                cancelledSessionIdentifiers.remove(sessionIdentifier)
                onCancellationTeardownCompleted?(sessionIdentifier)
                AppLog.capture.notice(
                    "Streaming capture cancellation teardown completed"
                )
            }
        }
        AppLog.capture.notice(
            "Streaming capture cancellation teardown scheduled"
        )
    }

    func shutdownImmediately(sessionIdentifier: UUID) {
        guard
            let context,
            context.sessionIdentifier == sessionIdentifier
        else {
            if preparingSessionIdentifiers.contains(sessionIdentifier) {
                cancelledSessionIdentifiers.insert(sessionIdentifier)
            }
            return
        }

        context.liveAudio?.abort()
        self.context = nil
        removeFailureObservers(from: context)
        startContinuation?.resume(throwing: CancellationError())
        startContinuation = nil
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        hasAcceptedAudio = false
        isExpectedFinish = false
        engineStartBeganAt = nil
        terminationContext = context
        fileStore.delete(context.outputURL)
        AppLog.capture.notice(
            "Streaming capture resources released to process termination"
        )
    }

    private func configureCapture(
        profile: RecordingProfile,
        outputURL: URL,
        candidate: AudioInputCaptureCandidate,
        sessionIdentifier: UUID,
        includeLiveAudio: Bool
    ) async throws -> CoreAudioCaptureContext {
        let onFirstBuffer: @Sendable (UUID, ContinuousClock.Instant) -> Void = {
            [weak self] identifier, acceptedAt in
            Task { @MainActor [weak self] in
                self?.handleFirstAcceptedBuffer(
                    sessionIdentifier: identifier,
                    acceptedAt: acceptedAt
                )
            }
        }
        let onWriteFailure: @Sendable (UUID) -> Void = {
            [weak self] identifier in
            Task { @MainActor [weak self] in
                self?.handleWriterFailure(
                    sessionIdentifier: identifier
                )
            }
        }

        let (preparedContext, configuredAt):
            (CoreAudioCaptureContext, ContinuousClock.Instant) =
            try await withCheckedThrowingContinuation { continuation in
                let queuedAt = ContinuousClock.now
                runtime.queue.async {
                    [runtime, onFirstBuffer, onWriteFailure] in
                    AppLog.recordLatency(
                        "capture_configuration_queue_wait",
                        since: queuedAt,
                        sessionID: sessionIdentifier
                    )
                    do {
                        let context = try CoreAudioCaptureContext.make(
                            runtime: runtime,
                            deviceID: candidate.deviceID,
                            outputURL: outputURL,
                            inputDeviceName: candidate.name,
                            isUsingFallback: candidate.isFallback,
                            profile: profile,
                            sessionIdentifier: sessionIdentifier,
                            includeLiveAudio: includeLiveAudio,
                            onFirstBuffer: onFirstBuffer,
                            onWriteFailure: onWriteFailure
                        )
                        continuation.resume(returning: (context, .now))
                    } catch let error as AudioRecorderError {
                        continuation.resume(throwing: error)
                    } catch {
                        continuation.resume(
                            throwing: AudioRecorderError.cannotConfigure
                        )
                    }
                }
            }
        AppLog.recordLatency(
            "capture_configuration_resume",
            since: configuredAt,
            sessionID: sessionIdentifier
        )
        return preparedContext
    }

    private func handleFirstAcceptedBuffer(
        sessionIdentifier: UUID,
        acceptedAt: ContinuousClock.Instant
    ) {
        guard
            let context,
            context.sessionIdentifier == sessionIdentifier,
            let continuation = startContinuation
        else {
            return
        }

        startContinuation = nil
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        hasAcceptedAudio = true
        if let engineStartBeganAt {
            AppLog.recordLatency(
                "audio_unit_start_to_first_audio",
                since: engineStartBeganAt,
                sessionID: sessionIdentifier,
                until: acceptedAt
            )
        }
        self.engineStartBeganAt = nil
        continuation.resume(returning: acceptedAt)
    }

    private func handleAudioUnitStartFailure(
        sessionIdentifier: UUID
    ) {
        guard
            context?.sessionIdentifier == sessionIdentifier,
            let continuation = startContinuation
        else {
            return
        }

        startContinuation = nil
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        engineStartBeganAt = nil
        continuation.resume(
            throwing: AudioRecorderError.cannotStart
        )
    }

    private func handleWriterFailure(
        sessionIdentifier: UUID
    ) {
        guard
            let context,
            context.sessionIdentifier == sessionIdentifier,
            !context.isHandlingUnexpectedFailure,
            !isExpectedFinish
        else {
            return
        }

        if !hasAcceptedAudio {
            handleAudioUnitStartFailure(
                sessionIdentifier: sessionIdentifier
            )
            return
        }

        handleUnexpectedCaptureSignal(for: context)
    }

    private func installFailureObservers(
        for context: CoreAudioCaptureContext
    ) {
        context.deviceAvailabilityObservation =
            CoreAudioPropertyObservation(
                objectID: context.deviceID,
                addresses: [CoreAudioHardware.deviceAliveAddress]
            ) { [weak self, weak context] in
                guard
                    let context,
                    !CoreAudioHardware.isAlive(context.deviceID)
                else {
                    return
                }
                self?.handleUnexpectedCaptureSignal(for: context)
            }
    }

    private func removeFailureObservers(
        from context: CoreAudioCaptureContext
    ) {
        context.deviceAvailabilityObservation = nil
    }

    private func handleUnexpectedCaptureSignal(
        for candidate: CoreAudioCaptureContext
    ) {
        guard
            context === candidate,
            !candidate.isHandlingUnexpectedFailure,
            !isExpectedFinish
        else {
            return
        }

        if !hasAcceptedAudio {
            handleAudioUnitStartFailure(
                sessionIdentifier: candidate.sessionIdentifier
            )
            return
        }

        candidate.isHandlingUnexpectedFailure = true
        candidate.liveAudio?.abort()
        AppLog.capture.error(
            "Streaming capture received an unexpected termination signal"
        )

        Task { [weak self] in
            await self?.reportUnexpectedCaptureOutcome(candidate)
        }
    }

    private func reportUnexpectedCaptureOutcome(
        _ context: CoreAudioCaptureContext
    ) async {
        do {
            let outputURL = try await finishCapture(context)
            removeFailureObservers(from: context)
            clearContext(ifMatching: context)
            let artifact = try await validateArtifact(
                at: outputURL,
                context: context
            )
            onUnexpectedCaptureFailure?(
                context.sessionIdentifier,
                .partial(artifact)
            )
        } catch {
            removeFailureObservers(from: context)
            clearContext(ifMatching: context)
            fileStore.delete(context.outputURL)
            onUnexpectedCaptureFailure?(
                context.sessionIdentifier,
                .failed(.cannotFinalize)
            )
        }
    }

    private func finishCapture(
        _ context: CoreAudioCaptureContext
    ) async throws -> URL {
        let finalizationBeganAt = ContinuousClock.now
        let result = await withCheckedContinuation { continuation in
            runtime.queue.async { [context] in
                continuation.resume(
                    returning: context.stopAndDisposeWriter()
                )
            }
        }

        if let audioStoppedAt = result.audioStoppedAt {
            AppLog.recordLatency(
                "capture_finalization_to_microphone_stop",
                since: finalizationBeganAt,
                sessionID: context.sessionIdentifier,
                until: audioStoppedAt
            )
        }
        AppLog.recordLatency(
            "m4a_writer_close",
            since: result.writerClosingAt,
            sessionID: context.sessionIdentifier,
            until: result.writerClosedAt
        )
        if !result.audioUnitTeardown.wasDisposed {
            AppLog.capture.error(
                "Audio input teardown could not safely dispose capture resources"
            )
        } else if result.audioUnitTeardown.failureCount > 0 {
            AppLog.capture.notice(
                "Audio input teardown completed with \(result.audioUnitTeardown.failureCount, privacy: .public) best-effort failure(s)"
            )
        }
        guard
            result.audioUnitTeardown.wasDisposed,
            result.writerFinalizationStatus == noErr
        else {
            throw AudioRecorderError.cannotFinalize
        }
        return context.outputURL
    }

    private func tearDownCapture(
        _ context: CoreAudioCaptureContext
    ) async {
        await withCheckedContinuation { continuation in
            runtime.queue.async { [context] in
                _ = context.stopAndDisposeWriter()
                continuation.resume()
            }
        }
    }

    private func clearContext(
        ifMatching candidate: CoreAudioCaptureContext
    ) {
        guard context === candidate else {
            return
        }
        context = nil
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        hasAcceptedAudio = false
        isExpectedFinish = false
        engineStartBeganAt = nil
    }

    private func validateArtifact(
        at url: URL,
        context: CoreAudioCaptureContext
    ) async throws -> AudioArtifact {
        let asset = AVURLAsset(url: url)

        do {
            let duration = try await asset.load(.duration).seconds
            let audioTracks = try await asset.loadTracks(
                withMediaType: .audio
            )
            guard
                duration.isFinite,
                duration > 0,
                !audioTracks.isEmpty,
                FileManager.default.isReadableFile(atPath: url.path)
            else {
                throw AudioRecorderError.invalidArtifact
            }

            let resourceValues = try url.resourceValues(
                forKeys: [.fileSizeKey]
            )
            guard let fileSize = resourceValues.fileSize, fileSize > 0 else {
                throw AudioRecorderError.invalidArtifact
            }

            return AudioArtifact(
                url: url,
                duration: duration,
                fileSize: Int64(fileSize),
                inputDeviceName: context.inputDeviceName
            )
        } catch let error as AudioRecorderError {
            throw error
        } catch {
            throw AudioRecorderError.invalidArtifact
        }
    }
}

// SAFETY: All AUHAL lifecycle operations are serialized on `queue`. A capture
// context stops its unit before releasing callback buffers or its writer.
nonisolated private final class AudioUnitRuntime: @unchecked Sendable {
    let queue = DispatchQueue(
        label: "com.danijelmitrovic.DictationApp.audio-unit",
        qos: .userInteractive
    )
}

nonisolated private func coreAudioInputCallback(
    _ reference: UnsafeMutableRawPointer,
    _ actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    _ timeStamp: UnsafePointer<AudioTimeStamp>,
    _ busNumber: UInt32,
    _ frameCount: UInt32,
    _ outputData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let context = Unmanaged<CoreAudioCaptureContext>
        .fromOpaque(reference)
        .takeUnretainedValue()
    return context.render(
        actionFlags: actionFlags,
        timeStamp: timeStamp,
        busNumber: busNumber,
        frameCount: frameCount
    )
}

// SAFETY: AUHAL start/stop/initialize/dispose and writer disposal are owned by
// AudioUnitRuntime.queue. While the unit is running, its real-time callback is
// the sole producer and exclusively mutates the buffer/reporting flags. Stop
// completes before the queue releases callback-owned state. MainActor owns
// only the device observation and unexpected-failure presentation flag.
nonisolated private final class CoreAudioCaptureContext:
    @unchecked Sendable
{
    let runtime: AudioUnitRuntime
    let deviceID: AudioObjectID
    let outputURL: URL
    let inputDeviceName: String
    let isUsingFallback: Bool
    let profile: RecordingProfile
    let sessionIdentifier: UUID
    let liveAudio: LiveRecordingAudio?
    let onFirstBuffer: @Sendable (UUID, ContinuousClock.Instant) -> Void
    let onWriteFailure: @Sendable (UUID) -> Void

    var deviceAvailabilityObservation:
        CoreAudioPropertyObservation?
    var isHandlingUnexpectedFailure = false

    private var audioUnit: AudioUnit?
    private let inputBuffer: AVAudioPCMBuffer
    private let writer: StreamingM4AWriter
    private var isInitialized = false
    private var isStarted = false
    private var didReportFirstBuffer = false
    private var didReportWriteFailure = false

    private init(
        runtime: AudioUnitRuntime,
        audioUnit: AudioUnit,
        inputBuffer: AVAudioPCMBuffer,
        deviceID: AudioObjectID,
        writer: StreamingM4AWriter,
        outputURL: URL,
        inputDeviceName: String,
        isUsingFallback: Bool,
        profile: RecordingProfile,
        sessionIdentifier: UUID,
        liveAudio: LiveRecordingAudio?,
        onFirstBuffer: @escaping @Sendable (UUID, ContinuousClock.Instant) -> Void,
        onWriteFailure: @escaping @Sendable (UUID) -> Void
    ) {
        self.runtime = runtime
        self.audioUnit = audioUnit
        self.inputBuffer = inputBuffer
        self.deviceID = deviceID
        self.writer = writer
        self.outputURL = outputURL
        self.inputDeviceName = inputDeviceName
        self.isUsingFallback = isUsingFallback
        self.profile = profile
        self.sessionIdentifier = sessionIdentifier
        self.liveAudio = liveAudio
        self.onFirstBuffer = onFirstBuffer
        self.onWriteFailure = onWriteFailure
    }

    static func make(
        runtime: AudioUnitRuntime,
        deviceID: AudioObjectID,
        outputURL: URL,
        inputDeviceName: String,
        isUsingFallback: Bool,
        profile: RecordingProfile,
        sessionIdentifier: UUID,
        includeLiveAudio: Bool,
        onFirstBuffer: @escaping @Sendable (UUID, ContinuousClock.Instant) -> Void,
        onWriteFailure: @escaping @Sendable (UUID) -> Void
    ) throws -> CoreAudioCaptureContext {
        let unitSetupBeganAt = ContinuousClock.now
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioRecorderError.cannotConfigure
        }

        var instance: AudioUnit?
        guard
            AudioComponentInstanceNew(component, &instance) == noErr,
            let audioUnit = instance
        else {
            throw AudioRecorderError.cannotConfigure
        }

        var context: CoreAudioCaptureContext?
        do {
            var enableInput: UInt32 = 1
            try requireNoError(
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_EnableIO,
                    kAudioUnitScope_Input,
                    1,
                    &enableInput,
                    UInt32(MemoryLayout<UInt32>.size)
                )
            )

            var disableOutput: UInt32 = 0
            try requireNoError(
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_EnableIO,
                    kAudioUnitScope_Output,
                    0,
                    &disableOutput,
                    UInt32(MemoryLayout<UInt32>.size)
                )
            )

            var selectedDeviceID = deviceID
            try requireNoError(
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &selectedDeviceID,
                    UInt32(MemoryLayout<AudioObjectID>.size)
                )
            )

            var deviceFormat = AudioStreamBasicDescription()
            var formatSize = UInt32(
                MemoryLayout<AudioStreamBasicDescription>.size
            )
            try requireNoError(
                AudioUnitGetProperty(
                    audioUnit,
                    kAudioUnitProperty_StreamFormat,
                    kAudioUnitScope_Input,
                    1,
                    &deviceFormat,
                    &formatSize
                )
            )
            guard
                deviceFormat.mSampleRate > 0,
                deviceFormat.mChannelsPerFrame > 0,
                profile.channelCount > 0
            else {
                throw AudioRecorderError.cannotConfigure
            }

            let channelCount = AVAudioChannelCount(
                min(
                    UInt32(profile.channelCount),
                    deviceFormat.mChannelsPerFrame
                )
            )
            guard
                let inputFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: deviceFormat.mSampleRate,
                    channels: channelCount,
                    interleaved: false
                )
            else {
                throw AudioRecorderError.cannotConfigure
            }

            var clientFormat = inputFormat.streamDescription.pointee
            try requireNoError(
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioUnitProperty_StreamFormat,
                    kAudioUnitScope_Output,
                    1,
                    &clientFormat,
                    UInt32(
                        MemoryLayout<AudioStreamBasicDescription>.size
                    )
                )
            )

            var maximumFrames: UInt32 = 0
            var maximumFramesSize = UInt32(
                MemoryLayout<UInt32>.size
            )
            try requireNoError(
                AudioUnitGetProperty(
                    audioUnit,
                    kAudioUnitProperty_MaximumFramesPerSlice,
                    kAudioUnitScope_Global,
                    0,
                    &maximumFrames,
                    &maximumFramesSize
                )
            )
            guard
                maximumFrames > 0,
                let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: inputFormat,
                    frameCapacity: maximumFrames
                )
            else {
                throw AudioRecorderError.cannotConfigure
            }

            AppLog.recordLatency(
                "capture_audio_unit_setup",
                since: unitSetupBeganAt,
                sessionID: sessionIdentifier
            )
            let writerSetupBeganAt = ContinuousClock.now
            let writer = try StreamingM4AWriter(
                url: outputURL,
                inputFormat: inputFormat,
                profile: profile
            )
            AppLog.recordLatency(
                "capture_writer_setup",
                since: writerSetupBeganAt,
                sessionID: sessionIdentifier
            )
            let preparedContext = CoreAudioCaptureContext(
                runtime: runtime,
                audioUnit: audioUnit,
                inputBuffer: inputBuffer,
                deviceID: deviceID,
                writer: writer,
                outputURL: outputURL,
                inputDeviceName: inputDeviceName,
                isUsingFallback: isUsingFallback,
                profile: profile,
                sessionIdentifier: sessionIdentifier,
                liveAudio: includeLiveAudio
                    ? LiveRecordingAudio(format: inputFormat) : nil,
                onFirstBuffer: onFirstBuffer,
                onWriteFailure: onWriteFailure
            )
            context = preparedContext

            var callback = AURenderCallbackStruct(
                inputProc: coreAudioInputCallback,
                inputProcRefCon: Unmanaged
                    .passUnretained(preparedContext)
                    .toOpaque()
            )
            try requireNoError(
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_SetInputCallback,
                    kAudioUnitScope_Global,
                    0,
                    &callback,
                    UInt32(MemoryLayout<AURenderCallbackStruct>.size)
                )
            )
            let initializationBeganAt = ContinuousClock.now
            try requireNoError(AudioUnitInitialize(audioUnit))
            AppLog.recordLatency(
                "capture_audio_unit_initialize",
                since: initializationBeganAt,
                sessionID: sessionIdentifier
            )
            preparedContext.isInitialized = true
            return preparedContext
        } catch {
            if let context {
                _ = context.stopAndDisposeWriter()
            } else {
                _ = AudioComponentInstanceDispose(audioUnit)
            }
            throw error
        }
    }

    func start() -> OSStatus {
        guard let audioUnit, isInitialized, !isStarted else {
            return kAudioUnitErr_Uninitialized
        }
        let status = AudioOutputUnitStart(audioUnit)
        if status == noErr {
            isStarted = true
        }
        return status
    }

    func render(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        busNumber: UInt32,
        frameCount: UInt32
    ) -> OSStatus {
        guard
            let audioUnit,
            frameCount > 0,
            frameCount <= inputBuffer.frameCapacity
        else {
            reportWriteFailureOnce()
            return kAudio_ParamError
        }

        inputBuffer.frameLength = frameCount
        let renderStatus = AudioUnitRender(
            audioUnit,
            actionFlags,
            timeStamp,
            busNumber,
            frameCount,
            inputBuffer.mutableAudioBufferList
        )
        guard renderStatus == noErr else {
            reportWriteFailureOnce()
            return renderStatus
        }

        let writeStatus = writer.write(inputBuffer)
        guard writeStatus == noErr else {
            reportWriteFailureOnce()
            return writeStatus
        }

        let firstAcceptedAt: ContinuousClock.Instant? =
            didReportFirstBuffer ? nil : .now
        liveAudio?.append(inputBuffer)
        if let firstAcceptedAt {
            didReportFirstBuffer = true
            onFirstBuffer(sessionIdentifier, firstAcceptedAt)
        }
        return noErr
    }

    func stopAndDisposeWriter() -> CaptureFinalizationResult {
        var teardownFailureCount = 0
        func recordTeardown(_ status: OSStatus) {
            if status != noErr {
                teardownFailureCount += 1
            }
        }

        var wasDisposed = true
        var audioStoppedAt: ContinuousClock.Instant?
        if let audioUnit {
            if isStarted {
                let status = AudioOutputUnitStop(audioUnit)
                if status == noErr {
                    audioStoppedAt = .now
                }
                recordTeardown(status)
                isStarted = false
            }
            if isInitialized {
                recordTeardown(AudioUnitUninitialize(audioUnit))
                isInitialized = false
            }
            let disposeStatus = AudioComponentInstanceDispose(audioUnit)
            recordTeardown(disposeStatus)
            wasDisposed = disposeStatus == noErr
            self.audioUnit = nil
        }
        if wasDisposed, audioStoppedAt != nil {
            liveAudio?.finish()
        } else {
            liveAudio?.abort()
        }
        let writerClosingAt = ContinuousClock.now
        let writerFinalizationStatus = writer.finish()
        return CaptureFinalizationResult(
            audioUnitTeardown: AudioUnitTeardownResult(
                failureCount: teardownFailureCount,
                wasDisposed: wasDisposed
            ),
            audioStoppedAt: audioStoppedAt,
            writerFinalizationStatus: writerFinalizationStatus,
            writerClosingAt: writerClosingAt,
            writerClosedAt: .now
        )
    }

    private func reportWriteFailureOnce() {
        guard !didReportWriteFailure else {
            return
        }
        didReportWriteFailure = true
        liveAudio?.abort()
        onWriteFailure(sessionIdentifier)
    }

    private static func requireNoError(_ status: OSStatus) throws {
        guard status == noErr else {
            throw AudioRecorderError.cannotConfigure
        }
    }
}

nonisolated private struct CaptureFinalizationResult: Sendable {
    let audioUnitTeardown: AudioUnitTeardownResult
    let audioStoppedAt: ContinuousClock.Instant?
    let writerFinalizationStatus: OSStatus
    let writerClosingAt: ContinuousClock.Instant
    let writerClosedAt: ContinuousClock.Instant
}

nonisolated private struct AudioUnitTeardownResult: Sendable {
    let failureCount: Int
    let wasDisposed: Bool
}

nonisolated private enum StreamingM4AWriterError: Error {
    case cannotCreate
    case cannotConfigure
}

// SAFETY: `write` is called serially by one AUHAL input callback. `finish`
// runs only after the input unit has stopped and been uninitialized.
// The underlying ExtAudioFile is never accessed concurrently across those
// phases, and asynchronous writes are flushed by ExtAudioFileDispose.
nonisolated private final class StreamingM4AWriter: @unchecked Sendable {
    private var file: ExtAudioFileRef?

    init(
        url: URL,
        inputFormat: AVAudioFormat,
        profile: RecordingProfile
    ) throws {
        var outputFormat = AudioStreamBasicDescription(
            mSampleRate: profile.sampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 0,
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(profile.channelCount),
            mBitsPerChannel: 0,
            mReserved: 0
        )
        var createdFile: ExtAudioFileRef?
        let createStatus = ExtAudioFileCreateWithURL(
            url as CFURL,
            kAudioFileM4AType,
            &outputFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &createdFile
        )
        guard createStatus == noErr, let createdFile else {
            throw StreamingM4AWriterError.cannotCreate
        }

        file = createdFile
        do {
            var clientFormat = inputFormat.streamDescription.pointee
            guard
                ExtAudioFileSetProperty(
                    createdFile,
                    kExtAudioFileProperty_ClientDataFormat,
                    UInt32(
                        MemoryLayout<AudioStreamBasicDescription>.size
                    ),
                    &clientFormat
                ) == noErr
            else {
                throw StreamingM4AWriterError.cannotConfigure
            }

            try configureBitRate(
                target: profile.targetBitRate,
                for: createdFile
            )

            guard ExtAudioFileWriteAsync(createdFile, 0, nil) == noErr
            else {
                throw StreamingM4AWriterError.cannotConfigure
            }
        } catch {
            _ = ExtAudioFileDispose(createdFile)
            file = nil
            throw error
        }
    }

    deinit {
        if let file {
            _ = ExtAudioFileDispose(file)
        }
    }

    func write(_ buffer: AVAudioPCMBuffer) -> OSStatus {
        guard let file else {
            return kExtAudioFileError_InvalidOperationOrder
        }
        return ExtAudioFileWriteAsync(
            file,
            buffer.frameLength,
            buffer.audioBufferList
        )
    }

    func finish() -> OSStatus {
        guard let file else {
            return noErr
        }
        self.file = nil
        return ExtAudioFileDispose(file)
    }

    private func configureBitRate(
        target: Int,
        for file: ExtAudioFileRef
    ) throws {
        var converter: AudioConverterRef?
        var converterSize = UInt32(
            MemoryLayout<AudioConverterRef?>.size
        )
        guard
            ExtAudioFileGetProperty(
                file,
                kExtAudioFileProperty_AudioConverter,
                &converterSize,
                &converter
            ) == noErr,
            let converter
        else {
            throw StreamingM4AWriterError.cannotConfigure
        }

        let selectedRate = nearestSupportedBitRate(
            to: target,
            converter: converter
        )
        var bitRate = UInt32(selectedRate)
        guard
            AudioConverterSetProperty(
                converter,
                kAudioConverterEncodeBitRate,
                UInt32(MemoryLayout<UInt32>.size),
                &bitRate
            ) == noErr
        else {
            throw StreamingM4AWriterError.cannotConfigure
        }

        var nilConfiguration: UnsafeRawPointer? = nil
        let synchronizeStatus = withUnsafePointer(
            to: &nilConfiguration
        ) { pointer in
            ExtAudioFileSetProperty(
                file,
                kExtAudioFileProperty_ConverterConfig,
                UInt32(MemoryLayout<UnsafeRawPointer?>.size),
                pointer
            )
        }
        guard synchronizeStatus == noErr else {
            throw StreamingM4AWriterError.cannotConfigure
        }
    }

    private func nearestSupportedBitRate(
        to target: Int,
        converter: AudioConverterRef
    ) -> Int {
        var dataSize: UInt32 = 0
        var writable = DarwinBoolean(false)
        guard
            AudioConverterGetPropertyInfo(
                converter,
                kAudioConverterApplicableEncodeBitRates,
                &dataSize,
                &writable
            ) == noErr,
            dataSize >= MemoryLayout<AudioValueRange>.stride
        else {
            return target
        }

        let count = Int(dataSize)
            / MemoryLayout<AudioValueRange>.stride
        var ranges = Array(
            repeating: AudioValueRange(),
            count: count
        )
        let status = ranges.withUnsafeMutableBytes { buffer in
            AudioConverterGetProperty(
                converter,
                kAudioConverterApplicableEncodeBitRates,
                &dataSize,
                buffer.baseAddress!
            )
        }
        guard status == noErr else {
            return target
        }

        let candidates = ranges.flatMap { range in
            [range.mMinimum, range.mMaximum]
        }
        .filter { $0 > 0 && $0.isFinite }
        .map(Int.init)
        guard !candidates.isEmpty else {
            return target
        }

        return candidates.min { lhs, rhs in
            abs(lhs - target) < abs(rhs - target)
        } ?? target
    }
}
