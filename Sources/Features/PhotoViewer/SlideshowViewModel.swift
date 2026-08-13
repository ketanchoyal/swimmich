import Foundation
import Observation

/// Pure slideshow state machine — no Timer, no AVFoundation (unit-testable).
///
/// The VIEW owns the ticking loop (see `SlideshowView`): it runs a
/// `Timer.publish` and calls `advance()` only when `isPlaying` and the current
/// slide is not an active video. `videoStarted()` / `videoEnded()` suspend and
/// resume the ticker around inline video playback (Photos behavior: the
/// slideshow pauses on a video and continues after it ends).
@MainActor
@Observable
final class SlideshowViewModel {

    enum SlideshowSpeed: TimeInterval, CaseIterable, Identifiable {
        case twoSeconds = 2
        case threeSeconds = 3
        case fiveSeconds = 5
        case tenSeconds = 10

        var id: TimeInterval { rawValue }

        var label: String { "\(Int(rawValue))s" }
    }

    // MARK: - State

    private(set) var currentIndex: Int
    private(set) var isPlaying = false
    var speed: SlideshowSpeed = .threeSeconds
    /// True while the current slide is a video being played inline — the
    /// ticker must not advance during playback.
    private(set) var isVideoActive = false

    let assets: [AssetReactItem]

    var currentAsset: AssetReactItem? {
        guard assets.indices.contains(currentIndex) else { return nil }
        return assets[currentIndex]
    }

    var count: Int { assets.count }

    // MARK: - Init

    init(assets: [AssetReactItem], startIndex: Int = 0) {
        self.assets = assets
        self.currentIndex = assets.isEmpty ? 0 : min(max(startIndex, 0), assets.count - 1)
    }

    // MARK: - Transport

    func start() { isPlaying = true }

    func stop() { isPlaying = false }

    func togglePlayPause() { isPlaying.toggle() }

    /// Advances one slide, wrapping at the end. No-op while paused or while a
    /// video is playing on the current slide (ticker gating, belt and braces).
    func advance() {
        guard isPlaying, !isVideoActive, !assets.isEmpty else { return }
        currentIndex = (currentIndex + 1) % assets.count
    }

    /// Manual next — allowed even while paused.
    func next() {
        guard !assets.isEmpty else { return }
        currentIndex = (currentIndex + 1) % assets.count
    }

    /// Manual previous — allowed even while paused.
    func previous() {
        guard !assets.isEmpty else { return }
        currentIndex = (currentIndex - 1 + assets.count) % assets.count
    }

    func goTo(index: Int) {
        guard !assets.isEmpty else { return }
        currentIndex = min(max(index, 0), assets.count - 1)
    }

    /// Called by the view when the current slide is a video that started
    /// playing — the ticker suspends until `videoEnded()`.
    func videoStarted() {
        guard let asset = currentAsset, asset.isVideo else { return }
        isVideoActive = true
    }

    /// Called via `VideoPlayerView.onPlaybackEnded` — the ticker resumes.
    func videoEnded() { isVideoActive = false }

    /// Jolts the state machine when the slide changes (view calls on
    /// `.onChange(of: currentIndex)`): a non-video slide never stays "video
    /// active", a video slide arms the suspension.
    func slideChanged() {
        if let asset = currentAsset, asset.isVideo {
            isVideoActive = true
        } else {
            isVideoActive = false
        }
    }
}