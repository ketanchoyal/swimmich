import Foundation

// MARK: - Albums (AC-500..AC-518)
//
// Source: github.com/immich-app/immich server/src/dtos/album.dto.ts
// Note: AlbumResponseDto does NOT include an `assets` array (only `assetCount`).
// Album assets are fetched separately via searchMetadata(albumIds:) — see FM-2.

/// `AlbumResponseDto` from `GET /api/albums` and `GET /api/albums/:id`.
/// Collaborator details (`albumUsers`, `contributorCounts`) and date bounds
/// are ignored for MVP (collaborative = V2). Explicit CodingKeys keeps decoding
/// resilient to server-side field additions.
struct AlbumResponseDto: Codable, Equatable {
    let id: String
    let albumName: String
    let description: String
    let createdAt: String
    let updatedAt: String
    let albumThumbnailAssetId: String?
    let shared: Bool
    let hasSharedLink: Bool
    let assetCount: Int
    let isActivityEnabled: Bool
    let order: AssetOrder?

    enum CodingKeys: String, CodingKey {
        case id, albumName, description, createdAt, updatedAt
        case albumThumbnailAssetId, shared, hasSharedLink, assetCount
        case isActivityEnabled, order
    }
}

/// `CreateAlbumDto` body for `POST /api/albums`.
/// Optional fields are omitted from JSON when nil (synthesized Codable behavior).
struct CreateAlbumDto: Codable, Equatable {
    let albumName: String
    let description: String?
    let assetIds: [String]?
}

/// `BulkIdResponseDto` — per-asset result for bulk add/remove album assets.
/// `error` and `errorMessage` are present only on failure.
enum BulkIdErrorReason: String, Codable {
    case duplicate = "DUPLICATE"
    case noPermission = "NO_PERMISSION"
    case notFound = "NOT_FOUND"
    case unknown = "UNKNOWN"
}

struct BulkIdResponseDto: Codable, Equatable {
    let id: String
    let success: Bool
    let error: BulkIdErrorReason?
    let errorMessage: String?
}
