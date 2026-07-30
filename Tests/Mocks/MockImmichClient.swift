import Foundation
@testable import ImmichSwiftUI

/// Test double for ImmichClient. Records the last call per endpoint + lets
/// tests inject canned responses / errors.
final class MockImmichClient: ImmichClient, @unchecked Sendable {
    // Captured request state (AC-003 / AC-008 / AC-010)
    private(set) var requestCount = 0
    private let lock = NSLock()

    // ImmichClient lifecycle surface (no-op storage; tests inspect directly).
    var configuredBaseURL: URL?
    var configuredToken: String?
    func configure(baseURL: URL?, token: String?) {
        configuredBaseURL = baseURL
        configuredToken = token
    }
    var authDelegate: (any AuthSessionDelegate)?

    var lastLoginBody: LoginCredentialDto?
    var loginResponse: LoginResponseDto?
    var loginError: Error?

    var pingResponse: ServerPingResponse?
    var pingError: Error?
    var pingResSequences: [ServerPingResponse] = []
    private var pingCallIndex = 0

    var logoutResponse: LogoutResponseDto?
    var validateResponse: ValidateAccessTokenResponseDto?

    var bucketsResponse: [TimeBucketsResponseDto] = []
    var bucketResponses: [String: TimeBucketAssetResponseDto] = [:]

    var getAssetResponse: [String: AssetResponseDto] = [:]
    var lastUpdateAssetId: String?
    var lastUpdateAssetBody: UpdateAssetDto?
    var lastUpdateMethod: HTTPMethod?
    var updateAssetResponse: AssetResponseDto?
    var lastDeleteBody: AssetBulkDeleteDto?
    var deleteError: Error?

    // Trash capture (AC-300, AC-307..AC-309)
    var lastTimeBucketsIsTrashed: Bool?
    var lastRestoreTrashAssetsIds: [String]?
    var restoreTrashAssetsResponse: TrashResponseDto?
    var restoreTrashAssetsError: Error?
    var restoreAllTrashCallCount = 0
    var restoreAllTrashResponse: TrashResponseDto?
    var restoreAllTrashError: Error?
    var emptyTrashCallCount = 0
    var emptyTrashResponse: TrashResponseDto?
    var emptyTrashError: Error?

    // Search capture (AC-400..AC-406)
    var lastMetadataSearchDto: MetadataSearchDto?
    var searchMetadataResponse: SearchResponseDto?
    var searchMetadataError: Error?
    var lastSmartSearchDto: SmartSearchDto?
    var smartSearchResponse: SearchResponseDto?
    var smartSearchError: Error?
    var exploreResponse: [SearchExploreResponseDto]?
    var exploreError: Error?

    // Albums capture (AC-500..AC-518)
    var albumsResponse: [AlbumResponseDto]?
    var albumsError: Error?
    var lastCreateAlbumDto: CreateAlbumDto?
    var createAlbumResponse: AlbumResponseDto?
    var createAlbumError: Error?
    var getAlbumResponse: [String: AlbumResponseDto] = [:]
    var getAlbumError: Error?
    var deleteAlbumCallCount = 0
    var lastDeletedAlbumId: String?
    var deleteAlbumError: Error?
    var lastAddAssetsAlbumId: String?
    var lastAddAssetsIds: [String]?
    var addAssetsResponse: [BulkIdResponseDto]?
    var addAssetsError: Error?
    var lastRemoveAssetsAlbumId: String?
    var lastRemoveAssetsIds: [String]?
    var removeAssetsResponse: [BulkIdResponseDto]?
    var removeAssetsError: Error?

    // Shared links capture (AC-500..AC-518)
    var lastSharedLinksAlbumId: String?
    var sharedLinksResponse: [SharedLinkResponseDto]?
    var sharedLinksError: Error?
    var lastCreateSharedLinkDto: SharedLinkCreateDto?
    var createSharedLinkResponse: SharedLinkResponseDto?
    var createSharedLinkError: Error?
    var lastDeleteSharedLinkId: String?
    var deleteSharedLinkCallCount = 0
    var deleteSharedLinkError: Error?

    // Upload capture (AC-008)
    var lastUploadData: Data?
    var lastUploadFileCreatedAt: String?
    var lastUploadFileModifiedAt: String?
    var lastUploadFilename: String?
    var lastUploadDuration: Int?
    var lastUploadIsFavorite: Bool?
    var lastUploadVisibility: AssetVisibility?
    var lastUploadChecksum: String?
    var uploadResponse: AssetMediaResponseDto?

    var bulkUploadCheckResponse: AssetBulkUploadCheckResponse?

    // Mutable global error that, if set, is thrown from any call.
    var globalError: Error?

    func bump() { lock.lock(); requestCount += 1; lock.unlock() }

    func ping() async throws -> ServerPingResponse {
        bump()
        if let e = globalError ?? pingError { throw e }
        if !pingResSequences.isEmpty {
            let r = pingResSequences[min(pingCallIndex, pingResSequences.count - 1)]
            pingCallIndex += 1
            return r
        }
        return pingResponse ?? ServerPingResponse(res: "pong")
    }

    func serverVersion() async throws -> ServerVersionResponseDto {
        bump()
        if let e = globalError { throw e }
        return ServerVersionResponseDto(major: 1, minor: 120, patch: 0, prerelease: nil)
    }

    func serverConfig() async throws -> ServerConfigDto {
        bump()
        if let e = globalError { throw e }
        return ServerConfigDto(
            oauthButtonText: "", loginPageMessage: "", trashDays: 30, userDeleteDelay: 7,
            isInitialized: true, isOnboarded: true, externalDomain: "", publicUsers: false,
            mapDarkStyleUrl: "", mapLightStyleUrl: "", maintenanceMode: false, minFaces: 3
        )
    }

    func login(email: String, password: String) async throws -> LoginResponseDto {
        bump()
        lastLoginBody = LoginCredentialDto(email: email, password: password)
        if let e = globalError ?? loginError { throw e }
        return loginResponse ?? LoginResponseDto(
            accessToken: "test-jwt", userId: "user-uuid", userEmail: email, name: "Test",
            profileImagePath: "", isAdmin: false, shouldChangePassword: false, isOnboarded: true
        )
    }

    func logout() async throws -> LogoutResponseDto {
        bump()
        if let e = globalError { throw e }
        return logoutResponse ?? LogoutResponseDto(successful: true, redirectUri: "")
    }

    func validateToken() async throws -> ValidateAccessTokenResponseDto {
        bump()
        if let e = globalError { throw e }
        return validateResponse ?? ValidateAccessTokenResponseDto(authStatus: true)
    }

    func getTimeBuckets(isFavorite: Bool?, isTrashed: Bool?) async throws -> [TimeBucketsResponseDto] {
        bump()
        lastTimeBucketsIsTrashed = isTrashed
        if let e = globalError { throw e }
        return bucketsResponse
    }

    func getTimeBucket(timeBucket: String) async throws -> TimeBucketAssetResponseDto {
        bump()
        if let e = globalError { throw e }
        return bucketResponses[timeBucket] ?? TimeBucketAssetResponseDto(
            id: [], ownerId: [], ratio: [], isFavorite: [], visibility: [], isTrashed: [],
            isImage: [], thumbhash: [], createdAt: [], fileCreatedAt: [], localOffsetHours: [],
            duration: [], livePhotoVideoId: [], projectionType: [],
            stack: nil, city: nil, country: nil, latitude: nil, longitude: nil
        )
    }

    func getAsset(id: String) async throws -> AssetResponseDto {
        bump()
        if let e = globalError { throw e }
        return getAssetResponse[id] ?? AssetResponseDto(
            id: id, type: "IMAGE", thumbhash: nil, localDateTime: "2024-07-01T00:00:00.000Z",
            duration: nil, hasMetadata: true, width: 100, height: 100, createdAt: "2024-07-01T00:00:00.000Z",
            ownerId: "owner", originalPath: "/x.jpg", originalFileName: "x.jpg",
            fileCreatedAt: "2024-07-01T00:00:00.000Z", fileModifiedAt: "2024-07-01T00:00:00.000Z",
            updatedAt: "2024-07-01T00:00:00.000Z", isFavorite: false, isArchived: false,
            isTrashed: false, isOffline: false, visibility: "timeline", checksum: "abc", isEdited: false
        )
    }

    func updateAsset(id: String, dto: UpdateAssetDto) async throws -> AssetResponseDto {
        bump()
        if let e = globalError { throw e }
        lastUpdateAssetId = id
        lastUpdateAssetBody = dto
        lastUpdateMethod = .PATCH
        if let r = updateAssetResponse { return r }
        // Echo back with isFavorite toggled.
        var base = try await getAsset(id: id)
        if let fav = dto.isFavorite { base.isFavorite = fav }
        return base
    }

    func deleteAssets(ids: [String], force: Bool?) async throws {
        bump()
        lastDeleteBody = AssetBulkDeleteDto(ids: ids, force: force)
        if let e = globalError ?? deleteError { throw e }
    }

    // MARK: - Trash (AC-307..AC-309)

    func restoreTrashAssets(ids: [String]) async throws -> TrashResponseDto {
        bump()
        lastRestoreTrashAssetsIds = ids
        if let e = globalError ?? restoreTrashAssetsError { throw e }
        return restoreTrashAssetsResponse ?? TrashResponseDto(count: ids.count)
    }

    func restoreAllTrash() async throws -> TrashResponseDto {
        bump()
        restoreAllTrashCallCount += 1
        if let e = globalError ?? restoreAllTrashError { throw e }
        return restoreAllTrashResponse ?? TrashResponseDto(count: 5)
    }

    func emptyTrash() async throws -> TrashResponseDto {
        bump()
        emptyTrashCallCount += 1
        if let e = globalError ?? emptyTrashError { throw e }
        return emptyTrashResponse ?? TrashResponseDto(count: 5)
    }

    // MARK: - Search (AC-400..AC-406)

    func searchMetadata(dto: MetadataSearchDto) async throws -> SearchResponseDto {
        bump()
        lastMetadataSearchDto = dto
        if let e = globalError ?? searchMetadataError { throw e }
        return searchMetadataResponse ?? SearchResponseDto(
            assets: SearchAssetResponseDto(count: 0, items: [], nextPage: nil)
        )
    }

    func searchSmart(dto: SmartSearchDto) async throws -> SearchResponseDto {
        bump()
        lastSmartSearchDto = dto
        if let e = globalError ?? smartSearchError { throw e }
        return smartSearchResponse ?? SearchResponseDto(
            assets: SearchAssetResponseDto(count: 0, items: [], nextPage: nil)
        )
    }

    func getExploreData() async throws -> [SearchExploreResponseDto] {
        bump()
        if let e = globalError ?? exploreError { throw e }
        return exploreResponse ?? []
    }

    // MARK: - Albums (AC-500..AC-518)

    private func cannedAlbum(id: String, name: String = "Album", count: Int = 0) -> AlbumResponseDto {
        AlbumResponseDto(
            id: id, albumName: name, description: "", createdAt: "2024-01-01T00:00:00.000Z",
            updatedAt: "2024-01-01T00:00:00.000Z", albumThumbnailAssetId: nil, shared: false,
            hasSharedLink: false, assetCount: count, isActivityEnabled: false, order: nil
        )
    }

    func getAlbums() async throws -> [AlbumResponseDto] {
        bump()
        if let e = globalError ?? albumsError { throw e }
        return albumsResponse ?? []
    }

    func createAlbum(dto: CreateAlbumDto) async throws -> AlbumResponseDto {
        bump()
        lastCreateAlbumDto = dto
        if let e = globalError ?? createAlbumError { throw e }
        return createAlbumResponse ?? cannedAlbum(id: "album-new", name: dto.albumName, count: dto.assetIds?.count ?? 0)
    }

    func getAlbum(id: String) async throws -> AlbumResponseDto {
        bump()
        if let e = globalError ?? getAlbumError { throw e }
        return getAlbumResponse[id] ?? cannedAlbum(id: id)
    }

    func deleteAlbum(id: String) async throws {
        bump()
        deleteAlbumCallCount += 1
        lastDeletedAlbumId = id
        if let e = globalError ?? deleteAlbumError { throw e }
    }

    func addAssetsToAlbum(albumId: String, dto: BulkIdsDto) async throws -> [BulkIdResponseDto] {
        bump()
        lastAddAssetsAlbumId = albumId
        lastAddAssetsIds = dto.ids
        if let e = globalError ?? addAssetsError { throw e }
        return addAssetsResponse ?? dto.ids.map { BulkIdResponseDto(id: $0, success: true, error: nil, errorMessage: nil) }
    }

    func removeAssetsFromAlbum(albumId: String, dto: BulkIdsDto) async throws -> [BulkIdResponseDto] {
        bump()
        lastRemoveAssetsAlbumId = albumId
        lastRemoveAssetsIds = dto.ids
        if let e = globalError ?? removeAssetsError { throw e }
        return removeAssetsResponse ?? dto.ids.map { BulkIdResponseDto(id: $0, success: true, error: nil, errorMessage: nil) }
    }

    // MARK: - Shared Links (AC-500..AC-518)

    func getSharedLinks(albumId: String?) async throws -> [SharedLinkResponseDto] {
        bump()
        lastSharedLinksAlbumId = albumId
        if let e = globalError ?? sharedLinksError { throw e }
        return sharedLinksResponse ?? []
    }

    func createSharedLink(dto: SharedLinkCreateDto) async throws -> SharedLinkResponseDto {
        bump()
        lastCreateSharedLinkDto = dto
        if let e = globalError ?? createSharedLinkError { throw e }
        if let r = createSharedLinkResponse { return r }
        return SharedLinkResponseDto(
            id: "link-new", description: dto.description, password: dto.password, userId: "owner",
            key: "a2V5", type: dto.type, createdAt: "2024-01-01T00:00:00.000Z", expiresAt: dto.expiresAt,
            assets: [], album: nil, allowUpload: dto.allowUpload ?? false,
            allowDownload: dto.allowDownload ?? true, showMetadata: dto.showMetadata ?? true, slug: nil
        )
    }

    func deleteSharedLink(id: String) async throws {
        bump()
        deleteSharedLinkCallCount += 1
        lastDeleteSharedLinkId = id
        if let e = globalError ?? deleteSharedLinkError { throw e }
    }

    func uploadAsset(
        data: Data, fileCreatedAt: String, fileModifiedAt: String, filename: String,
        duration: Int?, isFavorite: Bool, visibility: AssetVisibility, livePhotoVideoId: String?,
        checksum: String
    ) async throws -> AssetMediaResponseDto {
        bump()
        lastUploadData = data
        lastUploadFileCreatedAt = fileCreatedAt
        lastUploadFileModifiedAt = fileModifiedAt
        lastUploadFilename = filename
        lastUploadDuration = duration
        lastUploadIsFavorite = isFavorite
        lastUploadVisibility = visibility
        lastUploadChecksum = checksum
        if let e = globalError { throw e }
        return uploadResponse ?? AssetMediaResponseDto(id: "new-asset", status: "created")
    }

    func bulkUploadCheck(_ request: AssetBulkUploadCheckRequest) async throws -> AssetBulkUploadCheckResponse {
        bump()
        if let e = globalError { throw e }
        return bulkUploadCheckResponse ?? AssetBulkUploadCheckResponse(results: [])
    }
}
