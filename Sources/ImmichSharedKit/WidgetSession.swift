import Foundation
import Security
import os

/// The credentials a widget needs to talk to the user's Immich server.
///
/// A widget runs in its own process, outside the app's `ImmichAPIClient`, so it
/// cannot read the app's in-memory session — it reads this small snapshot from
/// the keychain instead. The app is the only writer.
public struct WidgetSession: Codable, Equatable, Sendable {
    /// Server address, exactly as the app stores it (no trailing slash).
    public var baseURL: String
    /// Bearer token of the active account.
    public var token: String
    /// Display name, for the widget's greeting. Nil when the server did not
    /// return one.
    public var userName: String?
    public var userId: String?

    public init(baseURL: String, token: String, userName: String? = nil, userId: String? = nil) {
        self.baseURL = baseURL
        self.token = token
        self.userName = userName
        self.userId = userId
    }
}

/// Read/write seam for `WidgetSession`. The app writes on sign-in and clears on
/// sign-out; the widget only reads, and tests swap in a double.
public protocol WidgetSessionStoring: Sendable {
    func save(_ session: WidgetSession)
    func load() -> WidgetSession?
    func clear()
}

/// Keychain-backed store, shared by app and widget through the
/// `keychain-access-groups` entitlement both targets declare
/// (`Resources/ImmichSwiftUI.entitlements`, `Resources/ImmichWidgets.entitlements`).
///
/// No `kSecAttrAccessGroup` is passed on purpose: the item lands in the process'
/// default group, which is the app-id-derived group both entitlements list, so
/// the widget process reads exactly what the app wrote without either side
/// hardcoding a Team ID.
///
/// Accessibility is `afterFirstUnlock` (not the app's stricter `whenUnlocked`):
/// Lock Screen widgets refresh while the device is locked, and a
/// `whenUnlocked` item would silently fail every fetch there.
public struct WidgetSessionStore: WidgetSessionStoring {
    private static let account = "session"
    private let service: String
    private let logger = Logger(subsystem: "app.immich.swiftui", category: "widget-session")

    public init(service: String = "app.immich.swiftui.widget") {
        self.service = service
    }

    public func save(_ session: WidgetSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("widget session save failed: \(status, privacy: .public)")
        }
    }

    public func load() -> WidgetSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let session = try? JSONDecoder().decode(WidgetSession.self, from: data),
              !session.token.isEmpty
        else { return nil }
        return session
    }

    public func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
