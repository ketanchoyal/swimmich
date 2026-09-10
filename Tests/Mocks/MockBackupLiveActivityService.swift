import Foundation
@testable import ImmichSwiftUI

/// Test double for `BackupLiveActivityServicing` — records every call, no
/// ActivityKit involvement (hermetic unit tests). The flattened tuples keep
/// existing assertions (`processed` / `total` / `success`) valid; the full
/// snapshots carry the richer breakdown the widget now consumes.
final class MockBackupLiveActivityService: BackupLiveActivityServicing, @unchecked Sendable {
    private let lock = NSLock()

    private(set) var startCalls: [(processed: Int, total: Int)] = []
    private(set) var updateCalls: [(processed: Int, total: Int)] = []
    private(set) var endCalls: [(processed: Int, total: Int, success: Bool)] = []
    private(set) var startSnapshots: [BackupActivitySnapshot] = []
    private(set) var updateSnapshots: [BackupActivitySnapshot] = []
    private(set) var endSnapshots: [(success: Bool, snapshot: BackupActivitySnapshot)] = []

    func start(_ snapshot: BackupActivitySnapshot) {
        lock.lock(); defer { lock.unlock() }
        startCalls.append((snapshot.processed, snapshot.total))
        startSnapshots.append(snapshot)
    }

    func update(_ snapshot: BackupActivitySnapshot) {
        lock.lock(); defer { lock.unlock() }
        updateCalls.append((snapshot.processed, snapshot.total))
        updateSnapshots.append(snapshot)
    }

    func end(success: Bool, snapshot: BackupActivitySnapshot) {
        lock.lock(); defer { lock.unlock() }
        endCalls.append((snapshot.processed, snapshot.total, success))
        endSnapshots.append((success, snapshot))
    }
}
