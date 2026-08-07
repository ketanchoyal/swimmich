import XCTest
@testable import ImmichSwiftUI

@MainActor
final class SearchViewModelTests: XCTestCase {

    /// Builds an `AssetResponseDto` suitable for search results.
    private func makeAsset(id: String, city: String? = nil) -> AssetResponseDto {
        var exif: ExifResponseDto? = nil
        if let city {
            exif = ExifResponseDto()
            exif?.city = city
        }
        return AssetResponseDto(
            id: id, type: "IMAGE", thumbhash: nil, localDateTime: "2024-07-01T00:00:00.000Z",
            duration: nil, hasMetadata: true, width: 100, height: 100,
            createdAt: "2024-07-01T00:00:00.000Z", ownerId: "owner",
            originalPath: "/\(id).jpg", originalFileName: "\(id).jpg",
            fileCreatedAt: "2024-07-01T00:00:00.000Z",
            fileModifiedAt: "2024-07-01T00:00:00.000Z",
            updatedAt: "2024-07-01T00:00:00.000Z",
            isFavorite: false, isArchived: false, isTrashed: false,
            isOffline: false, visibility: "timeline", checksum: "x", isEdited: false,
            exifInfo: exif
        )
    }

    private func makeMock(items: [AssetResponseDto] = [], nextPage: String? = nil) -> MockImmichClient {
        let mock = MockImmichClient()
        let resp = SearchResponseDto(
            assets: SearchAssetResponseDto(count: items.count, items: items, nextPage: nextPage)
        )
        mock.searchMetadataResponse = resp
        mock.smartSearchResponse = resp
        return mock
    }

    // MARK: - AC-401: searchMetadata success + error path

    func test_AC_401_searchMetadata_success() async {
        let mock = makeMock(items: [makeAsset(id: "a1"), makeAsset(id: "a2")])
        let vm = SearchViewModel(client: mock)
        vm.searchMode = .metadata
        vm.query = "Canon"

        await vm.search()

        XCTAssertEqual(mock.lastMetadataSearchDto?.query, "Canon")
        XCTAssertEqual(vm.results.count, 2)
        XCTAssertEqual(vm.results.map(\.id), ["a1", "a2"])
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.canLoadMore) // nextPage nil
        XCTAssertTrue(vm.hasSearched)
    }

    func test_AC_401_searchMetadata_error() async {
        let mock = makeMock()
        struct Boom: Error {}
        mock.searchMetadataError = Boom()
        let vm = SearchViewModel(client: mock)
        vm.searchMode = .metadata
        vm.query = "Canon"

        await vm.search()

        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - AC-401b: searchSmart success + error path

    func test_AC_401b_searchSmart_success() async {
        let mock = makeMock(items: [makeAsset(id: "s1"), makeAsset(id: "s2")])
        let vm = SearchViewModel(client: mock)
        vm.searchMode = .smart
        vm.query = "chien sur une plage"

        await vm.search()

        XCTAssertEqual(mock.lastSmartSearchDto?.query, "chien sur une plage")
        XCTAssertEqual(vm.results.count, 2)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(mock.requestCount, 1)
    }

    func test_AC_401b_searchSmart_error() async {
        let mock = makeMock()
        struct Boom: Error {}
        mock.smartSearchError = Boom()
        let vm = SearchViewModel(client: mock)
        vm.searchMode = .smart
        vm.query = "dog"

        await vm.search()

        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Cancellation must not surface as a user-visible error

    /// A `URLError(.cancelled)` (what `URLSession.data(for:)` throws when the
    /// enclosing debounced Task is cancelled mid-flight) must be swallowed —
    /// it is a normal outcome of typing/clearing/recents, never an error.
    func test_searchCancelled_doesNotSurfaceError_urlError() async {
        let mock = makeMock()
        mock.smartSearchError = URLError(.cancelled)
        let vm = SearchViewModel(client: mock)
        vm.searchMode = .smart
        vm.query = "beach"

        await vm.search()

        XCTAssertNil(vm.errorMessage, "URLError(.cancelled) must not surface as an error")
        XCTAssertTrue(vm.hasSearched, "the search attempt was registered")
    }

    /// A cooperative `CancellationError` (e.g. `Task.cancel()` propagating into
    /// a non-URLSession await) must likewise be swallowed.
    func test_searchCancelled_doesNotSurfaceError_cancellationError() async {
        let mock = makeMock()
        mock.smartSearchError = CancellationError()
        let vm = SearchViewModel(client: mock)
        vm.searchMode = .smart
        vm.query = "beach"

        await vm.search()

        XCTAssertNil(vm.errorMessage, "CancellationError must not surface as an error")
    }

    // MARK: - AC-402: dto dispatched selon mode

    func test_AC_402_metadata_dto_dispatched() async {
        let mock = makeMock(items: [makeAsset(id: "m1")])
        let vm = SearchViewModel(client: mock)
        vm.searchMode = .metadata
        vm.query = "Canon"

        await vm.search()

        XCTAssertEqual(mock.lastMetadataSearchDto?.query, "Canon")
        XCTAssertNil(mock.lastSmartSearchDto)
        XCTAssertEqual(mock.requestCount, 1)
    }

    func test_AC_402_smart_dto_dispatched() async {
        let mock = makeMock(items: [makeAsset(id: "s1")])
        let vm = SearchViewModel(client: mock)
        vm.searchMode = .smart
        vm.query = "chien sur une plage"

        await vm.search()

        XCTAssertEqual(mock.lastSmartSearchDto?.query, "chien sur une plage")
        XCTAssertNil(mock.lastMetadataSearchDto)
        XCTAssertEqual(mock.requestCount, 1)
    }

    // MARK: - AC-404a: loadExplore success path

    func test_AC_404a_loadExplore() async {
        let mock = MockImmichClient()
        let thumbnail = makeAsset(id: "t1", city: "Paris")
        mock.exploreResponse = [
            SearchExploreResponseDto(
                fieldName: "exifInfo.city",
                items: [SearchExploreItem(value: "Paris", data: thumbnail)]
            )
        ]
        let vm = SearchViewModel(client: mock)

        await vm.loadExplore()

        XCTAssertEqual(mock.requestCount, 1)
        XCTAssertEqual(vm.exploreData.count, 1)
        XCTAssertEqual(vm.exploreData.first?.fieldName, "exifInfo.city")
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - AC-404b: searchByCity resets state + dispatches dto.city

    func test_AC_404b_cityTapDispatchesCity() async {
        let mock = makeMock(items: [makeAsset(id: "p1"), makeAsset(id: "p2")])
        let vm = SearchViewModel(client: mock)

        await vm.searchByCity("Paris")

        XCTAssertEqual(mock.lastMetadataSearchDto?.city, "Paris")
        XCTAssertNil(mock.lastMetadataSearchDto?.query, "free-text query must be nil when city filter active")
        XCTAssertEqual(vm.searchMode, .metadata)
        XCTAssertEqual(vm.viewMode, .results)
        XCTAssertEqual(vm.query, "")
        XCTAssertEqual(vm.selectedCity, "Paris")
        XCTAssertEqual(vm.results.count, 2)
        XCTAssertEqual(vm.loadedIds.count, 2)
        XCTAssertEqual(vm.currentPage, 1, "currentPage reset to 1 (not accumulated)")
        XCTAssertNil(vm.nextPage)
    }

    // MARK: - AC-404c: loadExplore idempotency

    func test_AC_404c_loadExplore_idempotent() async {
        let mock = MockImmichClient()
        mock.exploreResponse = [
            SearchExploreResponseDto(
                fieldName: "exifInfo.city",
                items: [SearchExploreItem(value: "Paris", data: makeAsset(id: "t1"))]
            )
        ]
        let vm = SearchViewModel(client: mock)

        await vm.loadExplore()
        await vm.loadExplore()

        XCTAssertEqual(mock.requestCount, 1, "second call must no-op (exploreData non-empty)")
        XCTAssertFalse(vm.exploreData.isEmpty)
    }

    // MARK: - AC-405: empty state after search() returns 0 results

    func test_AC_405_empty_state() async {
        let mock = makeMock(items: []) // 0 results
        let vm = SearchViewModel(client: mock)
        vm.searchMode = .smart
        vm.query = "obscure term"

        await vm.search()

        XCTAssertTrue(vm.hasSearched)
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertNil(vm.errorMessage, "empty results != error")
    }

    // MARK: - AC-406: pagination loads next page, dedup, canLoadMore

    func test_AC_406_pagination_loads_next_page() async {
        // Two distinct responses: page 1 (nextPage "2") + page 2 (nextPage nil).
        let mock = MockImmichClient()
        mock.smartSearchResponse = SearchResponseDto(
            assets: SearchAssetResponseDto(
                count: 2, items: [makeAsset(id: "p1a"), makeAsset(id: "p1b")], nextPage: "2"
            )
        )
        let vm = SearchViewModel(client: mock)
        vm.searchMode = .smart
        vm.query = "beach"
        await vm.search()
        XCTAssertEqual(mock.requestCount, 1)
        XCTAssertEqual(vm.results.count, 2)
        XCTAssertTrue(vm.canLoadMore)

        // Swap mock response to page 2 (nextPage nil).
        mock.smartSearchResponse = SearchResponseDto(
            assets: SearchAssetResponseDto(
                count: 2, items: [makeAsset(id: "p2a"), makeAsset(id: "p2b")], nextPage: nil
            )
        )
        await vm.loadMore()

        XCTAssertEqual(mock.requestCount, 2)
        XCTAssertEqual(vm.results.count, 4, "page 2 appended")
        XCTAssertEqual(Set(vm.results.map(\.id)).count, 4, "no duplicate IDs")
        XCTAssertEqual(vm.currentPage, 2)
        XCTAssertNil(vm.nextPage)
        XCTAssertFalse(vm.canLoadMore)
    }

    func test_AC_406b_loadMore_noop_when_no_nextPage() async {
        let mock = makeMock(items: [makeAsset(id: "a1")], nextPage: nil)
        let vm = SearchViewModel(client: mock)
        vm.searchMode = .smart
        vm.query = "x"
        await vm.search()
        XCTAssertEqual(mock.requestCount, 1)
        XCTAssertFalse(vm.canLoadMore)

        await vm.loadMore()
        XCTAssertEqual(mock.requestCount, 1, "loadMore no-op when canLoadMore false")
    }

    // MARK: - AC-406c: loadMore persists city filter after searchByCity

    func test_AC_406c_loadMore_persists_city_filter() async {
        let mock = MockImmichClient()
        mock.searchMetadataResponse = SearchResponseDto(
            assets: SearchAssetResponseDto(
                count: 1, items: [makeAsset(id: "p1", city: "Paris")], nextPage: "2"
            )
        )
        let vm = SearchViewModel(client: mock)

        await vm.searchByCity("Paris")
        XCTAssertEqual(mock.requestCount, 1)

        // Page 2 response (nextPage nil).
        mock.searchMetadataResponse = SearchResponseDto(
            assets: SearchAssetResponseDto(
                count: 1, items: [makeAsset(id: "p2", city: "Paris")], nextPage: nil
            )
        )
        await vm.loadMore()

        XCTAssertEqual(mock.requestCount, 2)
        XCTAssertEqual(mock.lastMetadataSearchDto?.city, "Paris", "city filter persists across pages")
        XCTAssertNil(mock.lastMetadataSearchDto?.query)
        XCTAssertEqual(mock.lastMetadataSearchDto?.page, 2)
        XCTAssertEqual(vm.results.count, 2)
    }

    // MARK: - Live search (debounced) + clear + recents

    func test_liveSearch_debounced_dispatches_after_idle() async {
        let mock = makeMock(items: [makeAsset(id: "a1")])
        let vm = SearchViewModel(client: mock)
        vm.debounceInterval = .zero
        vm.query = "beach"
        XCTAssertEqual(mock.requestCount, 0, "no request before debounce fires")
        vm.queryDidChange()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(mock.requestCount, 1)
        XCTAssertEqual(mock.lastSmartSearchDto?.query, "beach")
        XCTAssertTrue(vm.hasSearched)
        XCTAssertEqual(vm.results.count, 1)
    }

    func test_liveSearch_empty_query_resets_to_idle() async {
        let mock = makeMock(items: [makeAsset(id: "a1")])
        let vm = SearchViewModel(client: mock)
        vm.debounceInterval = .zero
        vm.query = "beach"
        await vm.search()
        XCTAssertEqual(vm.results.count, 1)

        vm.query = ""
        vm.queryDidChange()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(vm.results.isEmpty, "clearing the field must drop stale results")
        XCTAssertFalse(vm.hasSearched)
        XCTAssertEqual(mock.requestCount, 1, "empty query must not dispatch")
    }

    func test_clearSearch_resets_results_and_query() async {
        let mock = makeMock(items: [makeAsset(id: "a1")])
        let vm = SearchViewModel(client: mock)
        vm.query = "beach"
        await vm.search()
        XCTAssertEqual(vm.results.count, 1)

        vm.clearSearch()

        XCTAssertEqual(vm.query, "")
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertFalse(vm.hasSearched)
        XCTAssertNil(vm.errorMessage)
    }

    func test_searchRecent_dispatches_without_second_search() async {
        let mock = makeMock(items: [makeAsset(id: "a1")])
        let vm = SearchViewModel(client: mock)
        vm.debounceInterval = .zero

        await vm.searchRecent("paris")

        XCTAssertEqual(mock.lastSmartSearchDto?.query, "paris")
        XCTAssertEqual(vm.query, "paris")
        XCTAssertEqual(vm.results.count, 1)

        // The View's onChange fires after the programmatic write; it must no-op.
        vm.queryDidChange()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(mock.requestCount, 1, "programmatic query write must not double-search")
    }

    func test_recents_recorded_deduped_and_capped() async {
        let suite = "SearchRecentsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RecentSearchesStore(defaults: defaults)

        let mock = makeMock(items: [makeAsset(id: "a1")])
        let vm = SearchViewModel(client: mock, recents: store)

        for i in 0..<10 {
            vm.query = "term\(i)"
            await vm.search()
        }
        XCTAssertEqual(vm.recentSearches.count, 8, "capped at capacity")
        XCTAssertEqual(vm.recentSearches.first, "term9", "newest first")

        vm.query = "term5"
        await vm.search()
        XCTAssertEqual(vm.recentSearches.first, "term5", "reused term moves to front")
        XCTAssertEqual(vm.recentSearches.filter { $0 == "term5" }.count, 1, "no duplicates")
        XCTAssertEqual(store.load(), vm.recentSearches, "persisted")
    }

    func test_recents_skip_empty_and_city_flows() async {
        let suite = "SearchRecentsEmptyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RecentSearchesStore(defaults: defaults)
        let mock = MockImmichClient()
        mock.searchMetadataResponse = SearchResponseDto(
            assets: SearchAssetResponseDto(count: 0, items: [], nextPage: nil)
        )
        let vm = SearchViewModel(client: mock, recents: store)

        // City flow: query stays empty → nothing recorded.
        await vm.searchByCity("Paris")
        XCTAssertTrue(vm.recentSearches.isEmpty, "city filter must not be recorded as a text search")
        XCTAssertTrue(store.load().isEmpty)
    }
}
