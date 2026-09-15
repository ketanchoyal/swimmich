import Foundation

// MARK: - Search filter DTOs (v3.2.0 structured filters)

/// `StringSimilarityFilter` — a text field matched by **similarity** (trigram /
/// full-text search), not by equality.
///
/// The server declares `additionalProperties: false` on the schema, so this
/// mirrors exactly what the OpenAPI publishes and nothing more.
struct StringSimilarityFilterDto: Codable, Equatable {
    var matches: String
}

/// `StringFilterNullable` — the operator set of the nullable string filters
/// (`city`, `state`, `country`, `make`, `model`, `lensModel`).
///
/// The sub-filters of `SearchFilter` are `nonEmptyPartial` server-side: a
/// sub-filter with no operator is rejected ("At least one of the following
/// fields is required"), which is why a projection writes at least one.
struct StringFilterNullableDto: Codable, Equatable {
    var eq: String?
    var ne: String?
    var `in`: [String]?
    var notIn: [String]?
}

/// `NumberFilterNullable` — the operator set of `SearchFilter.rating`.
///
/// `eq`/`ne` are nullable in the contract ("null for unrated"); the app only
/// writes `eq`, because the flat `rating` field it replaces cannot express
/// "unrated" either (a `nil` `Int?` leaves the body instead of sending `null`).
struct NumberFilterNullableDto: Codable, Equatable {
    var eq: Double?
    var ne: Double?
    var lt: Double?
    var lte: Double?
    var gt: Double?
    var gte: Double?
    var `in`: [Double]?
    var notIn: [Double]?
}

/// `DateFilter` — the operator set of `SearchFilter.takenAt`.
///
/// The schema publishes `date-time` strings, so the values are the very
/// ISO-8601 strings the flat `takenAfter`/`takenBefore` already carry: one
/// formatter, one wire format, whether the request goes out flat or structured.
struct DateFilterDto: Codable, Equatable {
    var eq: String?
    var ne: String?
    var gt: String?
    var gte: String?
    var lt: String?
    var lte: String?
}

/// `EnumFilterAssetType` — the operator set of `SearchFilter.type`, whose
/// values are `AssetTypeEnum`'s (`IMAGE`, `VIDEO`, `AUDIO`, `OTHER`).
struct EnumFilterAssetTypeDto: Codable, Equatable {
    var eq: String?
    var ne: String?
    var `in`: [String]?
    var notIn: [String]?
}

/// `BoolFilter` — `SearchFilter.isFavorite`. `eq` is the schema's only property
/// and the only **required** one in the whole filter tree.
struct BoolFilterDto: Codable, Equatable {
    var eq: Bool
}

/// `SearchFilter` — the v3.2.0 replacement of the deprecated scalar fields of
/// `MetadataSearchDto` (`city`, `rating`, `ocr` among them).
///
/// Stays a strict subset of `SearchFilter` (the server rejects additional
/// properties at this level) and carries **what the Filters sheet can set** —
/// the sheet has no picker for `personIds`, `tagIds`, `albumIds`, `visibility`,
/// `hasPeople`… so this type does not declare them. The sub-filters are
/// optional so an undone constraint leaves the body instead of sending `null`.
struct SearchFilterDto: Codable, Equatable {
    var ocr: StringSimilarityFilterDto?
    var city: StringFilterNullableDto?
    var state: StringFilterNullableDto?
    var country: StringFilterNullableDto?
    var make: StringFilterNullableDto?
    var model: StringFilterNullableDto?
    var lensModel: StringFilterNullableDto?
    var type: EnumFilterAssetTypeDto?
    var isFavorite: BoolFilterDto?
    var rating: NumberFilterNullableDto?
    /// `takenAt` — the structured form of the flat `takenAfter`/`takenBefore`
    /// pair (one range, `gte` × `lte`). The server maps it to
    /// `asset.fileCreatedAt`, the same column the flat bounds filter on, so the
    /// two routes answer the same question.
    var takenAt: DateFilterDto?
}
