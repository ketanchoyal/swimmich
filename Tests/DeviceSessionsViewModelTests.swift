import XCTest
@testable import ImmichSwiftUI

/// Behaviour of the connected-devices screen (gap G19): what actually reaches
/// the server, what the guards refuse **before** any request, and how the two
/// projections split the list.
///
/// Nothing here pins a user-visible label: every string on that screen is a
/// catalog key resolved against the interface language, which is exactly the
/// trap this suite must not walk into.
final class DeviceSessionsViewModelTests: XCTestCase {

    private struct BoomError: Error {}

    private func session(
        id: String,
        current: Bool = false,
        os: String = "iOS",
        type: String = "iPhone",
        version: String? = "1.135.0",
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        expiresAt: Date? = nil
    ) -> SessionResponseDto {
        SessionResponseDto(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_600_000_000),
            updatedAt: updatedAt,
            expiresAt: expiresAt,
            current: current,
            deviceType: type,
            deviceOS: os,
            appVersion: version,
            isPendingSyncReset: false
        )
    }

    // MARK: - Loading

    @MainActor
    func test_load_populatesSessionsAndFlagsCurrent() async {
        let mock = MockImmichClient()
        mock.sessionsResponse = [
            session(id: "phone", current: true),
            session(id: "laptop", os: "macOS", updatedAt: Date(timeIntervalSince1970: 1_700_100_000)),
            session(id: "tablet", os: "iOS", updatedAt: Date(timeIntervalSince1970: 1_700_200_000)),
        ]
        let vm = DeviceSessionsViewModel(client: mock)

        await vm.load()

        // The current session is pinned first, the others by last activity
        // descending — the server's own order is not kept.
        XCTAssertEqual(vm.sessions.map(\.id), ["phone", "tablet", "laptop"])
        XCTAssertEqual(vm.currentSession?.id, "phone")
        XCTAssertEqual(vm.otherSessions.map(\.id), ["tablet", "laptop"])
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func test_load_failure_surfacesErrorMessageAndKeepsListEmpty() async {
        let mock = MockImmichClient()
        mock.sessionsResponse = [session(id: "phone", current: true)]
        mock.sessionsError = BoomError()
        let vm = DeviceSessionsViewModel(client: mock)

        await vm.load()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.sessions.isEmpty)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Revocation

    @MainActor
    func test_revoke_sendsDeleteForTheGivenIdAndReloads() async {
        let mock = MockImmichClient()
        mock.sessionsResponse = [session(id: "phone", current: true), session(id: "laptop")]
        let vm = DeviceSessionsViewModel(client: mock)
        await vm.load()

        mock.sessionsResponse = [session(id: "phone", current: true)]

        await vm.revoke(vm.otherSessions[0])

        XCTAssertEqual(mock.deletedSessionIDs, ["laptop"])
        // load + delete + reload: the row must not outlive the server call.
        XCTAssertEqual(vm.sessions.map(\.id), ["phone"])
        XCTAssertEqual(mock.requestCount, 3)
    }

    @MainActor
    func test_revoke_ignoresTheCurrentSession() async {
        let mock = MockImmichClient()
        let phone = session(id: "phone", current: true)
        mock.sessionsResponse = [phone]
        let vm = DeviceSessionsViewModel(client: mock)
        await vm.load()
        let requestsBefore = mock.requestCount

        await vm.revoke(phone)

        XCTAssertTrue(mock.deletedSessionIDs.isEmpty)
        XCTAssertEqual(mock.requestCount, requestsBefore)
        // The surface cannot even arm the confirmation for it.
        vm.requestRevoke(phone)
        XCTAssertNil(vm.pendingRevocation)
    }

    @MainActor
    func test_revokeAllOthers_deletesWithoutIdAndReloads() async {
        let mock = MockImmichClient()
        mock.sessionsResponse = [
            session(id: "phone", current: true),
            session(id: "laptop"),
            session(id: "tablet"),
        ]
        let vm = DeviceSessionsViewModel(client: mock)
        await vm.load()

        mock.sessionsResponse = [session(id: "phone", current: true)]

        await vm.revokeAllOthers()

        XCTAssertEqual(mock.deleteAllSessionsCallCount, 1)
        // The bulk route names no id — that is what leaves the current session
        // alone, and it is not a loop over `deleteSession`.
        XCTAssertTrue(mock.deletedSessionIDs.isEmpty)
        XCTAssertEqual(vm.sessions.map(\.id), ["phone"])
    }

    // MARK: - Elevation

    @MainActor
    func test_lock_clearsElevation() async {
        let mock = MockImmichClient()
        let vm = DeviceSessionsViewModel(client: mock)
        await vm.unlock(pinCode: "123456")
        XCTAssertTrue(vm.isElevated)

        await vm.lockCurrentSession()

        XCTAssertEqual(mock.lockSessionCallCount, 1)
        XCTAssertFalse(vm.isElevated)
    }

    @MainActor
    func test_unlock_rejectsPinShorterThanSixDigitsWithoutCallingTheClient() async {
        let mock = MockImmichClient()
        let vm = DeviceSessionsViewModel(client: mock)

        await vm.unlock(pinCode: "12345")

        XCTAssertTrue(mock.unlockedPINs.isEmpty)
        XCTAssertEqual(mock.requestCount, 0)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isElevated)
    }

    @MainActor
    func test_unlock_withSixDigitPin_raisesElevation() async {
        let mock = MockImmichClient()
        let vm = DeviceSessionsViewModel(client: mock)

        await vm.unlock(pinCode: "123456")

        XCTAssertEqual(mock.unlockedPINs, ["123456"])
        XCTAssertTrue(vm.isElevated)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func test_unlock_serverRefusal_surfacesMessageAndLeavesElevationOff() async {
        let mock = MockImmichClient()
        // The API-key account: the route answers 400, and the screen must show
        // that instead of claiming an elevation it never got.
        mock.unlockAuthSessionError = BoomError()
        let vm = DeviceSessionsViewModel(client: mock)

        await vm.unlock(pinCode: "123456")

        XCTAssertEqual(mock.unlockedPINs, ["123456"])
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isElevated)
    }
}
