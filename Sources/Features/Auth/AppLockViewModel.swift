import Foundation
import LocalAuthentication
import SwiftUI

/// Concrete app-lock state. Wraps LocalAuthentication with an injectable
/// evaluator so unit tests never touch LAContext.
///
/// Source of truth for `isEnabled` lives in UserDefaults (key
/// `app_lock_enabled`); the matching `@AppStorage` declaration on
/// `BackupSettingsView` keeps the SwiftUI Toggle in sync. `isLocked` /
/// `isAuthenticating` are in-memory `@Observable` state.
@Observable
@MainActor
final class AppLockViewModel: AppLockService {
    nonisolated static let enabledKey = "app_lock_enabled"

    var isEnabled: Bool
    var isLocked: Bool = false
    var isAuthenticating: Bool = false

    private let evaluator: @Sendable () async -> Bool

    init(evaluator: @Sendable @escaping () async -> Bool = AppLockViewModel.systemEvaluator) {
        self.evaluator = evaluator
        // AC-113: fresh launch must be locked when the feature is enabled,
        // otherwise force-quit bypasses the gate.
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        self.isLocked = self.isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        // FM-2: turning the feature off must also release any active lock,
        // otherwise the user stays trapped behind the overlay.
        if !enabled { isLocked = false }
    }

    func lock() {
        // FM-1: never re-lock while a biometric prompt is already in flight
        // (LAContext flips scenePhase to .inactive during evaluation).
        guard !isAuthenticating else { return }
        guard isEnabled else { return }
        isLocked = true
    }

    @discardableResult
    func authenticate() async -> Bool {
        isAuthenticating = true
        defer { isAuthenticating = false }
        let ok = await evaluator()
        if ok { isLocked = false }
        return ok
    }

    /// Production evaluator: Face ID / Touch ID with passcode fallback via
    /// `.deviceOwnerAuthentication` (AC-106, FM-3 — works on simulators
    /// without enrolled biometrics because the policy includes the device
    /// passcode).
    static let systemEvaluator: @Sendable () async -> Bool = {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            return false
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "Unlock PhotoVault")
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
