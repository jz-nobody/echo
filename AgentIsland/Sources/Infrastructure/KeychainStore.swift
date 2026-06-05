import Foundation
import Security

protocol KeychainStoring: Sendable {
    func read(key: String) -> Data?
    func write(key: String, data: Data) -> Bool
    func delete(key: String) -> Bool
}

struct KeychainStore: KeychainStoring {
    private let service: String

    init(service: String = "com.agentisland.app.trial") {
        self.service = service
    }

    func read(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    func write(key: String, data: Data) -> Bool {
        let existing = read(key: key)
        if existing != nil {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]
            let update: [String: Any] = [
                kSecValueData as String: data
            ]
            let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            return status == errSecSuccess
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
