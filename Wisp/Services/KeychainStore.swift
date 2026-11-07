import Foundation
import Security

/// Secrets in the login Keychain as generic passwords under Wisp's service, so they never land
/// in UserDefaults or logs.
enum KeychainStore {
    static let service = "com.ayomideodewale.wisp"

    enum Account: String {
        /// The access token for a protected ntfy server.
        case ntfyToken = "ntfy-token"
        /// A token that can only post to the reply topic. The Allow and Deny buttons carry it,
        /// so it's stored in each notification; the access token never is.
        case ntfyReplyToken = "ntfy-reply-token"
        /// A Cursor API key, for listing its Cloud Agents.
        case cursorAPIKey = "cursor-api-key"
    }

    static func read(_ account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Saves `value`, or deletes the item when it's empty. False when the Keychain refused.
    @discardableResult
    static func write(_ value: String, for account: Account) -> Bool {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        guard !value.isEmpty else {
            let status = SecItemDelete(match as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(value.utf8)
        let update = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var add = match
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
