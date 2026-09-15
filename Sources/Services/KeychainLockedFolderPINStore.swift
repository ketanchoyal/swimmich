import Foundation

/// Keychain-backed `LockedFolderPINStoring`.
///
/// Delegates to the app's `KeychainStore` instead of talking to `Security`
/// itself: the entry then inherits `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
/// (the PIN never leaves the device, never syncs to iCloud) and the
/// delete-before-write of `KeychainStoreImpl`, which makes rotation and clearing
/// idempotent.
///
/// One **distinct account slot** per signed-in account: two servers must never
/// share a PIN, and the account id is the same key `SavedAccount.id` gives the
/// token store.
final class KeychainLockedFolderPINStore: LockedFolderPINStoring {
    private static let prefix = "lockedFolderPIN."

    private let keychain: any KeychainStore

    init(keychain: any KeychainStore) {
        self.keychain = keychain
    }

    private func slot(for account: String) -> String { Self.prefix + account }

    func storedPIN(for account: String) -> String? {
        keychain.getToken(for: slot(for: account))
    }

    @discardableResult
    func storePIN(_ pin: String, for account: String) -> Bool {
        keychain.saveToken(pin, for: slot(for: account))
    }

    @discardableResult
    func clearPIN(for account: String) -> Bool {
        keychain.deleteToken(for: slot(for: account))
    }
}
