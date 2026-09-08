import Foundation
@testable import ImmichSwiftUI

/// Deterministic library source: canned candidates/albums + per-id payloads.
final class MockBackupAssetSource: BackupAssetSource, @unchecked Sendable {
    nonisolated(unsafe) var candidates: [BackupCandidate] = []
    nonisolated(unsafe) var albums: [BackupAlbum] = []
    nonisolated(unsafe) var dataProvider: (String) -> Data = { _ in Data() }
    nonisolated(unsafe) var loadError: Error?
    /// Invoked exactly once on the first `exportOriginal` — cancellation-path
    /// tests must be idempotent (the engine loops through all candidates
    /// before honoring the flag).
    nonisolated(unsafe) var onFirstLoad: (() -> Void)?
    nonisolated(unsafe) var lastAlbumIDs: Set<String>?

    private let fetchLock = NSLock()

    func fetchAlbums() -> [BackupAlbum] { albums }

    func fetchCandidates(in albumIDs: Set<String>) -> [BackupCandidate] {
        fetchLock.lock()
        lastAlbumIDs = albumIDs
        fetchLock.unlock()
        return candidates
    }

    func exportOriginal(for candidate: BackupCandidate) async throws -> URL {
        onFirstLoad?()
        onFirstLoad = nil
        if let loadError { throw loadError }
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("immich-test-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString)-\(candidate.fileName)")
        try dataProvider(candidate.id).write(to: url)
        return url
    }
}

/// Deterministic environment — tests toggle the gates by hand.
final class MockBackupEnvironment: BackupEnvironment, @unchecked Sendable {
    nonisolated(unsafe) var isChargingValue = true
    nonisolated(unsafe) var hasWiFiValue = true

    var isCharging: Bool { isChargingValue }
    var hasWiFiConnection: Bool { hasWiFiValue }
}

/// Records submissions; production analog is BGTaskScheduler.
final class MockBackupScheduler: BackgroundBackupScheduling, @unchecked Sendable {
    nonisolated(unsafe) var submitCount = 0
    func submit() { submitCount += 1 }
}