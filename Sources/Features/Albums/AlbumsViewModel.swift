import Foundation

/// View model for the Albums tab (AC-506, AC-507).
/// Lists the user's albums + supports creation. Shared across the Albums tab
/// and the Timeline "Add to Album" picker (FM-3 mitigation — single source of
/// truth propagated via `.environment(AlbumsViewModel.self)`).
@MainActor
@Observable
final class AlbumsViewModel {
    private let client: any ImmichClient

    var albums: [AlbumResponseDto] = []
    var isLoading = false
    var errorMessage: String?
    var isCreating = false

    init(client: any ImmichClient) {
        self.client = client
    }

    // MARK: - Load (AC-506)

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await client.getAlbums()
            // try-then-mutate: only mutate on success.
            albums = result
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        await load()
    }

    // MARK: - Create (AC-507)

    func createAlbum(name: String, description: String? = nil, assetIds: [String]? = nil) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Album name cannot be empty."
            return
        }
        isCreating = true
        defer { isCreating = false }
        let dto = CreateAlbumDto(albumName: trimmed, description: description, assetIds: assetIds)
        do {
            let created = try await client.createAlbum(dto: dto)
            // try-then-mutate: append only on success.
            albums.append(created)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
