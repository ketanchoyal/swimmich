import Foundation
import UserNotifications

/// Local-notification seam for backup completion (gap #8). The real
/// implementation talks to UNUserNotificationCenter; tests inject a recorder.
protocol BackupNotificationServicing: AnyObject {
    func requestAuthorization()
    func notifyBackupComplete(uploaded: Int, total: Int, failed: Int, success: Bool)
}

/// UNUserNotificationCenter-backed notifier. Posts a single local notification
/// when a backup run finishes, so a background backup still surfaces its result.
final class BackupNotificationService: BackupNotificationServicing {
    nonisolated init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func notifyBackupComplete(uploaded: Int, total: Int, failed: Int, success: Bool) {
        let content = UNMutableNotificationContent()
        if success {
            content.title = "Backup complete"
            content.body = "\(uploaded) photos uploaded, \(failed) failed."
        } else {
            content.title = "Backup finished with errors"
            content.body = "\(uploaded) uploaded, \(failed) failed."
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
