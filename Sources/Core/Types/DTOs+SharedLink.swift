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
/// the shared content. Optional permission booleans default server-side.
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

    init(
        type: SharedLinkType,
        albumId: String? = nil,
        assetIds: [String]? = nil,
        description: String? = nil,
        password: String? = nil,
        expiresAt: String? = nil,
        allowUpload: Bool? = nil,
        allowDownload: Bool? = nil,
        showMetadata: Bool? = nil
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
