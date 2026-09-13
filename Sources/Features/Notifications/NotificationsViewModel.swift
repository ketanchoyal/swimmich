import Foundation
import Observation

/// Notification permission surface (issue #16).
///
/// The app posts exactly one kind of notification today — the local
/// "backup complete" alert — and it used to ask for the permission in
/// fire-and-forget at the start of every run, with nowhere to see the answer.
/// iOS shows that prompt **once per install**, so a denied user needs a screen
/// that says so and hands them to System Settings; that is what this drives
/// (same shape as the Flutter client's `notification_setting.dart`).
@MainActor
@Observable
final class NotificationsViewModel {
    private let service: any NotificationServicing

    private(set) var permission: NotificationPermission = .notDetermined
    /// True once the system's answer has been read — before that, the screen
    /// must not claim anything (it would flash "Enable" over an already-denied
    /// status).
    private(set) var loaded = false
    /// An authorization request is in flight; the button shows its progress.
    private(set) var isRequesting = false

    var isEnabled: Bool { permission.isEnabled }

    /// Only a never-asked install can be asked: from `.denied`, iOS silently
    /// ignores `requestAuthorization` and no prompt appears, so offering
    /// "Enable" again would be a dead button.
    var canAsk: Bool { permission == .notDetermined }

    init(service: any NotificationServicing = NotificationService()) {
        self.service = service
    }

    func load() async {
        permission = await service.permission()
        loaded = true
    }

    /// Asks the system and adopts whatever it answers (`.authorized` if the
    /// user allows, `.denied` if they refuse or had already refused).
    /// Re-entrancy guarded: a double tap would otherwise fire two prompts.
    @discardableResult
    func requestPermission() async -> NotificationPermission {
        guard !isRequesting else { return permission }
        isRequesting = true
        permission = await service.requestAuthorization()
        isRequesting = false
        return permission
    }
}
