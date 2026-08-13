import ActivityKit
import Foundation
import ImmichSharedKit

/// Live Activity driver seam. The real implementation talks ActivityKit;
/// tests inject a recorder. ActivityKit itself is not hermetic in unit tests.
protocol BackupLiveActivityServicing: AnyObject {
    func start(uploaded: Int, total: Int)
    func update(uploaded: Int, total: Int)
    func end(uploaded: Int, total: Int, success: Bool)
}

/// ActivityKit-backed Live Activity for backup progress (Dynamic Island +
/// Lock Screen). The `BackupActivityAttributes` type lives in the widget
/// extension target (`ImmichWidgets`) and is imported from there.
final class LiveActivityBackupService: BackupLiveActivityServicing {
    private var current: Activity<BackupActivityAttributes>?

    nonisolated init() {}

    func start(uploaded: Int, total: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = BackupActivityAttributes.ContentState(
            progress: progress(uploaded: uploaded, total: total),
            uploaded: uploaded,
            total: total
        )
        current = try? Activity.request(
            attributes: BackupActivityAttributes(totalCount: total),
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    func update(uploaded: Int, total: Int) {
        guard let current else { return }
        let state = BackupActivityAttributes.ContentState(
            progress: progress(uploaded: uploaded, total: total),
            uploaded: uploaded,
            total: total
        )
        Task {
            await current.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end(uploaded: Int, total: Int, success: Bool) {
        guard let current else { return }
        let state = BackupActivityAttributes.ContentState(
            progress: success ? 1 : progress(uploaded: uploaded, total: total),
            uploaded: uploaded,
            total: total
        )
        Task {
            await current.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.current = nil
    }

    private func progress(uploaded: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(Double(uploaded) / Double(total), 1)
    }
}