@preconcurrency import AVFoundation
import Foundation

struct PreparedRecording: Equatable, Sendable {
    let inputDeviceName: String
}

enum AudioRecorderError: Error, Equatable, Sendable {
    case noInputDevice
    case cannotConfigure
    case unsupportedFileType
    case cannotStart
    case cannotFinalize
    case invalidArtifact
}

enum UnexpectedCaptureOutcome: Sendable {
    case partial(AudioArtifact)
    case failed(AudioRecorderError)
}

@MainActor
protocol AudioRecorder: AnyObject {
    var onUnexpectedCaptureFailure:
        ((UnexpectedCaptureOutcome) -> Void)? { get set }

    func prepare(profile: RecordingProfile) async throws -> PreparedRecording
    func startPreparedRecording() async throws
    func stopRecording() async throws -> AudioArtifact
    func cancelRecording() async
    func cancelImmediately()
}

@MainActor
final class AVFoundationAudioRecorder:
    NSObject,
    AudioRecorder,
    AVCaptureFileOutputRecordingDelegate
{
    var onUnexpectedCaptureFailure:
        ((UnexpectedCaptureOutcome) -> Void)?

    private let fileStore: RecordingFileStore
    private let captureQueue = DispatchQueue(
        label: "com.danijelmitrovic.DictationApp.audio-capture",
        qos: .userInitiated
    )

    private var context: CaptureContext?
    private var startContinuation: CheckedContinuation<Void, any Error>?
    private var finishContinuation:
        CheckedContinuation<URL, any Error>?
    private var isExpectedFinish = false

    init(fileStore: RecordingFileStore) {
        self.fileStore = fileStore
        super.init()
    }

    func prepare(profile: RecordingProfile) async throws -> PreparedRecording {
        guard context == nil else {
            throw AudioRecorderError.cannotConfigure
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
            let preparedContext = try await configureCapture(
                profile: profile,
                outputURL: outputURL
            )
            context = preparedContext
            installFailureObservers(for: preparedContext)
            return PreparedRecording(
                inputDeviceName: preparedContext.inputDeviceName
            )
        } catch {
            fileStore.delete(outputURL)
            throw error
        }
    }

    func startPreparedRecording() async throws {
        guard let context else {
            throw AudioRecorderError.cannotStart
        }

        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation

            captureQueue.async { [weak self, context] in
                guard let self else {
                    return
                }

                context.output.startRecording(
                    to: context.outputURL,
                    outputFileType: .m4a,
                    recordingDelegate: self
                )
            }
        }
    }

    func stopRecording() async throws -> AudioArtifact {
        guard let context else {
            throw AudioRecorderError.cannotFinalize
        }

        let outputURL = try await finishRecording(context: context)

        do {
            return try await validateArtifact(
                at: outputURL,
                context: context
            )
        } catch {
            fileStore.delete(outputURL)
            throw error
        }
    }

    func cancelRecording() async {
        guard let context else {
            return
        }

        startContinuation?.resume(throwing: CancellationError())
        startContinuation = nil

        if context.output.isRecording {
            _ = try? await finishRecording(context: context)
        } else {
            await stopCaptureSession(context)
            removeFailureObservers(from: context)
            clearContext(ifMatching: context)
        }

        fileStore.delete(context.outputURL)
    }

    func cancelImmediately() {
        guard let context else {
            return
        }

        self.context = nil
        removeFailureObservers(from: context)
        startContinuation?.resume(throwing: CancellationError())
        startContinuation = nil
        finishContinuation?.resume(throwing: CancellationError())
        finishContinuation = nil
        isExpectedFinish = false

        captureQueue.sync {
            if context.output.isRecording {
                context.output.stopRecording()
            }
            if context.session.isRunning {
                context.session.stopRunning()
            }
        }
        fileStore.delete(context.outputURL)
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Task { @MainActor [weak self] in
            self?.handleDidStartRecording()
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        let finishedSuccessfully = Self.recordingFinishedSuccessfully(error)

        Task { @MainActor [weak self] in
            await self?.handleDidFinishRecording(
                at: outputFileURL,
                finishedSuccessfully: finishedSuccessfully
            )
        }
    }

    private func configureCapture(
        profile: RecordingProfile,
        outputURL: URL
    ) async throws -> CaptureContext {
        try await withCheckedThrowingContinuation { continuation in
            captureQueue.async {
                guard
                    AVCaptureAudioFileOutput.availableOutputFileTypes()
                        .contains(.m4a)
                else {
                    continuation.resume(
                        throwing: AudioRecorderError.unsupportedFileType
                    )
                    return
                }

                guard let device = AVCaptureDevice.default(for: .audio) else {
                    continuation.resume(
                        throwing: AudioRecorderError.noInputDevice
                    )
                    return
                }

                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureAudioFileOutput()
                    let session = AVCaptureSession()

                    session.beginConfiguration()
                    guard session.canAddInput(input) else {
                        session.commitConfiguration()
                        throw AudioRecorderError.cannotConfigure
                    }
                    session.addInput(input)

                    guard session.canAddOutput(output) else {
                        session.commitConfiguration()
                        throw AudioRecorderError.cannotConfigure
                    }
                    session.addOutput(output)
                    output.audioSettings = [
                        AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVSampleRateKey: profile.sampleRate,
                        AVNumberOfChannelsKey: profile.channelCount,
                        AVEncoderBitRateKey: profile.targetBitRate,
                        AVEncoderBitRateStrategyKey:
                            AVAudioBitRateStrategy_Constant,
                    ]
                    session.commitConfiguration()
                    session.startRunning()

                    guard session.isRunning else {
                        throw AudioRecorderError.cannotStart
                    }

                    continuation.resume(
                        returning: CaptureContext(
                            session: session,
                            device: device,
                            output: output,
                            outputURL: outputURL,
                            inputDeviceName: device.localizedName,
                            profile: profile
                        )
                    )
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

    private func finishRecording(
        context: CaptureContext
    ) async throws -> URL {
        guard context.output.isRecording else {
            await stopCaptureSession(context)
            clearContext(ifMatching: context)
            throw AudioRecorderError.cannotFinalize
        }

        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            isExpectedFinish = true

            captureQueue.async {
                context.output.stopRecording()
            }
        }
    }

    private func handleDidStartRecording() {
        startContinuation?.resume()
        startContinuation = nil
    }

    private func handleDidFinishRecording(
        at outputURL: URL,
        finishedSuccessfully: Bool
    ) async {
        guard let context else {
            fileStore.delete(outputURL)
            return
        }

        startContinuation?.resume(
            throwing: AudioRecorderError.cannotStart
        )
        startContinuation = nil

        let continuation = finishContinuation
        finishContinuation = nil
        let expectedFinish = isExpectedFinish
        isExpectedFinish = false

        await stopCaptureSession(context)
        removeFailureObservers(from: context)
        clearContext(ifMatching: context)

        if let continuation {
            continuation.resume(returning: outputURL)
            return
        }

        if !expectedFinish {
            await reportUnexpectedCaptureOutcome(
                at: outputURL,
                context: context,
                delegateReportedSuccess: finishedSuccessfully
            )
        } else {
            fileStore.delete(outputURL)
        }
    }

    private func installFailureObservers(for context: CaptureContext) {
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
                forName: AVCaptureSession.runtimeErrorNotification,
                object: context.session,
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
    }

    private func removeFailureObservers(from context: CaptureContext) {
        let center = NotificationCenter.default
        context.observerTokens.forEach(center.removeObserver)
        context.observerTokens.removeAll()
    }

    private func handleUnexpectedCaptureSignal(
        for candidate: CaptureContext
    ) {
        guard
            context === candidate,
            !candidate.isHandlingUnexpectedFailure,
            !isExpectedFinish
        else {
            return
        }

        candidate.isHandlingUnexpectedFailure = true

        if candidate.output.isRecording {
            captureQueue.async {
                candidate.output.stopRecording()
            }
            return
        }

        startContinuation?.resume(
            throwing: AudioRecorderError.cannotStart
        )
        startContinuation = nil

        Task { [weak self] in
            guard let self else {
                return
            }
            await stopCaptureSession(candidate)
            removeFailureObservers(from: candidate)
            clearContext(ifMatching: candidate)
            fileStore.delete(candidate.outputURL)
        }
    }

    private func reportUnexpectedCaptureOutcome(
        at outputURL: URL,
        context: CaptureContext,
        delegateReportedSuccess: Bool
    ) async {
        do {
            let artifact = try await validateArtifact(
                at: outputURL,
                context: context
            )
            onUnexpectedCaptureFailure?(.partial(artifact))
        } catch {
            fileStore.delete(outputURL)
            onUnexpectedCaptureFailure?(
                .failed(
                    delegateReportedSuccess
                        ? .invalidArtifact
                        : .cannotFinalize
                )
            )
        }
    }

    private func stopCaptureSession(_ context: CaptureContext) async {
        await withCheckedContinuation { continuation in
            captureQueue.async {
                if context.session.isRunning {
                    context.session.stopRunning()
                }
                continuation.resume()
            }
        }
    }

    private func clearContext(ifMatching candidate: CaptureContext) {
        guard context === candidate else {
            return
        }
        context = nil
    }

    private func validateArtifact(
        at url: URL,
        context: CaptureContext
    ) async throws -> AudioArtifact {
        let asset = AVURLAsset(url: url)

        do {
            let duration = try await asset.load(.duration).seconds
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
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

    nonisolated private static func recordingFinishedSuccessfully(
        _ error: (any Error)?
    ) -> Bool {
        guard let error else {
            return true
        }

        let nsError = error as NSError
        return nsError.userInfo[
            AVErrorRecordingSuccessfullyFinishedKey
        ] as? Bool == true
    }
}

private final class CaptureContext: @unchecked Sendable {
    let session: AVCaptureSession
    let device: AVCaptureDevice
    let output: AVCaptureAudioFileOutput
    let outputURL: URL
    let inputDeviceName: String
    let profile: RecordingProfile
    var observerTokens: [NSObjectProtocol] = []
    var isHandlingUnexpectedFailure = false

    init(
        session: AVCaptureSession,
        device: AVCaptureDevice,
        output: AVCaptureAudioFileOutput,
        outputURL: URL,
        inputDeviceName: String,
        profile: RecordingProfile
    ) {
        self.session = session
        self.device = device
        self.output = output
        self.outputURL = outputURL
        self.inputDeviceName = inputDeviceName
        self.profile = profile
    }
}
