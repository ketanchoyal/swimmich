import Foundation
import Observation

/// Persisted `device album → server album` map, keyed by server account.
///
/// The account key is the upstream "album sync is per user" requirement: two
/// Immich accounts on the same device must not share their albums, and a
/// mapping recorded for one of them must never be applied to the other.
protocol AlbumSyncMappingStoring: AnyObject {
    /// The server album already paired with this device album, or nil when the
    /// pair has never been resolved.
    func serverAlbumID(userID: String, deviceAlbumID: String) -> String?
    /// Freezes the pair. Called once per device album — after this the mapping
    /// wins over any name match, which is what keeps a mirror pointed at the
    /// album it created even if the server album is later renamed or a
    /// homonym appears.
    func record(userID: String, deviceAlbumID: String, serverAlbumID: String)
    /// Drops every pair of one account, leaving other accounts untouched.
    func forgetAll(userID: String)
}

/// `UserDefaults`-backed mapping (`suiteName: "albumSync"` in production, a
/// per-test suite in unit tests), stored under `albumSyncMap` as
/// `[userID: [deviceAlbumID: serverAlbumID]]`.
///
/// The three protocol methods are `nonisolated`: their only writer is
/// `AlbumSyncService`, an actor that serialises every access, and
/// `UserDefaults` is itself thread-safe, so a lock here would add nothing. The
/// class stays `@MainActor` so the settings screen can observe a mapping
/// change without hopping.
@Observable
@MainActor
final class AlbumSyncStore: AlbumSyncMappingStoring {
    @ObservationIgnored nonisolated(unsafe) let defaults: UserDefaults

    nonisolated static let mapKey = "albumSyncMap"

    init(suiteName: String = "albumSync") {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    nonisolated func serverAlbumID(userID: String, deviceAlbumID: String) -> String? {
        Self.map(from: defaults)[userID]?[deviceAlbumID]
    }

    nonisolated func record(userID: String, deviceAlbumID: String, serverAlbumID: String) {
        var map = Self.map(from: defaults)
        map[userID, default: [:]][deviceAlbumID] = serverAlbumID
        defaults.set(map, forKey: Self.mapKey)
    }

    nonisolated func forgetAll(userID: String) {
        var map = Self.map(from: defaults)
        map.removeValue(forKey: userID)
        defaults.set(map, forKey: Self.mapKey)
    }

    nonisolated private static func map(from defaults: UserDefaults) -> [String: [String: String]] {
        defaults.dictionary(forKey: mapKey) as? [String: [String: String]] ?? [:]
    }
}
