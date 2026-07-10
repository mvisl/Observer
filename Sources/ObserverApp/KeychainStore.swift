import Foundation
import Security

struct KeychainStore {
    let service: String
    let account: String

    static let geminiAPIKey = KeychainStore(
        service: "local.observer.gemini",
        account: "apiKey"
    )

    func setPassword(_ password: String) throws {
        let data = Data(password.utf8)
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }

        if addStatus == errSecDuplicateItem {
            let attributes: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainStoreError.status(updateStatus)
            }
            return
        }

        throw KeychainStoreError.status(addStatus)
    }

    func password() throws -> String? {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.status(status)
        }
        guard
            let data = result as? Data,
            let password = String(data: data, encoding: .utf8)
        else {
            throw KeychainStoreError.invalidData
        }
        return password
    }

    func deletePassword() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.status(status)
        }
    }

    func hasPassword() -> Bool {
        ((try? password()) ?? nil)?.isEmpty == false
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum KeychainStoreError: Error, CustomStringConvertible {
    case invalidData
    case status(OSStatus)

    var description: String {
        switch self {
        case .invalidData:
            return "Keychain item could not be decoded."
        case .status(let status):
            return "Keychain status \(status)."
        }
    }
}
