import Foundation
@testable import ImmichSwiftUI

/// Deterministic library source: canned candidates/albums + per-id payloads.
final class MockBackupAssetSource: BackupAssetSource, @unchecked Sendable {
    nonisolated(unsafe) var candidates: [BackupCandidate] = []
    nonisolated(unsafe) var albums: [BackupAlbum] = []
    nonisolated(unsafe) var dataProvider: (String) -> Data = { _ in Data() }
    nonisolated(unsafe) var loadError: Error?
    /// Called synchronously on the first `loadData` (cancel-path tests).
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

    func loadData(for candidate: BackupCandidate) async throws -> Data {
        onFirstLoad?()
        onFirstLoad = nil
        if let loadError { throw loadError }
        return dataProvider(candidate.id)
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