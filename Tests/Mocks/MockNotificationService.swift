import Foundation
@testable import ImmichSwiftUI

/// Records what the app asked of the notification center, and answers with
/// whatever the test decided the system would say.
@MainActor
final class MockNotificationService: NotificationServicing {
    var permissionResult: NotificationPermission = .notDetermined
    var requestResult: NotificationPermission = .authorized

    private(set) var permissionReads = 0
    private(set) var requestCount = 0
    private(set) var notifiedBackups: [(uploaded: Int, total: Int, failed: Int, success: Bool)] = []

    /// Awaited inside `requestAuthorization` — lets a test park a request in
    /// flight and prove the view model doesn't start a second one.
    var beforeRequestReturns: (@MainActor () async -> Void)?

    func permission() async -> NotificationPermission {
        permissionReads += 1
        return permissionResult
    }

    func requestAuthorization() async -> NotificationPermission {
        requestCount += 1
        await beforeRequestReturns?()
        return requestResult
    }

    func notifyBackupComplete(uploaded: Int, total: Int, failed: Int, success: Bool) async {
        notifiedBackups.append((uploaded, total, failed, success))
    }
}
