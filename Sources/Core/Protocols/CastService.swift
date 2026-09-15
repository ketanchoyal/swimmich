import Foundation

/// Thin, injectable seam over "send what I'm looking at to a screen" (gap G9).
///
/// The seam is not decorative: the two ways an asset can leave the device
/// disagree on who fetches the bytes. AirPlay hands the stream to the route
/// while the phone stays the HTTP client (`AVVideoPlaybackEngine` keeps sending
/// its Bearer token), whereas a Cast receiver downloads the media itself and
/// needs an unauthenticated, session-keyed URL. `supportsStillImages` carries
/// the same fork for the asset kind — AirPlay routes a video stream, never a
/// still image — and `CastViewModel` projects it so the viewer's sheet can tell
/// the user the truth instead of leaving a control that cannot work.
///
/// Only the facts the UI renders are exposed: `AirPlayCastService` owns
/// `AVRouteDetector` / `AVAudioSession`, and unit tests use `MockCastService`
/// (no window, no route, no AVFoundation objects).
@MainActor protocol CastService: AnyObject {
    /// An external screen is reachable right now.
    var isAvailable: Bool { get }
    /// The current output route is that screen.
    var isConnected: Bool { get }
    /// Display name of the connected route, when there is one.
    var connectedRouteName: String? { get }
    /// Whether a still image can be sent to the route: false for AirPlay, true
    /// for a receiver that fetches a fullsize thumbnail for itself.
    var supportsStillImages: Bool { get }

    /// Starts watching route changes. Called by the composition root, which
    /// holds the process-wide interest.
    func startObserving()
    /// Releases the calling owner's interest in route changes.
    func stopObserving()
}
