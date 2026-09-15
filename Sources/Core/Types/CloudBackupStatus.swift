import Foundation

/// Whether this device has proof that an asset reached the server (G6).
///
/// The answer is the local backup ledger's, and it is deliberately partial:
/// the ledger only knows the assets it *handled* (uploaded, or confirmed as
/// duplicates by `bulk-upload-check`). An asset the server's timeline shows
/// but this device never uploaded is not "not backed up" — it is unknown, and
/// unknown is spelled `nil` by the lookup, never a third case. A grey "not on
/// the server" badge on someone else's photo would be a lie.
enum CloudBackupStatus: Equatable, Sendable {
    /// The ledger recorded this asset as uploaded, or as a duplicate the
    /// server already had — the server holds a copy.
    case uploaded
    /// The asset is in this device's Photos library and the ledger has no
    /// record of it: the only copy is here.
    case localOnly

    /// SF Symbol drawn on the thumbnail badge. Filled glyphs only — the
    /// outlined variants vanish under 12 pt on `.ultraThinMaterial`.
    var systemImage: String {
        switch self {
        case .uploaded: "checkmark.icloud"
        case .localOnly: "icloud.slash"
        }
    }

    /// VoiceOver label. The badge is a glyph alone, so this string carries the
    /// whole meaning — and it is never the SF Symbol's name.
    var localizedLabel: String {
        switch self {
        case .uploaded: String(localized: "Saved on server")
        case .localOnly: String(localized: "Only on this device")
        }
    }
}
