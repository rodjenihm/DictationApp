import AppKit

@MainActor
protocol ClipboardTransactionHandling: AnyObject {
    var isStillOwned: Bool { get }

    @discardableResult
    func replaceOwnedContents(with text: String) -> Bool

    func holdRestoration(for delay: Duration)

    @discardableResult
    func restoreIfOwned() -> Bool

    func abandon()
}

@MainActor
protocol TranscriptClipboardServicing {
    func beginTransaction(
        replacingContentsWith transcript: String
    ) -> any ClipboardTransactionHandling
}

@MainActor
final class ClipboardTransaction: ClipboardTransactionHandling {
    private let pasteboard: NSPasteboard
    private let clock = ContinuousClock()
    private var ownedChangeCount: Int
    private var snapshot: ClipboardSnapshot?
    private var earliestRestoration: ContinuousClock.Instant?
    private var deferredRestorationTask: Task<Void, Never>?

    init(
        pasteboard: NSPasteboard,
        replacement: String
    ) {
        self.pasteboard = pasteboard
        snapshot = ClipboardSnapshot.materialize(from: pasteboard)

        pasteboard.clearContents()
        _ = pasteboard.setString(replacement, forType: .string)
        ownedChangeCount = pasteboard.changeCount
    }

    var isStillOwned: Bool {
        snapshot != nil && pasteboard.changeCount == ownedChangeCount
    }

    @discardableResult
    func replaceOwnedContents(with text: String) -> Bool {
        guard isStillOwned else {
            return false
        }

        pasteboard.clearContents()
        let didWrite = pasteboard.setString(text, forType: .string)
        ownedChangeCount = pasteboard.changeCount
        return didWrite
    }

    func holdRestoration(for delay: Duration) {
        let candidate = clock.now.advanced(by: delay)
        if
            let earliestRestoration,
            earliestRestoration >= candidate
        {
            return
        }
        earliestRestoration = candidate
    }

    @discardableResult
    func restoreIfOwned() -> Bool {
        guard let snapshot else {
            return false
        }

        if
            let earliestRestoration,
            clock.now < earliestRestoration
        {
            scheduleDeferredRestoration(at: earliestRestoration)
            return true
        }

        deferredRestorationTask?.cancel()
        deferredRestorationTask = nil
        self.earliestRestoration = nil
        self.snapshot = nil

        guard pasteboard.changeCount == ownedChangeCount else {
            return false
        }

        pasteboard.clearContents()

        let restoredItems: [NSPasteboardItem] =
            snapshot.items.compactMap { snapshotItem in
                guard !snapshotItem.representations.isEmpty else {
                    return nil
                }

                let item = NSPasteboardItem()
                for representation in snapshotItem.representations {
                    item.setData(
                        representation.data,
                        forType: representation.type
                    )
                }
                return item
            }

        if !restoredItems.isEmpty {
            _ = pasteboard.writeObjects(restoredItems)
        }

        return true
    }

    func abandon() {
        deferredRestorationTask?.cancel()
        deferredRestorationTask = nil
        earliestRestoration = nil
        snapshot = nil
    }

    private func scheduleDeferredRestoration(
        at deadline: ContinuousClock.Instant
    ) {
        guard deferredRestorationTask == nil else {
            return
        }

        deferredRestorationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await clock.sleep(until: deadline)
            deferredRestorationTask = nil
            _ = restoreIfOwned()
        }
    }
}

@MainActor
final class PasteboardClipboardService: TranscriptClipboardServicing {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func beginTransaction(
        replacingContentsWith transcript: String
    ) -> any ClipboardTransactionHandling {
        ClipboardTransaction(
            pasteboard: pasteboard,
            replacement: transcript
        )
    }
}
