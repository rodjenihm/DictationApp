@preconcurrency import AVFoundation
import Speech
import Synchronization

// SpeechAnalyzer pulls one buffer at a time through the stream's single
// iterator. Only that iterator uses the converter and its scratch buffer.
// The output format is immutable, and the end marker is read after analysis.
@available(macOS 26.0, *)
nonisolated final class AppleSpeechAudioInput: @unchecked Sendable {
    private let source: LiveRecordingAudio
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    private let scratch: AVAudioPCMBuffer?
    private let inputBatchSize: AVAudioFrameCount
    private let outputBatchSize: AVAudioFrameCount
    private let reachedEnd = Atomic<Bool>(false)

    init(source: LiveRecordingAudio, outputFormat: AVAudioFormat) throws {
        guard
            let inputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: source.sampleRate,
                channels: 1,
                interleaved: false
            ),
            outputFormat.sampleRate.isFinite,
            outputFormat.sampleRate >= 1,
            outputFormat.sampleRate <= 192_000
        else {
            throw AppleSpeechServiceError.invalidAudio
        }

        self.source = source
        self.outputFormat = outputFormat
        inputBatchSize = max(1, AVAudioFrameCount(inputFormat.sampleRate / 20))
        outputBatchSize = max(1, AVAudioFrameCount(outputFormat.sampleRate / 20))

        if inputFormat == outputFormat {
            converter = nil
            scratch = nil
        } else {
            guard
                let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
                let scratch = AVAudioPCMBuffer(
                    pcmFormat: inputFormat,
                    frameCapacity: inputBatchSize
                )
            else {
                throw AppleSpeechServiceError.invalidAudio
            }
            self.converter = converter
            self.scratch = scratch
        }
    }

    var wasFullyConsumed: Bool {
        reachedEnd.load(ordering: .acquiring)
            && source.isFinished && !source.isAborted
            && source.queuedFrameCount == 0
    }

    var inputs: AsyncThrowingStream<AnalyzerInput, any Error> {
        AsyncThrowingStream(unfolding: { try await self.next() })
    }

    private func next() async throws -> AnalyzerInput? {
        while true {
            try Task.checkCancellation()
            guard !source.isAborted else {
                throw AppleSpeechServiceError.invalidAudio
            }

            let finished = source.isFinished
            let availableFrames = source.queuedFrameCount
            if !finished && availableFrames < inputBatchSize {
                try await Task.sleep(for: .milliseconds(10))
                continue
            }

            if finished && availableFrames == 0 && converter == nil {
                reachedEnd.store(true, ordering: .releasing)
                return nil
            }

            guard let output = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputBatchSize
            ) else {
                throw AppleSpeechServiceError.invalidAudio
            }

            if let converter, let scratch {
                var error: NSError?
                let status = converter.convert(to: output, error: &error) {
                    packets, status in
                    let finished = self.source.isFinished
                    self.source.read(into: scratch, upTo: packets)
                    if scratch.frameLength > 0 {
                        status.pointee = .haveData
                        return scratch
                    }
                    status.pointee = finished ? .endOfStream : .noDataNow
                    return nil
                }
                if let error {
                    throw error
                }
                switch status {
                case .error:
                    throw AppleSpeechServiceError.invalidAudio
                case .endOfStream:
                    reachedEnd.store(true, ordering: .releasing)
                    return nil
                case .haveData, .inputRanDry:
                    break
                @unknown default:
                    throw AppleSpeechServiceError.invalidAudio
                }
            } else {
                source.read(into: output, upTo: outputBatchSize)
            }

            if output.frameLength > 0 {
                return AnalyzerInput(buffer: output)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
