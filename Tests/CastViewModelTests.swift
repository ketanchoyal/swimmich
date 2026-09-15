import Foundation
import XCTest
@testable import ImmichSwiftUI

/// The cast sheet's testable half (gap G9): which assets can leave the device
/// under a given `CastService`, and what the service's state projects to.
///
/// Nothing here touches `AVRouteDetector`, `AVAudioSession` or
/// `AVRoutePickerView` — none of those is simulatable, and the simulator
/// publishes no route at all.
@MainActor
final class CastViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeAsset(isVideo: Bool = false) -> AssetReactItem {
        AssetReactItem(
            id: "asset-1", ownerId: "owner", ratio: 0.75, isFavorite: false,
            visibility: "timeline", isTrashed: false, isImage: !isVideo, thumbhash: nil,
            createdAt: "2024-07-01T10:00:00.000Z", fileCreatedAt: "2024-07-01T10:00:00.000Z",
            localOffsetHours: 0, duration: isVideo ? 12 : nil, livePhotoVideoId: nil,
            projectionType: nil, city: nil, country: nil, latitude: nil, longitude: nil, stack: []
        )
    }

    // MARK: - The photo / video asymmetry

    func test_canCast_isTrueForVideo_whenServiceCannotCastImages() {
        let service = MockCastService()
        service.supportsStillImages = false
        let vm = CastViewModel(service: service)

        XCTAssertTrue(vm.canCast(makeAsset(isVideo: true)))
    }

    func test_canCast_isFalseForStill_whenServiceCannotCastImages() {
        let service = MockCastService()
        service.supportsStillImages = false
        let vm = CastViewModel(service: service)

        XCTAssertFalse(vm.canCast(makeAsset(isVideo: false)))
    }

    /// A service that fetches the media itself (a Cast receiver) can take a
    /// thumbnail, so the sheet must stop telling the user it cannot.
    func test_canCast_isTrueForStill_whenServiceCastsImages() {
        let service = MockCastService()
        service.supportsStillImages = true
        let vm = CastViewModel(service: service)

        XCTAssertTrue(vm.canCast(makeAsset(isVideo: false)))
        XCTAssertTrue(vm.canCast(makeAsset(isVideo: true)))
    }

    // MARK: - Status projection

    func test_statusText_isNil_whenDisconnected() {
        let service = MockCastService()
        service.isConnected = false
        service.connectedRouteName = "Living Room"
        let vm = CastViewModel(service: service)

        XCTAssertNil(vm.statusText)
        XCTAssertFalse(vm.isConnected)
    }

    func test_statusText_surfacesConnectedRouteName() {
        let service = MockCastService()
        service.isConnected = true
        service.connectedRouteName = "Living Room"
        let vm = CastViewModel(service: service)

        XCTAssertEqual(vm.statusText, "Living Room")
        XCTAssertEqual(vm.connectedRouteName, "Living Room")
        XCTAssertTrue(vm.isConnected)
    }

    // MARK: - The shipped implementation, as far as a simulator can tell

    func test_airPlayService_declaresNoStillImageSupport() {
        let service = AirPlayCastService()

        XCTAssertFalse(service.supportsStillImages)
    }

    // MARK: - Observation lifecycle

    func test_onAppear_delegatesToStartObserving() {
        let service = MockCastService()
        let vm = CastViewModel(service: service)

        vm.onAppear()

        XCTAssertEqual(service.startObservingCount, 1)
    }

    func test_onDisappear_delegatesToStopObserving() {
        let service = MockCastService()
        let vm = CastViewModel(service: service)

        vm.onDisappear()

        XCTAssertEqual(service.stopObservingCount, 1)
    }
}
