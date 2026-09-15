import XCTest
@testable import ImmichSwiftUI

/// Behaviour of the "API Keys" screen (gap G20): which route each action takes,
/// what the list shows after a mutation, and the one invariant the client cannot
/// enforce for the server — a secret is readable exactly once.
///
/// Nothing here pins an English label: the strings the screen shows come from
/// the catalog, so the expectations resolve them through `localizedString`
/// instead of freezing the language of the machine running the suite.
final class UserApiKeysViewModelTests: XCTestCase {

    private struct BoomError: Error {}

    private func key(
        _ id: String,
        name: String = "ci",
        createdAt: String? = "2024-07-29T14:30:00.000Z",
        permissions: [String]? = ["asset.read"]
    ) -> ApiKeyResponseDto {
        ApiKeyResponseDto(id: id, name: name, createdAt: createdAt, updatedAt: nil, permissions: permissions)
    }

    // MARK: - Loading

    @MainActor
    func test_load_populatesKeysFromTheListEndpoint() async {
        let mock = MockImmichClient()
        mock.apiKeysResponse = [key("k1"), key("k2", name: "laptop")]
        let vm = UserApiKeysViewModel(client: mock)

        await vm.load()

        XCTAssertEqual(vm.keys.map(\.id), ["k1", "k2"])
        XCTAssertEqual(vm.keys.map(\.name), ["ci", "laptop"])
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    @MainActor
    func test_loadMyKey_failure_leavesTheRowAbsent() async {
        let mock = MockImmichClient()
        mock.myAPIKeyResponse = key("k1", name: "session key")
        let vm = UserApiKeysViewModel(client: mock)

        await vm.loadMyKey()
        XCTAssertEqual(vm.myKey?.id, "k1")

        // A session-authenticated caller has no key carrying the request, so
        // this route can legitimately refuse: the row disappears, the screen
        // does not.
        mock.adminError = BoomError()
        await vm.loadMyKey()

        XCTAssertNil(vm.myKey)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Creation

    @MainActor
    func test_create_sendsNameAndPermissions_andExposesSecretOnce() async {
        let mock = MockImmichClient()
        mock.apiKeyCreateResponse = ApiKeyCreateResponseDto(secret: "s3cret", apiKey: key("k9"))
        mock.apiKeysResponse = [key("k9")]
        let vm = UserApiKeysViewModel(client: mock)

        let created = await vm.create(name: "  phone  ", permissions: ["asset.read", "asset.upload"])

        XCTAssertTrue(created)
        XCTAssertEqual(mock.lastCreateApiKeyName, "phone")
        XCTAssertEqual(mock.lastCreateApiKeyPermissions, ["asset.read", "asset.upload"])
        XCTAssertEqual(vm.pendingSecret, "s3cret")
        XCTAssertEqual(vm.keys.map(\.id), ["k9"], "the new key joins the list right away")

        vm.dismissSecret()
        XCTAssertNil(vm.pendingSecret, "the server answers a secret once; nothing keeps a second copy")
    }

    @MainActor
    func test_create_rejectsEmptyName_withoutCallingTheClient() async {
        let mock = MockImmichClient()
        let vm = UserApiKeysViewModel(client: mock)

        let created = await vm.create(name: "   ", permissions: ["all"])

        XCTAssertFalse(created, "the sheet must stay open on a refused name")
        XCTAssertEqual(mock.requestCount, 0)
        XCTAssertNil(vm.pendingSecret)
        XCTAssertNotNil(vm.errorMessage)
    }

    @MainActor
    func test_create_failure_keepsTheSheetOpen_andShowsNoSecret() async {
        let mock = MockImmichClient()
        mock.adminError = BoomError()
        let vm = UserApiKeysViewModel(client: mock)

        let created = await vm.create(name: "ci", permissions: ["all"])

        XCTAssertFalse(created)
        XCTAssertNil(vm.pendingSecret)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Rotation and revocation

    @MainActor
    func test_rotate_storesTheNewSecretAndInvalidatesNothingLocal() async {
        let mock = MockImmichClient()
        mock.apiKeysResponse = [key("k1")]
        mock.apiKeyRotateResponse = ApiKeyCreateResponseDto(secret: "fresh", apiKey: key("k1"))
        let vm = UserApiKeysViewModel(client: mock)
        await vm.load()

        vm.rotationTarget = vm.keys[0]
        await vm.rotate(vm.keys[0])

        XCTAssertEqual(mock.lastRotateApiKeyId, "k1")
        XCTAssertEqual(vm.pendingSecret, "fresh")
        XCTAssertNil(vm.rotationTarget, "the dialog closes on the key it confirmed")
        XCTAssertEqual(vm.keys.map(\.id), ["k1"], "rotation replaces the secret, not the key")
    }

    @MainActor
    func test_delete_dropsTheKeyFromTheList() async {
        let mock = MockImmichClient()
        mock.apiKeysResponse = [key("k1"), key("k2")]
        let vm = UserApiKeysViewModel(client: mock)
        await vm.load()

        mock.apiKeysResponse = [key("k2")]
        vm.deletionTarget = vm.keys[0]
        await vm.delete(vm.keys[0])

        XCTAssertEqual(mock.lastDeleteApiKeyId, "k1")
        XCTAssertNil(vm.deletionTarget)
        XCTAssertEqual(vm.keys.map(\.id), ["k2"])
    }

    // MARK: - Projections

    @MainActor
    func test_permissionsSummary_saysFullAccessForTheAllPermission() {
        let vm = UserApiKeysViewModel(client: MockImmichClient())

        XCTAssertEqual(vm.permissionsSummary(key("k1", permissions: ["all"])), localizedString("Full access"))
        XCTAssertEqual(
            vm.permissionsSummary(key("k2", permissions: ["asset.read", "asset.upload"])),
            localizedString("%lld permissions", 2)
        )
        XCTAssertEqual(vm.permissionsSummary(key("k3", permissions: nil)), localizedString("%lld permissions", 0))
    }

    @MainActor
    func test_createdAt_undecodable_returnsUnknownLabel() {
        let vm = UserApiKeysViewModel(client: MockImmichClient())

        XCTAssertEqual(vm.formattedCreatedAt(key("k1", createdAt: "not-a-date")), localizedString("Unknown"))
        XCTAssertEqual(vm.formattedCreatedAt(key("k2", createdAt: nil)), localizedString("Unknown"))
    }
}
