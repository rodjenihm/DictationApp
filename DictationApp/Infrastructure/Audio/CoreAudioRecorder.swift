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
        CheckedContinuation<Void, any Error>?
    private var startTimeoutTask: Task<Void, Never>?
    private var preparingSessionIdentifiers: Set<UUID> = []
    private var cancelledSessionIdentifiers: Set<UUID> = []
    private var isExpectedFinish = false
    private var hasAcceptedAudio = false
    private var engineStartBeganAt: TimeInterval?
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
        sessionIdentifier: UUID
    ) async throws -> PreparedRecording {
        let preparationBeganAt = ProcessInfo.processInfo.systemUptime
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

        let candidates = audioInputDeviceService.captureCandidates(
            for: audioInputPreference
        )
        guard !candidates.isEmpty else {
            throw AudioRecorderError.noInputDevice
        }

        let outputURL: URL
        do {
            outputURL = try fileStore.makeRecordingURL(
                fileExtension: profile.fileExtension
            )
        } catch {
            throw AudioRecorderError.cannotConfigure
        }

        do {
            var preparedContext: CoreAudioCaptureContext?
            var lastError: (any Error)?

            for candidate in candidates {
                do {
                    preparedContext = try await configureCapture(
                        profile: profile,
                        outputURL: outputURL,
                        candidate: candidate,
                        sessionIdentifier: sessionIdentifier
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
            installFailureObservers(for: preparedContext)
            let elapsedMilliseconds = Int(
                (
                    ProcessInfo.processInfo.systemUptime
                        - preparationBeganAt
                ) * 1_000
            )
            AppLog.capture.info(
                "Streaming capture preparation succeeded in \(elapsedMilliseconds, privacy: .public) ms"
            )
            return PreparedRecording(
                inputDeviceName: preparedContext.inputDeviceName,
                isUsingFallback: preparedContext.isUsingFallback
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

    func startPreparedRecording() async throws {
        guard let context else {
            throw AudioRecorderError.cannotStart
        }

        engineStartBeganAt = ProcessInfo.processInfo.systemUptime
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

        let finalizationBeganAt = ProcessInfo.processInfo.systemUptime
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
            let artifact = try await validateArtifact(
                at: outputURL,
                context: context
            )
            let elapsedMilliseconds = Int(
                (
                    ProcessInfo.processInfo.systemUptime
                        - finalizationBeganAt
                ) * 1_000
            )
            AppLog.capture.info(
                "Streaming capture finalized in \(elapsedMilliseconds, privacy: .public) ms"
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
        sessionIdentifier: UUID
    ) async throws -> CoreAudioCaptureContext {
        let onFirstBuffer: @Sendable (UUID) -> Void = {
            [weak self] identifier in
            Task { @MainActor [weak self] in
                self?.handleFirstAcceptedBuffer(
                    sessionIdentifier: identifier
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

        return try await withCheckedThrowingContinuation { continuation in
            runtime.queue.async {
                [runtime, onFirstBuffer, onWriteFailure] in
                do {
                    let preparedContext = try CoreAudioCaptureContext.make(
                        runtime: runtime,
                        deviceID: candidate.deviceID,
                        outputURL: outputURL,
                        inputDeviceName: candidate.name,
                        isUsingFallback: candidate.isFallback,
                        profile: profile,
                        sessionIdentifier: sessionIdentifier,
                        onFirstBuffer: onFirstBuffer,
                        onWriteFailure: onWriteFailure
                    )
                    continuation.resume(returning: preparedContext)
                } catch let error as AudioRecorderError {
                    continuation.resume(throwing: error)
                } catch {
                    continuation.resume(
                        throwing: AudioRecorderError.cannotConfigure
                    )
                }
            }
        }
    }

    private func handleFirstAcceptedBuffer(
        sessionIdentifier: UUID
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
            let elapsedMilliseconds = Int(
                (
                    ProcessInfo.processInfo.systemUptime
                        - engineStartBeganAt
                ) * 1_000
            )
            AppLog.capture.info(
                "Audio input unit reached first buffer in \(elapsedMilliseconds, privacy: .public) ms"
            )
        }
        self.engineStartBeganAt = nil
        continuation.resume()
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
        let result = await withCheckedContinuation { continuation in
            runtime.queue.async { [context] in
                continuation.resume(
                    returning: context.stopAndDisposeWriter()
                )
            }
        }

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
    let onFirstBuffer: @Sendable (UUID) -> Void
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
        onFirstBuffer: @escaping @Sendable (UUID) -> Void,
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
        onFirstBuffer: @escaping @Sendable (UUID) -> Void,
        onWriteFailure: @escaping @Sendable (UUID) -> Void
    ) throws -> CoreAudioCaptureContext {
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

            let writer = try StreamingM4AWriter(
                url: outputURL,
                inputFormat: inputFormat,
                profile: profile
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
            try requireNoError(AudioUnitInitialize(audioUnit))
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

        if !didReportFirstBuffer {
            didReportFirstBuffer = true
            onFirstBuffer(sessionIdentifier)
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
        if let audioUnit {
            if isStarted {
                recordTeardown(AudioOutputUnitStop(audioUnit))
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
        return CaptureFinalizationResult(
            audioUnitTeardown: AudioUnitTeardownResult(
                failureCount: teardownFailureCount,
                wasDisposed: wasDisposed
            ),
            writerFinalizationStatus: writer.finish()
        )
    }

    private func reportWriteFailureOnce() {
        guard !didReportWriteFailure else {
            return
        }
        didReportWriteFailure = true
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
    let writerFinalizationStatus: OSStatus
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
