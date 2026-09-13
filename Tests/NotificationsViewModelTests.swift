import XCTest
import UserNotifications
@testable import ImmichSwiftUI

/// Notification permission screen (issue #16): the table that turns the
/// system's answer into what the screen shows, and the two ways asking can
/// end (allowed / refused).
@MainActor
final class NotificationsViewModelTests: XCTestCase {

    private var service: MockNotificationService!
    private var vm: NotificationsViewModel!

    override func setUp() {
        super.setUp()
        service = MockNotificationService()
        vm = NotificationsViewModel(service: service)
    }

    // MARK: - The system status table

    /// `.provisional` (quiet) and `.ephemeral` (App Clip) still deliver alerts,
    /// so both read as on; only `.denied` and `.notDetermined` are off. This is
    /// the only place the app interprets `UNAuthorizationStatus`.
    func test_permissionMapping_coversEverySystemStatus() {
        XCTAssertEqual(NotificationPermission.from(.notDetermined), .notDetermined)
        XCTAssertEqual(NotificationPermission.from(.denied), .denied)
        XCTAssertEqual(NotificationPermission.from(.authorized), .authorized)
        XCTAssertEqual(NotificationPermission.from(.provisional), .provisional)
        XCTAssertEqual(NotificationPermission.from(.ephemeral), .provisional)

        XCTAssertFalse(NotificationPermission.from(.notDetermined).isEnabled)
        XCTAssertFalse(NotificationPermission.from(.denied).isEnabled)
        XCTAssertTrue(NotificationPermission.from(.provisional).isEnabled)
        XCTAssertTrue(NotificationPermission.from(.ephemeral).isEnabled)
    }

    // MARK: - Reading the current state

    /// Nothing may be claimed before the system answered: the screen would
    /// flash "Enable" over an already-refused status.
    func test_load_reportsNothingUntilTheSystemAnswered() async {
        service.permissionResult = .denied
        XCTAssertFalse(vm.loaded)

        await vm.load()

        XCTAssertTrue(vm.loaded)
        XCTAssertEqual(vm.permission, .denied)
        XCTAssertFalse(vm.isEnabled)
        XCTAssertFalse(vm.canAsk, "a refused install must not be offered 'Enable' again — iOS won't prompt")
    }

    func test_canAsk_isTrueOnlyBeforeTheSystemWasEverAsked() async {
        service.permissionResult = .notDetermined
        await vm.load()
        XCTAssertTrue(vm.canAsk)

        service.permissionResult = .authorized
        await vm.load()
        XCTAssertFalse(vm.canAsk)
    }

    // MARK: - Asking

    func test_requestPermission_adoptsGrantedAnswer() async {
        service.requestResult = .authorized

        let answer = await vm.requestPermission()

        XCTAssertEqual(answer, .authorized)
        XCTAssertTrue(vm.isEnabled)
        XCTAssertFalse(vm.canAsk)
        XCTAssertFalse(vm.isRequesting)
        XCTAssertEqual(service.requestCount, 1)
    }

    /// The refusal path is the one that must hand the user to System Settings.
    func test_requestPermission_adoptsRefusalWithoutOfferingToAskAgain() async {
        service.requestResult = .denied

        await vm.requestPermission()

        XCTAssertEqual(vm.permission, .denied)
        XCTAssertFalse(vm.isEnabled)
        XCTAssertFalse(vm.canAsk)
    }

    /// A double tap must not fire two prompts.
    func test_requestPermission_doesNotAskTwiceWhileInFlight() async {
        let gate = Gate()
        service.beforeRequestReturns = { await gate.wait() }

        let first = Task { await vm.requestPermission() }
        while service.requestCount == 0 { await Task.yield() }

        let second = await vm.requestPermission()

        XCTAssertEqual(service.requestCount, 1, "a second request reached the notification center")
        XCTAssertEqual(second, .notDetermined, "the state must not change while the first request is in flight")
        XCTAssertTrue(vm.isRequesting)

        await gate.open()
        _ = await first.value

        XCTAssertFalse(vm.isRequesting)
        XCTAssertTrue(vm.isEnabled)
    }
}

/// One-shot async gate: parks the first request until the test releases it.
private actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
