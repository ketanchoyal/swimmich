import Foundation

/// Abstraction over the secure token store (Keychain in production).
///
/// The single-account methods (`saveToken(_:)`, `getToken()`, `deleteToken()`)
/// address the legacy "active session" slot used to restore the app on launch.
/// The `for account:` variants store per-account tokens keyed by the account
/// identity (`SavedAccount.id`), which powers the multi-server / multi-account
/// switcher.
protocol KeychainStore: AnyObject, Sendable {
    @discardableResult
    func saveToken(_ token: String) -> Bool
    func getToken() -> String?
    @discardableResult
    func deleteToken() -> Bool

    @discardableResult
    func saveToken(_ token: String, for account: String) -> Bool
    func getToken(for account: String) -> String?
    @discardableResult
    func deleteToken(for account: String) -> Bool
}
