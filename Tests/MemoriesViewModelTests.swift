import XCTest
@testable import ImmichSwiftUI

final class MemoriesViewModelTests: XCTestCase {

    private func makeMemory(id: String, year: Int, assetCount: Int = 2) -> MemoryResponseDto {
        let assets = (0..<assetCount).map { i in
            AssetResponseDto(
                id: "\(id)-a\(i)", type: "IMAGE", thumbhash: nil, localDateTime: "2024-07-01T00:00:00.000Z",
                duration: nil, hasMetadata: true, width: 100, height: 100, createdAt: "2024-07-01T00:00:00.000Z",
                ownerId: "owner", originalPath: "/x\(i).jpg", originalFileName: "x\(i).jpg",
                fileCreatedAt: "2024-07-01T00:00:00.000Z", fileModifiedAt: "2024-07-01T00:00:00.000Z",
                updatedAt: "2024-07-01T00:00:00.000Z", isFavorite: false, isArchived: false,
                isTrashed: false, isOffline: false, visibility: "timeline", checksum: "abc", isEdited: false
            )
        }
        return MemoryResponseDto(
            id: id, createdAt: "2024-07-01T00:00:00.000Z", updatedAt: "2024-07-01T00:00:00.000Z",
            memoryAt: "\(year)-07-01T00:00:00.000Z", ownerId: "owner", type: .on_this_day,
            data: OnThisDayDto(year: year), assets: assets, isSaved: false,
            showAt: nil, hideAt: nil, seenAt: nil, deletedAt: nil
        )
    }

    private func makeMemory(
        id: String,
        year: Int,
        memoryAt: String,
        assetTypes: [String],
        durations: [Int?],
        favorites: [Bool],
        exifs: [ExifResponseDto?]
    ) -> MemoryResponseDto {
        let assets = assetTypes.indices.map { i in
            AssetResponseDto(
                id: "\(id)-a\(i)", type: assetTypes[i], thumbhash: nil, localDateTime: "2024-07-01T00:00:00.000Z",
                duration: durations[i], hasMetadata: true, width: 100, height: 100, createdAt: "2024-07-01T00:00:00.000Z",
                ownerId: "owner", originalPath: "/x\(i).jpg", originalFileName: "x\(i).jpg",
                fileCreatedAt: "2024-07-01T00:00:00.000Z", fileModifiedAt: "2024-07-01T00:00:00.000Z",
                updatedAt: "2024-07-01T00:00:00.000Z", isFavorite: favorites[i], isArchived: false,
                isTrashed: false, isOffline: false, visibility: "timeline", checksum: "abc", isEdited: false,
                exifInfo: exifs[i]
            )
        }
        return MemoryResponseDto(
            id: id, createdAt: "2024-07-01T00:00:00.000Z", updatedAt: "2024-07-01T00:00:00.000Z",
            memoryAt: memoryAt, ownerId: "owner", type: .on_this_day,
            data: OnThisDayDto(year: year), assets: assets, isSaved: false,
            showAt: nil, hideAt: nil, seenAt: nil, deletedAt: nil
        )
    }

    @MainActor
    func test_load_mapsServerList() async {
        let mock = MockImmichClient()
        mock.memoriesResponse = [makeMemory(id: "m1", year: 2022), makeMemory(id: "m2", year: 2023)]
        let vm = MemoriesViewModel(client: mock)

        await vm.load()

        XCTAssertEqual(vm.memories.count, 2)
        XCTAssertEqual(vm.memories.map(\.id), ["m2", "m1"])
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    @MainActor
    func test_load_failure_setsError() async {
        let mock = MockImmichClient()
        let vm = MemoriesViewModel(client: mock)

        mock.globalError = APIError.serverError(500, "boom")
        await vm.load()

        XCTAssertTrue(vm.memories.isEmpty)
        XCTAssertEqual(vm.errorMessage?.contains("boom"), true)
    }

    @MainActor
    func test_load_emptyKeepsEmptyList() async {
        let mock = MockImmichClient()
        let vm = MemoriesViewModel(client: mock)

        await vm.load()

        XCTAssertTrue(vm.memories.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func test_load_failureKeepsPreviousList() async {
        let mock = MockImmichClient()
        mock.memoriesResponse = [makeMemory(id: "m1", year: 2022)]
        let vm = MemoriesViewModel(client: mock)
        await vm.load()

        mock.memoriesResponse = nil
        mock.globalError = APIError.serverError(500, "boom")
        await vm.load()

        XCTAssertEqual(vm.memories.map(\.id), ["m1"])
        XCTAssertEqual(vm.errorMessage?.contains("boom"), true)
    }

    @MainActor
    func test_load_failure_usesDedicatedMemoriesErrorChannel() async {
        let mock = MockImmichClient()
        mock.memoriesError = APIError.serverError(500, "memories boom")
        let vm = MemoriesViewModel(client: mock)

        await vm.load()

        XCTAssertTrue(vm.memories.isEmpty)
        XCTAssertEqual(vm.errorMessage?.contains("memories boom"), true)
    }

    // MARK: - MemoryCardPresentation

    private func now(year: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: 6, day: 15))!
    }

    private let enUS = Locale(identifier: "en_US")

    func test_presentation_yearsAgoCount() {
        let now = now(year: 2026)
        XCTAssertEqual(MemoryCardPresentation.yearsAgoCount(year: 2023, now: now), 3)
        XCTAssertEqual(MemoryCardPresentation.yearsAgoCount(year: 2025, now: now), 1)
        XCTAssertNil(MemoryCardPresentation.yearsAgoCount(year: 2026, now: now))
        XCTAssertNil(MemoryCardPresentation.yearsAgoCount(year: 2027, now: now))
    }

    func test_presentation_yearsAgoText_guardsNonPastCount() {
        XCTAssertNil(MemoryCardPresentation.yearsAgoText(count: 0, locale: enUS))
        XCTAssertNil(MemoryCardPresentation.yearsAgoText(count: -2, locale: enUS))
    }

    func test_presentation_dayLabel_usesMemoryDay() {
        let memory = makeMemory(id: "m", year: 2023, memoryAt: "2023-07-01T00:00:00.000Z",
                                assetTypes: ["IMAGE"], durations: [nil], favorites: [false], exifs: [nil])
        let date = MemoryCardPresentation.parseMemoryAt("2023-07-01T00:00:00.000Z")!
        let expectedDay = MemoryCardPresentation.monthDayLabel(from: date, locale: enUS)
        XCTAssertEqual(MemoryCardPresentation.dayLabel(for: memory, locale: enUS), expectedDay)
    }

    func test_presentation_dayLabel_plainSecondsTimestampParses() {
        let memory = makeMemory(id: "m", year: 2023, memoryAt: "2023-07-01T00:00:00Z",
                                assetTypes: ["IMAGE"], durations: [nil], favorites: [false], exifs: [nil])
        let date = MemoryCardPresentation.parseMemoryAt("2023-07-01T00:00:00Z")!
        let expectedDay = MemoryCardPresentation.monthDayLabel(from: date, locale: enUS)
        XCTAssertEqual(MemoryCardPresentation.dayLabel(for: memory, locale: enUS), expectedDay)
    }

    func test_presentation_dayLabel_malformedMemoryAt_returnsNil() {
        let memory = makeMemory(id: "m", year: 2023, memoryAt: "not-a-date",
                                assetTypes: ["IMAGE"], durations: [nil], favorites: [false], exifs: [nil])
        XCTAssertNil(MemoryCardPresentation.dayLabel(for: memory))
    }

    func test_presentation_monthDayLabel_usesRequestedLocale() {
        let date = MemoryCardPresentation.parseMemoryAt("2023-07-01T00:00:00.000Z")!
        XCTAssertEqual(MemoryCardPresentation.monthDayLabel(from: date, locale: enUS), "July 1")
        XCTAssertEqual(MemoryCardPresentation.monthDayLabel(from: date, locale: Locale(identifier: "fr_FR")), "1 juillet")
    }

    func test_presentation_mediaCount_mixed() {
        let memory = makeMemory(id: "m", year: 2023, memoryAt: "2023-07-01T00:00:00.000Z",
                                assetTypes: ["IMAGE", "IMAGE", "VIDEO", "VIDEO", "IMAGE"],
                                durations: [nil, nil, 500, 61, nil], favorites: [false, true, false, false, false],
                                exifs: [nil, nil, nil, nil, nil])
        let (photos, videos) = MemoryCardPresentation.mediaCount(for: memory)
        XCTAssertEqual(photos, 3)
        XCTAssertEqual(videos, 2)
    }

    func test_presentation_mediaCount_allVideos() {
        let memory = makeMemory(id: "v", year: 2023, memoryAt: "2023-07-01T00:00:00.000Z",
                                assetTypes: ["VIDEO", "VIDEO"], durations: [nil, nil],
                                favorites: [false, false], exifs: [nil, nil])
        let (photos, videos) = MemoryCardPresentation.mediaCount(for: memory)
        XCTAssertEqual(photos, 0)
        XCTAssertEqual(videos, 2)
    }

    func test_presentation_mediaCount_empty_isZeroZero() {
        let memory = makeMemory(id: "m", year: 2023, memoryAt: "2023-07-01T00:00:00.000Z",
                                assetTypes: [], durations: [], favorites: [], exifs: [])
        let (photos, videos) = MemoryCardPresentation.mediaCount(for: memory)
        XCTAssertEqual(photos, 0)
        XCTAssertEqual(videos, 0)
        XCTAssertNil(MemoryCardPresentation.mediaCountLabel(for: memory))
    }

    func test_presentation_mediaCount_empty_isNil() {
        let memory = makeMemory(id: "m", year: 2023, memoryAt: "2023-07-01T00:00:00.000Z",
                                assetTypes: [], durations: [], favorites: [], exifs: [])
        XCTAssertNil(MemoryCardPresentation.mediaCountLabel(for: memory))
    }

    func test_presentation_location_prefersCityAndCountry() {
        let exif = ExifResponseDto(city: "Paris", country: "France")
        let memory = makeMemory(id: "m", year: 2023, memoryAt: "2023-07-01T00:00:00.000Z",
                                assetTypes: ["IMAGE"], durations: [nil], favorites: [false], exifs: [exif])
        XCTAssertEqual(MemoryCardPresentation.locationLabel(for: memory), "Paris, France")
    }

    func test_presentation_location_fallsBackAcrossAssets() {
        let countryOnly = ExifResponseDto(city: nil, country: "Japan")
        let memory = makeMemory(id: "m", year: 2023, memoryAt: "2023-07-01T00:00:00.000Z",
                                assetTypes: ["IMAGE", "IMAGE"], durations: [nil, nil],
                                favorites: [false, false], exifs: [nil, countryOnly])
        XCTAssertEqual(MemoryCardPresentation.locationLabel(for: memory), "Japan")
    }

    func test_presentation_location_trimsWhitespace() {
        let exif = ExifResponseDto(city: "  Paris  ", country: " ")
        let memory = makeMemory(id: "m", year: 2023, memoryAt: "2023-07-01T00:00:00.000Z",
                                assetTypes: ["IMAGE"], durations: [nil], favorites: [false], exifs: [exif])
        XCTAssertEqual(MemoryCardPresentation.locationLabel(for: memory), "Paris")
    }

    func test_presentation_location_noExif_isNil() {
        let memory = makeMemory(id: "m", year: 2023, memoryAt: "2023-07-01T00:00:00.000Z",
                                assetTypes: ["IMAGE"], durations: [nil], favorites: [false], exifs: [nil])
        XCTAssertNil(MemoryCardPresentation.locationLabel(for: memory))
    }
}
