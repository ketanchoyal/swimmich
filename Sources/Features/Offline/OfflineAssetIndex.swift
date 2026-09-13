import Foundation
import Observation

/// UI-side mirror of `OfflineAssetStore`'s index.
///
/// Why a separate observable object instead of reading the store directly:
/// the store is an `actor` (correct — it mutates files and index off the main
/// thread), but a SwiftUI `body` must answer "is this asset cached?" and
/// "where is its file?" **synchronously**, once per cell. `AssetThumbnailCell`
/// is instantiated from six different grids, so threading a parameter through
/// all of them would be forgotten at one; the environment is the right carrier.
///
/// The view model keeps this in sync: every mutation goes through the store and
/// then calls `refresh(from:)`, so the badge, the offline screen and the disk
/// never disagree.
@MainActor
@Observable
final class OfflineAssetIndex {
    /// Cached assets by id, most recent first (display order).
    private(set) var items: [CachedAssetInfo] = []

    /// Lookup tables for the per-cell reads below. Deliberately **observed**
    /// (not `@ObservationIgnored`): a `body` that calls `isCached(_:)` must
    /// re-evaluate when the cache changes, and the only dependency observation
    /// can see is the property the lookup reads.
    private var byID: [String: CachedAssetInfo] = [:]
    private var urlsByID: [String: URL] = [:]

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    func isCached(_ assetID: String) -> Bool { byID[assetID] != nil }

    func info(_ assetID: String) -> CachedAssetInfo? { byID[assetID] }

    /// Local file for an asset, or nil when it isn't cached. A `body` can call
    /// this without awaiting anything.
    func localURL(for assetID: String) -> URL? { urlsByID[assetID] }

    /// Rebuilds the mirror from the store. Awaits the actor once, then the
    /// per-cell lookups above stay synchronous.
    func refresh(from store: OfflineAssetStore) async {
        let cached = await store.allCached()
        let folder = store.folderURL
        items = cached
        byID = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        urlsByID = Dictionary(uniqueKeysWithValues: cached.map {
            ($0.id, folder.appendingPathComponent($0.fileName))
        })
    }

    /// Drops an asset from the mirror without a store round-trip, so a swipe
    /// removes the row immediately.
    func remove(_ assetID: String) {
        guard byID.removeValue(forKey: assetID) != nil else { return }
        urlsByID[assetID] = nil
        items.removeAll { $0.id == assetID }
    }

    func removeAll() {
        byID.removeAll()
        urlsByID.removeAll()
        items.removeAll()
    }
}
