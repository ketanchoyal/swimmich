import Foundation

/// A user-named saved search (gap #11). Immich has no server-side saved-search
/// endpoint, so these live in local UserDefaults — same approach as
/// `RecentSearchesStore`.
struct SavedSearch: Codable, Equatable, Identifiable {
    var id: String
    let name: String
    let query: String
}

/// Lightweight UserDefaults-backed store for saved searches. Pure value type
/// with an injectable `UserDefaults` so tests can isolate it.
struct SavedSearchesStore {
    private let defaults: UserDefaults
    private let key = "savedSearches"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [SavedSearch] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SavedSearch].self, from: data)) ?? []
    }

    func save(_ items: [SavedSearch]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
