import XCTest
@testable import ImmichSwiftUI

/// Deterministic state-machine tests — the ticking loop is view-owned
/// (`.task(id:)` in SlideshowView), so no Timer and no AVFoundation here.
@MainActor
final class SlideshowViewModelTests: XCTestCase {

    private func makeAsset(id: String, video: Bool = false, livePhoto: Bool = false) -> AssetReactItem {
        AssetReactItem(
            id: id, ownerId: "owner", ratio: 1.0, isFavorite: false, visibility: "timeline",
            isTrashed: false, isImage: !video, thumbhash: nil,
            createdAt: "2024-07-01T00:00:00.000Z", fileCreatedAt: "2024-07-01T00:00:00.000Z",
            localOffsetHours: 0, duration: video ? 12 : nil, livePhotoVideoId: livePhoto ? "pair-\(id)" : nil,
            projectionType: nil, city: nil, country: nil, latitude: nil, longitude: nil, stack: []
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

    func test_init_identityOrder() {
        let vm = SlideshowViewModel(assets: [makeAsset(id: "a"), makeAsset(id: "b"), makeAsset(id: "c")])
        XCTAssertEqual(vm.order, [0, 1, 2])
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

    // MARK: - videoEnded (B2/B3: immediate advance, idempotent, skip on failure)

    func test_videoEnded_advancesImmediately() {
        let assets = [makeAsset(id: "photo"), makeAsset(id: "clip", video: true)]
        let vm = SlideshowViewModel(assets: assets, startIndex: 1)
        vm.start()
        vm.slideChanged()
        XCTAssertTrue(vm.isVideoActive)
        vm.videoEnded()
        XCTAssertFalse(vm.isVideoActive)
        XCTAssertEqual(vm.currentIndex, 0)
    }

    func test_videoEnded_noopWhenPaused() {
        let assets = [makeAsset(id: "photo"), makeAsset(id: "clip", video: true)]
        let vm = SlideshowViewModel(assets: assets, startIndex: 1)
        vm.slideChanged()
        XCTAssertTrue(vm.isVideoActive)
        vm.videoEnded()
        XCTAssertFalse(vm.isVideoActive)
        XCTAssertEqual(vm.currentIndex, 1)
    }

    func test_videoEnded_idempotent() {
        let assets = [makeAsset(id: "photo"), makeAsset(id: "clip", video: true)]
        let vm = SlideshowViewModel(assets: assets, startIndex: 1)
        vm.start()
        vm.slideChanged()
        vm.videoEnded()
        vm.videoEnded()
        XCTAssertEqual(vm.currentIndex, 0)
    }

    func test_videoEnded_noopOnStillSlide() {
        let vm = SlideshowViewModel(assets: [makeAsset(id: "a"), makeAsset(id: "b")], startIndex: 0)
        vm.start()
        vm.videoEnded()
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

    // MARK: - Live Photos (F4) + motion detection

    func test_hasPlayableMotion() {
        XCTAssertTrue(makeAsset(id: "v", video: true).hasPlayableMotion)
        XCTAssertFalse(makeAsset(id: "p").hasPlayableMotion)
        XCTAssertTrue(makeAsset(id: "l", livePhoto: true).hasPlayableMotion)
    }

    func test_slideChanged_armsLivePhoto() {
        let assets = [makeAsset(id: "l", livePhoto: true), makeAsset(id: "p")]
        let vm = SlideshowViewModel(assets: assets, startIndex: 0)
        vm.start()
        vm.slideChanged()
        XCTAssertTrue(vm.isVideoActive)
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

    // MARK: - Transport + speed + transition

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

    func test_transition_defaultDissolve() {
        let vm = SlideshowViewModel(assets: [makeAsset(id: "a")])
        XCTAssertEqual(vm.transition, .dissolve)
    }

    func test_goTo_clamps() {
        let vm = SlideshowViewModel(assets: [makeAsset(id: "a"), makeAsset(id: "b")])
        vm.goTo(index: 5)
        XCTAssertEqual(vm.currentIndex, 1)
    }

    // MARK: - Shuffle (F5)

    func test_shuffle_coversAllIndices() {
        let assets = (0..<10).map { makeAsset(id: "\($0)") }
        let vm = SlideshowViewModel(assets: assets)
        vm.shuffle()
        XCTAssertEqual(Set(vm.order), Set(0..<10))
        XCTAssertEqual(vm.count, 10)
    }

    func test_shuffle_preservesCurrentAsset() {
        let assets = [makeAsset(id: "a"), makeAsset(id: "b"), makeAsset(id: "c"), makeAsset(id: "d")]
        let vm = SlideshowViewModel(assets: assets, startIndex: 2)
        let currentID = vm.currentAsset?.id
        vm.shuffle()
        XCTAssertEqual(vm.currentAsset?.id, currentID)
    }

    func test_shuffle_singleAssetNoop() {
        let vm = SlideshowViewModel(assets: [makeAsset(id: "only")])
        vm.shuffle()
        XCTAssertEqual(vm.order, [0])
    }
}

// MARK: - Pure helpers (no @MainActor needed)

final class SlideshowHelpersTests: XCTestCase {

    // MARK: SlideshowDirection

    func test_direction_forwardNormal() {
        XCTAssertTrue(SlideshowDirection.isForward(from: 0, to: 1, count: 5))
        XCTAssertFalse(SlideshowDirection.isForward(from: 1, to: 0, count: 5))
    }

    func test_direction_wrap() {
        XCTAssertTrue(SlideshowDirection.isForward(from: 4, to: 0, count: 5))
        XCTAssertFalse(SlideshowDirection.isForward(from: 0, to: 4, count: 5))
    }

    func test_direction_singleAsset() {
        XCTAssertTrue(SlideshowDirection.isForward(from: 0, to: 0, count: 1))
    }

    // MARK: KenBurnsPhase

    func test_kenBurns_identityWhenReduceMotion() {
        let phase = KenBurnsPhase.progress(elapsed: 5, reduceMotion: true)
        XCTAssertEqual(phase.scale, 1.0)
        XCTAssertEqual(phase.offset, .zero)
    }

    func test_kenBurns_scaleWithinBounds() {
        for t in stride(from: 0.0, through: 64.0, by: 0.25) {
            let scale = KenBurnsPhase.progress(elapsed: t, reduceMotion: false).scale
            XCTAssertGreaterThanOrEqual(scale, 1.0)
            XCTAssertLessThanOrEqual(scale, 1.06 + 0.0001)
        }
    }

    func test_kenBurns_periodic() {
        let a = KenBurnsPhase.progress(elapsed: 2, reduceMotion: false)
        let b = KenBurnsPhase.progress(elapsed: 34, reduceMotion: false)
        XCTAssertEqual(a.scale, b.scale, accuracy: 0.001)
    }

    func test_kenBurns_peakAtMidCycle() {
        let peak = KenBurnsPhase.progress(elapsed: 16, reduceMotion: false)
        XCTAssertEqual(peak.scale, 1.06, accuracy: 0.001)
    }
}
