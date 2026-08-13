import XCTest
@testable import ImmichSwiftUI

@MainActor
final class VideoPlaybackViewModelTests: XCTestCase {

    private let baseURL = URL(string: "https://example.com")!

    private func makeVideoAsset(id: String = "v1", livePair: String? = nil) -> AssetReactItem {
        AssetReactItem(
            id: id, ownerId: "owner", ratio: 1.0, isFavorite: false, visibility: "timeline",
            isTrashed: false, isImage: false, thumbhash: nil,
            createdAt: "2024-07-01T00:00:00.000Z", fileCreatedAt: "2024-07-01T00:00:00.000Z",
            localOffsetHours: 0, duration: 12, livePhotoVideoId: livePair, projectionType: nil,
            city: nil, country: nil, latitude: nil, longitude: nil
        )
    }

    private func makeLivePhotoStill(id: String = "still-1", livePair: String? = "vid-9") -> AssetReactItem {
        AssetReactItem(
            id: id, ownerId: "owner", ratio: 1.0, isFavorite: false, visibility: "timeline",
            isTrashed: false, isImage: true, thumbhash: nil,
            createdAt: "2024-07-01T00:00:00.000Z", fileCreatedAt: "2024-07-01T00:00:00.000Z",
            localOffsetHours: 0, duration: nil, livePhotoVideoId: livePair, projectionType: nil,
            city: nil, country: nil, latitude: nil, longitude: nil
        )
    }

    // MARK: - Prepare / URL

    func test_prepare_uses_videoPlaybackEndpoint_and_PassesToken() async {
        let mock = MockVideoPlaybackEngine()
        let vm = VideoPlaybackViewModel(engine: mock)

        await vm.prepare(asset: makeVideoAsset(id: "v9"), baseURL: baseURL, token: "tok-123")

        XCTAssertEqual(mock.preparedURL?.path, "/api/assets/v9/video/playback")
        XCTAssertEqual(mock.preparedToken, "tok-123")
        XCTAssertEqual(mock.preparedURL?.host, "example.com")
    }

    func test_prepare_autoplays_afterReady() async {
        let mock = MockVideoPlaybackEngine()
        let vm = VideoPlaybackViewModel(engine: mock)

        await vm.prepare(asset: makeVideoAsset(), baseURL: baseURL, token: nil)

        XCTAssertEqual(vm.status, .playing)
        XCTAssertEqual(mock.playCount, 1)
        XCTAssertEqual(vm.duration, 30)
    }

    func test_prepare_failure_setsFailedState() async {
        let mock = MockVideoPlaybackEngine()
        mock.prepareError = URLError(.notConnectedToInternet)
        let vm = VideoPlaybackViewModel(engine: mock)

        await vm.prepare(asset: makeVideoAsset(), baseURL: baseURL, token: nil)

        guard case .failed(let message) = vm.status else {
            return XCTFail("expected failed, got \(vm.status)")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Play / Pause / Seek

    func test_togglePlayPause_transitions() async {
        let mock = MockVideoPlaybackEngine()
        let vm = VideoPlaybackViewModel(engine: mock)
        await vm.prepare(asset: makeVideoAsset(), baseURL: baseURL, token: nil)

        vm.pause()
        XCTAssertEqual(vm.status, .paused)
        XCTAssertEqual(mock.pauseCount, 1)

        vm.togglePlayPause()
        XCTAssertEqual(vm.status, .playing)
        XCTAssertEqual(mock.playCount, 2)
    }

    func test_seekBy_clampsToDuration() async {
        let mock = MockVideoPlaybackEngine()
        let vm = VideoPlaybackViewModel(engine: mock)
        await vm.prepare(asset: makeVideoAsset(), baseURL: baseURL, token: nil)

        mock.fireTimeUpdate(10)
        vm.seek(by: 15)
        XCTAssertEqual(vm.currentTime, 25)
        XCTAssertEqual(mock.lastSeek, 25)

        vm.seek(by: 60)
        XCTAssertEqual(vm.currentTime, 30)
        XCTAssertEqual(mock.lastSeek, 30)

        vm.seek(by: -100)
        XCTAssertEqual(vm.currentTime, 0)
        XCTAssertEqual(mock.lastSeek, 0)
    }

    func test_seekTo_scrubber_position() async {
        let mock = MockVideoPlaybackEngine()
        let vm = VideoPlaybackViewModel(engine: mock)
        await vm.prepare(asset: makeVideoAsset(), baseURL: baseURL, token: nil)

        vm.seek(to: 7.5)

        XCTAssertEqual(vm.currentTime, 7.5)
        XCTAssertEqual(mock.lastSeek, 7.5)
        XCTAssertEqual(vm.progress, 7.5 / 30, accuracy: 0.001)
    }

    // MARK: - End / Time / Retry

    func test_ended_setsState_and_replay_restarts() async {
        let mock = MockVideoPlaybackEngine()
        let vm = VideoPlaybackViewModel(engine: mock)
        await vm.prepare(asset: makeVideoAsset(), baseURL: baseURL, token: nil)

        mock.fireEnded()

        XCTAssertEqual(vm.status, .ended)
        XCTAssertEqual(vm.currentTime, 30)

        vm.replay()
        XCTAssertEqual(vm.status, .playing)
        XCTAssertEqual(mock.lastSeek, 0)
        XCTAssertEqual(mock.playCount, 2)
    }

    func test_timeUpdate_drivesProgress() async {
        let mock = MockVideoPlaybackEngine()
        let vm = VideoPlaybackViewModel(engine: mock)
        await vm.prepare(asset: makeVideoAsset(), baseURL: baseURL, token: nil)

        vm.pause()
        mock.fireTimeUpdate(15)

        XCTAssertEqual(vm.currentTime, 15)
        XCTAssertEqual(vm.progress, 0.5, accuracy: 0.001)
    }

    func test_retry_after_failure_rePrepares() async {
        let mock = MockVideoPlaybackEngine()
        mock.prepareError = URLError(.cannotConnectToHost)
        let vm = VideoPlaybackViewModel(engine: mock)
        await vm.prepare(asset: makeVideoAsset(), baseURL: baseURL, token: nil)
        guard case .failed = vm.status else {
            return XCTFail("expected failed")
        }

        vm.reset()
        XCTAssertEqual(vm.status, .idle)
        XCTAssertEqual(mock.reloadCount, 1)

        mock.prepareError = nil
        await vm.prepare(asset: makeVideoAsset(), baseURL: baseURL, token: nil)

        XCTAssertEqual(vm.status, .playing)
        XCTAssertEqual(mock.playCount, 1)
    }

    func test_engineFailureHook_setsFailed() async {
        let mock = MockVideoPlaybackEngine()
        let vm = VideoPlaybackViewModel(engine: mock)
        await vm.prepare(asset: makeVideoAsset(), baseURL: baseURL, token: nil)

        mock.fireFailure("stream unavailable")

        guard case .failed(let message) = vm.status else {
            return XCTFail("expected failed")
        }
        XCTAssertEqual(message, "stream unavailable")
    }

    // MARK: - Live Photo pair (P1)

    func test_P1_livePhoto_pairUsesPairAssetID() async {
        let mock = MockVideoPlaybackEngine()
        let vm = VideoPlaybackViewModel(engine: mock)
        let still = makeLivePhotoStill(livePair: "vid-42")

        await vm.prepareLivePhoto(asset: still, baseURL: baseURL, token: "tok-lp")

        XCTAssertEqual(vm.preparedAssetID, "vid-42")
        XCTAssertEqual(mock.preparedURL?.path, "/api/assets/vid-42/video/playback")
        XCTAssertEqual(mock.preparedToken, "tok-lp")
        XCTAssertEqual(vm.status, .playing)
    }

    func test_P1_livePhoto_prepareByID_override() async {
        let mock = MockVideoPlaybackEngine()
        let vm = VideoPlaybackViewModel(engine: mock)

        await vm.prepare(assetID: "vid-7", baseURL: baseURL, token: nil)

        XCTAssertEqual(vm.preparedAssetID, "vid-7")
        XCTAssertEqual(mock.preparedURL?.path, "/api/assets/vid-7/video/playback")
    }

    func test_P1_livePhoto_missingPair_fails() async {
        let mock = MockVideoPlaybackEngine()
        let vm = VideoPlaybackViewModel(engine: mock)
        let orphan = makeLivePhotoStill(livePair: nil)

        await vm.prepareLivePhoto(asset: orphan, baseURL: baseURL, token: nil)

        guard case .failed(let message) = vm.status else {
            return XCTFail("expected failed, got \(vm.status)")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertNil(mock.preparedURL, "engine must not prepare without a pair")
        XCTAssertEqual(mock.playCount, 0)
    }
}