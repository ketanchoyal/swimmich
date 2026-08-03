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

    func getTimeBuckets(isFavorite: Bool?, isTrashed: Bool?) async throws -> [TimeBucketsResponseDto]
    func getTimeBucket(timeBucket: String) async throws -> TimeBucketAssetResponseDto

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

    // MARK: - Map (AC-710)
    func getMapMarkers(isFavorite: Bool?, isArchived: Bool?) async throws -> [MapMarkerResponseDto]

    // MARK: - Albums (AC-500..AC-518)
    func getAlbums() async throws -> [AlbumResponseDto]
    func createAlbum(dto: CreateAlbumDto) async throws -> AlbumResponseDto
    func getAlbum(id: String) async throws -> AlbumResponseDto
    func deleteAlbum(id: String) async throws
    func addAssetsToAlbum(albumId: String, dto: BulkIdsDto) async throws -> [BulkIdResponseDto]
    func removeAssetsFromAlbum(albumId: String, dto: BulkIdsDto) async throws -> [BulkIdResponseDto]

    // MARK: - Shared Links (AC-500..AC-518)
    func getSharedLinks(albumId: String?) async throws -> [SharedLinkResponseDto]
    func createSharedLink(dto: SharedLinkCreateDto) async throws -> SharedLinkResponseDto
    func deleteSharedLink(id: String) async throws

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
