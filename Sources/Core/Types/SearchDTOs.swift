import Foundation

// MARK: - Search Request DTOs

/// Body for `POST /api/search/metadata` — text/EXIF field search.
/// For MVP free-text search: caller sets `query`. Field-specific search
/// (city, make, model, ...) is used by Explore tap (AC-404b).
struct MetadataSearchDto: Codable, Equatable {
    var query: String?
    /// v3.2.0 field filters — the replacement of the struct's deprecated scalar
    /// fields (`ocr` among them). Optional so the key disappears from the body
    /// when no filter is active; see `SearchFilterDto`.
    var filter: SearchFilterDto?
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
    /// Direction-only sort, deprecated since v3.2.0 — **never written**: the
    /// sheet's Sort option goes through `orderBy` (which names a field; `order`
    /// cannot). Kept declared because the DTO mirrors the published schema.
    var order: String?
    var page: Int?
    var size: Int?
    var withExif: Bool?
    /// Detected-text criterion. The flat field is `x-immich-state: Deprecated`
    /// since v3.2.0; its replacement is `filter.ocr.matches`
    /// (`StringSimilarityFilter`), which is the only route this app writes
    /// (ocr-text). Declared so the DTO mirrors the published schema, never set.
    var ocr: String?
    /// Taken-date range — ISO-8601 strings, because the schema publishes them
    /// as `string`/`date-time` and the `Date` → `String` step belongs to the
    /// ViewModel. Deprecated flat fields like `ocr` above (replacement:
    /// `filter.takenAt`), kept for the same reason as `rating`: the whole
    /// screen is still on the flat route. Written only while the Filters
    /// sheet's date toggle is on.
    var takenAfter: String?
    var takenBefore: String?
    /// Sort of the result set — a `SearchOrder` (`field` × `direction`), added
    /// in v3.2.0 and the non-deprecated replacement of `order`, which is
    /// therefore never written (it cannot name a field).
    var orderBy: SearchOrderDto?
}

/// `SearchOrder` of the published contract: the `orderBy` body of a metadata
/// search. Both members are enums server-side (`SearchOrderField`,
/// `AssetOrder`); kept as strings here so the DTO stays a plain mirror.
struct SearchOrderDto: Codable, Equatable {
    var field: String
    var direction: String
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
