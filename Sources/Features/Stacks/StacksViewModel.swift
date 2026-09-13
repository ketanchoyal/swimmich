import Foundation

/// Photo-stack state (gap #1): the stacks the server holds, their covers, and
/// the mutations the `/api/stacks` routes expose.
///
/// All six stack routes were already wired in `ImmichClient`; `searchStacks`
/// and `createStack` had no caller, and the rest were only reachable from the
/// viewer's `StackSheet`. This VM is the hub-level surface — list, create,
/// unstack, change cover, drop a member — plus the create-flow state (recent
/// assets to pick from, current selection).
///
/// `@Observable @MainActor` mirrors TagsViewModel / PeopleViewModel.
@Observable
@MainActor
final class StacksViewModel {
    let client: any ImmichClient

    var stacks: [StackResponseDto] = []
    var isLoading = false
    var errorMessage: String?

    /// Stack currently opened in the detail screen (nil until it loads).
    var selectedStack: StackResponseDto?

    // MARK: - Create flow

    /// Recent assets offered by `CreateStackSheet`. Paged through
    /// `POST /api/search/metadata` (newest first) rather than the timeline
    /// buckets: the sheet can be opened from the hub, where no timeline page
    /// is loaded.
    var recentAssets: [AssetReactItem] = []
    var selectedIds: Set<String> = []
    var isLoadingAssets = false

    /// Drives the create sheet. Lives on the VM (not the view) so a reload of
    /// the hub list can't dismiss the sheet mid-selection.
    var showCreate = false

    /// Page size per picker fetch.
    private let pickerPageSize = 100
    private var pickerNextPage: String?
    /// False once the server reported no next page (and before the first load
    /// is requested — `beginCreateFlow` is what opens the flow).
    private var pickerHasMore = true
    /// Ids already handed to the picker — the server may repeat an asset across
    /// pages while the library changes under us.
    private var pickerLoadedIds: Set<String> = []

    init(client: any ImmichClient) {
        self.client = client
    }

    var canLoadMoreAssets: Bool { pickerHasMore && !recentAssets.isEmpty }

    // MARK: - List

    func loadStacks(force: Bool = false) async {
        guard !(isLoading && !force) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            stacks = try await client.searchStacks(primaryAssetId: nil)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Loads one stack and keeps it in `selectedStack` for the detail screen.
    /// A failure surfaces through `errorMessage` and leaves the screen with
    /// nothing to show — the detail view renders the error with a retry.
    func loadStack(id: String, force: Bool = false) async {
        if !force, let current = selectedStack, current.id == id { return }
        isLoading = true
        defer { isLoading = false }
        do {
            selectedStack = try await client.getStack(id: id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Mutations

    /// Creates a stack from `assetIds` (first id becomes the cover, min 2 —
    /// the server rejects anything shorter).
    func createStack(assetIds: [String]) async {
        guard assetIds.count >= 2 else { return }
        do {
            _ = try await client.createStack(assetIds: assetIds)
            resetCreateFlow()
            showCreate = false
            errorMessage = nil
            await loadStacks(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteStack(id: String) async {
        do {
            try await client.deleteStack(id: id)
            stacks.removeAll { $0.id == id }
            if selectedStack?.id == id { selectedStack = nil }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePrimary(stackId: String, assetId: String) async {
        do {
            selectedStack = try await client.updateStack(id: stackId, primaryAssetId: assetId)
            await refreshCover(inList: stackId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeAssetFromStack(stackId: String, assetId: String) async {
        do {
            try await client.removeAssetFromStack(stackId: stackId, assetId: assetId)
            await loadStack(id: stackId, force: true)
            await refreshCover(inList: stackId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Re-reads one stack so the hub list shows the new cover/count. Cheap
    /// (one GET) and keeps the list truthful without a full reload.
    private func refreshCover(inList stackId: String) async {
        guard let index = stacks.firstIndex(where: { $0.id == stackId }) else { return }
        if let updated = try? await client.getStack(id: stackId) {
            stacks[index] = updated
        }
    }

    // MARK: - Picker

    /// Resets the picker and loads its first page. Called when the create sheet
    /// appears, so a reopened sheet never shows the previous selection.
    func beginCreateFlow() async {
        resetCreateFlow()
        await loadMoreAssets()
    }

    private func resetCreateFlow() {
        recentAssets = []
        selectedIds = []
        pickerNextPage = nil
        pickerHasMore = true
        pickerLoadedIds = []
    }

    func toggleSelection(id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    /// Loads the next page of pickable assets. A no-op once the library is
    /// exhausted; errors surface through `errorMessage` (the grid keeps what it
    /// already has).
    func loadMoreAssets() async {
        guard !isLoadingAssets, pickerHasMore else { return }
        isLoadingAssets = true
        defer { isLoadingAssets = false }
        do {
            // `order: "desc"` = newest first, matching the timeline's first page.
            var dto = MetadataSearchDto(order: "desc", size: pickerPageSize)
            if let page = pickerNextPage { dto.page = Int(page) }
            let response = try await client.searchMetadata(dto: dto)
            let fresh = response.assets.items
                .filter { pickerLoadedIds.insert($0.id).inserted }
                .map(AssetReactItem.init(from:))
            recentAssets.append(contentsOf: fresh)
            pickerNextPage = response.assets.nextPage
            pickerHasMore = response.assets.nextPage != nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
