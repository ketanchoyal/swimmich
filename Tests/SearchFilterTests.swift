import XCTest
@testable import ImmichSwiftUI

/// search-filters (AC-5130…AC-5139): the filter the sheet edits, the display
/// options it persists, and — the part that matters — what the server actually
/// receives. Assertions read `MockImmichClient.lastMetadataSearchDto` (the
/// captured body) rather than the ViewModel's wiring.
@MainActor
final class SearchFilterTests: XCTestCase {

    private func makeMock() -> MockImmichClient {
        let mock = MockImmichClient()
        let empty = SearchResponseDto(
            assets: SearchAssetResponseDto(count: 0, items: [], nextPage: nil)
        )
        mock.searchMetadataResponse = empty
        mock.smartSearchResponse = empty
        return mock
    }

    /// Throwaway `UserDefaults` suite: the display options must neither leak
    /// between cases nor into the host app's defaults. Caller removes the domain.
    private func makeDefaults() -> (defaults: UserDefaults, suite: String) {
        let suite = "search-filters-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    // MARK: - AC-5130 / AC-5133: the filter reaches the body, and only what is set

    func test_filterApply_writesOnlyNonNilFields() throws {
        let filter = SearchFilter(rating: 4, city: "Lyon", country: "France")

        var dto = MetadataSearchDto(query: "quai", page: 1)
        filter.apply(to: &dto)

        XCTAssertEqual(dto.rating, 4)
        XCTAssertEqual(dto.city, "Lyon")
        XCTAssertEqual(dto.country, "France")
        XCTAssertNil(dto.state)
        XCTAssertNil(dto.make)
        XCTAssertNil(dto.model)
        XCTAssertNil(dto.lensModel)
        XCTAssertNil(dto.type)
        XCTAssertNil(dto.isFavorite)
        XCTAssertNil(dto.filter, "no OCR criterion means no similarity node")

        // …and the untouched fields really leave the request body (synthesized
        // `Codable` omits the key, it does not send null).
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder.immich.encode(dto)) as? [String: Any]
        )
        XCTAssertNil(body["state"])
        XCTAssertNil(body["make"])
        XCTAssertEqual(body["rating"] as? Int, 4)
        XCTAssertEqual(body["city"] as? String, "Lyon")
    }

    func test_activeCount_countsEachConstraintOnce() {
        var filter = SearchFilter()
        XCTAssertTrue(filter.isEmpty)
        XCTAssertEqual(filter.activeCount, 0)
        XCTAssertTrue(filter.constraints.isEmpty)

        filter.rating = 3
        filter.city = "Lyon"
        filter.lensModel = "XF 23mm"
        filter.isFavorite = true
        XCTAssertEqual(filter.activeCount, 4)
        XCTAssertFalse(filter.isEmpty)

        // A blank text field is not a constraint — the sheet normalizes it to
        // nil, and the chip row must not outlive the request field.
        filter.ocrText = ""
        XCTAssertEqual(filter.activeCount, 4)
        XCTAssertEqual(filter.constraints.map(\.field), [.rating, .city, .lensModel, .isFavorite])

        filter.clear(.city)
        XCTAssertEqual(filter.activeCount, 3)
        XCTAssertFalse(filter.constraints.contains { $0.field == .city }, "a chip removes exactly one constraint")

        filter = SearchFilter.none
        XCTAssertTrue(filter.isEmpty)
    }

    func test_rating_outOfRange_isIgnoredByApply() {
        var filter = SearchFilter()
        filter.rating = 7

        var dto = MetadataSearchDto(query: nil, page: 1)
        filter.apply(to: &dto)

        XCTAssertNil(dto.rating, "the server's scale is 1…5 — an out-of-range value is not a request")
        XCTAssertEqual(filter.activeCount, 0, "and it is not a constraint the grid claims to be filtered by")
    }

    func test_ocrText_switchesFromSmartToMetadata() async {
        let mock = makeMock()
        let vm = SearchViewModel(client: mock)
        vm.searchMode = .smart
        vm.query = "receipt"
        vm.filter.ocrText = "invoice"

        await vm.applyFilters()

        XCTAssertEqual(vm.searchMode, .metadata, "SmartSearchDto has no filter field")
        XCTAssertNil(mock.lastSmartSearchDto)
        XCTAssertEqual(mock.lastMetadataSearchDto?.filter?.ocr?.matches, "invoice")
        XCTAssertEqual(
            mock.lastMetadataSearchDto?.query, "receipt",
            "an OCR criterion typed in the sheet is a filter, not a replacement for the query"
        )
    }

    func test_orderBy_isWrittenAndOrderIsNeverSet() async {
        let mock = makeMock()
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = SearchViewModel(client: mock, display: SearchDisplayOptionsStore(defaults: defaults))
        vm.searchMode = .metadata
        vm.query = "lyon"

        await vm.setSort(.oldestAdded)

        XCTAssertEqual(
            mock.lastMetadataSearchDto?.orderBy,
            SearchOrderDto(field: "localDateTime", direction: "asc")
        )
        XCTAssertNil(mock.lastMetadataSearchDto?.order, "the flat `order` is deprecated and cannot name a field")
    }

    func test_setSort_sameOrder_doesNotRefetch() async {
        let mock = makeMock()
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = SearchViewModel(client: mock, display: SearchDisplayOptionsStore(defaults: defaults))
        await vm.search()
        let requests = mock.requestCount

        await vm.setSort(vm.sort)

        XCTAssertEqual(mock.requestCount, requests, "re-picking the current order changes nothing")
    }

    // MARK: - AC-5136 / AC-5138: the two ways back to no filter

    func test_clearFilters_resetsFilterButKeepsQuery() async {
        let mock = makeMock()
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SearchDisplayOptionsStore(defaults: defaults)
        let vm = SearchViewModel(client: mock, display: store)
        vm.query = "lyon"
        vm.filter.city = "Lyon"
        vm.filter.rating = 3
        await vm.setSort(.oldestTaken)
        vm.setDensity(.large)

        await vm.clearFilters()

        XCTAssertTrue(vm.filter.isEmpty)
        XCTAssertFalse(vm.isFilterActive)
        XCTAssertEqual(vm.query, "lyon")
        XCTAssertEqual(vm.sort, .oldestTaken, "display options are not filters")
        XCTAssertEqual(vm.density, .large)
        XCTAssertEqual(store.loadSort(), .oldestTaken, "and the reset did not un-persist them")
        XCTAssertEqual(store.loadDensity(), .large)
        XCTAssertNil(mock.lastMetadataSearchDto?.city)
        XCTAssertNil(mock.lastMetadataSearchDto?.rating)
    }

    func test_clearSearch_doesNotClearFilters() async {
        let mock = makeMock()
        let vm = SearchViewModel(client: mock)
        vm.query = "lyon"
        vm.filter.city = "Lyon"
        vm.filter.rating = 3

        vm.clearSearch()

        XCTAssertEqual(vm.filter.city, "Lyon", "emptying the query is not erasing the filters")
        XCTAssertEqual(vm.ratingFilter, 3)
        XCTAssertTrue(vm.isFilterActive)

        await vm.applyFilters()
        XCTAssertEqual(mock.lastMetadataSearchDto?.city, "Lyon")
        XCTAssertEqual(mock.lastMetadataSearchDto?.rating, 3)
    }

    // MARK: - AC-5137: the display options

    func test_displayOptions_roundTripThroughUserDefaults() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SearchDisplayOptionsStore(defaults: defaults)

        XCTAssertEqual(store.loadSort(), .newestTaken, "an absent key falls back to the server's own order")
        XCTAssertEqual(store.loadDensity(), .comfortable, "and to the grid the tab shipped with")

        store.saveSort(.oldestAdded)
        store.saveDensity(.large)
        XCTAssertEqual(store.loadSort(), .oldestAdded)
        XCTAssertEqual(store.loadDensity(), .large)

        // A readable key with an unreadable value is still a fallback, not a crash.
        defaults.set("nonsense", forKey: "searchSortOrder")
        defaults.set("nonsense", forKey: "searchGridDensity")
        XCTAssertEqual(store.loadSort(), .newestTaken)
        XCTAssertEqual(store.loadDensity(), .comfortable)

        // A fresh ViewModel adopts what was persisted.
        store.saveSort(.oldestTaken)
        store.saveDensity(.compact)
        let vm = SearchViewModel(client: makeMock(), display: SearchDisplayOptionsStore(defaults: defaults))
        XCTAssertEqual(vm.sort, .oldestTaken)
        XCTAssertEqual(vm.density, .compact)
    }

    func test_density_columnCount_matchesDensity() {
        XCTAssertEqual(SearchGridDensity.compact.columnCount, 5)
        XCTAssertEqual(SearchGridDensity.comfortable.columnCount, 3)
        XCTAssertEqual(SearchGridDensity.large.columnCount, 2)

        let mock = makeMock()
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SearchDisplayOptionsStore(defaults: defaults)
        let vm = SearchViewModel(client: mock, display: store)

        vm.setDensity(.large)

        XCTAssertEqual(vm.density, .large)
        XCTAssertEqual(store.loadDensity(), .large, "persisted for the next launch")
        XCTAssertEqual(mock.requestCount, 0, "density is client-only: the grid re-flows, nothing is refetched")
    }

    // MARK: - AC-5133: the dates on the wire

    func test_dispatch_writesDateRangeAsISO8601() async {
        let mock = makeMock()
        let vm = SearchViewModel(client: mock)
        vm.searchMode = .metadata
        vm.filter.takenAfter = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01T00:00:00Z
        vm.filter.takenBefore = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01T00:00:00Z

        await vm.applyFilters()

        XCTAssertEqual(mock.lastMetadataSearchDto?.takenAfter, "2024-01-01T00:00:00.000Z")
        XCTAssertEqual(mock.lastMetadataSearchDto?.takenBefore, "2025-01-01T00:00:00.000Z")
    }

    func test_dispatch_writesNoDateWhenToggleIsOff() async {
        let mock = makeMock()
        let vm = SearchViewModel(client: mock)
        vm.searchMode = .metadata
        vm.filter.takenBefore = Date(timeIntervalSince1970: 1_735_689_600)

        await vm.applyFilters()
        XCTAssertNil(mock.lastMetadataSearchDto?.takenAfter, "only the enabled bound is sent")
        XCTAssertEqual(mock.lastMetadataSearchDto?.takenBefore, "2025-01-01T00:00:00.000Z")

        vm.filter.takenBefore = nil
        await vm.applyFilters()
        XCTAssertNil(mock.lastMetadataSearchDto?.takenBefore)
    }
}
