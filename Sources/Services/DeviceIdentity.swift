import Foundation

/// Stable identifier for this app installation, sent as the upload's `deviceId`
/// so the server can attribute assets to a device (the web UI's device filter,
/// and the per-device asset listing the docs recommend for reconciliation).
///
/// Deliberately NOT `identifierForVendor`: that value is derived per vendor and
/// changes when the last app of the vendor is removed, which would silently
/// split one device's uploads across two identities and orphan the older half.
/// A UUID we generate once and keep in UserDefaults stays put for the
/// installation's lifetime — the same contract the Flutter client uses.
enum DeviceIdentity {
    static let defaultsKey = "immichDeviceId"

    /// Read lazily so a test can inject its own `UserDefaults` before first use.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: String?

    /// This installation's id, generated and persisted on first access.
    static var current: String {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            cached = existing
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: defaultsKey)
        cached = generated
        return generated
    }
}
