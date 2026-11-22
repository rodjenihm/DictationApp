import Foundation

@MainActor
protocol LiveTranscriptionProvider: TranscriptionProvider {
    func supportsLiveTranscription(for language: LanguageSelection) -> Bool

    func startLiveTranscription(
        audio: LiveRecordingAudio,
        language: LanguageSelection
    ) -> LiveTranscriptionSession
}

@MainActor
final class LiveTranscriptionSession {
    private let audio: LiveRecordingAudio
    private let results: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private let analysis: Task<Void, Never>

    init(
        audio: LiveRecordingAudio,
        transcribe: @escaping @Sendable () async -> String?
    ) {
        self.audio = audio
        let (results, continuation) = AsyncStream.makeStream(
            of: String.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.results = results
        self.continuation = continuation
        analysis = Task { @concurrent in
            defer {
                audio.abort()
                continuation.finish()
            }
            if let transcript = await transcribe(), !Task.isCancelled {
                continuation.yield(transcript)
            }
        }
    }

    func finalTranscript() async -> String? {
        let results = self.results
        defer { cancel() }
        // Both children are cancellation-aware. A blocked Speech framework
        // call belongs to the independently owned analysis task.
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                var iterator = results.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(250))
                return nil
            }
            let transcript = await group.next() ?? nil
            group.cancelAll()
            return transcript
        }
    }

    func cancel() {
        audio.abort()
        analysis.cancel()
        continuation.finish()
    }
}
