import Foundation

/// One row in the Explore Places list — a distinct city with its representative
/// asset (for the hero thumbnail), location metadata, most-recent date, and
/// (lazily loaded) photo count. Identifiable by city name (server returns one
/// representative asset per distinct city via GET /search/cities).
struct ExplorePlace: Identifiable, Equatable {
    let id: String          // city name (stable identity)
    let city: String
    let state: String?
    let country: String?
    let date: Date?         // representative asset's dateTimeOriginal
    let assetId: String     // representative asset (thumbnail URL source)
    let thumbhash: String?
    var photoCount: Int?    // nil = count still loading

    /// Subtitle: "State, Country" (whichever parts exist), joined.
    var subtitle: String {
        [state, country].compactMap { $0 }.joined(separator: ", ")
    }

    /// Flag emoji derived client-side from `country`, or nil if unresolved.
    var flag: String? { CountryFlag.emoji(forCountryName: country) }
}

/// Search feature ViewModel — covers cahier §6 MVP:
/// - free-text metadata search (`POST /api/search/metadata`)
/// - CLIP semantic smart search (`POST /api/search/smart`)
/// - curated explore suggestions (`GET /api/search/explore`)
///
/// People / faces (L136) + object detection (L137) deferred to a future
/// iteration — searchMetadata(personIds:) already supports the drill-down.
///
/// `@Observable @MainActor` mirrors TimelineViewModel / TrashViewModel.
@Observable
@MainActor
final class SearchViewModel {
    enum SearchMode: Hashable { case metadata, smart }
    enum ViewMode: Hashable { case results, explore, map }

    /// EXIF field a user can drill into from an Explore card. Maps the server's
    /// `fieldName` ("exifInfo.city" …) onto the matching `MetadataSearchDto`
    /// property so a tap under "Cameras" searches `make`, not `city`.
    enum ExploreField: String {
        case city, country, make, model, state, lensModel

        /// Parses a raw Immich `fieldName` ("exifInfo.city" → `.city`).
        /// Returns nil for unrecognized fields (card tap no-ops gracefully).
        init?(rawFieldName: String) {
            // Strip the "exifInfo." prefix; map the remainder to the enum case.
            let key = rawFieldName.hasPrefix("exifInfo.")
                ? String(rawFieldName.dropFirst("exifInfo.".count))
                : rawFieldName
            self.init(rawValue: key)
        }

        /// Writes `value` into the matching EXIF field on `dto`.
        func apply(_ value: String, to dto: inout MetadataSearchDto) {
            switch self {
            case .city: dto.city = value
            case .country: dto.country = value
            case .make: dto.make = value
            case .model: dto.model = value
            case .state: dto.state = value
            case .lensModel: dto.lensModel = value
            }
        }
    }

    let client: any ImmichClient
    private let recentsStore: RecentSearchesStore
    private let savedStore: SavedSearchesStore

    // Inputs
    var query: String = ""
    var searchMode: SearchMode = .smart
    var viewMode: ViewMode = .results
    /// Active Explore drill-down filter (AC-404b, generalized to any field).
    /// When non-nil, metadata `search()` ignores free-text `query` and filters
    /// by this field instead. Public for `recordRecentSearch` / view wiring.
    var pendingExploreFilter: (ExploreField, String)? = nil

    /// Star-rating filter (star-ratings) — `nil` = no rating constraint.
    /// Sticky by design: it survives text edits and Explore drill-downs; only
    /// "Any rating" in the filter menu and `clearSearch()` clear it.
    var ratingFilter: Int?
    /// Convenience: the city value when the active filter is a city (legacy
    /// accessor + tests). Nil for non-city filters or when no filter is set.
    var selectedCity: String? {
        if case (.city, let value)? = pendingExploreFilter { return value }
        return nil
    }

    // Results
    private(set) var results: [AssetReactItem] = []
    private(set) var loadedIds: Set<String> = []
    private(set) var currentPage: Int = 1
    private(set) var nextPage: String? = nil
    var canLoadMore: Bool { nextPage != nil }
    var hasSearched: Bool = false

    // Explore (AC-404) — Places list powered by GET /search/cities.
    private(set) var exploreData: [SearchExploreResponseDto] = []
    /// The full Places list (every city, no ≥5-photo floor), enriched with
    /// per-place photo counts. Drives the Explore view. `photoCount == nil`
    /// means the count is still loading for that place.
    private(set) var explorePlaces: [ExplorePlace] = []

    // Recent searches (UX)
    private(set) var recentSearches: [String] = []

    // Saved searches (gap #11, local)
    private(set) var savedSearches: [SavedSearch] = []

    // UI state
    private(set) var isLoading: Bool = false
    var errorMessage: String? = nil

    /// Debounce for live search (queryDidChange). Tests override with `.zero`.
    var debounceInterval: Duration = .milliseconds(400)

    /// Max recent searches kept in memory + persisted.
    private let recentsCapacity = 8

    /// Last query actually dispatched (or "") so programmatic query writes
    /// (searchRecent, clear) don't trigger a second debounced search.
    private var lastQueried = ""
    private var searchTask: Task<Void, Never>?
    /// Bumped on every new search intent; guards stale in-flight responses
    /// from overwriting the idle state after clear/reset.
    private var searchGeneration = 0

    init(client: any ImmichClient, recents: RecentSearchesStore = RecentSearchesStore(), saved: SavedSearchesStore = SavedSearchesStore()) {
        self.client = client
        self.recentsStore = recents
        self.savedStore = saved
        self.recentSearches = recents.load()
        self.savedSearches = saved.load()
    }

    // MARK: - Live search (debounced)

    /// Called by the View on `onChange(of: query)`. Debounces free-text input;
    /// an empty query resets to the idle (suggestions) state instead of
    /// dispatching. Programmatic writes already searched are skipped.
    func queryDidChange() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != lastQueried else { return }
        searchGeneration += 1
        guard !trimmed.isEmpty else {
            resetToIdle()
            lastQueried = ""
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            // Wait for any in-flight search/loadMore to settle so the fresh
            // query wins instead of being swallowed by the isLoading guard.
            while isLoading && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    // MARK: - Search (AC-401 / AC-401b / AC-402 / AC-405)

    /// Reset + dispatch a fresh search (page=1).
    func search() async {
        guard !isLoading else { return }
        searchTask?.cancel()
        let gen = searchGeneration + 1
        searchGeneration = gen
        lastQueried = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // A free-text search supersedes any Explore drill-down filter — if the
        // user types after tapping a card, the typed query wins and the EXIF
        // field filter is cleared. (`searchByExplore` calls `search()` with an
        // empty query but pre-sets the filter, so we only clear when there is
        // actual free-text to run.)
        if !lastQueried.isEmpty { pendingExploreFilter = nil }
        isLoading = true
        defer { isLoading = false }

        // Reset pagination state (AC-404b: not accumulated).
        results = []
        loadedIds = []
        currentPage = 1
        nextPage = nil
        errorMessage = nil
        hasSearched = true

        do {
            let resp = try await dispatchSearch(page: 1)
            // A superseded search (newer keystroke / clear / city tap bumped the
            // generation) must never overwrite the fresher state. We don't check
            // `Task.isCancelled` here because `search()` runs inside the very
            // `searchTask` it cancels on line above — that self-cancel is benign
            // (it only clears the debounce sleep) and must not short-circuit a
            // successful response. Cancellation from a *newer* search is caught
            // by the generation guard.
            guard gen == searchGeneration else { return }
            applyResponse(resp)
            recordRecentSearch()
        } catch {
            // Cancellation is a normal outcome of debounced live search
            // (rapid typing cancels the in-flight request). Never surface it.
            if isCancellation(error) { return }
            guard gen == searchGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// AC-406 / AC-406b / AC-406c: load next page when canLoadMore.
    func loadMore() async {
        guard !isLoading, let _ = nextPage else { return }
        let gen = searchGeneration
        isLoading = true
        defer { isLoading = false }

        let nextPageNumber = currentPage + 1
        do {
            let resp = try await dispatchSearch(page: nextPageNumber)
            // Only apply if no newer search superseded this pagination.
            guard gen == searchGeneration else { return }
            currentPage = nextPageNumber
            applyResponse(resp, append: true)
        } catch {
            if isCancellation(error) { return }
            guard gen == searchGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Clears results back to the idle state (empty query path).
    func clearSearch() {
        query = ""
        ratingFilter = nil
        searchTask?.cancel()
        searchGeneration += 1
        resetToIdle()
        lastQueried = ""
    }

    /// Sets (or clears) the star-rating filter and re-runs the search.
    ///
    /// Metadata mode is forced when a value is set: `SmartSearchDto` carries no
    /// filter field, so a rating filter under Smart search would be dropped
    /// silently. Values outside the server's `1...5` scale (including `0`, which
    /// is invalid since v3) mean "no filter" rather than a request the server
    /// would reject.
    func setRatingFilter(_ value: Int?) async {
        let valid = value.flatMap { (1...5).contains($0) ? $0 : nil }
        ratingFilter = valid
        if valid != nil { searchMode = .metadata }
        await search()
    }

    /// Recent-search chip tap: write the term into the field, then search
    /// immediately (the subsequent onChange is deduped via `lastQueried`).
    func searchRecent(_ term: String) async {
        searchTask?.cancel()
        query = term
        await search()
    }

    // MARK: - Saved searches (gap #11, local persistence)

    /// Saves the current free-text query under a name. No-op for an empty
    /// query or duplicate name (updates the existing entry instead).
    func saveCurrentSearch(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedQuery.isEmpty else { return }
        var saved = savedSearches
        saved.removeAll { $0.name == trimmedName || $0.id == trimmedName }
        saved.insert(SavedSearch(id: UUID().uuidString, name: trimmedName, query: trimmedQuery), at: 0)
        savedSearches = saved
        savedStore.save(saved)
    }

    func deleteSavedSearch(id: String) {
        savedSearches.removeAll { $0.id == id }
        savedStore.save(savedSearches)
    }

    /// Saved-search tap: write its query into the field, then search.
    func searchSaved(_ saved: SavedSearch) async {
        searchTask?.cancel()
        query = saved.query
        await search()
    }

    private func resetToIdle() {
        results = []
        loadedIds = []
        currentPage = 1
        nextPage = nil
        errorMessage = nil
        hasSearched = false
    }

    private func recordRecentSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, pendingExploreFilter == nil, !results.isEmpty else { return }
        var recents = recentSearches
        recents.removeAll { $0 == trimmed }
        recents.insert(trimmed, at: 0)
        recentSearches = Array(recents.prefix(recentsCapacity))
        recentsStore.save(recentSearches)
    }

    /// `true` when `error` represents cooperative Task cancellation — either a
    /// `URLError(.cancelled)` (what `URLSession.data(for:)` throws when its
    /// enclosing Task is cancelled) wrapped as `APIError.network`, or a raw
    /// `CancellationError`. Cancellation is a normal outcome of debounced live
    /// search and must never surface as a user-visible error.
    ///
    /// We check only the *error type*, not `Task.isCancelled`: `search()` runs
    /// inside the very `searchTask` it cancels (`:100`), so `Task.isCancelled`
    /// is true for the current search even when the dispatched request itself
    /// failed with a genuine (non-cancellation) error.
    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let api = error as? APIError, api.isCancellation { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }

    /// Builds the right DTO for the current mode + dispatches.
    /// `pendingExploreFilter` overrides `query` for metadata mode, routed to
    /// the matching EXIF field (AC-404b / AC-406c — generalized beyond city).
    private func dispatchSearch(page: Int) async throws -> SearchResponseDto {
        switch searchMode {
        case .metadata:
            var dto = MetadataSearchDto(query: query, page: page)
            if let (field, value) = pendingExploreFilter {
                dto.query = nil
                field.apply(value, to: &dto)
            }
            dto.rating = ratingFilter
            return try await client.searchMetadata(dto: dto)
        case .smart:
            let dto = SmartSearchDto(query: query, page: page)
            return try await client.searchSmart(dto: dto)
        }
    }

    private func applyResponse(_ resp: SearchResponseDto, append: Bool = false) {
        nextPage = resp.assets.nextPage
        let newItems = resp.assets.items.compactMap { item -> AssetReactItem? in
            // Dedup via loadedIds (AC-406).
            guard !loadedIds.contains(item.id) else { return nil }
            loadedIds.insert(item.id)
            return AssetReactItem(from: item)
        }
        if append {
            results.append(contentsOf: newItems)
        } else {
            results = newItems
        }
    }

    // MARK: - Explore (AC-404a / AC-404c)

    /// Explore is considered stale after this interval; the Search tab is now
    /// persistent, so a once-per-VM fetch would never reflect new uploads.
    private let exploreStaleInterval: TimeInterval = 5 * 60
    private var exploreLoadedAt: Date? = nil
    /// Max concurrent per-city count fetches during enrichment.
    private let exploreCountConcurrency = 6

    /// Loads the Places list if empty or older than `exploreStaleInterval`
    /// (AC-404a). Idempotent within the freshness window so tab-focus
    /// re-entry doesn't spam the server (AC-404c). Pass `force: true` to
    /// bypass the freshness check (used by pull-to-refresh).
    ///
    /// Flow: GET /search/cities → map to ExplorePlace (sorted by most-recent
    /// date desc so the freshest trip lands on top immediately) → fan out
    /// POST /search/statistics per city (concurrency-limited) and update each
    /// place's photoCount as it arrives, re-sorting by count desc.
    func loadExplore(force: Bool = false) async {
        guard !isLoading else { return }
        let stale = exploreLoadedAt.map { Date().timeIntervalSince($0) > exploreStaleInterval } ?? true
        guard force || explorePlaces.isEmpty || stale else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let assets = try await client.getAssetsByCity()
            explorePlaces = Self.buildPlaces(from: assets)
            exploreLoadedAt = Date()
            if !explorePlaces.isEmpty { errorMessage = nil }
            // Enrich counts concurrently; updates are visible progressively.
            await enrichPlaceCounts()
        } catch {
            if isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Pull-to-refresh: clears cached data then forces a fresh fetch.
    func refreshExplore() async {
        explorePlaces = []
        exploreData = []
        exploreLoadedAt = nil
        await loadExplore(force: true)
    }

    /// Maps the raw cities response into deduplicated, date-sorted places.
    /// Static + pure so it's unit-testable without a live client.
    static func buildPlaces(from assets: [AssetResponseDto]) -> [ExplorePlace] {
        var seen = Set<String>()
        let places = assets.compactMap { asset -> ExplorePlace? in
            guard let city = asset.exifInfo?.city?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !city.isEmpty else { return nil }
            guard !seen.contains(city) else { return nil } // dedup by city
            seen.insert(city)
            return ExplorePlace(
                id: city,
                city: city,
                state: asset.exifInfo?.state,
                country: asset.exifInfo?.country,
                date: Self.parseDate(asset.exifInfo?.dateTimeOriginal),
                assetId: asset.id,
                thumbhash: asset.thumbhash,
                photoCount: nil
            )
        }
        // Initial order: most-recent first (counts re-sort once loaded).
        return places.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Parses an Immich ISO-8601 `dateTimeOriginal` string into a Date.
    /// Tolerates fractional seconds; nil if unparseable/absent.
    static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        return plain.date(from: raw)
    }

    /// Fans out a statistics request per place (concurrency-limited) and
    /// updates each `photoCount` in place, re-sorting by count desc as the
    /// results arrive so the most-photographed places rise to the top.
    private func enrichPlaceCounts() async {
        let cities = explorePlaces.map(\.city)
        await withTaskGroup(of: (String, Int?).self) { [weak self] group in
            for city in cities {
                group.addTask { [weak self] in
                    guard let self else { return (city, nil) }
                    do {
                        let resp = try await self.client.searchStatistics(
                            dto: SearchStatisticsDto(city: city)
                        )
                        return (city, resp.total)
                    } catch {
                        return (city, nil)
                    }
                }
            }
            // TaskGroup already bounds concurrency at the cooperative pool
            // level; collect results as they complete and apply.
            var counts: [String: Int] = [:]
            for await (city, total) in group {
                if let total { counts[city] = total }
            }
            guard !counts.isEmpty else { return }
            // Update + re-sort: places with a known count first (desc), then
            // unresolved ones keep their date order.
            for i in explorePlaces.indices {
                if let total = counts[explorePlaces[i].city] {
                    explorePlaces[i].photoCount = total
                }
            }
            explorePlaces.sort { lhs, rhs in
                Self.comparePlaces(lhs, rhs)
            }
        }
    }

    /// Ordering: known photo count desc; ties (incl. both-unknown) broken by
    /// most-recent date desc so unresolved places keep a sensible position.
    private static func comparePlaces(_ lhs: ExplorePlace, _ rhs: ExplorePlace) -> Bool {
        switch (lhs.photoCount, rhs.photoCount) {
        case let (l?, r?): return l > r
        case (let l?, nil): return true   // known count ranks above unknown
        case (nil, let r?): return false
        default:
            return (lhs.date ?? .distantPast) > (rhs.date ?? .distantPast)
        }
    }

    /// AC-404b (generalized): Explore card tap → switch to Results mode +
    /// metadata search filtered by the card's EXIF field. Clears free-text
    /// `query`, stores the field+value filter, then dispatches (`search()`
    /// resets pagination state). For a city card this matches the legacy
    /// `searchByCity` behavior; for make/model/country/state/lensModel it
    /// now routes to the correct field instead of misusing `city`.
    func searchByExplore(field: ExploreField, value: String) async {
        searchTask?.cancel()
        viewMode = .results
        searchMode = .metadata
        pendingExploreFilter = (field, value)
        query = ""
        await search()
    }
}
