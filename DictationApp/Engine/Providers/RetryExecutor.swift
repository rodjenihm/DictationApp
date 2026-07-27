import Foundation
import OSLog

struct RetryExecutor {
    typealias Sleep = (TimeInterval) async throws -> Void
    typealias Jitter = (ClosedRange<Double>) -> Double

    private let maximumAttempts: Int
    private let baseDelay: TimeInterval
    private let maximumDelay: TimeInterval
    private let maximumCumulativeWait: TimeInterval
    private let sleep: Sleep
    private let jitter: Jitter

    init(
        maximumAttempts: Int = 3,
        baseDelay: TimeInterval = 1,
        maximumDelay: TimeInterval = 8,
        maximumCumulativeWait: TimeInterval = 30,
        sleep: @escaping Sleep = { delay in
            try await Task.sleep(for: .seconds(delay))
        },
        jitter: @escaping Jitter = { range in
            Double.random(in: range)
        }
    ) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.baseDelay = max(0, baseDelay)
        self.maximumDelay = max(0, maximumDelay)
        self.maximumCumulativeWait = max(0, maximumCumulativeWait)
        self.sleep = sleep
        self.jitter = jitter
    }

    func execute<Value>(
        _ operation: () async throws -> Value
    ) async throws -> Value {
        var attempt = 1
        var cumulativeWait: TimeInterval = 0

        while true {
            try Task.checkCancellation()
            AppLog.providers.debug(
                "Provider attempt \(attempt, privacy: .public) started"
            )

            do {
                let value = try await operation()
                AppLog.providers.debug(
                    "Provider attempt \(attempt, privacy: .public) succeeded"
                )
                return value
            } catch is CancellationError {
                AppLog.providers.notice("Provider operation cancelled")
                throw ProviderOperationFailure.cancelled
            } catch let failure as ProviderOperationFailure {
                guard
                    failure.isAutomaticallyRetryable,
                    attempt < maximumAttempts
                else {
                    AppLog.providers.error(
                        "Provider operation stopped with classification \(failure.logClassification, privacy: .public)"
                    )
                    throw failure
                }

                let remainingWait = max(
                    0,
                    maximumCumulativeWait - cumulativeWait
                )

                let delay = min(
                    retryDelay(
                        for: failure,
                        completedAttempt: attempt
                    ),
                    remainingWait
                )

                if delay > 0 {
                    AppLog.providers.notice(
                        "Provider transient failure scheduled retry"
                    )
                    do {
                        try await sleep(delay)
                    } catch is CancellationError {
                        AppLog.providers.notice(
                            "Provider retry wait cancelled"
                        )
                        throw ProviderOperationFailure.cancelled
                    }
                    cumulativeWait += delay
                }

                attempt += 1
            } catch {
                AppLog.providers.error(
                    "Provider operation stopped with unclassified failure"
                )
                throw ProviderOperationFailure.operation(
                    message: "The provider operation failed."
                )
            }
        }
    }

    private func retryDelay(
        for failure: ProviderOperationFailure,
        completedAttempt: Int
    ) -> TimeInterval {
        if let providerDelay = failure.retryDelay {
            return max(0, providerDelay)
        }

        let exponentialDelay = min(
            baseDelay * pow(2, Double(completedAttempt - 1)),
            maximumDelay
        )
        return jitter(0...max(0, exponentialDelay))
    }
}
