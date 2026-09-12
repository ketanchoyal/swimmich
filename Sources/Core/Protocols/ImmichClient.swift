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
    /// `PUT /api/shared-links/{id}` — edit expiry, upload/download toggles, metadata visibility.
    func updateSharedLink(id: String, dto: SharedLinkEditDto) async throws -> SharedLinkResponseDto
    func deleteSharedLink(id: String) async throws

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

    // MARK: - Partners (P0 api-surface-expansion)
    func getPartners() async throws -> [PartnerResponseDto]
    func updatePartner(id: String, isInTimeline: Bool) async throws -> PartnerResponseDto
    func removePartner(id: String) async throws

    // MARK: - Activity (P0 api-surface-expansion)
    func getActivities(albumId: String, assetId: String?) async throws -> [ActivityResponseDto]
    func createActivity(dto: ActivityCreateDto) async throws -> ActivityResponseDto
    func deleteActivity(id: String) async throws

    // MARK: - Memories (P0 api-surface-expansion)
    func getMemories() async throws -> [MemoryResponseDto]

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
