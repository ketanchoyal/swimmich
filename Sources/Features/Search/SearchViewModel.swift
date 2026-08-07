import Foundation

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

    let client: any ImmichClient
    private let recentsStore: RecentSearchesStore

    // Inputs
    var query: String = ""
    var searchMode: SearchMode = .smart
    var viewMode: ViewMode = .results
    /// Drives `MetadataSearchDto.city` when non-nil (Explore tap flow, AC-404b).
    /// `search()` for metadata mode passes `query: nil` when this is set.
    var selectedCity: String? = nil

    // Results
    private(set) var results: [AssetReactItem] = []
    private(set) var loadedIds: Set<String> = []
    private(set) var currentPage: Int = 1
    private(set) var nextPage: String? = nil
    var canLoadMore: Bool { nextPage != nil }
    var hasSearched: Bool = false

    // Explore (AC-404)
    private(set) var exploreData: [SearchExploreResponseDto] = []

    // Recent searches (UX)
    private(set) var recentSearches: [String] = []

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

    init(client: any ImmichClient, recents: RecentSearchesStore = RecentSearchesStore()) {
        self.client = client
        self.recentsStore = recents
        self.recentSearches = recents.load()
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
        searchTask?.cancel()
        searchGeneration += 1
        resetToIdle()
        lastQueried = ""
    }

    /// Recent-search chip tap: write the term into the field, then search
    /// immediately (the subsequent onChange is deduped via `lastQueried`).
    func searchRecent(_ term: String) async {
        searchTask?.cancel()
        query = term
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
        guard !trimmed.isEmpty, selectedCity == nil, !results.isEmpty else { return }
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
    /// `selectedCity` overrides `query` for metadata mode (AC-404b / AC-406c).
    private func dispatchSearch(page: Int) async throws -> SearchResponseDto {
        switch searchMode {
        case .metadata:
            let dto = MetadataSearchDto(
                query: selectedCity != nil ? nil : query,
                city: selectedCity,
                page: page
            )
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

    /// Loads explore data once per VM lifetime (guard exploreData.isEmpty +
    /// !isLoading). Project convention: callers drive this via `.task {}`
    /// (TimelineView.swift:84, TrashView.swift:85).
    func loadExplore() async {
        guard !isLoading, exploreData.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            exploreData = try await client.getExploreData()
        } catch {
            if isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    /// AC-404b: Explore city tap → switch to Results mode + metadata search
    /// filtered by city. Clears free-text `query`, sets `selectedCity`, then
    /// dispatches a fresh search (resets state via `search()`).
    func searchByCity(_ city: String) async {
        searchTask?.cancel()
        viewMode = .results
        searchMode = .metadata
        selectedCity = city
        query = ""
        await search()
    }
}
