import Foundation

// MARK: - Search filter DTOs (v3.2.0 field filters)

/// `StringSimilarityFilter` — a text field matched by **similarity** (trigram /
/// full-text search), not by equality.
///
/// The server declares `additionalProperties: false` on the schema, so this
/// mirrors exactly what the OpenAPI publishes and nothing more.
struct StringSimilarityFilterDto: Codable, Equatable {
    var matches: String
}

/// `SearchFilter` — the v3.2.0 replacement of the deprecated scalar fields of
/// `MetadataSearchDto` (`ocr` among them).
///
/// Stays a strict subset of `SearchFilter` (the server rejects additional
/// properties) and is optional so the `filter` key disappears from the body
/// when no filter is active.
struct SearchFilterDto: Codable, Equatable {
    var ocr: StringSimilarityFilterDto?
}
