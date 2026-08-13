import XCTest
@testable import ImmichSwiftUI

@MainActor
final class AssetDetailGeocodingTests: XCTestCase {

    /// Minimal AssetReactItem (coords not required; EXIF is the source of truth for geocoding).
    private func makeAsset(id: String = "a1") -> AssetReactItem {
        AssetReactItem(
            id: id, ownerId: "owner", ratio: 1.0, isFavorite: false, visibility: "timeline",
            isTrashed: false, isImage: true, thumbhash: nil,
            createdAt: "2024-07-01T00:00:00.000Z", fileCreatedAt: "2024-07-01T00:00:00.000Z",
            localOffsetHours: 0, duration: nil, livePhotoVideoId: nil, projectionType: nil,
            city: nil, country: nil, latitude: nil, longitude: nil, stack: []
        )
    }

    /// AssetResponseDto with optional exifInfo injected.
    private func makeDetail(id: String = "a1", exif: ExifResponseDto?) -> AssetResponseDto {
        AssetResponseDto(
            id: id, type: "IMAGE", thumbhash: nil, localDateTime: "2024-07-01T00:00:00.000Z",
            duration: nil, hasMetadata: true, width: 100, height: 100,
            createdAt: "2024-07-01T00:00:00.000Z", ownerId: "owner", originalPath: "/x.jpg",
            originalFileName: "x.jpg", fileCreatedAt: "2024-07-01T00:00:00.000Z",
            fileModifiedAt: "2024-07-01T00:00:00.000Z", updatedAt: "2024-07-01T00:00:00.000Z",
            isFavorite: false, isArchived: false, isTrashed: false, isOffline: false,
            visibility: "timeline", checksum: "abc", isEdited: false, exifInfo: exif
        )
    }

    private func clientReturning(detail: AssetResponseDto) -> MockImmichClient {
        let mock = MockImmichClient()
        mock.getAssetResponse = [detail.id: detail]
        return mock
    }

    // MARK: - AC-204: geocoder success populates placeName

    func test_AC_204_geocode_success() async {
        let exif = ExifResponseDto(latitude: 48.8566, longitude: 2.3522)
        let mock = clientReturning(detail: makeDetail(exif: exif))
        let geocoder = MockLocationGeocoding()
        geocoder.placeNameResult = "Test Place"
        let vm = AssetDetailViewModel(asset: makeAsset(), client: mock)
        vm.geocoder = geocoder

        await vm.loadDetail()

        XCTAssertEqual(vm.placeName, "Test Place")
        XCTAssertEqual(geocoder.callCount, 1)
    }

    // MARK: - AC-205: geocoder throw → fallback to exif.city+state+country

    func test_AC_205_geocode_fallback() async {
        let exif = ExifResponseDto(
            latitude: 48.8566, longitude: 2.3522,
            city: "Paris", state: "Île-de-France", country: "France"
        )
        let mock = clientReturning(detail: makeDetail(exif: exif))
        let geocoder = MockLocationGeocoding()
        struct Boom: Error {}
        geocoder.placeNameError = Boom()
        let vm = AssetDetailViewModel(asset: makeAsset(), client: mock)
        vm.geocoder = geocoder

        await vm.loadDetail()

        XCTAssertEqual(vm.placeName, "Paris, Île-de-France, France")
        XCTAssertEqual(geocoder.callCount, 1)
    }

    // MARK: - AC-205b: all fallback data nil + geocoder throw → placeName nil

    func test_AC_205b_geocode_no_fallback_data() async {
        let exif = ExifResponseDto(latitude: 48.8566, longitude: 2.3522)
        let mock = clientReturning(detail: makeDetail(exif: exif))
        let geocoder = MockLocationGeocoding()
        struct Boom: Error {}
        geocoder.placeNameError = Boom()
        let vm = AssetDetailViewModel(asset: makeAsset(), client: mock)
        vm.geocoder = geocoder

        await vm.loadDetail()

        XCTAssertNil(vm.placeName, "no geocode result and no fallback data → placeName nil")
    }

    // MARK: - AC-206: no coords → geocoder never invoked

    func test_AC_206_no_geocode_without_coords() async {
        let exif = ExifResponseDto() // no lat/lon
        let mock = clientReturning(detail: makeDetail(exif: exif))
        let geocoder = MockLocationGeocoding()
        geocoder.placeNameResult = "Should Not Be Used"
        let vm = AssetDetailViewModel(asset: makeAsset(), client: mock)
        vm.geocoder = geocoder

        await vm.loadDetail()

        XCTAssertEqual(geocoder.callCount, 0)
        XCTAssertNil(vm.placeName)
    }

    // MARK: - AC-208: loadDetail called twice → geocoder invoked exactly once (FM-3)

    func test_AC_208_geocode_no_double_invoke() async {
        let exif = ExifResponseDto(latitude: 48.8566, longitude: 2.3522)
        let mock = clientReturning(detail: makeDetail(exif: exif))
        let geocoder = MockLocationGeocoding()
        geocoder.placeNameResult = "Test Place"
        let vm = AssetDetailViewModel(asset: makeAsset(), client: mock)
        vm.geocoder = geocoder

        await vm.loadDetail()
        await vm.loadDetail()

        XCTAssertEqual(geocoder.callCount, 1, "geocoder must be invoked once even across reloads")
    }
}
