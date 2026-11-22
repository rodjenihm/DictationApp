import AVFoundation
import Synchronization

// The AUHAL callback is the sole producer. The speech input iterator is the
// sole consumer. Release/acquire cursor updates transfer ownership of the
// corresponding ranges of the preallocated storage between them.
nonisolated final class LiveRecordingAudio: @unchecked Sendable {
    let sampleRate: Double
    private let capacity: Int
    private let samples: UnsafeMutablePointer<Float>
    private let writeCursor = Atomic<Int>(0)
    private let readCursor = Atomic<Int>(0)
    private let producerFinished = Atomic<Bool>(false)
    private let aborted = Atomic<Bool>(false)

    init?(format: AVAudioFormat) {
        let sampleRate = format.sampleRate
        guard
            format.channelCount == 1,
            format.commonFormat == .pcmFormatFloat32,
            sampleRate.isFinite,
            sampleRate >= 1,
            sampleRate <= 192_000
        else {
            return nil
        }

        self.sampleRate = sampleRate
        capacity = Int((sampleRate * 2).rounded(.down))
        samples = .allocate(capacity: capacity)
        samples.initialize(repeating: 0, count: capacity)
    }

    deinit {
        samples.deinitialize(count: capacity)
        samples.deallocate()
    }

    var isFinished: Bool {
        producerFinished.load(ordering: .acquiring)
    }

    var isAborted: Bool {
        aborted.load(ordering: .acquiring)
    }

    var queuedFrameCount: Int {
        writeCursor.load(ordering: .acquiring)
            - readCursor.load(ordering: .relaxed)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard !isAborted else {
            return
        }
        let write = writeCursor.load(ordering: .relaxed)
        let read = readCursor.load(ordering: .acquiring)
        let count = Int(buffer.frameLength)
        guard
            count <= capacity - (write - read),
            let source = buffer.floatChannelData?.pointee
        else {
            abort()
            return
        }

        let start = write % capacity
        let firstCount = min(count, capacity - start)
        samples.advanced(by: start).update(from: source, count: firstCount)
        if firstCount < count {
            samples.update(
                from: source.advanced(by: firstCount),
                count: count - firstCount
            )
        }
        writeCursor.store(write + count, ordering: .releasing)
    }

    func read(into buffer: AVAudioPCMBuffer, upTo maximum: AVAudioFrameCount) {
        let read = readCursor.load(ordering: .relaxed)
        let write = writeCursor.load(ordering: .acquiring)
        let count = min(write - read, Int(maximum), Int(buffer.frameCapacity))
        buffer.frameLength = 0
        guard count > 0, let destination = buffer.floatChannelData?.pointee else {
            return
        }

        let start = read % capacity
        let firstCount = min(count, capacity - start)
        destination.update(from: samples.advanced(by: start), count: firstCount)
        if firstCount < count {
            destination.advanced(by: firstCount).update(
                from: samples,
                count: count - firstCount
            )
        }
        buffer.frameLength = AVAudioFrameCount(count)
        readCursor.store(read + count, ordering: .releasing)
    }

    // Called after the audio unit can no longer invoke its input callback.
    func finish() {
        producerFinished.store(true, ordering: .releasing)
    }

    func abort() {
        aborted.store(true, ordering: .releasing)
    }
}
