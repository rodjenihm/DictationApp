import Foundation

enum ProviderOperationFailure: Equatable, LocalizedError, Sendable {
    case cancelled
    case transient(message: String, retryAfter: TimeInterval?)
    case configuration(message: String)
    case operation(message: String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "The provider operation was cancelled."
        case .transient(let message, _),
             .configuration(let message),
             .operation(let message):
            message
        }
    }

    var isConfigurationFailure: Bool {
        if case .configuration = self {
            return true
        }
        return false
    }

    var retryDelay: TimeInterval? {
        if case .transient(_, let retryAfter) = self {
            return retryAfter
        }
        return nil
    }

    var isAutomaticallyRetryable: Bool {
        if case .transient = self {
            return true
        }
        return false
    }

    var logClassification: String {
        switch self {
        case .cancelled:
            "cancelled"
        case .transient:
            "transient"
        case .configuration:
            "configuration"
        case .operation:
            "operation"
        }
    }
}
