import XCTest
@testable import ImmichSwiftUI

/// Folder view (gap G11) — the tree built from `unique-paths`, the per-path
/// asset cache, the in-memory sort, and the error paths.
final class FolderViewModelTests: XCTestCase {

    private struct BoomError: Error {}

    // MARK: - Helpers

    @MainActor
    private func makeVM(_ mock: MockImmichClient) -> FolderViewModel {
        FolderViewModel(client: mock)
    }

    private func makeAssetDTO(id: String, fileCreatedAt: String = "2024-07-01T00:00:00.000Z") -> AssetResponseDto {
        AssetResponseDto(
            id: id, type: "IMAGE", thumbhash: nil, localDateTime: fileCreatedAt,
            duration: nil, hasMetadata: true, width: 100, height: 100, createdAt: fileCreatedAt,
            ownerId: "owner", originalPath: "/mnt/media/Photos/\(id).jpg", originalFileName: "\(id).jpg",
            fileCreatedAt: fileCreatedAt, fileModifiedAt: fileCreatedAt,
            updatedAt: fileCreatedAt, isFavorite: false, isArchived: false,
            isTrashed: false, isOffline: false, visibility: "timeline", checksum: "abc", isEdited: false
        )
    }

    // MARK: - Tree

    func test_buildTree_groupsPathsByLevel() {
        let tree = FolderViewModel.buildTree(from: [
            "/mnt/media/Photos/2024",
            "/mnt/media/Photos/2025"
        ])

        // One node per segment: the two paths share every level but the year.
        let levels = [tree.root, tree.root.children[0], tree.root.children[0].children[0], tree.root.children[0].children[0].children[0]]
        XCTAssertEqual(levels.map(\.name), ["", "mnt", "media", "Photos"])
        XCTAssertEqual(levels.map(\.path), ["", "/mnt", "/mnt/media", "/mnt/media/Photos"])
        XCTAssertEqual(levels.last?.children.map(\.name), ["2024", "2025"])
        XCTAssertEqual(levels.last?.children.map(\.path), ["/mnt/media/Photos/2024", "/mnt/media/Photos/2025"])
        XCTAssertFalse(tree.hasRootLevelAssets)
    }

    func test_buildTree_flagsRootLevelAssets() {
        let tree = FolderViewModel.buildTree(from: ["", "/mnt/media"])

        // The empty path is a flag, never a node: `unique-paths` uses it for
        // files sitting at the filesystem root.
        XCTAssertTrue(tree.hasRootLevelAssets)
        XCTAssertEqual(tree.root.children.map(\.name), ["mnt"])
    }

    func test_buildTree_sortsSiblingsByName() {
        let tree = FolderViewModel.buildTree(from: [
            "/lib/10",
            "/lib/9",
            "/lib/2024/b",
            "/lib/2024/a"
        ])

        // Finder-like order: numeric-aware ("9" before "10", where a plain
        // lexicographic sort would print "10" first).
        XCTAssertEqual(tree.root.children[0].children.map(\.name), ["9", "10", "2024"])
        XCTAssertEqual(tree.root.children[0].children[2].children.map(\.name), ["a", "b"])
    }

    // MARK: - Assets

    @MainActor
    func test_loadAssets_sendsTheFolderPathAsIs() async {
        let mock = MockImmichClient()
        mock.folderAssetsResponse = [makeAssetDTO(id: "a1")]
        let vm = makeVM(mock)

        await vm.loadAssets(for: "/mnt/media/Photos")

        // The wire contract: the leading slash rides along (the server only
        // strips trailing ones), so the server answers with the right level.
        XCTAssertEqual(mock.requestedFolderPaths, ["/mnt/media/Photos"])
        XCTAssertEqual(vm.sortedAssets(for: "/mnt/media/Photos").map(\.id), ["a1"])
    }

    @MainActor
    func test_loadAssets_cachesPerPath() async {
        let mock = MockImmichClient()
        mock.folderAssetsResponse = [makeAssetDTO(id: "a1")]
        let vm = makeVM(mock)

        await vm.loadAssets(for: "/a")
        await vm.loadAssets(for: "/a")

        XCTAssertEqual(mock.requestCount, 1)
        XCTAssertEqual(mock.requestedFolderPaths, ["/a"])
    }

    @MainActor
    func test_refresh_forcesARefetch() async {
        let mock = MockImmichClient()
        mock.folderAssetsResponse = [makeAssetDTO(id: "a1")]
        let vm = makeVM(mock)

        await vm.loadAssets(for: "/a")
        await vm.refresh(path: "/a")

        XCTAssertEqual(mock.requestCount, 2)
    }

    @MainActor
    func test_toggleAssetOrder_reordersInMemoryWithoutRefetching() async {
        let mock = MockImmichClient()
        mock.folderAssetsResponse = [
            makeAssetDTO(id: "old", fileCreatedAt: "2024-01-01T00:00:00.000Z"),
            makeAssetDTO(id: "new", fileCreatedAt: "2025-01-01T00:00:00.000Z")
        ]
        let vm = makeVM(mock)

        await vm.loadAssets(for: "/a")
        let afterLoad = mock.requestCount

        XCTAssertEqual(vm.sortedAssets(for: "/a").map(\.id), ["new", "old"])
        vm.toggleAssetOrder()

        // The route does not paginate and the server sorts by file name, so the
        // date order is client-side and the flip must not cost a request.
        XCTAssertEqual(vm.assetOrder, .ascending)
        XCTAssertEqual(vm.sortedAssets(for: "/a").map(\.id), ["old", "new"])
        XCTAssertEqual(mock.requestCount, afterLoad)
    }

    // MARK: - Errors

    @MainActor
    func test_assetsError_isScopedToItsPath() async {
        let mock = MockImmichClient()
        let vm = makeVM(mock)
        mock.folderAssetsError = BoomError()

        await vm.loadAssets(for: "/broken")

        XCTAssertNotNil(vm.errorMessage("/broken"))
        XCTAssertNil(vm.sortedAssets(for: "/broken").first)

        mock.folderAssetsError = nil
        mock.folderAssetsResponse = [makeAssetDTO(id: "a1")]
        await vm.loadAssets(for: "/fine")

        XCTAssertNil(vm.errorMessage("/fine"))
        XCTAssertEqual(vm.sortedAssets(for: "/fine").map(\.id), ["a1"])
        // The failure of one folder leaves the other one readable.
        XCTAssertNotNil(vm.errorMessage("/broken"))
    }

    @MainActor
    func test_loadTree_surfacesError() async {
        let mock = MockImmichClient()
        mock.folderPathsError = BoomError()
        let vm = makeVM(mock)

        await vm.loadTree()

        XCTAssertNotNil(vm.treeError)
        XCTAssertNil(vm.root)
        XCTAssertFalse(vm.isBuildingTree)
    }

    // MARK: - Loading discipline

    @MainActor
    func test_loadTree_buildsTheTreeOnceAndChildrenComeFromIt() async {
        let mock = MockImmichClient()
        mock.folderPathsResponse = ["/mnt/media/Photos", "/mnt/backup"]
        let vm = makeVM(mock)

        await vm.loadTree()
        // Descending a level (or popping back) must not replay `unique-paths`.
        await vm.loadTree()

        XCTAssertEqual(mock.requestCount, 1)
        XCTAssertEqual(vm.children(of: nil).map(\.name), ["mnt"])
        XCTAssertEqual(vm.children(of: vm.root?.children.first).map(\.name), ["backup", "media"])
    }
}
