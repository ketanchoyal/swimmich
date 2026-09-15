import Foundation

/// Storage for the locked folder's PIN — the code Face ID is allowed to replay.
///
/// Deliberately a distinct type from `KeychainStore`: the folder's ViewModel
/// must never see a token API (a PIN is not a session, and storing one in the
/// session slot would make the two indistinguishable), and a test must be able
/// to stub it without touching the device Keychain.
///
/// Storing a PIN is **opt-in** per account: an empty store is the normal state,
/// and `storedPIN(for:)` returning nil simply means the biometric door has
/// nothing to replay.
protocol LockedFolderPINStoring: AnyObject, Sendable {
    /// The PIN remembered for `account`, or nil when none was stored.
    func storedPIN(for account: String) -> String?

    /// Remembers `pin` for `account`. Returns whether the keychain accepted it.
    @discardableResult
    func storePIN(_ pin: String, for account: String) -> Bool

    /// Forgets the PIN for `account` — used when the user turns the Face ID
    /// shortcut off, and when the server rejects a remembered PIN.
    @discardableResult
    func clearPIN(for account: String) -> Bool
}
