import Foundation
import SwiftUI

/// Timeline state: drives bucket-level pagination + columnar→object zip.
///
/// AC-006 + AC-013: loads buckets one at a time (no in-bucket pagination).
/// loadMore() advances to the next bucket, accumulates items, dedupes by id.
@Observable
final class TimelineViewModel {
    var buckets: [TimeBucketsResponseDto] = []
    var items: [AssetReactItem] = []
    var bucketIndex: Int = 0
    var isLoading: Bool = false
    var errorMessage: String?

    /// Loaded item IDs for O(1) dedup (FM-1 / AC-006).
    private(set) var loadedIds: Set<String> = []

    let client: any ImmichClient
    var filterIsFavorite: Bool?
    var filterIsTrashed: Bool?
    var filterVisibility: String?


    init(client: any ImmichClient) {
        self.client = client
    }

    var canLoadMore: Bool { bucketIndex < buckets.count }

    // MARK: - Selection mode (AC-201)

    /// True while the grid is in multi-select mode (long-press entry). Drives
    /// per-cell checkmark overlays + the selection toolbar.
    var selectionMode: Bool = false

    /// Ids the user has checked while in selection mode. Keyed by id so it
    /// survives pagination (`loadMore` appends items but selectedIds is stable).
    var selectedIds: Set<String> = []

    func enterSelectionMode() { selectionMode = true }

    func exitSelectionMode() {
        selectionMode = false
        selectedIds.removeAll()
    }

    /// Toggles membership of `id` in `selectedIds`. Callers enter selection
    /// mode first (long-press / Select button); the toggle itself is mode-agnostic.
    func toggleSelection(id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    // MARK: - Filter (AC-1010)

    /// Applies a timeline filter and reloads. No-op when the requested filter
    /// already matches, so the grid keeps its position between identical taps.
    @MainActor
    func setFilter(isFavorite: Bool?, visibility: String?) async {
        guard filterIsFavorite != isFavorite || filterVisibility != visibility else { return }
        filterIsFavorite = isFavorite
        filterVisibility = visibility
        await refresh()
    }

    // MARK: - Favorite toggle (AC-202)

    /// Toggles favorite on a single asset via `updateAsset`, then patches
    /// `items` in place via `AssetReactItem.with(isFavorite:)`.
    /// Try-then-mutate discipline: on throw the `items` array is left untouched
    /// and `errorMessage` is surfaced — UI never lies about server state.
    @MainActor
    func toggleFavorite(id: String) async {
        guard let current = items.first(where: { $0.id == id }) else { return }
        let newValue = !current.isFavorite
        do {
            let dto = UpdateAssetDto(isFavorite: newValue)
            _ = try await client.updateAsset(id: id, dto: dto)
            // Mutate only after the network call succeeded.
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx] = current.with(isFavorite: newValue)
            }
        } catch let e {
            errorMessage = e.localizedDescription
        }
    }

    // MARK: - Batch delete (AC-203 / AC-203b)

    /// Deletes all selected assets. On success removes them from `items` +
    /// `loadedIds` and exits selection mode. On throw, state is preserved so
    /// the user can retry (errorMessage set, selectedIds kept, selectionMode
    /// stays true). Empty selection is a no-op.
    @MainActor
    func deleteSelected() async {
        guard !selectedIds.isEmpty else { return }
        let ids = Array(selectedIds)
        do {
            // MUST throw-or-succeed before mutating anything.
            try await client.deleteAssets(ids: ids, force: false)
            items.removeAll { selectedIds.contains($0.id) }
            loadedIds.subtract(selectedIds)
            exitSelectionMode()
        } catch let e {
            errorMessage = e.localizedDescription
        }
    }

    // MARK: - Refresh (AC-204)

    /// Pull-to-refresh: exits selection, re-fetches buckets, reloads only the
    /// first bucket. Subsequent buckets come back on scroll (`loadMore`).
    @MainActor
    func archiveSelected() async {
        guard !selectedIds.isEmpty else { return }
        let ids = Array(selectedIds)
        do {
            try await client.bulkUpdateAssets(dto: AssetBulkUpdateDto(ids: ids, visibility: .archive))
            items.removeAll { selectedIds.contains($0.id) }
            loadedIds.subtract(selectedIds)
            exitSelectionMode()
        } catch let e {
            errorMessage = e.localizedDescription
        }
    }

    @MainActor
    func archive(id: String) async {
        do {
            try await client.bulkUpdateAssets(dto: AssetBulkUpdateDto(ids: [id], visibility: .archive))
            items.removeAll { $0.id == id }
            loadedIds.remove(id)
        } catch let e {
            errorMessage = e.localizedDescription
        }
    }

    @MainActor
    func refresh() async {
        exitSelectionMode()
        isLoading = true
        errorMessage = nil
        do {
            buckets = try await client.getTimeBuckets(isFavorite: filterIsFavorite, isTrashed: filterIsTrashed, personId: nil, withPartners: nil, visibility: filterVisibility, withStacked: nil)
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
    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            buckets = try await client.getTimeBuckets(isFavorite: filterIsFavorite, isTrashed: filterIsTrashed, personId: nil, withPartners: nil, visibility: filterVisibility, withStacked: nil)
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
            let columnar = try await client.getTimeBucket(timeBucket: bucket.timeBucket, personId: nil, withPartners: nil, visibility: filterVisibility, withStacked: nil)
            // AC-013: zip columnar into objects.
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
    /// Provided as a convenience for the grid view.
    ///
    /// Memoized: the Dictionary grouping + two sorts ran on every `body`
    /// evaluation (audit P1) even though the grouping only depends on `items`.
    /// The cache is invalidated by a `(count, lastId)` signature — every
    /// `items` mutation (append, replace-all, removeAll) changes one of these,
    /// so the cache is always fresh. In-place favorite patches change neither,
    /// but favorite state isn't part of the grouping (only `fileCreatedAt` is),
    /// so they correctly reuse the cache.
    private var _groupedByDay: [(day: String, items: [AssetReactItem])]?
    private var _groupedByDayKey: (count: Int, lastId: String?)?

    var groupedByDay: [(day: String, items: [AssetReactItem])] {
        let key = (count: items.count, lastId: items.last?.id)
        if let cacheKey = _groupedByDayKey, cacheKey.count == key.count, cacheKey.lastId == key.lastId,
           let cached = _groupedByDay {
            return cached
        }
        let groups = Dictionary(grouping: items) { item -> String in
            // ISO8601 YYYY-MM-DD prefix
            String(item.fileCreatedAt.prefix(10))
        }
        let computed = groups
            .map { (day: $0.key, items: $0.value.sorted { $0.fileCreatedAt > $1.fileCreatedAt }) }
            .sorted { $0.day > $1.day }
        _groupedByDay = computed
        _groupedByDayKey = key
        return computed
    }

    /// The interleaved month-header + day-group sections the grid renders,
    /// built from `groupedByDay` via `TimelineSectionBuilder.build`. Memoized
    /// on the same `(count, lastId)` signature as `groupedByDay` so the whole
    /// section pipeline (Dictionary + sorts + banner interleave) runs only
    /// when `items` changes, not per `body` evaluation (audit P1).
    private var _timelineSections: [TimelineSectionBuilder.Section]?
    private var _timelineSectionsKey: (count: Int, lastId: String?)?

    var timelineSections: [TimelineSectionBuilder.Section] {
        let key = (count: items.count, lastId: items.last?.id)
        if let cacheKey = _timelineSectionsKey, cacheKey.count == key.count, cacheKey.lastId == key.lastId,
           let cached = _timelineSections {
            return cached
        }
        let computed = TimelineSectionBuilder.build(from: groupedByDay)
        _timelineSections = computed
        _timelineSectionsKey = key
        return computed
    }

    // MARK: - Batch favorite (V7)

    /// Sets favorite uniformly across `ids` (skips ids already in the target
    /// state). Backs the selection-toolbar heart action. Same try-then-mutate
    /// discipline as `toggleFavorite`; first throw stops the batch and surfaces
    /// `errorMessage` without mutating the remaining items.
    /// - Returns: `true` when every id reached the target state, `false` on
    ///   error — callers exit selection mode only on success (audit fix).
    @MainActor
    @discardableResult
    func batchSetFavorite(_ ids: Set<String>, favorite value: Bool) async -> Bool {
        for id in ids {
            guard let current = items.first(where: { $0.id == id }), current.isFavorite != value else { continue }
            do {
                _ = try await client.updateAsset(id: id, dto: UpdateAssetDto(isFavorite: value))
                if let idx = items.firstIndex(where: { $0.id == id }) {
                    items[idx] = current.with(isFavorite: value)
                }
            } catch let e {
                errorMessage = e.localizedDescription
                return false
            }
        }
        return true
    }

    // MARK: - Single-asset delete (V9 context menu)

    /// Deletes a single asset by id (used by the cell context menu). Does NOT
    /// touch selection state — distinct from `deleteSelected` which operates on
    /// the selection set. Same try-then-mutate discipline.
    @MainActor
    func delete(id: String) async {
        do {
            try await client.deleteAssets(ids: [id], force: false)
            items.removeAll { $0.id == id }
            loadedIds.remove(id)
        } catch let e {
            errorMessage = e.localizedDescription
        }
    }
}
