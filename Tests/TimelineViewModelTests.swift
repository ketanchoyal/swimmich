import XCTest
@testable import ImmichSwiftUI

final class TimelineViewModelTests: XCTestCase {

    /// Builds a columnar TimeBucketAssetResponseDto with two well-known assets
    /// so the zip step has predictable per-index values (AC-013).
    private func columnar(ids: [String], ratios: [Double], thumbhashes: [String?], favorites: [Bool]) -> TimeBucketAssetResponseDto {
        TimeBucketAssetResponseDto(
            id: ids,
            ownerId: ids.map { _ in "owner" },
            ratio: ratios,
            isFavorite: favorites,
            visibility: ids.map { _ in "timeline" },
            isTrashed: ids.map { _ in false },
            isImage: ids.map { _ in true },
            thumbhash: thumbhashes,
            createdAt: ids.map { _ in "2024-07-01T00:00:00.000Z" },
            fileCreatedAt: ids.map { _ in "2024-07-01T00:00:00.000Z" },
            localOffsetHours: ids.map { _ in 0.0 },
            duration: ids.map { _ in nil },
            livePhotoVideoId: ids.map { _ in nil },
            projectionType: ids.map { _ in nil },
            stack: nil, city: nil, country: nil, latitude: nil, longitude: nil
        )
    }

    // AC-006: bucket-level pagination accumulates with no dup IDs.
    @MainActor
    func test_AC_006_bucketPaginationNoDuplicates() async {
        let mock = MockImmichClient()
        mock.bucketsResponse = [
            TimeBucketsResponseDto(timeBucket: "2024-07-01", count: 2),
            TimeBucketsResponseDto(timeBucket: "2024-06-01", count: 2)
        ]
        mock.bucketResponses = [
            "2024-07-01": columnar(
                ids: ["a1", "a2"], ratios: [0.75, 1.33], thumbhashes: ["h1", "h2"], favorites: [false, true]
            ),
            "2024-06-01": columnar(
                ids: ["a3", "a4"], ratios: [0.5, 2.0], thumbhashes: ["h3", "h4"], favorites: [true, false]
            )
        ]

        let vm = TimelineViewModel(client: mock)
        await vm.load()
        XCTAssertEqual(vm.items.count, 2)
        XCTAssertEqual(Set(vm.items.map(\.id)), Set(["a1", "a2"]))

        await vm.loadMore()
        XCTAssertEqual(vm.items.count, 4)
        XCTAssertEqual(Set(vm.items.map(\.id)), Set(["a1", "a2", "a3", "a4"]))

        // loadMore past the last bucket is a no-op (no dup, no growth).
        await vm.loadMore()
        XCTAssertEqual(vm.items.count, 4)
        XCTAssertEqual(vm.loadedIds.count, vm.items.count)
        XCTAssertFalse(vm.canLoadMore)
    }

    // AC-009: constructor-injected VM + mock client; state derived without network.
    @MainActor
    func test_AC_009_MVVMTestability() async {
        let mock = MockImmichClient()
        mock.bucketsResponse = [TimeBucketsResponseDto(timeBucket: "2024-07-01", count: 1)]
        mock.bucketResponses = [
            "2024-07-01": columnar(ids: ["x"], ratios: [1.0], thumbhashes: [nil], favorites: [false])
        ]

        let vm = TimelineViewModel(client: mock)
        XCTAssertFalse(vm.isLoading)
        await vm.load()
        XCTAssertGreaterThan(mock.requestCount, 0)
        XCTAssertFalse(vm.items.isEmpty)
        XCTAssertEqual(vm.items.first?.id, "x")
    }

    // AC-013: columnar→object zip correctness (id[i]↔ratio[i]↔thumbhash[i]↔isFavorite[i]).
    @MainActor
    func test_AC_013_columnarZipCorrectness() async {
        let mock = MockImmichClient()
        mock.bucketsResponse = [TimeBucketsResponseDto(timeBucket: "2024-07-01", count: 2)]
        let ids = ["alpha", "beta"]
        let ratios = [0.75, 1.5]
        let thumbs = ["thumb-a", "thumb-b"]
        let favs = [false, true]
        mock.bucketResponses = [
            "2024-07-01": columnar(ids: ids, ratios: ratios, thumbhashes: thumbs, favorites: favs)
        ]

        let vm = TimelineViewModel(client: mock)
        await vm.load()

        let alpha = vm.items.first { $0.id == "alpha" }
        let beta = vm.items.first { $0.id == "beta" }
        XCTAssertNotNil(alpha)
        XCTAssertNotNil(beta)
        XCTAssertEqual(alpha?.ratio, 0.75)
        XCTAssertEqual(alpha?.thumbhash, "thumb-a")
        XCTAssertEqual(alpha?.isFavorite, false)
        XCTAssertEqual(beta?.ratio, 1.5)
        XCTAssertEqual(beta?.thumbhash, "thumb-b")
        XCTAssertEqual(beta?.isFavorite, true)
    }

    // AC-013b: zip returns [] on malformed (length-mismatched) required arrays.
    func test_AC_013b_zipRejectsMalformed() {
        let bad = TimeBucketAssetResponseDto(
            id: ["a", "b"],
            ownerId: ["o"], // wrong length
            ratio: [1, 1], isFavorite: [false, true], visibility: ["timeline", "timeline"],
            isTrashed: [false, false], isImage: [true, true], thumbhash: [nil, nil],
            createdAt: ["", ""], fileCreatedAt: ["", ""], localOffsetHours: [0, 0],
            duration: [nil, nil], livePhotoVideoId: [nil, nil], projectionType: [nil, nil],
            stack: nil, city: nil, country: nil, latitude: nil, longitude: nil
        )
        XCTAssertTrue(AssetReactItem.zip(bad).isEmpty)
    }

    // AC-007: thumbnailURL canonical format.
    func test_AC_007_thumbnailURL() {
        let url = ImmichAssetURL.thumbnail(
            assetId: "abc123",
            thumbhash: "xyz",
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(
            url.absoluteString,
            "https://example.com/api/assets/abc123/thumbnail?size=thumbnail&c=xyz"
        )
    }
}
