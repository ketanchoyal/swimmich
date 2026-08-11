import Foundation

/// View model for a single album's detail screen (AC-508..AC-513).
///
/// FM-2 mitigation: the Immich server's `AlbumResponseDto` does NOT include an
/// `assets` array, so album assets are fetched separately via
/// `searchMetadata(albumIds:[albumId])` (reuses the existing search endpoint,
/// no new server endpoint needed).
@MainActor
@Observable
final class AlbumDetailViewModel {
    private let client: any ImmichClient
    let albumId: String

    var album: AlbumResponseDto?
    var assets: [AssetReactItem] = []
    private var loadedIds: Set<String> = []
    var sharedLinks: [SharedLinkResponseDto] = []

    // Pre-load state: true from init so the first rendered frame shows the
    // spinner, not the "Album Unavailable" fallback (`.task` runs after the
    // initial body evaluation). `load()` re-sets it and clears it on exit.
    var isLoading = true
    var errorMessage: String?
    var isDeleted = false

    init(client: any ImmichClient, albumId: String) {
        self.client = client
        self.albumId = albumId
    }

    // MARK: - Selection mode (AC-201 parity)

    /// True while the grid is in multi-select mode (Select button or long-press
    /// entry). Drives per-cell checkmark overlays + the selection toolbar.
    var selectionMode: Bool = false

    /// Ids the user has checked while in selection mode. Keyed by id so it
    /// stays stable across asset-list mutations.
    var selectedIds: Set<String> = []

    func enterSelectionMode() { selectionMode = true }

    func exitSelectionMode() {
        selectionMode = false
        selectedIds.removeAll()
    }

    /// Toggles membership of `id` in `selectedIds`.
    func toggleSelection(id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    // MARK: - Bulk actions (selection toolbar)

    /// Removes all selected assets from the album, then exits selection mode.
    /// On throw, selection state is preserved so the user can retry.
    func removeSelected() async {
        guard !selectedIds.isEmpty else { return }
        let ids = Array(selectedIds)
        do {
            _ = try await client.removeAssetsFromAlbum(albumId: albumId, dto: BulkIdsDto(ids: ids))
            let removeSet = Set(ids)
            assets.removeAll { removeSet.contains($0.id) }
            loadedIds.subtract(removeSet)
            exitSelectionMode()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sets favorite uniformly across `ids` (skips ids already in the target
    /// state). Same try-then-mutate discipline as `removeAssets`; first throw
    /// stops the batch and surfaces `errorMessage` without mutating the rest.
    /// - Returns: `true` on full success, `false` on error — callers exit
    ///   selection mode only on success (audit fix).
    @MainActor
    @discardableResult
    func batchSetFavorite(_ ids: Set<String>, favorite value: Bool) async -> Bool {
        for id in ids {
            guard let current = assets.first(where: { $0.id == id }), current.isFavorite != value else { continue }
            do {
                _ = try await client.updateAsset(id: id, dto: UpdateAssetDto(isFavorite: value))
                if let idx = assets.firstIndex(where: { $0.id == id }) {
                    assets[idx] = current.with(isFavorite: value)
                }
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }
        return true
    }

    /// Deletes all selected assets from the library. On success removes them
    /// from `assets` + `loadedIds` and exits selection mode. On throw, state is
    /// preserved so the user can retry (errorMessage set, selection kept).
    func deleteSelected() async {
        guard !selectedIds.isEmpty else { return }
        let ids = Array(selectedIds)
        do {
            // MUST throw-or-succeed before mutating anything.
            try await client.deleteAssets(ids: ids, force: false)
            let removeSet = Set(ids)
            assets.removeAll { removeSet.contains($0.id) }
            loadedIds.subtract(removeSet)
            exitSelectionMode()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Load (AC-508)

    /// Two-phase load: album metadata (try-then-mutate `album`) THEN assets
    /// via searchMetadata (try-then-mutate `assets` independently). A failure
    /// in the second phase still leaves `album` populated.
    func load() async {
        isLoading = true
        defer { isLoading = false }

        // Selection is scoped to the current asset list; a reload starts clean.
        exitSelectionMode()

        // Phase 1: album metadata.
        do {
            album = try await client.getAlbum(id: albumId)
            errorMessage = nil
        } catch {
            // Album fetch failed: nothing else to do.
            errorMessage = error.localizedDescription
            return
        }

        // Phase 2: assets via search (albumIds filter).
        await fetchAssets()
    }

    private func fetchAssets() async {
        do {
            let dto = MetadataSearchDto(albumIds: [albumId], size: 1000)
            let response = try await client.searchMetadata(dto: dto)
            applyAssets(response.assets.items, append: false)
        } catch {
            // Album metadata already populated; surface asset-fetch error but
            // keep `album` intact (try-then-mutate discipline).
            errorMessage = error.localizedDescription
        }
    }

    private func applyAssets(_ dtos: [AssetResponseDto], append: Bool) {
        if !append {
            assets = []
            loadedIds = []
        }
        for dto in dtos where !loadedIds.contains(dto.id) {
            loadedIds.insert(dto.id)
            assets.append(AssetReactItem(from: dto))
        }
    }

    // MARK: - Add assets (AC-509)

    func addAssets(ids: [String]) async {
        guard !ids.isEmpty else { return }
        do {
            _ = try await client.addAssetsToAlbum(albumId: albumId, dto: BulkIdsDto(ids: ids))
            // Refresh assets from server after a successful add.
            await fetchAssets()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Remove assets (AC-510)

    func removeAssets(ids: [String]) async {
        guard !ids.isEmpty else { return }
        do {
            _ = try await client.removeAssetsFromAlbum(albumId: albumId, dto: BulkIdsDto(ids: ids))
            // try-then-mutate: update local list only on success.
            let removeSet = Set(ids)
            assets.removeAll { removeSet.contains($0.id) }
            loadedIds.subtract(removeSet)
            // Keep the selection set consistent when a selected asset is
            // removed via the context menu (audit fix — stale "N selected").
            selectedIds.subtract(removeSet)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete album (AC-511)

    func deleteAlbum() async {
        do {
            try await client.deleteAlbum(id: albumId)
            // 204 No Content handled by sendAuthedRaw — no decode crash (AC-518).
            isDeleted = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Shared links (AC-512, AC-513)

    func loadSharedLinks() async {
        do {
            sharedLinks = try await client.getSharedLinks(albumId: albumId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createSharedLink(password: String?, description: String?) async {
        let trimmedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pw = (trimmedPassword?.isEmpty ?? true) ? nil : trimmedPassword
        let dto = SharedLinkCreateDto(
            type: .album,
            albumId: albumId,
            description: description,
            password: pw
        )
        do {
            let link = try await client.createSharedLink(dto: dto)
            sharedLinks.append(link)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revokeSharedLink(id: String) async {
        do {
            try await client.deleteSharedLink(id: id)
            sharedLinks.removeAll { $0.id == id }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
