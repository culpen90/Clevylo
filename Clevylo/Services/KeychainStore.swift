import Foundation
import Security

/// One device-local generic-password item. Keys never enter the JSON library or logs.
struct KeychainStore {
    private let service: String
    private let account = "openrouter-api-key"

    init(service: String = "com.clevylo.app.credentials") { self.service = service }

    static func save(_ key: String) throws { try KeychainStore().save(key) }
    static func load() throws -> String? { try KeychainStore().load() }
    static func delete() throws { try KeychainStore().delete() }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func save(_ key: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIProviderError.missingKey }
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
                                       kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }

    func load() throws -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode)
        }
        return key
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        "Clevylo could not access macOS Keychain (\(status)). Unlock your login keychain and try again."
    }
}
