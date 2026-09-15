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

/// `POST /api/users/profile-image` (gap G16) — the `201` body of
/// `CreateProfileImageResponseDto` in the OpenAPI `main` spec. Only the photo
/// moved: the rest of the user row is untouched, so the screen reuses the
/// identity it already loaded rather than refetching.
struct CreateProfileImageResponseDto: Codable, Equatable {
    let userId: String
    let profileImagePath: String
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
    var parentId: String?
    var createdAt: String?
    var updatedAt: String?
}

struct TagCreateDto: Codable, Equatable {
    let name: String
    var color: String?
    var parentId: String?
}

struct TagUpdateDto: Codable, Equatable {
    var color: String?
}

struct AssetStackResponseDto: Codable, Equatable {
    let id: String
    let primaryAssetId: String
    let assetCount: Int
}

// MARK: - Stacks (gap #1)

/// `StackResponseDto` — full stack: primary id + member assets.
struct StackResponseDto: Codable, Equatable {
    let id: String
    let primaryAssetId: String
    let assets: [AssetResponseDto]
}

/// `POST /api/stacks` — first asset id becomes primary (min 2).
struct StackCreateDto: Codable, Equatable {
    let assetIds: [String]
}

/// `PUT /api/stacks/{id}` — change the stack's primary asset.
struct StackUpdateDto: Codable, Equatable {
    var primaryAssetId: String?
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

/// Body for `PATCH /api/assets/:id` when the only field written is the rating.
///
/// The server has three valid rating states — `1…5` (starred), `-1` (rejected)
/// and `null` (unrated) — and rejects `0` since v3, so « not rated » is the
/// *absence* of a value and can only travel as an explicit JSON `null`.
/// `UpdateAssetDto.rating` is a plain `Int?`: its synthesized encoder **omits**
/// the key when nil, which would make un-rating an asset impossible to express
/// (the request body would arrive as `{}`). `RatingValue` keeps the key on the
/// wire, so `RatingUpdateDto(rating: nil)` encodes as `{"rating":null}`.
struct RatingUpdateDto: Codable, Equatable {
    var rating: RatingValue

    init(rating: Int?) {
        self.rating = rating.map(RatingValue.value) ?? .unrated
    }
}

/// Nullable rating value: a number in `1…5`, or `null` for "unrated".
enum RatingValue: Codable, Equatable {
    case value(Int)
    case unrated

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .unrated
        } else {
            self = .value(try container.decode(Int.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value(let number): try container.encode(number)
        case .unrated: try container.encodeNil()
        }
    }
}

struct AssetBulkDeleteDto: Codable, Equatable {
    let ids: [String]
    var force: Bool?
}

/// `PUT /api/assets` — bulk update; archive is expressed as `visibility: "archive"`.
struct AssetBulkUpdateDto: Codable, Equatable {
    let ids: [String]
    var dateTimeOriginal: String?
    var dateTimeRelative: String?
    var description: String?
    var isFavorite: Bool?
    var latitude: Double?
    var longitude: Double?
    var rating: Int?
    var timeZone: String?
    var visibility: AssetVisibility?
    var duplicateId: String?
}

// MARK: - Trash DTOs (AC-310)

struct BulkIdsDto: Codable, Equatable {
    let ids: [String]
}

struct TrashResponseDto: Codable, Equatable {
    let count: Int
}
