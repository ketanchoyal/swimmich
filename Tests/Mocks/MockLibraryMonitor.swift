import Foundation
@testable import ImmichSwiftUI

/// Records start/stop and lets a test fire the insertion callback by hand —
/// the production monitor is an observer of the real `PHPhotoLibrary` and
/// cannot be exercised in a unit test, so the wiring is what gets covered.
final class MockLibraryMonitor: PhotoLibraryChangeMonitoring, @unchecked Sendable {
    nonisolated(unsafe) var startCount = 0
    nonisolated(unsafe) var stopCount = 0

    @MainActor var onAssetsInserted: (@MainActor @Sendable () -> Void)?

    var isRunning: Bool { startCount > stopCount }

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }

    /// Simulates Photos reporting inserted assets.
    @MainActor
    func simulateInsertion() {
        onAssetsInserted?()
    }
}
