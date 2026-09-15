import SwiftUI

/// The two "recent" consultation pages of the official client (gap G13).
///
/// Upstream ships them as two 32-line pages that differ only by the timeline
/// they mount; here the whole difference is this enum — the sort axis asked of
/// the server, the title, the icon and the empty message. One view and one view
/// model read it, so the two screens cannot drift apart.
///
/// `orderBy` is what the server sorts the **buckets** by: `.takenAt` gives days
/// of capture ("recently taken"), `.createdAt` gives days of upload ("recently
/// added"). The upload axis has no equivalent in the search route — only
/// `GET /api/timeline/buckets` accepts it.
enum RecentAssetsMode: String, Sendable, CaseIterable {
    case taken
    case added

    /// Sort axis sent as `orderBy` on `GET /api/timeline/buckets`.
    var orderBy: AssetOrderBy {
        switch self {
        case .taken: .takenAt
        case .added: .createdAt
        }
    }

    /// Navigation title, hub row label, and the headline of both empty/error
    /// states — one key, three places, no room for divergence.
    var title: LocalizedStringKey {
        switch self {
        case .taken: "Recently Taken"
        case .added: "Recently Added"
        }
    }

    /// SF Symbol of the mode, shown on the hub row and on both states above.
    var systemImage: String {
        switch self {
        case .taken: "clock.arrow.circlepath"
        case .added: "arrow.up.circle"
        }
    }

    /// Shown when the server has no bucket at all for this axis.
    var emptyMessage: LocalizedStringKey {
        switch self {
        case .taken: "Photos you take will appear here."
        case .added: "Photos you add to the server will appear here."
        }
    }
}
