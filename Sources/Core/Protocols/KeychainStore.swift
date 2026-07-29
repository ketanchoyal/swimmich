import Foundation

/// Abstraction over the secure token store (Keychain in production).
protocol KeychainStore: AnyObject, Sendable {
    @discardableResult
    func saveToken(_ token: String) -> Bool
    func getToken() -> String?
    @discardableResult
    func deleteToken() -> Bool
}
