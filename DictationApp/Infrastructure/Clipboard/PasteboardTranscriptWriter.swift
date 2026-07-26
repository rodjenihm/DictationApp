import AppKit

@MainActor
protocol TranscriptClipboardWriting {
    func write(_ transcript: String)
}

final class PasteboardTranscriptWriter: TranscriptClipboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func write(_ transcript: String) {
        pasteboard.clearContents()
        _ = pasteboard.setString(transcript, forType: .string)
    }
}
