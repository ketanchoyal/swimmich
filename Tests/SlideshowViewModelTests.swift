import XCTest
@testable import ImmichSwiftUI

/// Deterministic state-machine tests — the ticking loop is view-owned
/// (`.task(id:)` in SlideshowView), so no Timer and no AVFoundation here.
@MainActor
final class SlideshowViewModelTests: XCTestCase {

    private func makeAsset(id: String, video: Bool = false) -> AssetReactItem {
        AssetReactItem(
            id: id, ownerId: "owner", ratio: 1.0, isFavorite: false, visibility: "timeline",
            isTrashed: false, isImage: !video, thumbhash: nil,
            createdAt: "2024-07-01T00:00:00.000Z", fileCreatedAt: "2024-07-01T00:00:00.000Z",
            localOffsetHours: 0, duration: video ? 12 : nil, livePhotoVideoId: nil, projectionType: nil,
            city: nil, country: nil, latitude: nil, longitude: nil, stack: []
        )
    }

    // MARK: - Init

    func test_init_clampsStartIndex() {
        let assets = [makeAsset(id: "a"), makeAsset(id: "b"), makeAsset(id: "c")]
        let vm = SlideshowViewModel(assets: assets, startIndex: 7)
        XCTAssertEqual(vm.currentIndex, 2)
        XCTAssertEqual(vm.currentAsset?.id, "c")

        let empty = SlideshowViewModel(assets: [], startIndex: 0)
        XCTAssertEqual(empty.currentIndex, 0)
        XCTAssertNil(empty.currentAsset)
    }

    func test_init_defaultNotPlaying_threeSeconds() {
        let vm = SlideshowViewModel(assets: [makeAsset(id: "a")])
        XCTAssertFalse(vm.isPlaying)
        XCTAssertEqual(vm.speed, .threeSeconds)
        XCTAssertEqual(vm.speed.rawValue, 3)
    }

    // MARK: - Advance / wrap

    func test_advance_wrapsAround() {
        let vm = SlideshowViewModel(assets: [makeAsset(id: "a"), makeAsset(id: "b"), makeAsset(id: "c")])
        vm.start()
        vm.advance()
        XCTAssertEqual(vm.currentIndex, 1)
        vm.advance()
        XCTAssertEqual(vm.currentIndex, 2)
        vm.advance()
        XCTAssertEqual(vm.currentIndex, 0)
        vm.advance()
        XCTAssertEqual(vm.currentIndex, 1)
    }

    func test_advance_noop_whilePaused() {
        let vm = SlideshowViewModel(assets: [makeAsset(id: "a"), makeAsset(id: "b")], startIndex: 1)
        vm.advance()
        XCTAssertEqual(vm.currentIndex, 1)
        vm.togglePlayPause()
        vm.advance()
        XCTAssertEqual(vm.currentIndex, 0)
    }

    func test_advance_noop_whileVideoActive() {
        let assets = [makeAsset(id: "photo"), makeAsset(id: "clip", video: true)]
        let vm = SlideshowViewModel(assets: assets, startIndex: 1)
        vm.start()
        vm.slideChanged()
        XCTAssertTrue(vm.isVideoActive)
        vm.advance()
        XCTAssertEqual(vm.currentIndex, 1)
    }

    func test_videoEnded_resumesAdvance() {
        let assets = [makeAsset(id: "photo"), makeAsset(id: "clip", video: true)]
        let vm = SlideshowViewModel(assets: assets, startIndex: 1)
        vm.start()
        vm.slideChanged()
        XCTAssertTrue(vm.isVideoActive)
        vm.videoEnded()
        XCTAssertFalse(vm.isVideoActive)
        vm.advance()
        XCTAssertEqual(vm.currentIndex, 0)
    }

    func test_slideChanged_clearsVideoActiveOnStill() {
        let assets = [makeAsset(id: "clip", video: true), makeAsset(id: "photo")]
        let vm = SlideshowViewModel(assets: assets, startIndex: 0)
        vm.start()
        vm.slideChanged()
        XCTAssertTrue(vm.isVideoActive)
        vm.next()
        XCTAssertEqual(vm.currentIndex, 1)
        vm.slideChanged()
        XCTAssertFalse(vm.isVideoActive)
    }

    // MARK: - Manual navigation (allowed while paused)

    func test_next_previous_wrapWhilePaused() {
        let vm = SlideshowViewModel(assets: [makeAsset(id: "a"), makeAsset(id: "b"), makeAsset(id: "c")])
        vm.previous()
        XCTAssertEqual(vm.currentIndex, 2)
        vm.next()
        XCTAssertEqual(vm.currentIndex, 0)
    }

    func test_singleAsset_neverLeavesZero() {
        let vm = SlideshowViewModel(assets: [makeAsset(id: "only")])
        vm.start()
        vm.advance()
        XCTAssertEqual(vm.currentIndex, 0)
        vm.next()
        XCTAssertEqual(vm.currentIndex, 0)
        vm.previous()
        XCTAssertEqual(vm.currentIndex, 0)
    }

    // MARK: - Transport + speed

    func test_startStopToggle() {
        let vm = SlideshowViewModel(assets: [makeAsset(id: "a")])
        vm.start()
        XCTAssertTrue(vm.isPlaying)
        vm.stop()
        XCTAssertFalse(vm.isPlaying)
        vm.togglePlayPause()
        XCTAssertTrue(vm.isPlaying)
        vm.togglePlayPause()
        XCTAssertFalse(vm.isPlaying)
    }

    func test_speedChange() {
        let vm = SlideshowViewModel(assets: [makeAsset(id: "a")])
        XCTAssertEqual(vm.speed, .threeSeconds)
        vm.speed = .tenSeconds
        XCTAssertEqual(vm.speed, .tenSeconds)
        XCTAssertEqual(SlideshowViewModel.SlideshowSpeed.allCases.count, 4)
    }

    func test_goTo_clamps() {
        let vm = SlideshowViewModel(assets: [makeAsset(id: "a"), makeAsset(id: "b")])
        vm.goTo(index: 5)
        XCTAssertEqual(vm.currentIndex, 1)
    }
}