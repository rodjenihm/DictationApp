import Foundation
import OSLog

enum AppLog {
    private static let subsystem =
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
}
