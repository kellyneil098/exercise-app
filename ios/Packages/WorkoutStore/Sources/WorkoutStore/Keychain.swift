import Foundation
import Security

/// Bearer token + identity live in the Keychain, never in UserDefaults or the SQLite file.
public enum Keychain {
    static let service = "com.kellyneil.workout"

    /// The bearer token never leaves this device (excluded from backups/restores). The local user ids are not
    /// credentials and keep migrating so a restored device still owns its restored SQLite rows.
    static func accessibility(for key: String) -> CFString {
        key == tokenKey ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly : kSecAttrAccessibleAfterFirstUnlock
    }

    /// Re-classes a token written by an older build, which used a backup-migratable accessibility class.
    public static func migrateAccessibility() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: tokenKey]
        SecItemUpdate(query as CFDictionary, [kSecAttrAccessible as String: accessibility(for: tokenKey)] as CFDictionary)
    }

    public static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = accessibility(for: key)
        SecItemAdd(add as CFDictionary, nil)
    }

    public static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public static func remove(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }

    public static let tokenKey = "api_token"
    public static let userIdKey = "user_id"
    /// The last user id handed out by the server on this device; a local id that never signed in has none.
    public static let serverIssuedUserIdKey = "server_issued_user_id"
}
