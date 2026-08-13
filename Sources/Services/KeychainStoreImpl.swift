import Foundation
import Security

/// Keychain-backed implementation of KeychainStore.
///
/// FM-3 mitigation: uses `kSecAttrAccessible = .whenUnlockedThisDeviceOnly`
/// (suitable for tokens, non-iCloud syncable).
///
/// Tokens are keyed by an `account` string: the legacy "active session" slot
/// uses `legacyAccount`; the multi-account layer uses `SavedAccount.id`.
final class KeychainStoreImpl: KeychainStore, @unchecked Sendable {
    private let service: String

    /// Account used by the legacy single-session methods (restore-on-launch).
    static let legacyAccount = "accessToken"

    init(service: String = "app.immich.swiftui") {
        self.service = service
    }

    @discardableResult
    func saveToken(_ token: String) -> Bool {
        saveToken(token, for: Self.legacyAccount)
    }

    func getToken() -> String? {
        getToken(for: Self.legacyAccount)
    }

    @discardableResult
    func deleteToken() -> Bool {
        deleteToken(for: Self.legacyAccount)
    }

    @discardableResult
    func saveToken(_ token: String, for account: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        deleteToken(for: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func getToken(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func deleteToken(for account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
