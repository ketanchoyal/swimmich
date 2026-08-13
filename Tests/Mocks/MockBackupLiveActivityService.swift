import Foundation
@testable import ImmichSwiftUI

/// Test double for `BackupLiveActivityServicing` — records every call, no
/// ActivityKit involvement (hermetic unit tests).
final class MockBackupLiveActivityService: BackupLiveActivityServicing, @unchecked Sendable {
    private let lock = NSLock()

    private(set) var startCalls: [(uploaded: Int, total: Int)] = []
    private(set) var updateCalls: [(uploaded: Int, total: Int)] = []
    private(set) var endCalls: [(uploaded: Int, total: Int, success: Bool)] = []

    func start(uploaded: Int, total: Int) {
        lock.lock(); defer { lock.unlock() }
        startCalls.append((uploaded, total))
    }

    func update(uploaded: Int, total: Int) {
        lock.lock(); defer { lock.unlock() }
        updateCalls.append((uploaded, total))
    }

    func end(uploaded: Int, total: Int, success: Bool) {
        lock.lock(); defer { lock.unlock() }
        endCalls.append((uploaded, total, success))
    }
}