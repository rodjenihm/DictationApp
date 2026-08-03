import Foundation

enum AudioInputPreference: Codable, Equatable, Hashable, Sendable {
    enum Identity: Equatable, Hashable, Sendable {
        case systemDefault
        case builtIn
        case device(uid: String)
    }

    case systemDefault
    case builtIn
    case device(uid: String, lastKnownName: String)

    static let `default`: AudioInputPreference = .builtIn

    var identity: Identity {
        switch self {
        case .systemDefault:
            .systemDefault
        case .builtIn:
            .builtIn
        case .device(let uid, _):
            .device(uid: uid)
        }
    }
}
