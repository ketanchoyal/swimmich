import XCTest
@testable import ImmichSwiftUI

final class StacksViewModelTests: XCTestCase {

    private func asset(_ id: String) -> AssetResponseDto {
        AssetResponseDto(
            id: id, type: "IMAGE", thumbhash: nil, localDateTime: "2024-07-01T00:00:00.000Z",
            duration: nil, hasMetadata: true, width: 100, height: 100, createdAt: "2024-07-01T00:00:00.000Z",
            ownerId: "owner", originalPath: "/\(id).jpg", originalFileName: "\(id).jpg",
            fileCreatedAt: "2024-07-01T00:00:00.000Z", fileModifiedAt: "2024-07-01T00:00:00.000Z",
            updatedAt: "2024-07-01T00:00:00.000Z", isFavorite: false, isArchived: false,
            isTrashed: false, isOffline: false, visibility: "timeline", checksum: "abc", isEdited: false
        )
    }

    private func stack(id: String, primary: String, members: [String]) -> StackResponseDto {
        StackResponseDto(id: id, primaryAssetId: primary, assets: members.map(asset))
    }

    private func searchPage(ids: [String], nextPage: String?) -> SearchResponseDto {
        SearchResponseDto(
            assets: SearchAssetResponseDto(count: ids.count, items: ids.map(asset), nextPage: nextPage)
        )
    }

    @MainActor
    func test_loadStacks_mapsServerStacks() async {
        let mock = MockImmichClient()
        mock.stacksResponse = [stack(id: "s1", primary: "a1", members: ["a1", "a2"])]
        let vm = StacksViewModel(client: mock)

        await vm.loadStacks()

        XCTAssertEqual(vm.stacks.map(\.id), ["s1"])
        XCTAssertEqual(vm.stacks.first?.assets.count, 2)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func test_loadStacks_failureSurfacesError() async {
        let mock = MockImmichClient()
        mock.stacksError = APIError.serverError(500, "boom")
        let vm = StacksViewModel(client: mock)

        await vm.loadStacks()

        XCTAssertTrue(vm.stacks.isEmpty)
        XCTAssertEqual(vm.errorMessage?.contains("boom"), true)
    }

    @MainActor
    func test_createStack_sendsIdsAndReloads() async {
        let mock = MockImmichClient()
        mock.stacksResponse = [stack(id: "s9", primary: "x", members: ["x", "y"])]
        let vm = StacksViewModel(client: mock)

        await vm.createStack(assetIds: ["x", "y"])

        XCTAssertEqual(mock.lastCreateStackIds, ["x", "y"])
        XCTAssertEqual(vm.stacks.map(\.id), ["s9"], "the hub list must show the new stack")
    }

    /// The server rejects fewer than 2 ids (`StackCreateDto.assetIds` has
    /// `.min(2)`) — the VM must not spend a round trip on a doomed request.
    @MainActor
    func test_createStack_singleIdIsRejectedLocally() async {
        let mock = MockImmichClient()
        let vm = StacksViewModel(client: mock)

        await vm.createStack(assetIds: ["only-one"])

        XCTAssertNil(mock.lastCreateStackIds)
        XCTAssertEqual(mock.requestCount, 0)
    }

    @MainActor
    func test_createStack_failureKeepsFlowOpen() async {
        let mock = MockImmichClient()
        mock.stacksError = APIError.serverError(400, "nope")
        let vm = StacksViewModel(client: mock)
        vm.showCreate = true
        vm.selectedIds = ["x", "y"]

        await vm.createStack(assetIds: ["x", "y"])

        XCTAssertTrue(vm.showCreate, "a failed create must leave the picker up")
        XCTAssertEqual(vm.selectedIds, ["x", "y"], "and keep the selection")
        XCTAssertEqual(vm.errorMessage?.contains("nope"), true)
    }

    @MainActor
    func test_deleteStack_removesItFromTheList() async {
        let mock = MockImmichClient()
        mock.stacksResponse = [
            stack(id: "s1", primary: "a1", members: ["a1", "a2"]),
            stack(id: "s2", primary: "b1", members: ["b1", "b2"])
        ]
        let vm = StacksViewModel(client: mock)
        await vm.loadStacks()

        await vm.deleteStack(id: "s1")

        XCTAssertEqual(mock.lastDeleteStackId, "s1")
        XCTAssertEqual(vm.stacks.map(\.id), ["s2"])
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func test_updatePrimary_sendsAssetIdAndRefreshesCover() async {
        let mock = MockImmichClient()
        mock.stacksResponse = [stack(id: "s1", primary: "a1", members: ["a1", "a2"])]
        mock.stackDetailResponses["s1"] = stack(id: "s1", primary: "a2", members: ["a2", "a1"])
        mock.updateStackResponse = stack(id: "s1", primary: "a2", members: ["a2", "a1"])
        let vm = StacksViewModel(client: mock)
        await vm.loadStacks()

        await vm.updatePrimary(stackId: "s1", assetId: "a2")

        XCTAssertEqual(mock.lastUpdateStackId, "s1")
        XCTAssertEqual(mock.lastUpdateStackPrimaryId, "a2")
        XCTAssertEqual(vm.selectedStack?.primaryAssetId, "a2")
        XCTAssertEqual(vm.stacks.first?.primaryAssetId, "a2", "the hub row shows the new cover")
    }

    @MainActor
    func test_removeAssetFromStack_sendsIdsAndReloadsStack() async {
        let mock = MockImmichClient()
        mock.stackDetailResponses["s1"] = stack(id: "s1", primary: "a1", members: ["a1"])
        let vm = StacksViewModel(client: mock)

        await vm.removeAssetFromStack(stackId: "s1", assetId: "a2")

        XCTAssertEqual(mock.lastRemoveFromStackId, "s1")
        XCTAssertEqual(mock.lastRemoveFromStackAssetId, "a2")
        XCTAssertEqual(vm.selectedStack?.assets.count, 1)
    }

    @MainActor
    func test_loadStack_keepsSelectedStack() async {
        let mock = MockImmichClient()
        mock.stackDetailResponses["s1"] = stack(id: "s1", primary: "a1", members: ["a1", "a2", "a3"])
        let vm = StacksViewModel(client: mock)

        await vm.loadStack(id: "s1")

        XCTAssertEqual(vm.selectedStack?.id, "s1")
        XCTAssertEqual(vm.selectedStack?.assets.count, 3)
    }

    @MainActor
    func test_loadStack_failureLeavesNothingToShow() async {
        let mock = MockImmichClient()
        mock.stacksError = APIError.serverError(404, "gone")
        let vm = StacksViewModel(client: mock)

        await vm.loadStack(id: "s1")

        XCTAssertNil(vm.selectedStack, "the detail screen renders its error state")
        XCTAssertEqual(vm.errorMessage?.contains("gone"), true)
    }

    // MARK: - Create picker

    @MainActor
    func test_beginCreateFlow_loadsFirstPageAndClearsSelection() async {
        let mock = MockImmichClient()
        mock.searchMetadataResponse = searchPage(ids: ["a1", "a2", "a3"], nextPage: nil)
        let vm = StacksViewModel(client: mock)
        vm.selectedIds = ["stale"]

        await vm.beginCreateFlow()

        XCTAssertEqual(vm.recentAssets.map(\.id), ["a1", "a2", "a3"])
        XCTAssertTrue(vm.selectedIds.isEmpty, "reopening the picker must not resurrect an old selection")
        XCTAssertEqual(mock.lastMetadataSearchDto?.order, "desc", "newest first")
    }

    @MainActor
    func test_loadMoreAssets_pagesAndDedupes() async {
        let mock = MockImmichClient()
        mock.searchMetadataResponse = searchPage(ids: ["a1", "a2"], nextPage: "2")
        let vm = StacksViewModel(client: mock)
        await vm.beginCreateFlow()
        XCTAssertTrue(vm.canLoadMoreAssets)

        // Second page repeats a1 (the library can shift between pages).
        mock.searchMetadataResponse = searchPage(ids: ["a1", "a3"], nextPage: nil)
        await vm.loadMoreAssets()

        XCTAssertEqual(vm.recentAssets.map(\.id), ["a1", "a2", "a3"])
        XCTAssertFalse(vm.canLoadMoreAssets, "no next page left")
    }

    @MainActor
    func test_toggleSelection_isSymmetric() async {
        let mock = MockImmichClient()
        let vm = StacksViewModel(client: mock)

        vm.toggleSelection(id: "a1")
        vm.toggleSelection(id: "a2")
        XCTAssertEqual(vm.selectedIds, ["a1", "a2"])

        vm.toggleSelection(id: "a1")
        XCTAssertEqual(vm.selectedIds, ["a2"])
    }
}
