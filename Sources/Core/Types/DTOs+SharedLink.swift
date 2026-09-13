import Foundation

// MARK: - Shared Links (AC-500..AC-518)
//
// Source: github.com/immich-app/immich server/src/dtos/shared-link.dto.ts

/// `SharedLinkType` enum — ALBUM shares a whole album, INDIVIDUAL shares
/// a set of standalone assets.
enum SharedLinkType: String, Codable, Sendable {
    case album = "ALBUM"
    case individual = "INDIVIDUAL"
}

/// `SharedLinkCreateDto` body for `POST /api/shared-links`.
/// `type` is required; `albumId` (ALBUM) or `assetIds` (INDIVIDUAL) provides
/// the shared content. Optional permission booleans default server-side
/// (`allowUpload ?? true`, `allowDownload ?? true`).
///
/// `slug` is the custom URL slug ("Custom URL slug" in the OpenAPI): when set,
/// the link's public URL becomes `…/s/<slug>` instead of `…/share/<key>`.
struct SharedLinkCreateDto: Codable, Equatable {
    let type: SharedLinkType
    let albumId: String?
    let assetIds: [String]?
    let description: String?
    let password: String?
    let expiresAt: String?
    let allowUpload: Bool?
    let allowDownload: Bool?
    let showMetadata: Bool?
    let slug: String?

    init(
        type: SharedLinkType,
        albumId: String? = nil,
        assetIds: [String]? = nil,
        description: String? = nil,
        password: String? = nil,
        expiresAt: String? = nil,
        allowUpload: Bool? = nil,
        allowDownload: Bool? = nil,
        showMetadata: Bool? = nil,
        slug: String? = nil
    ) {
        self.type = type
        self.albumId = albumId
        self.assetIds = assetIds
        self.description = description
        self.password = password
        self.expiresAt = expiresAt
        self.allowUpload = allowUpload
        self.allowDownload = allowDownload
        self.showMetadata = showMetadata
        self.slug = slug
    }
}

/// `SharedLinkResponseDto` from `GET /api/shared-links` and `POST /api/shared-links`.
/// `password` is returned by the server (nullable) — MUST NOT be displayed in UI
/// (VM-J manual). `album`/`assets` are inlined by the server.
struct SharedLinkResponseDto: Codable, Equatable {
    let id: String
    let description: String?
    let password: String?
    let userId: String
    let key: String
    let type: SharedLinkType
    let createdAt: String
    let expiresAt: String?
    let assets: [AssetResponseDto]
    let album: AlbumResponseDto?
    let allowUpload: Bool
    let allowDownload: Bool
    let showMetadata: Bool
    let slug: String?

    enum CodingKeys: String, CodingKey {
        case id, description, password, userId, key, type
        case createdAt, expiresAt, assets, album
        case allowUpload, allowDownload, showMetadata, slug
    }
}

// MARK: - Shared link assets (owner-side)

/// `AssetIdsDto` — body of `PUT /api/shared-links/{id}/assets`.
/// Note the field name: this route takes `assetIds`, where the album routes
/// take `ids` (`BulkIdsDto`).
struct AssetIdsDto: Codable, Equatable {
    let assetIds: [String]
}

/// Error reason of `AssetIdsResponseDto`. The server enum is `@deprecated` in
/// favour of `BulkIdErrorReason`, but this route still serialises the
/// **lowercase** values, so the raw strings are not the `BulkIdResponseDto`
/// ones.
enum AssetIdErrorReason: String, Codable, Equatable {
    case duplicate
    case noPermission = "no_permission"
    case notFound = "not_found"
}

/// `AssetIdsResponseDto` — per-asset result of `PUT /api/shared-links/{id}/assets`.
/// `error` is present only on failure. Field is `assetId`, not `id`: this is
/// NOT `BulkIdResponseDto`.
struct AssetIdsResponseDto: Codable, Equatable {
    let assetId: String
    let success: Bool
    let error: AssetIdErrorReason?
}
