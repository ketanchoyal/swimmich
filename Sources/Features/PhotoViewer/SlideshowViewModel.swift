import Foundation
import Observation

/// Pure slideshow state machine — no Timer, no AVFoundation (unit-testable).
///
/// The VIEW owns the ticking loop (see `SlideshowView`): it runs a `.task(id:)`
/// loop re-armed whenever speed/play/video-active state changes, and calls
/// `advance()` only when `isPlaying` and the current slide is not an active
/// video. `slideChanged()` arms the video suspension when a video/Live-Photo
/// slide appears; `videoEnded()` releases it and moves on immediately (Photos
/// behavior: the slideshow pauses on a video and continues the instant it ends).
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

    /// Cross-slide transition flavor. `kenBurns` only affects stills (the
    /// image itself drifts); the cross-slide transition stays a crossfade.
    enum SlideshowTransitionStyle: String, CaseIterable, Identifiable {
        case dissolve
        case slide
        case kenBurns

        var id: String { rawValue }

        var label: String {
            switch self {
            case .dissolve: return "Fondu"
            case .slide: return "Glissement"
            case .kenBurns: return "Ken Burns"
            }
        }
    }

    // MARK: - State

    private(set) var currentIndex: Int
    private(set) var isPlaying = false
    var speed: SlideshowSpeed = .threeSeconds
    var transition: SlideshowTransitionStyle = .dissolve
    /// True while the current slide is a video/Live-Photo being played inline —
    /// the ticker must not advance during playback.
    private(set) var isVideoActive = false

    let assets: [AssetReactItem]
    /// Playback order: position → asset index. Identity until `shuffle()`.
    private(set) var order: [Int]

    var currentAsset: AssetReactItem? {
        guard order.indices.contains(currentIndex) else { return nil }
        let assetIndex = order[currentIndex]
        guard assets.indices.contains(assetIndex) else { return nil }
        return assets[assetIndex]
    }

    var count: Int { assets.count }

    // MARK: - Init

    init(assets: [AssetReactItem], startIndex: Int = 0) {
        self.assets = assets
        self.order = Array(assets.indices)
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

    /// Called via `VideoPlayerView.onStatusChange` on `.ended` AND `.failed` —
    /// releases the suspension and advances immediately (Photos skips a broken
    /// video). Idempotent: only advances if a video was actually active.
    func videoEnded() {
        let wasVideo = isVideoActive
        isVideoActive = false
        if wasVideo { advance() }
    }

    /// Jolts the state machine when the slide changes (view calls on
    /// `.onChange(of: currentIndex)`): a video/Live-Photo slide arms the
    /// suspension, a still clears it.
    func slideChanged() {
        if let asset = currentAsset, asset.hasPlayableMotion {
            isVideoActive = true
        } else {
            isVideoActive = false
        }
    }

    /// Randomizes the playback order while keeping the current asset on screen
    /// (no visual jump). No-op for fewer than two assets.
    func shuffle() {
        guard assets.count > 1 else { return }
        let currentAssetID = currentAsset?.id
        order.shuffle()
        if let id = currentAssetID, let newPosition = order.firstIndex(where: { assets[$0].id == id }) {
            currentIndex = newPosition
        } else {
            currentIndex = min(currentIndex, assets.count - 1)
        }
    }
}

/// Pure swipe/step direction helper for the cross-slide transition (unit-testable,
/// no SwiftUI): `isForward` decides whether moving `old → new` is a "next" step
/// (insertion from the trailing edge) or a "previous" step, accounting for wrap.
enum SlideshowDirection {
    static func isForward(from old: Int, to new: Int, count: Int) -> Bool {
        guard count > 1 else { return true }
        let forward = (new - old + count) % count
        let backward = (old - new + count) % count
        return forward <= backward
    }
}

/// Pure Ken Burns phase math (unit-testable, no SwiftUI): maps elapsed time to a
/// slow drift (scale 1.0→1.06 + gentle pan). Identity when Reduce Motion is on —
/// the image stays static.
struct KenBurnsPhase: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero

    static let identity = KenBurnsPhase()

    /// `elapsed` = seconds since an arbitrary epoch (e.g. reference date).
    /// Ping-pong drift over `period`: zoom in, then back out, with a subtle pan.
    static func progress(elapsed: TimeInterval, reduceMotion: Bool, period: TimeInterval = 16) -> KenBurnsPhase {
        guard !reduceMotion else { return .identity }
        let cycle = elapsed.truncatingRemainder(dividingBy: period * 2) / period   // 0..<2
        let pingPong = cycle <= 1 ? cycle : 2 - cycle                              // 0→1→0
        let scale = 1.0 + 0.06 * pingPong
        let pan = 8 * sin(pingPong * .pi * 2)
        return KenBurnsPhase(scale: scale, offset: CGSize(width: pan, height: pan * 0.5))
    }
}
