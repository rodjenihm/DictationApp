import Foundation
import OSLog

final class RecordingFileStore {
    private let fileManager: FileManager
    private let directoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let cachesURL =
            fileManager.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first
            ?? fileManager.temporaryDirectory

        directoryURL = cachesURL
            .appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "DictationApp",
                isDirectory: true
            )
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    func makeRecordingURL(fileExtension: String) throws -> URL {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        return directoryURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
    }

    func delete(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try? fileManager.removeItem(at: url)
    }

    @discardableResult
    func removeOrphanedRecordings() -> Int {
        guard
            let contents = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )
        else {
            return 0
        }

        var removedCount = 0
        for url in contents {
            do {
                try fileManager.removeItem(at: url)
                removedCount += 1
            } catch {
                AppLog.lifecycle.error(
                    "Startup recording cleanup could not remove an item"
                )
            }
        }
        return removedCount
    }
}
