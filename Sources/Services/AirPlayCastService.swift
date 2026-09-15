import AVFoundation
import Foundation

/// The one `CastService` implementation shipped today: AirPlay.
///
/// iOS, not this app, owns route discovery and selection: `AVRouteDetector`
/// publishes a single boolean ("more than the local route is reachable") and
/// `AVRoutePickerView` presents the system picker. There is therefore no
/// `connect()` on the seam — no public API lets an app route a stream on the
/// user's behalf — and the sheet never enumerates devices it cannot see.
///
/// `@Observable` (and not `ObservableObject`) is the repository's convention for
/// anything a view reads directly: `PhotoViewer` renders the cast badge from
/// `isAvailable` / `isConnected` through the `any CastService` existential, with
/// no duplicated `@State` copy to resynchronise when a route changes outside the
/// app.
@MainActor @Observable final class AirPlayCastService: CastService {

    /// AirPlay hands a video/audio stream to the route; the protocol has no
    /// path for a still image, so a photo can only be shown on the phone
    /// (Screen Mirroring, from Control Center, is the sole exception and it is
    /// not drivable by an app). Written as a stored constant on purpose: the
    /// sheet asks the service, it does not guess.
    let supportsStillImages = false

    private let detector = AVRouteDetector()
    private var routeObserver: NSObjectProtocol?
    private var resetObserver: NSObjectProtocol?
    private var detectionObserver: NSObjectProtocol?

    private(set) var isAvailable = false
    private(set) var isConnected = false
    private(set) var connectedRouteName: String?

    /// How many owners want route observation right now. The composition root
    /// holds one for the whole process and a cast sheet takes a second one while
    /// it is open, so the detector and the notifications are only released when
    /// the last interest goes away: dismissing the sheet must never freeze the
    /// viewer's badge in a stale state.
    private var interests = 0

    func startObserving() {
        interests += 1
        guard interests == 1 else {
            // Already watching: the new owner only needs current state.
            refresh()
            return
        }
        detector.isRouteDetectionEnabled = true

        let center = NotificationCenter.default
        routeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        resetObserver = center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // `isAvailable` below is read from `multipleRoutesDetected`, and this is
        // the notification that says it moved: a screen appearing on the Wi-Fi
        // moves no audio route, so without it the badge would stay disabled —
        // and, since the badge is the only way into the sheet, the user would
        // have no way to refresh it.
        detectionObserver = center.addObserver(
            forName: .AVRouteDetectorMultipleRoutesDetectedDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func stopObserving() {
        guard interests > 0 else { return }
        interests -= 1
        guard interests == 0 else { return }

        let center = NotificationCenter.default
        if let routeObserver { center.removeObserver(routeObserver) }
        if let resetObserver { center.removeObserver(resetObserver) }
        if let detectionObserver { center.removeObserver(detectionObserver) }
        routeObserver = nil
        resetObserver = nil
        detectionObserver = nil
        detector.isRouteDetectionEnabled = false
    }

    /// Re-reads the two facts the UI shows. Also fired by headphone / Bluetooth
    /// route changes — the badge stays stable through them because only a
    /// `.airPlay` output counts as connected.
    private func refresh() {
        // `AVRouteDetector` has no `routeDetected` member on the iOS 26 SDK;
        // `multipleRoutesDetected` ("more than the local route") is the only
        // reachability fact it publishes, and it is exactly the condition under
        // which AVKit documents its picker as usable.
        isAvailable = detector.multipleRoutesDetected

        let airPlay = AVAudioSession.sharedInstance().currentRoute.outputs
            .first { $0.portType == .airPlay }
        isConnected = airPlay != nil
        connectedRouteName = airPlay?.portName
    }
}
