import Foundation

/// Foreground wake-up for "new photos". iOS has no equivalent of Android's
/// content-URI triggers, so the only ways a backup can start are: scene
/// activation, an OS `BGTaskScheduler` window, and — while the app is actually
/// running — a Photos change callback. This is that last one.
///
/// Behind a protocol so the scene/settings wiring is testable without
/// `PHPhotoLibrary` (the production monitor cannot be exercised in a unit test).
protocol PhotoLibraryChangeMonitoring: AnyObject, Sendable {
    /// Called on the main actor, debounced, and only after assets were
    /// *inserted* — an edit, a favorite or a deletion does not wake the backup.
    var onAssetsInserted: (@MainActor @Sendable () -> Void)? { get set }

    /// Starts observing. Idempotent.
    func start()

    /// Stops observing and drops the baseline. Idempotent.
    func stop()
}
