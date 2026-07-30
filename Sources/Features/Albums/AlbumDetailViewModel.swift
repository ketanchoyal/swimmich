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

    var isLoading = false
    var errorMessage: String?
    var isDeleted = false

    init(client: any ImmichClient, albumId: String) {
        self.client = client
        self.albumId = albumId
    }

    // MARK: - Load (AC-508)

    /// Two-phase load: album metadata (try-then-mutate `album`) THEN assets
    /// via searchMetadata (try-then-mutate `assets` independently). A failure
    /// in the second phase still leaves `album` populated.
    func load() async {
        isLoading = true
        defer { isLoading = false }

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
