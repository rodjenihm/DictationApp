@preconcurrency import AVFoundation
@preconcurrency import AudioToolbox
import Foundation
import OSLog

@MainActor
final class AVAudioEngineRecorder: AudioRecorder {
    var onUnexpectedCaptureFailure:
        ((UUID, UnexpectedCaptureOutcome) -> Void)?
    var onCancellationTeardownCompleted:
        ((UUID) -> Void)?

    private let fileStore: RecordingFileStore
    private let runtime = AudioEngineRuntime()

    private var context: AudioEngineCaptureContext?
    private var startContinuation:
        CheckedContinuation<Void, any Error>?
    private var preparingSessionIdentifiers: Set<UUID> = []
    private var cancelledSessionIdentifiers: Set<UUID> = []
    private var isExpectedFinish = false
    private var hasAcceptedAudio = false
    private var engineStartBeganAt: TimeInterval?
    private var terminationContext: AudioEngineCaptureContext?

    init(fileStore: RecordingFileStore) {
        self.fileStore = fileStore
    }

    func prepare(
        profile: RecordingProfile,
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

        let outputURL: URL
        do {
            outputURL = try fileStore.makeRecordingURL(
                fileExtension: profile.fileExtension
            )
        } catch {
            throw AudioRecorderError.cannotConfigure
        }

        guard let device = AVCaptureDevice.default(for: .audio) else {
            fileStore.delete(outputURL)
            throw AudioRecorderError.noInputDevice
        }

        do {
            let preparedContext = try await configureCapture(
                profile: profile,
                outputURL: outputURL,
                device: device,
                sessionIdentifier: sessionIdentifier
            )

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
                inputDeviceName: device.localizedName
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
        return try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation

            runtime.queue.async { [weak self, context] in
                do {
                    try context.runtime.engine.start()
                } catch {
                    Task { @MainActor [weak self] in
                        self?.handleEngineStartFailure(
                            sessionIdentifier: context.sessionIdentifier
                        )
                    }
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
        hasAcceptedAudio = false
        isExpectedFinish = false
        engineStartBeganAt = nil

        runtime.queue.async { [weak self, context] in
            _ = context.stopEngineAndDisposeWriter()
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
        device: AVCaptureDevice,
        sessionIdentifier: UUID
    ) async throws -> AudioEngineCaptureContext {
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
                    guard !runtime.engine.isRunning else {
                        throw AudioRecorderError.cannotConfigure
                    }

                    let inputNode = runtime.engine.inputNode
                    let inputFormat = inputNode.outputFormat(forBus: 0)
                    guard
                        inputFormat.sampleRate > 0,
                        inputFormat.channelCount > 0
                    else {
                        throw AudioRecorderError.cannotConfigure
                    }

                    let writer = try StreamingM4AWriter(
                        url: outputURL,
                        inputFormat: inputFormat,
                        profile: profile
                    )
                    let preparedContext = AudioEngineCaptureContext(
                        runtime: runtime,
                        inputNode: inputNode,
                        device: device,
                        writer: writer,
                        outputURL: outputURL,
                        inputDeviceName: device.localizedName,
                        profile: profile,
                        sessionIdentifier: sessionIdentifier,
                        onFirstBuffer: onFirstBuffer,
                        onWriteFailure: onWriteFailure
                    )

                    inputNode.installTap(
                        onBus: 0,
                        bufferSize: 256,
                        format: inputFormat
                    ) { [weak preparedContext] buffer, _ in
                        preparedContext?.accept(buffer)
                    }
                    preparedContext.tapInstalled = true
                    runtime.engine.prepare()
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
        hasAcceptedAudio = true
        if let engineStartBeganAt {
            let elapsedMilliseconds = Int(
                (
                    ProcessInfo.processInfo.systemUptime
                        - engineStartBeganAt
                ) * 1_000
            )
            AppLog.capture.info(
                "Audio engine reached first buffer in \(elapsedMilliseconds, privacy: .public) ms"
            )
        }
        self.engineStartBeganAt = nil
        continuation.resume()
    }

    private func handleEngineStartFailure(
        sessionIdentifier: UUID
    ) {
        guard
            context?.sessionIdentifier == sessionIdentifier,
            let continuation = startContinuation
        else {
            return
        }

        startContinuation = nil
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
            handleEngineStartFailure(
                sessionIdentifier: sessionIdentifier
            )
            return
        }

        handleUnexpectedCaptureSignal(for: context)
    }

    private func installFailureObservers(
        for context: AudioEngineCaptureContext
    ) {
        let center = NotificationCenter.default

        context.observerTokens.append(
            center.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: context.device,
                queue: nil
            ) { [weak self, weak context] _ in
                guard let context else {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.handleUnexpectedCaptureSignal(for: context)
                }
            }
        )

        context.observerTokens.append(
            center.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: context.runtime.engine,
                queue: nil
            ) { [weak self, weak context] _ in
                guard let context else {
                    return
                }
                Task { @MainActor [weak self] in
                    guard self?.hasAcceptedAudio == true else {
                        return
                    }
                    self?.handleUnexpectedCaptureSignal(for: context)
                }
            }
        )
    }

    private func removeFailureObservers(
        from context: AudioEngineCaptureContext
    ) {
        let center = NotificationCenter.default
        context.observerTokens.forEach(center.removeObserver)
        context.observerTokens.removeAll()
    }

    private func handleUnexpectedCaptureSignal(
        for candidate: AudioEngineCaptureContext
    ) {
        guard
            context === candidate,
            !candidate.isHandlingUnexpectedFailure,
            !isExpectedFinish
        else {
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
        _ context: AudioEngineCaptureContext
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
        _ context: AudioEngineCaptureContext
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            runtime.queue.async { [context] in
                let status = context.stopEngineAndDisposeWriter()
                if status == noErr {
                    continuation.resume(returning: context.outputURL)
                } else {
                    continuation.resume(
                        throwing: AudioRecorderError.cannotFinalize
                    )
                }
            }
        }
    }

    private func tearDownCapture(
        _ context: AudioEngineCaptureContext
    ) async {
        await withCheckedContinuation { continuation in
            runtime.queue.async { [context] in
                _ = context.stopEngineAndDisposeWriter()
                continuation.resume()
            }
        }
    }

    private func clearContext(
        ifMatching candidate: AudioEngineCaptureContext
    ) {
        guard context === candidate else {
            return
        }
        context = nil
        hasAcceptedAudio = false
        isExpectedFinish = false
        engineStartBeganAt = nil
    }

    private func validateArtifact(
        at url: URL,
        context: AudioEngineCaptureContext
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

// SAFETY: The reusable engine and all engine control operations are owned by
// `queue`. The engine is stopped before a context's writer is disposed.
nonisolated private final class AudioEngineRuntime: @unchecked Sendable {
    let queue = DispatchQueue(
        label: "com.danijelmitrovic.DictationApp.audio-engine",
        qos: .userInteractive
    )
    let engine = AVAudioEngine()
}

// SAFETY: Mutable presentation fields and observer tokens are accessed only on
// MainActor. `tapInstalled`, engine control, and writer disposal are owned by
// AudioEngineRuntime.queue. The render callback is the writer's sole producer;
// engine shutdown completes before the queue disposes the writer.
nonisolated private final class AudioEngineCaptureContext:
    @unchecked Sendable
{
    let runtime: AudioEngineRuntime
    let inputNode: AVAudioInputNode
    let device: AVCaptureDevice
    let writer: StreamingM4AWriter
    let outputURL: URL
    let inputDeviceName: String
    let profile: RecordingProfile
    let sessionIdentifier: UUID
    let onFirstBuffer: @Sendable (UUID) -> Void
    let onWriteFailure: @Sendable (UUID) -> Void

    var observerTokens: [NSObjectProtocol] = []
    var isHandlingUnexpectedFailure = false
    var tapInstalled = false

    private var didReportFirstBuffer = false
    private var didReportWriteFailure = false

    init(
        runtime: AudioEngineRuntime,
        inputNode: AVAudioInputNode,
        device: AVCaptureDevice,
        writer: StreamingM4AWriter,
        outputURL: URL,
        inputDeviceName: String,
        profile: RecordingProfile,
        sessionIdentifier: UUID,
        onFirstBuffer: @escaping @Sendable (UUID) -> Void,
        onWriteFailure: @escaping @Sendable (UUID) -> Void
    ) {
        self.runtime = runtime
        self.inputNode = inputNode
        self.device = device
        self.writer = writer
        self.outputURL = outputURL
        self.inputDeviceName = inputDeviceName
        self.profile = profile
        self.sessionIdentifier = sessionIdentifier
        self.onFirstBuffer = onFirstBuffer
        self.onWriteFailure = onWriteFailure
    }

    func accept(_ buffer: AVAudioPCMBuffer) {
        let status = writer.write(buffer)
        guard status == noErr else {
            if !didReportWriteFailure {
                didReportWriteFailure = true
                onWriteFailure(sessionIdentifier)
            }
            return
        }

        guard !didReportFirstBuffer else {
            return
        }
        didReportFirstBuffer = true
        onFirstBuffer(sessionIdentifier)
    }

    func stopEngineAndDisposeWriter() -> OSStatus {
        if runtime.engine.isRunning {
            runtime.engine.stop()
        }
        if tapInstalled {
            inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        return writer.finish()
    }
}

nonisolated private enum StreamingM4AWriterError: Error {
    case cannotCreate
    case cannotConfigure
}

// SAFETY: `write` is called serially by one AVAudioEngine render callback.
// `finish` runs only after the engine has stopped and its tap has been removed.
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
