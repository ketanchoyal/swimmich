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

    init(client: any ImmichClient) {
        self.client = client
    }

    var canLoadMore: Bool { bucketIndex < buckets.count }

    @MainActor
    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            buckets = try await client.getTimeBuckets(isFavorite: filterIsFavorite, isTrashed: filterIsTrashed)
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
            let columnar = try await client.getTimeBucket(timeBucket: bucket.timeBucket)
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
    var groupedByDay: [(day: String, items: [AssetReactItem])] {
        let groups = Dictionary(grouping: items) { item -> String in
            // ISO8601 YYYY-MM-DD prefix
            String(item.fileCreatedAt.prefix(10))
        }
        return groups
            .map { (day: $0.key, items: $0.value.sorted { $0.fileCreatedAt > $1.fileCreatedAt }) }
            .sorted { $0.day > $1.day }
    }
}
