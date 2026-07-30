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
    enum ViewMode: Hashable { case results, explore }

    let client: any ImmichClient

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

    // UI state
    private(set) var isLoading: Bool = false
    var errorMessage: String? = nil

    init(client: any ImmichClient) {
        self.client = client
    }

    // MARK: - Search (AC-401 / AC-401b / AC-402 / AC-405)

    /// Reset + dispatch a fresh search (page=1).
    func search() async {
        guard !isLoading else { return }
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
            applyResponse(resp)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// AC-406 / AC-406b / AC-406c: load next page when canLoadMore.
    func loadMore() async {
        guard !isLoading, let _ = nextPage else { return }
        isLoading = true
        defer { isLoading = false }

        let nextPageNumber = currentPage + 1
        do {
            let resp = try await dispatchSearch(page: nextPageNumber)
            currentPage = nextPageNumber
            applyResponse(resp, append: true)
        } catch {
            errorMessage = error.localizedDescription
        }
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
            errorMessage = error.localizedDescription
        }
    }

    /// AC-404b: Explore city tap → switch to Results mode + metadata search
    /// filtered by city. Clears free-text `query`, sets `selectedCity`, then
    /// dispatches a fresh search (resets state via `search()`).
    func searchByCity(_ city: String) async {
        viewMode = .results
        searchMode = .metadata
        selectedCity = city
        query = ""
        await search()
    }
}
