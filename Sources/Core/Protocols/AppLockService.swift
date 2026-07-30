import Foundation

/// Abstraction over device-local app lock (Face ID / Touch ID / passcode).
/// `@MainActor` matches the `AppLockViewModel` impl; conformers are UI-layer
/// `@Observable` view models.
@MainActor
protocol AppLockService: AnyObject {
    var isLocked: Bool { get }
    var isEnabled: Bool { get }
    var isAuthenticating: Bool { get }
    func authenticate() async -> Bool
    func setEnabled(_ enabled: Bool)
    func lock()
}
