import Foundation
import Security

protocol CredentialStore {
    func credentialExists() throws -> Bool
    func readCredential() throws -> String?
    func replaceCredential(with credential: String) throws
    func deleteCredential() throws
}

enum CredentialStoreError: LocalizedError {
    case invalidCredentialEncoding
    case unexpectedData
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidCredentialEncoding:
            "The API key could not be encoded."
        case .unexpectedData:
            "The saved API key could not be read."
        case .keychain(let status):
            "Keychain operation failed (status \(status))."
        }
    }
}

final class KeychainCredentialStore: CredentialStore {
    private let service = "com.danijelmitrovic.DictationApp.openai"
    private let account = "api-key"

    func credentialExists() throws -> Bool {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        default:
            throw CredentialStoreError.keychain(status)
        }
    }

    func readCredential() throws -> String? {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )

        switch status {
        case errSecSuccess:
            guard
                let data = result as? Data,
                let credential = String(data: data, encoding: .utf8)
            else {
                throw CredentialStoreError.unexpectedData
            }
            return credential
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError.keychain(status)
        }
    }

    func replaceCredential(with credential: String) throws {
        guard let data = credential.data(using: .utf8) else {
            throw CredentialStoreError.invalidCredentialEncoding
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.keychain(updateStatus)
        }

        var item = baseQuery
        attributes.forEach { item[$0.key] = $0.value }

        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.keychain(addStatus)
        }
    }

    func deleteCredential() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
