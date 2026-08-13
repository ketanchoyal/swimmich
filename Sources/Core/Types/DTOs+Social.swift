import Foundation

// MARK: - Activity DTOs (P0 api-surface-expansion)

enum ReactionType: String, Codable, Equatable {
    case comment
    case like
}

/// `POST /api/activities`
struct ActivityCreateDto: Codable, Equatable {
    let albumId: String
    let type: ReactionType
    var assetId: String?
    var comment: String?
}

/// `GET /api/activities`
struct ActivityResponseDto: Codable, Equatable {
    let id: String
    let createdAt: String
    let type: ReactionType
    let user: UserResponseDto
    let assetId: String
    var comment: String?
}

// MARK: - Memories DTOs (P0 api-surface-expansion)

enum MemoryType: String, Codable, Equatable {
    case on_this_day
    /// Server-side memory types this client doesn't render yet. Decoding
    /// unknown types as `.unknown` keeps the whole `GET /api/memories`
    /// payload decodable instead of failing the entire list.
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MemoryType(rawValue: raw) ?? .unknown
    }
}

struct OnThisDayDto: Codable, Equatable {
    let year: Int
}

/// `GET /api/memories`
struct MemoryResponseDto: Codable, Equatable {
    let id: String
    let createdAt: String
    let updatedAt: String
    let memoryAt: String
    let ownerId: String
    let type: MemoryType
    let data: OnThisDayDto
    let assets: [AssetResponseDto]
    let isSaved: Bool
    var showAt: String?
    var hideAt: String?
    var seenAt: String?
    var deletedAt: String?
}

// MARK: - Duplicates DTOs (P0 api-surface-expansion)

/// `GET /api/duplicates` — one entry per detected duplicate group.
struct DuplicateResponseDto: Codable, Equatable {
    let duplicateId: String
    let assets: [AssetResponseDto]
    let suggestedKeepAssetIds: [String]
}