import BackgroundTasks
import Foundation

/// Builds + submits a one-shot background backup request (testable seam).
protocol BackgroundBackupScheduling: Sendable {
    func submit()
}

/// BGTaskScheduler-backed scheduler. One submitted request = one engine run;
/// the app resubmits at the end of every run.
struct BGTaskBackupScheduler: BackgroundBackupScheduling, @unchecked Sendable {
    static let taskIdentifier = "app.immich.background-backup"

    func submit() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }
}