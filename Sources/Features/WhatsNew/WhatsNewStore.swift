import Foundation

/// The only state the "What's New" feature persists: the release the user has
/// already seen (gap G23).
///
/// A `UserDefaults` suite is injected rather than reached for, on the
/// `BackupSettingsStore(suiteName:)` pattern: tests get a throwaway suite, the
/// app gets `.standard`. Nothing else is stored — the batch itself is embedded,
/// and a "dismissed for this session" flag would re-present the sheet at the
/// next launch, which is exactly what "seen" means here.
struct WhatsNewStore {
    /// Read by `AuthViewModel.applySession` too: adding an account marks the
    /// current batch seen, so a brand-new account never gets a batch that was
    /// authored before it existed.
    static let seenReleaseKey = "whatsNewSeenRelease"

    let defaults: UserDefaults

    /// The release already presented, or `"0.0.0"` for a user who has seen
    /// nothing — every real release is newer, which is what makes the first
    /// launch show the batch.
    var seenRelease: String {
        defaults.string(forKey: Self.seenReleaseKey) ?? "0.0.0"
    }

    /// An empty catalog never presents: with no cards there is nothing to
    /// announce, and the sheet would open a blank screen.
    var shouldShow: Bool {
        !FeatureHighlightCatalog.all.isEmpty
            && FeatureHighlightCatalog.isNewer(FeatureHighlightCatalog.release, than: seenRelease)
    }

    func markSeen() {
        defaults.set(FeatureHighlightCatalog.release, forKey: Self.seenReleaseKey)
    }
}
