import Foundation

// MARK: - Auth DTOs

struct LoginCredentialDto: Codable, Equatable {
    let email: String
    let password: String
}

struct LoginResponseDto: Codable, Equatable {
    let accessToken: String
    let userId: String
    let userEmail: String
    let name: String
    let profileImagePath: String
    let isAdmin: Bool
    let shouldChangePassword: Bool
    let isOnboarded: Bool
}

struct LogoutResponseDto: Codable, Equatable {
    let successful: Bool
    let redirectUri: String
}

struct ValidateAccessTokenResponseDto: Codable, Equatable {
    let authStatus: Bool
}

// MARK: - Server DTOs

struct ServerPingResponse: Codable, Equatable {
    let res: String
}

struct ServerVersionResponseDto: Codable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: Int?
}

struct ServerConfigDto: Codable, Equatable {
    let oauthButtonText: String
    let loginPageMessage: String
    let trashDays: Int
    let userDeleteDelay: Int
    let isInitialized: Bool
    let isOnboarded: Bool
    let externalDomain: String
    let publicUsers: Bool
    let mapDarkStyleUrl: String
    let mapLightStyleUrl: String
    let maintenanceMode: Bool
    let minFaces: Int
}

// MARK: - Timeline DTOs

/// One element of `GET /api/timeline/buckets`.
struct TimeBucketsResponseDto: Codable, Equatable {
    let timeBucket: String
    let count: Int
}

/// Columnar response of `GET /api/timeline/bucket`.
///
/// FM-1: All parallel arrays must be zipped by index. Required arrays: 14. Optional: 5.
struct TimeBucketAssetResponseDto: Codable, Equatable {
    // Required (14)
    let id: [String]
    let ownerId: [String]
    let ratio: [Double]
    let isFavorite: [Bool]
    let visibility: [String]
    let isTrashed: [Bool]
    let isImage: [Bool]
    let thumbhash: [String?]
    let createdAt: [String]
    let fileCreatedAt: [String]
    let localOffsetHours: [Double]
    let duration: [Int?]
    let livePhotoVideoId: [String?]
    let projectionType: [String?]
    // Optional (5)
    let stack: [[String?]?]?
    let city: [String?]?
    let country: [String?]?
    let latitude: [Double?]?
    let longitude: [Double?]?
}

// MARK: - Asset Response (full) DTOs

struct AssetResponseDto: Codable, Equatable {
    let id: String
    let type: String
    var thumbhash: String?
    var localDateTime: String
    var duration: Int?
    var hasMetadata: Bool
    var width: Int?
    var height: Int?
    var createdAt: String
    var ownerId: String
    var originalPath: String
    var originalFileName: String
    var fileCreatedAt: String
    var fileModifiedAt: String
    var updatedAt: String
    var isFavorite: Bool
    var isArchived: Bool
    var isTrashed: Bool
    var isOffline: Bool
    var visibility: String
    var checksum: String
    var isEdited: Bool
    // optional
    var originalMimeType: String?
    var livePhotoVideoId: String?
    var owner: UserResponseDto?
    var libraryId: String?
    var exifInfo: ExifResponseDto?
    var tags: [TagResponseDto]?
    var people: [PersonResponseDto]?
    var stack: AssetStackResponseDto?
    var duplicateId: String?
    var resized: Bool?
}

struct UserResponseDto: Codable, Equatable {
    let id: String
    let name: String
    let email: String
    let profileImagePath: String
    let avatarColor: String
    let profileChangedAt: String
}

struct ExifResponseDto: Codable, Equatable {
    var make: String?
    var model: String?
    var exifImageWidth: Int?
    var exifImageHeight: Int?
    var fileSizeInByte: Int?
    var orientation: String?
    var dateTimeOriginal: String?
    var modifyDate: String?
    var timeZone: String?
    var lensModel: String?
    var fNumber: Double?
    var focalLength: Double?
    var iso: Int?
    var exposureTime: String?
    var latitude: Double?
    var longitude: Double?
    var city: String?
    var state: String?
    var country: String?
    var description: String?
    var projectionType: String?
    var rating: Int?
}

struct TagResponseDto: Codable, Equatable {
    let id: String
    let name: String
    var value: String?
    var color: String?
}

struct PersonResponseDto: Codable, Equatable {
    let id: String
    let name: String
    var thumbnailPath: String?
    var isHidden: Bool?
}

struct AssetStackResponseDto: Codable, Equatable {
    let id: String
    let primaryAssetId: String
    let assetCount: Int
}

// MARK: - Upload DTOs

struct AssetMediaResponseDto: Codable, Equatable {
    let id: String
    let status: String
}

struct AssetBulkUploadCheckRequest: Codable, Equatable {
    struct Item: Codable, Equatable {
        let id: String
        let checksum: String
    }
    let assets: [Item]
}

struct AssetBulkUploadCheckResponse: Codable, Equatable {
    struct Result: Codable, Equatable {
        let id: String
        let action: String // "accept" | "reject"
        var reason: String?
        var assetId: String?
        var isTrashed: Bool?
    }
    let results: [Result]
}

// MARK: - Update / Delete

struct UpdateAssetDto: Codable, Equatable {
    var isFavorite: Bool?
    var visibility: String?
    var dateTimeOriginal: String?
    var latitude: Double?
    var longitude: Double?
    var rating: Int?
    var description: String?
    var livePhotoVideoId: String?
}

struct AssetBulkDeleteDto: Codable, Equatable {
    let ids: [String]
    var force: Bool?
}
