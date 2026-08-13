import Foundation

/// View model for the cross-album "Shared" tab (PRD §4). Lists ALL of the
/// user's shared links (album + individual), supports revoking, and creating
/// new album-typed links.
///
/// Reuses the existing `ImmichClient` shared-link endpoints — no new server
/// contract. `getSharedLinks(albumId: nil)` returns every link for the user.
@MainActor
@Observable
final class SharedLinksViewModel {
    private let client: any ImmichClient

    var sharedLinks: [SharedLinkResponseDto] = []
    var isLoading = false
    var errorMessage: String?

    // MARK: - Partners (AC-1072)

    var partners: [PartnerResponseDto] = []
    var isPartnersLoading = false
    var partnersError: String?

    init(client: any ImmichClient) {
        self.client = client
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // albumId: nil → list ALL shared links for the authenticated user.
            sharedLinks = try await client.getSharedLinks(albumId: nil)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        await load()
    }

    // MARK: - Partners (AC-1072)

    func loadPartners() async {
        isPartnersLoading = true
        defer { isPartnersLoading = false }
        do {
            partners = try await client.getPartners()
            partnersError = nil
        } catch {
            partnersError = error.localizedDescription
        }
    }

    /// Updates a partner's "show in timeline" flag. Try-then-mutate: row is
    /// replaced only after the server call succeeds.
    func togglePartnerTimeline(id: String, enabled: Bool) async {
        do {
            let updated = try await client.updatePartner(id: id, isInTimeline: enabled)
            if let idx = partners.firstIndex(where: { $0.id == id }) {
                partners[idx] = updated
            }
            partnersError = nil
        } catch {
            partnersError = error.localizedDescription
        }
    }

    /// Removes a partner (unshares their library access).
    func removePartner(id: String) async {
        do {
            try await client.removePartner(id: id)
            partners.removeAll { $0.id == id }
            partnersError = nil
        } catch {
            partnersError = error.localizedDescription
        }
    }

    // MARK: - Revoke

    /// Revokes a shared link. Returns `true` when the link was removed, `false`
    /// on failure (the caller can then re-show the card + surface the error).
    @discardableResult
    func revoke(id: String) async -> Bool {
        do {
            try await client.deleteSharedLink(id: id)
            // try-then-mutate: remove only on success.
            sharedLinks.removeAll { $0.id == id }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Create (album-typed)

    /// Creates a new album shared link. The caller provides an `albumId` (from
    /// the user's album list). Returns success so the view can dismiss + refresh.
    @discardableResult
    func createAlbumLink(albumId: String, description: String?, password: String?) async -> Bool {
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
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
