enum CleanupFallback: Equatable, Sendable {
    case couldNotFinish(detail: String? = nil)
    case timedOut
    case editRejected(PostProcessingOutputPolicyError)

    var title: String {
        switch self {
        case .couldNotFinish:
            "Cleanup couldn’t finish"
        case .timedOut:
            "Cleanup took too long"
        case .editRejected:
            "Cleanup edit rejected"
        }
    }

    var message: String {
        switch self {
        case .couldNotFinish(let detail?):
            detail
        case .editRejected(.wordingChanged):
            "Cleanup edit rejected because it changed your words."
        default:
            title + "."
        }
    }
}
