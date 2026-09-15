import Foundation

/// Value-typed state of the Search tab's Filters sheet (search-filters).
///
/// One constraint per `MetadataSearchDto` field, and exactly one writer: the
/// sheet mutates the value, `apply(to:)` projects it into the request body, and
/// `constraints` is the projection the chips bar displays. A constraint the
/// sheet cannot show is a constraint this type does not carry — which is why
/// `personIds`, `tagIds`, `albumIds`, `originalPath`, `originalFileName` and
/// `description` are absent (their pickers belong to People / Tags / no screen
/// yet; see the spec's out-of-scope list).
struct SearchFilter: Equatable {
    /// 1…5, the server's scale since v3; `nil` = no rating constraint.
    var rating: Int?
    /// Detected-text criterion, projected onto `filter.ocr.matches` (the
    /// v3.2.0 replacement of the deprecated scalar `MetadataSearchDto.ocr`).
    var ocrText: String?
    var city: String?
    var state: String?
    var country: String?
    var make: String?
    var model: String?
    var lensModel: String?
    /// `AssetTypeEnum`'s two values — see `photoType` / `videoType`.
    var type: String?
    var isFavorite: Bool?
    var takenAfter: Date?
    var takenBefore: Date?

    /// The empty filter — what `clearFilters()` restores.
    static let none = SearchFilter()

    /// `AssetTypeEnum`'s values, as the published contract spells them.
    static let photoType = "IMAGE"
    static let videoType = "VIDEO"

    var isEmpty: Bool { constraints.isEmpty }
    var activeCount: Int { constraints.count }

    /// The DTO property a constraint writes. The chips bar builds its
    /// accessibility identifiers from the raw value
    /// (`searchFilterChip_<field>` / `searchFilterChipRemove_<field>`).
    enum Field: String, CaseIterable {
        case rating, ocr, city, state, country, make, model, lensModel
        case type, isFavorite, takenAfter, takenBefore
    }

    /// One active constraint, ready to display and to remove.
    struct Constraint: Identifiable, Equatable {
        let field: Field
        /// Complete localized sentence for the chip and its VoiceOver label —
        /// "Rating, 4 stars", "City, Lyon", "Taken after, 1 Jan 2024" — so the
        /// chip is one stop, never a title followed by a value.
        let label: String
        var id: String { field.rawValue }
    }

    /// Active constraints, in the order the sheet lists its sections.
    ///
    /// A field is listed only if `apply(to:)` would write it — the chips bar
    /// says what the request carries, no less and no more (a blank text field
    /// is not a constraint, and neither is a rating outside the server's scale).
    var constraints: [Constraint] {
        var result: [Constraint] = []
        if let rating, (1...5).contains(rating) {
            result.append(Constraint(field: .rating, label: String(localized: "Rating, \(rating) stars")))
        }
        if let ocrText, !ocrText.isEmpty {
            result.append(Constraint(field: .ocr, label: String(localized: "Detected text, \(ocrText)")))
        }
        if let city, !city.isEmpty {
            result.append(Constraint(field: .city, label: String(localized: "City, \(city)")))
        }
        if let state, !state.isEmpty {
            result.append(Constraint(field: .state, label: String(localized: "State, \(state)")))
        }
        if let country, !country.isEmpty {
            result.append(Constraint(field: .country, label: String(localized: "Country, \(country)")))
        }
        if let make, !make.isEmpty {
            result.append(Constraint(field: .make, label: String(localized: "Make, \(make)")))
        }
        if let model, !model.isEmpty {
            result.append(Constraint(field: .model, label: String(localized: "Model, \(model)")))
        }
        if let lensModel, !lensModel.isEmpty {
            result.append(Constraint(field: .lensModel, label: String(localized: "Lens, \(lensModel)")))
        }
        if let type, !type.isEmpty {
            let value = type == Self.photoType ? String(localized: "Photos") : String(localized: "Videos")
            result.append(Constraint(field: .type, label: String(localized: "Type, \(value)")))
        }
        if let isFavorite {
            result.append(Constraint(
                field: .isFavorite,
                label: isFavorite ? String(localized: "Favourites") : String(localized: "Not favourites")
            ))
        }
        if let takenAfter {
            result.append(Constraint(
                field: .takenAfter,
                label: String(localized: "Taken after, \(takenAfter.formatted(date: .abbreviated, time: .omitted))")
            ))
        }
        if let takenBefore {
            result.append(Constraint(
                field: .takenBefore,
                label: String(localized: "Taken before, \(takenBefore.formatted(date: .abbreviated, time: .omitted))")
            ))
        }
        return result
    }

    /// Drops exactly one constraint — what a chip's tap or cross does. The
    /// sheet's Done applies whatever is left; nothing else clears a field here.
    mutating func clear(_ field: Field) {
        switch field {
        case .rating: rating = nil
        case .ocr: ocrText = nil
        case .city: city = nil
        case .state: state = nil
        case .country: country = nil
        case .make: make = nil
        case .model: model = nil
        case .lensModel: lensModel = nil
        case .type: type = nil
        case .isFavorite: isFavorite = nil
        case .takenAfter: takenAfter = nil
        case .takenBefore: takenBefore = nil
        }
    }

    /// Writes every constraint that is set, and only those: the synthesized
    /// `Codable` omits an `Optional` that stays `nil` (`encodeIfPresent`), so an
    /// undone field leaves the request body instead of sending `null`.
    ///
    /// The six EXIF fields go through `ExploreField.apply(_:to:)`, the same
    /// writer the Explore drill-down uses — one place knows how `city` or
    /// `lensModel` reaches the DTO. The two dates are **not** written here: the
    /// DTO carries them as ISO-8601 strings and the formatting belongs to the
    /// ViewModel (one call site, one formatter).
    func apply(to dto: inout MetadataSearchDto) {
        // A rating outside the server's scale is ignored rather than sent as a
        // request the contract rejects (`min(1).max(5)`, `-1` removed in v3).
        if let rating, (1...5).contains(rating) { dto.rating = rating }

        let exifFields: [(SearchViewModel.ExploreField, String?)] = [
            (.city, city),
            (.state, state),
            (.country, country),
            (.make, make),
            (.model, model),
            (.lensModel, lensModel),
        ]
        for (field, value) in exifFields {
            guard let value, !value.isEmpty else { continue }
            field.apply(value, to: &dto)
        }

        if let type, !type.isEmpty { dto.type = type }
        if let isFavorite { dto.isFavorite = isFavorite }

        // Detected text: the similarity filter, never the deprecated scalar.
        if let ocrText, !ocrText.isEmpty {
            dto.filter = SearchFilterDto(ocr: StringSimilarityFilterDto(matches: ocrText))
        }
    }
}

/// The sheet's Sort picker — one case per `orderBy` the contract can express.
///
/// `orderBy` is a `SearchOrder` **object** (`field` × `direction`), added in
/// v3.2.0: the deprecated flat `order` only carries a direction and cannot name
/// a field, which is why the sort never writes it.
enum SearchSortOrder: String, CaseIterable, Identifiable {
    case newestTaken, oldestTaken, newestAdded, oldestAdded

    var id: String { rawValue }

    /// `SearchOrderField`. "Taken" is `fileCreatedAt` — the column the server
    /// itself filters `takenAfter`/`takenBefore` on.
    var field: String {
        switch self {
        case .newestTaken, .oldestTaken: "fileCreatedAt"
        case .newestAdded, .oldestAdded: "localDateTime"
        }
    }

    /// `AssetOrder`.
    var direction: String {
        switch self {
        case .newestTaken, .newestAdded: "desc"
        case .oldestTaken, .oldestAdded: "asc"
        }
    }

    /// The value of `MetadataSearchDto.orderBy`.
    var serverValue: SearchOrderDto { SearchOrderDto(field: field, direction: direction) }

    var label: String {
        switch self {
        case .newestTaken: String(localized: "Newest first")
        case .oldestTaken: String(localized: "Oldest first")
        case .newestAdded: String(localized: "Recently added")
        case .oldestAdded: String(localized: "Added long ago")
        }
    }
}

/// Result-grid density — a display option the server never sees. `compact`
/// stays at 5 columns (the floor where `AssetThumbnailCell` keeps a usable tap
/// target), `large` at 2; `comfortable` is the grid the tab shipped with.
enum SearchGridDensity: String, CaseIterable, Identifiable {
    case compact, comfortable, large

    var id: String { rawValue }

    var columnCount: Int {
        switch self {
        case .compact: 5
        case .comfortable: 3
        case .large: 2
        }
    }

    var label: String {
        switch self {
        case .compact: String(localized: "Compact")
        case .comfortable: String(localized: "Comfortable")
        case .large: String(localized: "Large")
        }
    }
}
