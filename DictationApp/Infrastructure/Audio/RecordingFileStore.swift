import Foundation

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
}
