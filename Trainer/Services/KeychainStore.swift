import Foundation
import Security

/// Minimal Keychain wrapper for the Anthropic API key.
/// The key never goes to UserDefaults, logs, or any server other than api.anthropic.com.
enum KeychainStore {
    private static let service = (Bundle.main.bundleIdentifier ?? "Trainer") + ".anthropic"
    private static let account = "anthropic-api-key"

    static var apiKey: String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    static var hasAPIKey: Bool { apiKey != nil }

    @discardableResult
    static func setAPIKey(_ key: String?) -> Bool {
        SecItemDelete(baseQuery as CFDictionary)
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return true }
        var attrs = baseQuery
        attrs[kSecValueData as String] = Data(key.utf8)
        // Available after first unlock so check-ins can prepare context; never synced to iCloud.
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
