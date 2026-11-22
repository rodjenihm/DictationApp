import Foundation
import OSLog

enum AppLog {
    private nonisolated static let subsystem =
        Bundle.main.bundleIdentifier ?? "DictationApp"

    static let lifecycle = Logger(
        subsystem: subsystem,
        category: "lifecycle"
    )
    static let configuration = Logger(
        subsystem: subsystem,
        category: "configuration"
    )
    static let session = Logger(
        subsystem: subsystem,
        category: "session"
    )
    static let providers = Logger(
        subsystem: subsystem,
        category: "providers"
    )
    static let capture = Logger(
        subsystem: subsystem,
        category: "capture"
    )
    static let insertion = Logger(
        subsystem: subsystem,
        category: "insertion"
    )
    private nonisolated static let latency = Logger(
        subsystem: subsystem,
        category: "latency"
    )

    nonisolated static func recordLatency(
        _ stage: String,
        since start: ContinuousClock.Instant,
        sessionID: UUID? = nil,
        until end: ContinuousClock.Instant = .now
    ) {
        let parts = start.duration(to: end).components
        let milliseconds = parts.seconds * 1_000
            + parts.attoseconds / 1_000_000_000_000_000
        latency.info(
            "\(stage, privacy: .public) duration_ms=\(milliseconds, privacy: .public) session=\(sessionID?.uuidString ?? "-", privacy: .public)"
        )
    }
}
