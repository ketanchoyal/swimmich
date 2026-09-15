import Foundation
import SwiftUI

/// Trash tab state: bucket-level pagination over `isTrashed=true` assets +
/// restore / restore-all / delete-permanently / empty-trash operations.
///
/// Mirrors `TimelineViewModel` pagination semantics (loadNextBucket zip +
/// loadedIds dedup). All mutating operations follow try-then-mutate
/// discipline: nothing local is touched before the network call succeeds.
///
/// AC-300..AC-314.
@Observable
final class TrashViewModel {
    var buckets: [TimeBucketsResponseDto] = []
    var items: [AssetReactItem] = []
    var bucketIndex: Int = 0
    var isLoading: Bool = false
    var errorMessage: String?

    /// Loaded item IDs for O(1) dedup (mirrors TimelineViewModel.loadedIds).
    private(set) var loadedIds: Set<String> = []

    let client: any ImmichClient

    init(client: any ImmichClient) {
        self.client = client
    }

    var canLoadMore: Bool { bucketIndex < buckets.count }

    // MARK: - Loading (AC-300 / AC-305)

    @MainActor
    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            buckets = try await client.getTimeBuckets(isFavorite: nil, isTrashed: true, personId: nil, withPartners: nil, visibility: nil, withStacked: nil, orderBy: nil)
            bucketIndex = 0
            items = []
            loadedIds = []
            await loadNextBucket()
        } catch let e {
            errorMessage = e.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            buckets = try await client.getTimeBuckets(isFavorite: nil, isTrashed: true, personId: nil, withPartners: nil, visibility: nil, withStacked: nil, orderBy: nil)
            bucketIndex = 0
            items = []
            loadedIds = []
            await loadNextBucket()
        } catch let e {
            errorMessage = e.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    func loadMore() async {
        guard !isLoading else { return }
        await loadNextBucket()
    }

    @MainActor
    private func loadNextBucket() async {
        guard bucketIndex < buckets.count else { return }
        let bucket = buckets[bucketIndex]
        do {
            let columnar = try await client.getTimeBucket(timeBucket: bucket.timeBucket, personId: nil, withPartners: nil, visibility: nil, withStacked: nil)
            let zipped = AssetReactItem.zip(columnar)
            for item in zipped where !loadedIds.contains(item.id) {
                items.append(item)
                loadedIds.insert(item.id)
            }
            bucketIndex += 1
        } catch let e {
            errorMessage = e.localizedDescription
        }
    }

    /// Grouped view of loaded items by day (fileCreatedAt date portion).
    var groupedByDay: [(day: String, items: [AssetReactItem])] {
        let groups = Dictionary(grouping: items) { item -> String in
            String(item.fileCreatedAt.prefix(10))
        }
        return groups
            .map { (day: $0.key, items: $0.value.sorted { $0.fileCreatedAt > $1.fileCreatedAt }) }
            .sorted { $0.day > $1.day }
    }

    // MARK: - Restore (AC-301 / AC-302 / AC-313)

    /// Restores a single asset. Removes it from `items` + `loadedIds` only
    /// after the network call succeeds (try-then-mutate). On throw the local
    /// state is preserved and `errorMessage` is surfaced.
    @MainActor
    func restore(id: String) async {
        do {
            _ = try await client.restoreTrashAssets(ids: [id])
            items.removeAll { $0.id == id }
            loadedIds.remove(id)
        } catch let e {
            errorMessage = e.localizedDescription
        }
    }

    /// Restores every trashed asset. Clears all pagination state on success
    /// (items, loadedIds, buckets, bucketIndex reset to 0).
    @MainActor
    func restoreAll() async {
        do {
            _ = try await client.restoreAllTrash()
            resetAllState()
        } catch let e {
            errorMessage = e.localizedDescription
        }
    }

    // MARK: - Permanent delete (AC-303 / AC-314)

    /// Permanently deletes a single asset via `deleteAssets(force: true)`.
    /// Removes it from `items` + `loadedIds` only after the network call
    /// succeeds. On throw the local state is preserved.
    @MainActor
    func deletePermanently(id: String) async {
        do {
            try await client.deleteAssets(ids: [id], force: true)
            items.removeAll { $0.id == id }
            loadedIds.remove(id)
        } catch let e {
            errorMessage = e.localizedDescription
        }
    }

    // MARK: - Empty trash (AC-304)

    /// Empties the entire trash. Clears all pagination state on success.
    /// On throw EVERY field is preserved (items, loadedIds, buckets,
    /// bucketIndex) so the UI keeps showing what may still be trashed.
    @MainActor
    func emptyTrash() async {
        do {
            _ = try await client.emptyTrash()
            resetAllState()
        } catch let e {
            errorMessage = e.localizedDescription
        }
    }

    /// Centralised state reset used by `restoreAll` + `emptyTrash` success
    /// paths. Each field is set so tests can assert every one is cleared.
    private func resetAllState() {
        items = []
        loadedIds = []
        buckets = []
        bucketIndex = 0
    }
}
