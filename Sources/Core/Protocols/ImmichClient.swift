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
    func getOAuthMobileURL(redirectURI: String) async throws -> OAuthMobileResponseDto
    func exchangeOAuthCode(url: String, redirectURI: String) async throws -> OAuthCallbackResponseDto

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

    // MARK: - People (P0 api-surface-expansion)
    func getPeople(page: Int?, withHidden: Bool?) async throws -> PeopleResponseDto
    func updatePerson(id: String, dto: PersonUpdateDto) async throws -> PersonResponseDto
    /// `POST /api/people/{id}/merge` — merge persons; returns bulk results.
    func mergePeople(ids: [String], into id: String) async throws -> [BulkIdResponseDto]
    func getPersonStatistics(id: String) async throws -> PersonStatisticsResponseDto

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

    // MARK: - Server statistics (P0 api-surface-expansion)
    func getServerStatistics() async throws -> ServerStatsResponseDto

    // MARK: - Bulk asset update (P0: archive via visibility)
    func bulkUpdateAssets(dto: AssetBulkUpdateDto) async throws

    // MARK: - Users (photo share — shared-album user picker)
    func getUsers() async throws -> [UserResponseDto]

    /// Uploads an asset via multipart/form-data.
    /// `checksum` is base64-encoded SHA1 (also sent as `x-immich-checksum` header).
    func uploadAsset(
        data: Data,
        fileCreatedAt: String,
        fileModifiedAt: String,
        filename: String,
        duration: Int?,
        isFavorite: Bool,
        visibility: AssetVisibility,
        livePhotoVideoId: String?,
        checksum: String
    ) async throws -> AssetMediaResponseDto

    func bulkUploadCheck(_ request: AssetBulkUploadCheckRequest) async throws -> AssetBulkUploadCheckResponse

    /// Number of requests dispatched since creation (test aid).
    var requestCount: Int { get }
}
