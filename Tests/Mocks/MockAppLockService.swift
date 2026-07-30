import Foundation
@testable import ImmichSwiftUI

/// Test double for `AppLockService`. Mirrors `AppLockViewModel` semantics
/// (FM-1/FM-2 mitigations) but lets tests inject the authentication result
/// without touching `LAContext`.
@MainActor
final class MockAppLockService: AppLockService, @unchecked Sendable {
    var isLocked: Bool
    var isEnabled: Bool
    var isAuthenticating: Bool = false

    /// Result returned by `authenticate()`. Default `true` for happy-path wiring tests.
    var authenticateResult: Bool

    init(isEnabled: Bool = false, isLocked: Bool? = nil, authenticateResult: Bool = true) {
        self.isEnabled = isEnabled
        self.isLocked = isLocked ?? isEnabled
        self.authenticateResult = authenticateResult
    }

    @discardableResult
    func authenticate() async -> Bool {
        isAuthenticating = true
        defer { isAuthenticating = false }
        if authenticateResult { isLocked = false }
        return authenticateResult
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { isLocked = false }
    }

    func lock() {
        guard !isAuthenticating, isEnabled else { return }
        isLocked = true
    }
}
