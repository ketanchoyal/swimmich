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
