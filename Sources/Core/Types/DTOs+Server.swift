import Foundation

// MARK: - Server statistics DTOs (P0 api-surface-expansion)

/// `GET /api/server/statistics` — current user's storage usage.
struct ServerStatsResponseDto: Codable, Equatable {
    let photos: Int
    let videos: Int
    let usage: Int
    let usagePhotos: Int
    let usageVideos: Int
    let usageByUser: [UsageByUserDto]
}

struct UsageByUserDto: Codable, Equatable {
    let userId: String
    let userName: String
    let photos: Int
    let videos: Int
    let usage: Int
    let usagePhotos: Int
    let usageVideos: Int
    let quotaSizeInBytes: Int
}

// MARK: - Shared link edit DTOs (P0 api-surface-expansion)

/// `PUT /api/shared-links/{id}` — all fields optional, only provided fields are updated.
struct SharedLinkEditDto: Codable, Equatable {
    var password: String?
    var expiresAt: String?
    var allowUpload: Bool?
    var allowDownload: Bool?
    var showMetadata: Bool?
    var description: String?
}