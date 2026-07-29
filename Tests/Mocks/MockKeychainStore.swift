import Foundation
@testable import ImmichSwiftUI

final class MockKeychainStore: KeychainStore, @unchecked Sendable {
    private let lock = NSLock()
    private var _token: String?

    var savedToken: String? { lock.lock(); defer { lock.unlock() }; return _token }

    @discardableResult
    func saveToken(_ token: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        _token = token
        return true
    }

    func getToken() -> String? {
        lock.lock(); defer { lock.unlock() }
        return _token
    }

    @discardableResult
    func deleteToken() -> Bool {
        lock.lock(); defer { lock.unlock() }
        _token = nil
        return true
    }
}
