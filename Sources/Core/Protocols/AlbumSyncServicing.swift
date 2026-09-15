import Foundation

/// One-way mirror of the device's Photos albums onto server albums.
///
/// Direction is `device → server` and it never removes anything: an asset that
/// leaves a Photos album stays in the server album, and the server album's
/// structure is frozen at creation — the same contract as the upstream Flutter
/// client (`sync_linked_album.service.dart`). Renaming, deleting and inviting
/// users are out of scope.
///
/// Four entry points, one owner. The mirror's state — the resolved
/// `device album → server album` map and the per-album buffer of freshly
/// uploaded assets — belongs to a single object: two of them would each hold
/// half a run's assets and neither would see the other's buffer. The
/// implementation is an actor (`AlbumSyncService`), driven by `BackupEngine`
/// from the run itself, never from a view.
protocol AlbumSyncServicing: Sendable {
    /// Resolves the server album of every device album the user asked to
    /// mirror, returning `deviceAlbumID → serverAlbumID`.
    ///
    /// Per album, in order: the persisted mapping; else a server album with the
    /// same name **owned** by `userID`; else one with the same name **shared
    /// with** `userID`; else a new album (`POST /api/albums`, name only — the
    /// mirror never invites anyone, and it never hijacks a stranger's album
    /// that merely shares the name). Smart albums, and every album absent from
    /// `syncedDeviceAlbumIDs`, stay out of the map: their membership changes in
    /// Photos without an upload, so a mirror of them could never settle.
    ///
    /// `albumMembership` is the inverse index built by the asset source
    /// (`deviceAssetID → deviceAlbumIDs`, one Photos fetch per album). It is
    /// remembered, so `stage` routes an uploaded asset without asking Photos
    /// again.
    ///
    /// Throws when the server cannot be listed; a caller that must not lose the
    /// backup because the mirror is unavailable treats the throw as "empty map
    /// for this run".
    func resolveAlbums(
        deviceAlbums: [BackupAlbum],
        syncedDeviceAlbumIDs: Set<String>,
        albumMembership: [String: [String]],
        userID: String,
        client: any ImmichClient
    ) async throws -> [String: String]

    /// Buffers a freshly uploaded asset under every mirrored server album its
    /// device album resolved to. An asset whose device albums are all
    /// unmirrored is dropped, and staging the same asset twice sends it once.
    ///
    /// `assetID` is the **server** id returned by the upload; `deviceAssetID`
    /// is the Photos `localIdentifier` the membership index is keyed by.
    func stage(assetID: String, deviceAssetID: String) async

    /// Sends the buffer (`PUT /albums/{id}/assets`, `batchSize` ids per call)
    /// and empties it. Returns the counts accumulated since the previous flush:
    /// one flush closes one window, so a summary can never mix two runs. An
    /// empty buffer makes no request at all.
    func flush(client: any ImmichClient) async -> AlbumSyncOutcome

    /// Maps already-backed-up ledger entries onto the mirrored albums — the
    /// "Reorganize into album" catch-up for assets uploaded before the mirror
    /// was turned on. Nothing is re-uploaded: the ledger stores no server id,
    /// so each entry's id is recovered with `bulk-upload-check`, results
    /// without an `assetId` and entries trashed on the server are ignored, and
    /// the resolved ids are staged and flushed.
    ///
    /// Uses the map resolved by the current run (or by a previous
    /// `resolveAlbums` on the same service); device albums it has no server
    /// album for are skipped rather than re-resolved by name.
    func reorganize(
        entries: [(id: String, checksum: String)],
        albumMembership: [String: [String]],
        userID: String,
        client: any ImmichClient
    ) async -> AlbumSyncOutcome
}
