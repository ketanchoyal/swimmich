import Foundation
@testable import ImmichSwiftUI

final class MockKeychainStore: KeychainStore, @unchecked Sendable {
    private let lock = NSLock()
    private var _tokens: [String: String] = [:]

    private static let legacyAccount = "accessToken"

    var savedToken: String? {
        lock.lock(); defer { lock.unlock() }
        return _tokens[Self.legacyAccount]
    }

    var allTokens: [String: String] {
        lock.lock(); defer { lock.unlock() }
        return _tokens
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
        lock.lock(); defer { lock.unlock() }
        _tokens[account] = token
        return true
    }

    func getToken(for account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return _tokens[account]
    }

    @discardableResult
    func deleteToken(for account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        _tokens[account] = nil
        return true
    }
}
