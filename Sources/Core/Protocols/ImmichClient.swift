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
