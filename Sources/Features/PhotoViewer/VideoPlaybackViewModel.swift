import Foundation

/// State machine for one full-screen video page in the photo viewer.
///
/// Owns playback state; the concrete AVFoundation player lives behind the
/// injectable `engine` seam, so unit tests exercise every transition with
/// `MockVideoPlaybackEngine`. Auto-plays once prepared (Photos behavior).
@Observable @MainActor
final class VideoPlaybackViewModel {

    private(set) var status: VideoPlaybackStatus = .idle
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var preparedAssetID: String?

    let engine: any VideoPlaybackEngine

    init(engine: any VideoPlaybackEngine = AVVideoPlaybackEngine()) {
        self.engine = engine
        // Hooks stay synchronous: the concrete engine fires them on the main
        // queue (time observer + end notification), and the mock fires them
        // synchronously in tests — no async hop needed.
        engine.onTimeUpdate = { [weak self] seconds in
            self?.applyTime(seconds)
        }
        engine.onReady = { [weak self] seconds in
            guard let self else { return }
            self.duration = seconds
            self.status = .ready
            self.play()
        }
        engine.onEnded = { [weak self] in
            guard let self else { return }
            self.currentTime = self.duration
            self.status = .ended
        }
        engine.onFailure = { [weak self] message in
            self?.status = .failed(message)
        }
    }

    /// Prepares the video page for `asset` against `baseURL` (HLS playback
    /// URL via `ImmichAssetURL.videoPlayback`) and auto-plays.
    func prepare(asset: AssetReactItem, baseURL: URL, token: String?) async {
        let url = ImmichAssetURL.videoPlayback(assetId: asset.id, baseURL: baseURL)
        await prepare(url: url, assetID: asset.id, token: token)
    }

    /// Re-entrant safe core — tests call this directly with a crafted URL.
    func prepare(url: URL, assetID: String, token: String?) async {
        guard status != .preparing else { return }
        status = .preparing
        preparedAssetID = assetID
        currentTime = 0
        duration = 0
        do {
            try await engine.prepare(url: url, token: token)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func togglePlayPause() {
        switch status {
        case .playing:
            pause()
        case .ready, .paused, .ended:
            play()
        case .idle, .preparing, .failed:
            break
        }
    }

    func play() {
        guard status != .preparing else { return }
        engine.play()
        status = .playing
    }

    func pause() {
        engine.pause()
        if status == .playing { status = .paused }
    }

    /// Replay from the start after the movie finished (Photos parity).
    func replay() {
        seek(to: 0)
        play()
    }

    /// Jumps ±15 s (Photos' go-backward/forward 15 buttons).
    func seek(by seconds: Double) {
        let target = (currentTime + seconds).clamped(to: 0...max(duration, currentTime))
        seek(to: target)
    }

    func seek(to seconds: Double) {
        let target = max(0, seconds)
        engine.seek(to: target)
        currentTime = target
    }

    /// 0...1 scrubber position.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var errorMessage: String? {
        if case .failed(let message) = status { return message }
        return nil
    }

    /// Tears down a failed engine (drops the stuck item) so a Retry can
    /// re-prepare cleanly.
    func reset() {
        engine.reload()
        status = .idle
        preparedAssetID = nil
        currentTime = 0
        duration = 0
    }

    // MARK: - Engine hooks

    private func applyTime(_ seconds: Double) {
        currentTime = max(0, seconds)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}