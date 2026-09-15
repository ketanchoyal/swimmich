import Foundation

// MARK: - Search Request DTOs

/// Body for `POST /api/search/metadata` — text/EXIF field search.
/// For MVP free-text search: caller sets `query`. Field-specific search
/// (city, make, model, ...) is used by Explore tap (AC-404b).
struct MetadataSearchDto: Codable, Equatable {
    var query: String?
    var make: String?
    var model: String?
    var lensModel: String?
    var city: String?
    var state: String?
    var country: String?
    var type: String?
    var isFavorite: Bool?
    /// Filter by rating `1...5` (the server's scale — `0` is invalid since v3).
    ///
    /// The flat field is `x-immich-state: Deprecated` since v3.2.0, **but so are
    /// the 33 other flat fields of this schema** (`isFavorite`, `city`, `make`,
    /// `model`, `visibility`, …), i.e. every filter this screen already sends.
    /// The replacement is `filter: SearchFilter` (whose `rating` is a
    /// `NumberFilterNullable`) and the migration is cross-cutting — switching
    /// `rating` alone would put two conventions in one request body and break
    /// servers older than v3.2.0. Keep it flat until that migration happens.
    var rating: Int?
    var personIds: [String]?
    var albumIds: [String]? // AC-519 — enables album asset fetch (FM-2 mitigation)
    var order: String?
    var page: Int?
    var size: Int?
    var withExif: Bool?
}

/// Body for `POST /api/search/smart` — CLIP semantic search.
struct SmartSearchDto: Codable, Equatable {
    var query: String
    var page: Int?
    var size: Int?
    var withExif: Bool?
}

/// Body for `POST /api/search/statistics` — returns a total count for a given
/// metadata filter. Used by Explore to show "247 photos" per place. Mirrors
/// the subset of `BaseSearchSchema` field filters the server honors.
struct SearchStatisticsDto: Codable, Equatable {
    var city: String?
    var state: String?
    var country: String?
    var make: String?
    var model: String?
    var lensModel: String?
}

/// Response for `POST /api/search/statistics`.
struct SearchStatisticsResponseDto: Codable, Equatable {
    let total: Int
}

// MARK: - Search Response DTOs

/// Top-level response wrapper. Immich server also serializes `albums`, which
/// we intentionally ignore via explicit CodingKeys (FM-1 mitigation — Swift
/// JSONDecoder ignores unknown JSON keys when CodingKeys is explicit).
struct SearchResponseDto: Codable, Equatable {
    let assets: SearchAssetResponseDto

    enum CodingKeys: String, CodingKey {
        case assets
    }
}

/// `assets` payload. Immich server also sends `total` (deprecated) and
/// `facets` arrays — ignored via CodingKeys.
struct SearchAssetResponseDto: Codable, Equatable {
    let count: Int
    let items: [AssetResponseDto]
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case count, items, nextPage
    }
}

// MARK: - Explore

/// `GET /api/search/explore` response. Grouped by `fieldName`
/// (e.g. "exifInfo.city"), each value carrying a representative thumbnail.
struct SearchExploreResponseDto: Codable, Equatable {
    let fieldName: String
    let items: [SearchExploreItem]
}

struct SearchExploreItem: Codable, Equatable {
    let value: String
    let data: AssetResponseDto
}
