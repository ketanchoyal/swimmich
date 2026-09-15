import Foundation

/// UserDefaults-backed store for the Search tab's two display options — the
/// sort order and the result-grid density. Same shape as `RecentSearchesStore`:
/// a pure value type with an injectable `UserDefaults`, so tests isolate it.
///
/// These are **not** filters: they never reach the server through the filter
/// projection, they do not count in the chips badge, and `clearFilters()`
/// leaves them alone.
struct SearchDisplayOptionsStore {
    private let defaults: UserDefaults
    private let sortKey = "searchSortOrder"
    private let densityKey = "searchGridDensity"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `.newestTaken` when the key is absent — the server's own default order.
    func loadSort() -> SearchSortOrder {
        guard let raw = defaults.string(forKey: sortKey) else { return .newestTaken }
        return SearchSortOrder(rawValue: raw) ?? .newestTaken
    }

    func saveSort(_ order: SearchSortOrder) {
        defaults.set(order.rawValue, forKey: sortKey)
    }

    /// `.comfortable` when the key is absent — the 3-column grid the tab
    /// shipped with, so an upgrade does not silently re-flow the results.
    func loadDensity() -> SearchGridDensity {
        guard let raw = defaults.string(forKey: densityKey) else { return .comfortable }
        return SearchGridDensity(rawValue: raw) ?? .comfortable
    }

    func saveDensity(_ density: SearchGridDensity) {
        defaults.set(density.rawValue, forKey: densityKey)
    }
}
