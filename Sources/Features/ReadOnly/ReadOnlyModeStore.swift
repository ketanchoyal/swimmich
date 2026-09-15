import Foundation
import Observation

/// Device-level **read-only mode** (gap G17) — the "kid mode" of the upstream
/// Flutter client (`ReadOnlyModeNotifier`, `readonlyModeEnabled`).
///
/// One boolean, one writer, one reader:
/// - the UI toggles it (the Me hub's switch, the avatar's long press) and reads
///   `isEnabled` to draw the state;
/// - `ReadOnlyGuardClient` reads the same fact *without* touching this
///   `@MainActor` object (see `isEnabledIn(_:)`), because it asserts from
///   non-isolated `async` methods.
///
/// The value is persisted **before** it is published, exactly like the
/// upstream `setMode` — a kill right after the switch must not lose the
/// setting. It is a device preference read at launch, not a server flag: no
/// route carries it (the upstream client is client-only too).
@MainActor
@Observable
final class ReadOnlyModeStore {
    /// The upstream setting name (`AppSettingsEnum.readonlyModeEnabled`) — kept
    /// verbatim so the two clients describe the same preference.
    static let defaultsKey = "readOnlyModeEnabled"

    private let defaults: UserDefaults

    private(set) var isEnabled: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.defaultsKey)
    }

    /// Turns the mode on or off, persisting first and publishing after.
    func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: Self.defaultsKey)
        isEnabled = value
    }

    /// The second entry point of the same mutation (the avatar's long press).
    func toggle() {
        setEnabled(!isEnabled)
    }

    /// Reads the setting without hopping to the main actor.
    ///
    /// `ReadOnlyGuardClient.assertWritable()` runs inside non-isolated `async`
    /// methods of a `Sendable` decorator: it cannot await a `@MainActor`
    /// property, and it must not cache the answer either — the mode is flipped
    /// at runtime and the very next write has to see it.
    nonisolated static func isEnabledIn(_ defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }
}
