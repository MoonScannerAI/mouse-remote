import Foundation
import Security

/// Stores the 16-byte AUTH token issued by the dongle in the Keychain.
enum TokenStore {
    private static let service = "com.andyli.mouseremote.dongle"
    private static let account = "auth-token"

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func load() -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              data.count == BLEProtocol.tokenLength else { return nil }
        return data
    }

    static func save(_ token: Data) {
        delete()
        var query = baseQuery()
        query[kSecValueData as String] = token
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
