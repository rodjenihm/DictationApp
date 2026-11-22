import Foundation
import OSLog

nonisolated final class OpenAICleanupRequestDiagnostics: NSObject, URLSessionTaskDelegate {
    private let sessionID: UUID
    private let attempt: Int
    private let requestedTier: String
    private let isFastRejectionFallback: Bool
    private let startedAt = ContinuousClock.now

    init(
        sessionID: UUID,
        attempt: Int,
        requestedTier: String,
        isFastRejectionFallback: Bool
    ) {
        self.sessionID = sessionID
        self.attempt = attempt
        self.requestedTier = requestedTier
        self.isFastRejectionFallback = isFastRejectionFallback
    }

    func recordOutcome(_ outcome: String, reportedTier: String?) {
        let parts = startedAt.duration(to: .now).components
        let milliseconds = parts.seconds * 1_000
            + parts.attoseconds / 1_000_000_000_000_000
        let servedTier = Self.servedTier(reportedTier)
        let fastRejectionFallback = String(isFastRejectionFallback)
        AppLog.cleanup.info(
            """
            openai_cleanup_attempt session=\(self.sessionID.uuidString, privacy: .public) \
            attempt=\(self.attempt, privacy: .public) requested_tier=\(self.requestedTier, privacy: .public) \
            served_tier=\(servedTier, privacy: .public) outcome=\(outcome, privacy: .public) \
            fast_rejection_fallback=\(fastRejectionFallback, privacy: .public) \
            duration_ms=\(milliseconds, privacy: .public)
            """
        )
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        let transactions = metrics.transactionMetrics
        if transactions.isEmpty {
            AppLog.cleanup.info(
                """
                openai_cleanup_transport session=\(self.sessionID.uuidString, privacy: .public) \
                attempt=\(self.attempt, privacy: .public) transaction_count=0
                """
            )
        }

        for (index, transaction) in transactions.enumerated() {
            let reusedConnection = transaction.resourceFetchType == .networkLoad
                ? String(transaction.isReusedConnection) : "-"
            let dns = Self.milliseconds(
                from: transaction.domainLookupStartDate,
                to: transaction.domainLookupEndDate
            )
            let connect = Self.milliseconds(
                from: transaction.connectStartDate,
                to: transaction.connectEndDate
            )
            let tls = Self.milliseconds(
                from: transaction.secureConnectionStartDate,
                to: transaction.secureConnectionEndDate
            )
            let upload = Self.milliseconds(
                from: transaction.requestStartDate,
                to: transaction.requestEndDate
            )
            let firstResponseWait = Self.milliseconds(
                from: transaction.requestEndDate,
                to: transaction.responseStartDate
            )
            let download = Self.milliseconds(
                from: transaction.responseStartDate,
                to: transaction.responseEndDate
            )

            AppLog.cleanup.info(
                """
                openai_cleanup_transport session=\(self.sessionID.uuidString, privacy: .public) \
                attempt=\(self.attempt, privacy: .public) transaction=\(index + 1, privacy: .public) \
                transaction_count=\(transactions.count, privacy: .public) \
                reused_connection=\(reusedConnection, privacy: .public) dns_ms=\(dns, privacy: .public) \
                connect_ms=\(connect, privacy: .public) tls_ms=\(tls, privacy: .public) \
                upload_ms=\(upload, privacy: .public) first_response_wait_ms=\(firstResponseWait, privacy: .public) \
                download_ms=\(download, privacy: .public)
                """
            )
        }
    }

    private static func servedTier(_ reportedTier: String?) -> String {
        switch reportedTier {
        case "fast", "priority": "fast"
        case "default": "standard"
        case "auto": "project_default"
        case "flex": "flex"
        case "scale": "scale"
        case "ultrafast": "ultrafast"
        case nil: "unreported"
        default: "unknown"
        }
    }

    private static func milliseconds(from start: Date?, to end: Date?) -> String {
        guard let start, let end else {
            return "-"
        }
        let interval = end.timeIntervalSince(start)
        guard interval >= 0, let milliseconds = Int(exactly: (interval * 1_000).rounded()) else {
            return "-"
        }
        return String(milliseconds)
    }
}
