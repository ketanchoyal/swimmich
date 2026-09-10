import Foundation
import Photos

/// `PHPhotoLibraryChangeObserver` that wakes the backup only when photos were
/// *inserted* while the app is in the foreground.
///
/// Two decisions matter here:
///
/// - **Filter on `insertedObjects`.** Waking on every change would turn any
///   edit, favorite or deletion into a full library scan — the hottest path in
///   the engine. Only additions are worth a run.
/// - **Debounce.** One import produces a burst of change callbacks (a burst
///   capture, an AirDrop of 50 files, a mass edit). Coalescing them keeps that
///   burst to a single scan.
///
/// The observer only exists while the app is active: `DependencyContainer`
/// starts it on `.active` and stops it on `.background`, so it never races the
/// BGTask window.
final class PhotoLibraryChangeMonitor: NSObject, PHPhotoLibraryChangeObserver,
                                        PhotoLibraryChangeMonitoring, @unchecked Sendable {
    /// Delay before firing after the last insertion — long enough to merge an
    /// import burst, short enough that a photo taken now starts uploading
    /// within seconds. Injectable for tests.
    private let debounce: TimeInterval

    private let lock = NSLock()
    private var started = false
    private var baseline: PHFetchResult<PHAsset>?
    private var debounceTask: Task<Void, Never>?

    /// Set from the wiring layer, read on the main actor.
    @MainActor var onAssetsInserted: (@MainActor @Sendable () -> Void)?

    init(debounce: TimeInterval = 5) {
        self.debounce = debounce
        super.init()
    }

    deinit {
        // Never leave a registered observer behind: Photos holds it weakly but
        // the callback would land on a half-torn-down object.
        if started { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    }

    func start() {
        lock.lock()
        let alreadyStarted = started
        started = true
        lock.unlock()
        guard !alreadyStarted else { return }

        // Only identifiers are read, so no property prefetch is needed here —
        // unlike the candidate scan, this must stay cheap.
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let baseline = PHAsset.fetchAssets(with: options)
        lock.lock()
        self.baseline = baseline
        lock.unlock()
        PHPhotoLibrary.shared().register(self)
    }

    func stop() {
        lock.lock()
        let wasStarted = started
        started = false
        let task = debounceTask
        debounceTask = nil
        baseline = nil
        lock.unlock()
        task?.cancel()
        guard wasStarted else { return }
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // MARK: - PHPhotoLibraryChangeObserver

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        lock.lock()
        let baseline = self.baseline
        let isStarted = started
        lock.unlock()
        guard isStarted, let baseline,
              let details = changeInstance.changeDetails(for: baseline),
              !details.insertedObjects.isEmpty
        else { return }

        // Advance the baseline even when the debounce is later cancelled —
        // otherwise every subsequent change would diff against a stale result
        // and re-report the same insertions.
        lock.lock()
        self.baseline = details.fetchResultAfterChanges
        debounceTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.debounce * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self.onAssetsInserted?() }
        }
        debounceTask = task
        lock.unlock()
    }
}
