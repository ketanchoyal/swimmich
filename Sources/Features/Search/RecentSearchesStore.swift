import Foundation

/// Lightweight UserDefaults-backed store for recent search terms.
/// Pure value type with an injectable `UserDefaults` so tests can isolate it.
struct RecentSearchesStore {
    private let defaults: UserDefaults
    private let key = "recentSearches"
    private let capacity = 8

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    /// Persists items, newest-first, capped at `capacity`.
    func save(_ items: [String]) {
        defaults.set(Array(items.prefix(capacity)), forKey: key)
    }
}
