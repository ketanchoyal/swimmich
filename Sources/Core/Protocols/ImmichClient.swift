import Foundation

/// Abstraction over the Immich HTTP API.
///
/// All methods are async throws and return decoded DTOs. The client is
/// responsible for: attaching the bearer token, URL construction, decoding,
/// and surfacing `.unauthorized` on 401 (FM-4).
///
/// A single `requestCount` is exposed to aid MVVM testing (AC-009).
protocol ImmichClient: AnyObject, Sendable {
    /// Configures the server base URL + bearer token. Called by AuthViewModel.
    func configure(baseURL: URL?, token: String?)

    /// Delegate notified on global 401 (FM-4).
    var authDelegate: (any AuthSessionDelegate)? { get set }

    func ping() async throws -> ServerPingResponse
    func serverVersion() async throws -> ServerVersionResponseDto
    func serverConfig() async throws -> ServerConfigDto

    func login(email: String, password: String) async throws -> LoginResponseDto
    func logout() async throws -> LogoutResponseDto
    func validateToken() async throws -> ValidateAccessTokenResponseDto
    func authorizeOAuth(redirectURI: String, state: String, codeChallenge: String) async throws -> OAuthAuthorizeResponseDto
    /// Returns the same payload as `login` — the server replies with `LoginResponseDto`.
    func exchangeOAuthCode(url: String, state: String, codeVerifier: String) async throws -> LoginResponseDto

    // MARK: - Timeline (P0: person/partner/visibility filters)
    /// `GET /api/timeline/buckets` — optional filters; all extra params default nil.
    func getTimeBuckets(
        isFavorite: Bool?,
        isTrashed: Bool?,
        personId: String?,
        withPartners: Bool?,
        visibility: String?,
        withStacked: Bool?
    ) async throws -> [TimeBucketsResponseDto]
    /// `GET /api/timeline/bucket` — optional filters matching buckets.
    func getTimeBucket(
        timeBucket: String,
        personId: String?,
        withPartners: Bool?,
        visibility: String?,
        withStacked: Bool?
    ) async throws -> TimeBucketAssetResponseDto

    func getAsset(id: String) async throws -> AssetResponseDto
    func updateAsset(id: String, dto: UpdateAssetDto) async throws -> AssetResponseDto
    func deleteAssets(ids: [String], force: Bool?) async throws

    // MARK: - Trash (AC-300..AC-309)
    func restoreTrashAssets(ids: [String]) async throws -> TrashResponseDto
    func restoreAllTrash() async throws -> TrashResponseDto
    func emptyTrash() async throws -> TrashResponseDto

    // MARK: - Search (AC-400..AC-406)
    func searchMetadata(dto: MetadataSearchDto) async throws -> SearchResponseDto
    func searchSmart(dto: SmartSearchDto) async throws -> SearchResponseDto
    func getExploreData() async throws -> [SearchExploreResponseDto]
    /// `GET /api/search/cities` — one representative asset per distinct city
    /// (no 12-cap, no ≥5-photo floor). Powers the Explore Places list.
    func getAssetsByCity() async throws -> [AssetResponseDto]
    /// `POST /api/search/statistics` — total asset count for a metadata filter.
    func searchStatistics(dto: SearchStatisticsDto) async throws -> SearchStatisticsResponseDto

    // MARK: - Map (AC-710)
    func getMapMarkers(isFavorite: Bool?, isArchived: Bool?) async throws -> [MapMarkerResponseDto]

    // MARK: - Albums (AC-500..AC-518)
    func getAlbums() async throws -> [AlbumResponseDto]
    func createAlbum(dto: CreateAlbumDto) async throws -> AlbumResponseDto
    func getAlbum(id: String) async throws -> AlbumResponseDto
    func updateAlbum(id: String, dto: UpdateAlbumDto) async throws -> AlbumResponseDto
    func deleteAlbum(id: String) async throws
    func addAssetsToAlbum(albumId: String, dto: BulkIdsDto) async throws -> [BulkIdResponseDto]
    func removeAssetsFromAlbum(albumId: String, dto: BulkIdsDto) async throws -> [BulkIdResponseDto]

    // MARK: - Album users (share to instance users)
    func addUsersToAlbum(albumId: String, dto: AddUsersDto) async throws -> AlbumResponseDto
    func updateAlbumUserRole(albumId: String, userId: String, dto: UpdateAlbumUserDto) async throws
    func removeUserFromAlbum(albumId: String, userId: String) async throws

    // MARK: - Shared Links (AC-500..AC-518)
    func getSharedLinks(albumId: String?) async throws -> [SharedLinkResponseDto]
    func createSharedLink(dto: SharedLinkCreateDto) async throws -> SharedLinkResponseDto
    /// `PATCH /api/shared-links/{id}` — edit slug, expiry, upload/download
    /// toggles, metadata visibility. The server exposes **PATCH**, not PUT.
    ///
    /// `dto.slug` is always applied: an omitted slug clears the link's slug
    /// server-side, so callers must echo the current value when they are not
    /// changing it.
    func updateSharedLink(id: String, dto: SharedLinkEditDto) async throws -> SharedLinkResponseDto
    /// `PUT /api/shared-links/{id}/assets` body `AssetIdsDto` — the OWNER adds
    /// assets to an `INDIVIDUAL` link (an `ALBUM` link answers 400). A visitor
    /// cannot call this: it needs the `SharedLinkUpdate` permission.
    @discardableResult
    func addAssetsToSharedLink(id: String, assetIds: [String]) async throws -> [AssetIdsResponseDto]
    func deleteSharedLink(id: String) async throws

    // MARK: - Opening a shared link (issue #22 — visitor side)
    //
    // These four calls carry no bearer token: the credential goes in the query
    // (`?key=` / `?slug=`) and the server authenticates the request with
    // `AuthService.validateSharedLinkKey` / `…Slug`. Their failures are
    // therefore about the *link* (a password is required, the password is
    // wrong, the link is revoked or expired, uploads are not allowed) and never
    // about the signed-in session — see `ImmichAPIClient.sendSharedLinkRaw`.

    /// `GET /api/shared-links/me?key=|slug=` — the link as its owner's browser
    /// would see it. 401 `"Password required"` means the caller must call
    /// `loginToSharedLink` first; any other 401 means the link is dead.
    func getSharedLinkMine(_ credential: SharedLinkCredential) async throws -> SharedLinkResponseDto

    /// `POST /api/shared-links/login?key=|slug=` body `{password}` — exchanges
    /// the password for the DTO **and** for the session cookie the server sets
    /// (`immich_shared_link_token`). The client replays that cookie on every
    /// later visitor request; nothing else makes `getSharedLinkMine` succeed on
    /// a protected link (the web client navigates again after login and relies
    /// on exactly this cookie).
    func loginToSharedLink(_ credential: SharedLinkCredential, password: String) async throws -> SharedLinkResponseDto

    /// `POST /api/search/metadata?key=|slug=` with `albumIds: [albumId]` — how
    /// an **album** link's assets are listed. `SharedLinkResponseDto.album` has
    /// no `assets` array (`AlbumResponseDto` never carries one), and the server
    /// refuses an unfiltered metadata search under shared-link auth
    /// (`"Shared link access is only allowed in combination with an albumIds
    /// filter"`). An INDIVIDUAL link needs no call at all: its assets come
    /// inlined in `getSharedLinkMine`.
    func getSharedLinkAlbumAssets(
        _ credential: SharedLinkCredential,
        albumId: String,
        page: Int,
        size: Int
    ) async throws -> SearchResponseDto

    /// `POST /api/assets?key=|slug=` — a guest upload. The server gates it with
    /// `requireUploadAccess`: a bare **401** means this link does not allow
    /// uploads (`allowUpload == false`). The asset lands in the link's album
    /// (`AssetMediaService.addToSharedLink`).
    func uploadAssetToSharedLink(
        fileURL: URL,
        filename: String,
        fileCreatedAt: String,
        fileModifiedAt: String,
        checksum: String,
        deviceAssetId: String,
        deviceId: String,
        credential: SharedLinkCredential
    ) async throws -> AssetMediaResponseDto

    // MARK: - Tags (gap #2)
    func getAllTags() async throws -> [TagResponseDto]
    func createTag(name: String, color: String?) async throws -> TagResponseDto
    func updateTag(id: String, color: String?) async throws -> TagResponseDto
    func deleteTag(id: String) async throws
    /// `PUT /api/tags/{id}/assets` — add assets to a tag.
    func tagAssets(tagId: String, assetIds: [String]) async throws
    /// `DELETE /api/tags/{id}/assets` — remove assets from a tag.
    func untagAssets(tagId: String, assetIds: [String]) async throws

    // MARK: - People (P0 api-surface-expansion)
    func getPeople(page: Int?, withHidden: Bool?) async throws -> PeopleResponseDto
    func createPerson(name: String) async throws -> PersonResponseDto
    func updatePerson(id: String, dto: PersonUpdateDto) async throws -> PersonResponseDto
    /// `POST /api/people/{id}/merge` — merge persons; returns bulk results.
    func mergePeople(ids: [String], into id: String) async throws -> [BulkIdResponseDto]
    func getPersonStatistics(id: String) async throws -> PersonStatisticsResponseDto
    /// `PUT /api/faces/{personId}` body `{ id: faceId }` — re-assign one face (gap #5).
    func reassignFace(faceId: String, toPersonId: String) async throws -> PersonResponseDto
    /// `GET /api/faces?id={assetId}` — all faces detected on an asset (gap #5).
    func getFaces(assetId: String) async throws -> [AssetFaceResponseDto]
    /// `GET /api/assets/{id}/ocr` — the text boxes the server detected on an
    /// asset (gap #8, ocr-text). Readable under the normal read permission; the
    /// array is empty when nothing was detected — an empty answer is NOT an
    /// error.
    func getAssetOcr(id: String) async throws -> [AssetOcrResponseDto]

    // MARK: - Partners (P0 api-surface-expansion; direction corrected 2026-09-13)
    /// `GET /api/partners?direction=` — `direction` is **required**; without it
    /// the server answers 400. The response always carries the *other* user of
    /// the pair (see `PartnerDirection`).
    func getPartners(direction: PartnerDirection) async throws -> [PartnerResponseDto]
    /// `POST /api/partners` body `{ sharedWithId }` — the server takes a user
    /// id, never an email.
    func createPartner(sharedWithId: String) async throws -> PartnerResponseDto
    /// `PUT /api/partners/{id}` — valid **only** for a row from
    /// `getPartners(direction: .sharedWith)`: the server pairs `{sharedById: id,
    /// sharedWithId: me}`.
    func updatePartner(id: String, isInTimeline: Bool) async throws -> PartnerResponseDto
    /// `DELETE /api/partners/{id}` — valid **only** for a row from
    /// `getPartners(direction: .sharedBy)`: the server pairs `{sharedById: me,
    /// sharedWithId: id}`.
    func removePartner(id: String) async throws

    // MARK: - Activity (P0 api-surface-expansion)
    func getActivities(albumId: String, assetId: String?) async throws -> [ActivityResponseDto]
    func createActivity(dto: ActivityCreateDto) async throws -> ActivityResponseDto
    func deleteActivity(id: String) async throws

    // MARK: - Memories (P0 api-surface-expansion; CRUD added 2026-09-13)
    func getMemories() async throws -> [MemoryResponseDto]
    /// `GET /api/memories/{id}` — one memory. Used to re-read a memory after a
    /// mutation that answers with per-asset results rather than the memory.
    func getMemory(id: String) async throws -> MemoryResponseDto
    /// `PUT /api/memories/{id}` — **PUT**, not PATCH: the published OpenAPI
    /// exposes `get|put|delete` on this route and no PATCH (a PATCH 404s, the
    /// same trap the shared-links edit had).
    func updateMemory(id: String, dto: MemoryUpdateDto) async throws -> MemoryResponseDto
    func deleteMemory(id: String) async throws
    /// `POST /api/memories` body `MemoryCreateDto` — `data`, `memoryAt` and
    /// `type` are required; there is no name field anywhere in the memory API.
    func createMemory(dto: MemoryCreateDto) async throws -> MemoryResponseDto
    /// `PUT /api/memories/{id}/assets` body `BulkIdsDto` — **PUT** (the route is
    /// `put|delete`, so a POST 404s), answers one `BulkIdResponseDto` per id.
    @discardableResult
    func addAssetsToMemory(id: String, assetIds: [String]) async throws -> [BulkIdResponseDto]
    /// `DELETE /api/memories/{id}/assets` body `BulkIdsDto` — answers one
    /// `BulkIdResponseDto` per id (200, not 204).
    @discardableResult
    func removeAssetsFromMemory(id: String, assetIds: [String]) async throws -> [BulkIdResponseDto]
    /// `GET /api/memories/statistics` — the server's memory count. Part of the
    /// api-surface expansion: it is what the server's own paging answers to
    /// (`size`/`page` on `GET /api/memories` only take effect when the caller
    /// passes `size`), and no screen consumes it yet.
    func getMemoriesStatistics() async throws -> MemoryStatisticsResponseDto

    // MARK: - Duplicates (P0 api-surface-expansion)
    func getDuplicates() async throws -> [DuplicateResponseDto]

    // MARK: - Stacks (gap #1)
    func searchStacks(primaryAssetId: String?) async throws -> [StackResponseDto]
    func createStack(assetIds: [String]) async throws -> StackResponseDto
    func getStack(id: String) async throws -> StackResponseDto
    func updateStack(id: String, primaryAssetId: String?) async throws -> StackResponseDto
    func deleteStack(id: String) async throws
    func removeAssetFromStack(stackId: String, assetId: String) async throws

    // MARK: - Admin (gap #12)
    func getAdminUsers() async throws -> [UserAdminResponseDto]
    func createAdminUser(dto: UserAdminCreateDto) async throws -> UserAdminResponseDto
    func updateAdminUser(id: String, dto: UserAdminUpdateDto) async throws -> UserAdminResponseDto
    func deleteAdminUser(id: String, force: Bool) async throws -> UserAdminResponseDto
    func restoreAdminUser(id: String) async throws -> UserAdminResponseDto
    func getJobsStatus() async throws -> [String: QueueResponseLegacyDto]
    func sendJobCommand(name: String, command: String, force: Bool?) async throws -> QueueResponseLegacyDto
    func getLibraries() async throws -> [LibraryResponseDto]
    func scanLibrary(id: String) async throws
    func deleteLibrary(id: String) async throws
    func getAPIKeys() async throws -> [ApiKeyResponseDto]
    func createAPIKey(name: String) async throws -> ApiKeyCreateResponseDto
    func deleteAPIKey(id: String) async throws

    // MARK: - Server statistics (P0 api-surface-expansion)
    func getServerStatistics() async throws -> ServerStatsResponseDto

    // MARK: - Bulk asset update (P0: archive via visibility)
    func bulkUpdateAssets(dto: AssetBulkUpdateDto) async throws

    // MARK: - Users (photo share — shared-album user picker)
    func getUsers() async throws -> [UserResponseDto]

    /// Uploads an asset via streamed multipart/form-data — the body is
    /// assembled from `fileURL` on disk, never held in memory.
    /// `checksum` is base64-encoded SHA1 (also sent as `x-immich-checksum` header).
    /// `deviceAssetId` is the source Photos identifier and `deviceId` this
    /// installation's stable id: together they let the server attribute the
    /// asset to a device, which is what the web UI's device filter and any
    /// per-device server-side query rely on.
    func uploadAsset(
        fileURL: URL,
        fileCreatedAt: String,
        fileModifiedAt: String,
        filename: String,
        duration: Int?,
        isFavorite: Bool,
        visibility: AssetVisibility,
        livePhotoVideoId: String?,
        checksum: String,
        deviceAssetId: String,
        deviceId: String
    ) async throws -> AssetMediaResponseDto

    func bulkUploadCheck(_ request: AssetBulkUploadCheckRequest) async throws -> AssetBulkUploadCheckResponse

    /// Number of requests dispatched since creation (test aid).
    var requestCount: Int { get }
}
