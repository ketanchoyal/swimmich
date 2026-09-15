import Foundation
import Observation

/// Persisted Free Up Space preferences, in an injectable UserDefaults suite
/// ("cleanupSettings" in production, a per-test suite in unit tests) — the
/// structural twin of `BackupSettingsStore`.
///
/// Everything here mirrors upstream's `CleanupConfig` +
/// `SettingsRepository` writers. The cutoff is stored as *days ago* rather than
/// as an absolute date: a persisted date would slowly drift into the past (or
/// into the future, which would make every asset a candidate), while "90 days"
/// keeps meaning 90 days on the next launch.
@Observable
@MainActor
final class CleanupSettingsStore {
    @ObservationIgnored let defaults: UserDefaults

    /// `nil` = no date chosen yet, which is upstream's `cutoffDaysAgo == -1`:
    /// `scanAssets()` does nothing at all until a date exists.
    var cutoffDate: Date? {
        didSet { defaults.set(Self.daysAgo(from: cutoffDate), forKey: Self.cutoffKey) }
    }

    var keepFavorites: Bool {
        didSet { defaults.set(keepFavorites, forKey: Self.favoritesKey) }
    }

    var keepMediaType: CleanupKeepMediaType {
        didSet { defaults.set(keepMediaType.rawValue, forKey: Self.mediaTypeKey) }
    }

    /// Albums (Photos `localIdentifier`s and `BackupAlbum.SmartID` values) whose
    /// assets stay on device regardless of the cutoff.
    var keepAlbumIDs: Set<String> {
        didSet { defaults.set(Array(keepAlbumIDs).sorted(), forKey: Self.albumsKey) }
    }

    /// One-shot guard for the messaging-app defaults. Without it the pre-ticked
    /// albums would come back on every appearance, undoing an explicit uncheck.
    var defaultsInitialized: Bool {
        didSet { defaults.set(defaultsInitialized, forKey: Self.initializedKey) }
    }

    static let cutoffKey = "cleanupCutoffDaysAgo"
    static let favoritesKey = "cleanupKeepFavorites"
    static let mediaTypeKey = "cleanupKeepMediaType"
    static let albumsKey = "cleanupKeepAlbumIds"
    static let initializedKey = "cleanupDefaultsInitialized"

    /// Album names that mean "this is the messages app's own folder" — media
    /// re-encoded by WhatsApp and friends, which the user almost never revisits
    /// in Photos. Matched by `contains` on the lowercased name, verbatim from
    /// upstream `CleanupService.getDefaultKeepAlbumIds`.
    static let messagingAppNames = [
        "whatsapp", "telegram", "signal", "messenger", "viber", "wechat", "line",
    ]

    init(suiteName: String = "cleanupSettings") {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.defaults = defaults
        let days = defaults.object(forKey: Self.cutoffKey) as? Int ?? -1
        cutoffDate = days < 0 ? nil : Calendar.current.date(byAdding: .day, value: -days, to: Date())
        keepFavorites = defaults.object(forKey: Self.favoritesKey) as? Bool ?? true
        keepMediaType = CleanupKeepMediaType(rawValue: defaults.string(forKey: Self.mediaTypeKey) ?? "") ?? .none
        keepAlbumIDs = Set(defaults.stringArray(forKey: Self.albumsKey) ?? [])
        defaultsInitialized = defaults.bool(forKey: Self.initializedKey)
    }

    /// Pre-ticks the messaging apps' albums, **once ever** — upstream's
    /// `applyDefaultAlbumSelections` behind its `defaultsInitialized` guard.
    func applyDefaultKeepAlbums(_ albums: [BackupAlbum]) {
        guard !defaultsInitialized else { return }
        for album in albums where Self.isMessagingAlbum(album.name) {
            keepAlbumIDs.insert(album.id)
        }
        defaultsInitialized = true
    }

    /// Upstream's `cleanupStaleAlbumIds`: a kept album that no longer exists
    /// would otherwise stay in the set forever, silently protecting nothing and
    /// showing a filter the user cannot see or uncheck.
    func pruneStaleAlbums(existing: Set<String>) {
        let stale = keepAlbumIDs.subtracting(existing)
        guard !stale.isEmpty else { return }
        keepAlbumIDs.subtract(stale)
    }

    static func isMessagingAlbum(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return messagingAppNames.contains { lowered.contains($0) }
    }

    /// `-1` when no date is set, else whole days between `date` and now.
    private static func daysAgo(from date: Date?) -> Int {
        guard let date else { return -1 }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? -1
    }
}
