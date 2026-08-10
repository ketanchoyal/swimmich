import XCTest
@testable import ImmichSwiftUI

@MainActor
final class SharedLinksViewModelTests: XCTestCase {

    private struct Boom: Error {}

    // MARK: - Helpers

    private func makeSharedLink(id: String) -> SharedLinkResponseDto {
        SharedLinkResponseDto(
            id: id, description: nil, password: nil, userId: "owner", key: "k\(id)",
            type: .album, createdAt: "2024-01-01T00:00:00.000Z", expiresAt: nil,
            assets: [], album: nil, allowUpload: false, allowDownload: true,
            showMetadata: true, slug: nil
        )
    }

    // MARK: - Load (cross-album: albumId nil)

    func test_load_success() async {
        let mock = MockImmichClient()
        mock.sharedLinksResponse = [makeSharedLink(id: "l1"), makeSharedLink(id: "l2")]
        let vm = SharedLinksViewModel(client: mock)
        await vm.load()
        XCTAssertEqual(vm.sharedLinks.count, 2)
        XCTAssertEqual(vm.sharedLinks.map(\.id), ["l1", "l2"])
        XCTAssertNil(mock.lastSharedLinksAlbumId, "cross-album list must pass albumId: nil")
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    func test_load_error() async {
        let mock = MockImmichClient()
        mock.sharedLinksError = Boom()
        let vm = SharedLinksViewModel(client: mock)
        await vm.load()
        XCTAssertTrue(vm.sharedLinks.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Refresh

    func test_refresh_delegatesToLoad() async {
        let mock = MockImmichClient()
        mock.sharedLinksResponse = [makeSharedLink(id: "l1")]
        let vm = SharedLinksViewModel(client: mock)
        await vm.refresh()
        XCTAssertEqual(vm.sharedLinks.count, 1)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Revoke

    func test_revoke_success_removesLink() async {
        let mock = MockImmichClient()
        mock.sharedLinksResponse = [makeSharedLink(id: "l1"), makeSharedLink(id: "l2")]
        let vm = SharedLinksViewModel(client: mock)
        await vm.load()
        let ok = await vm.revoke(id: "l1")
        XCTAssertTrue(ok)
        XCTAssertEqual(mock.lastDeleteSharedLinkId, "l1")
        XCTAssertEqual(vm.sharedLinks.map(\.id), ["l2"], "revoked link removed from list")
        XCTAssertNil(vm.errorMessage)
    }

    func test_revoke_error_keepsLink() async {
        let mock = MockImmichClient()
        mock.sharedLinksResponse = [makeSharedLink(id: "l1")]
        let vm = SharedLinksViewModel(client: mock)
        await vm.load()
        mock.deleteSharedLinkError = Boom()
        let ok = await vm.revoke(id: "l1")
        XCTAssertFalse(ok)
        XCTAssertEqual(vm.sharedLinks.count, 1, "failed revoke must keep the link")
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Create album-typed link

    func test_createAlbumLink_success() async {
        let mock = MockImmichClient()
        let vm = SharedLinksViewModel(client: mock)
        let ok = await vm.createAlbumLink(albumId: "a1", description: "Trip", password: nil)
        XCTAssertTrue(ok)
        XCTAssertEqual(mock.lastCreateSharedLinkDto?.type, .album)
        XCTAssertEqual(mock.lastCreateSharedLinkDto?.albumId, "a1")
        XCTAssertEqual(mock.lastCreateSharedLinkDto?.description, "Trip")
        XCTAssertNil(mock.lastCreateSharedLinkDto?.password)
        XCTAssertEqual(vm.sharedLinks.count, 1, "created link appended to list")
        XCTAssertNil(vm.errorMessage)
    }

    func test_createAlbumLink_whitespacePasswordTrimmedToNil() async {
        let mock = MockImmichClient()
        let vm = SharedLinksViewModel(client: mock)
        let ok = await vm.createAlbumLink(albumId: "a1", description: nil, password: "   ")
        XCTAssertTrue(ok)
        XCTAssertNil(mock.lastCreateSharedLinkDto?.password, "whitespace-only password must be nil")
    }

    func test_createAlbumLink_error_appendsNothing() async {
        let mock = MockImmichClient()
        mock.createSharedLinkError = Boom()
        let vm = SharedLinksViewModel(client: mock)
        let ok = await vm.createAlbumLink(albumId: "a1", description: nil, password: nil)
        XCTAssertFalse(ok)
        XCTAssertTrue(vm.sharedLinks.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
    }
}
