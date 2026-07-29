import XCTest
@testable import ImmichSwiftUI

final class AssetDetailViewModelTests: XCTestCase {

    // AC-010: toggleFavorite issues PATCH /api/assets/:id {isFavorite: true}.
    @MainActor
    func test_AC_010_toggleFavoriteUsesPATCH() async {
        let mock = MockImmichClient()
        let asset = AssetReactItem(
            id: "asset-1", ownerId: "owner", ratio: 1.0,
            isFavorite: false, visibility: "timeline", isTrashed: false,
            isImage: true, thumbhash: nil, createdAt: "2024-07-01T00:00:00.000Z",
            fileCreatedAt: "2024-07-01T00:00:00.000Z", localOffsetHours: 0,
            duration: nil, livePhotoVideoId: nil, projectionType: nil,
            city: nil, country: nil, latitude: nil, longitude: nil
        )
        let vm = AssetDetailViewModel(asset: asset, client: mock)
        await vm.toggleFavorite()

        XCTAssertEqual(mock.lastUpdateAssetId, "asset-1")
        XCTAssertEqual(mock.lastUpdateAssetBody?.isFavorite, true)
        XCTAssertEqual(mock.lastUpdateMethod, .PATCH)
        XCTAssertTrue(vm.isFavorite)
    }
}
