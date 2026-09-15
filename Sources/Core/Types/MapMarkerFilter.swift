import Foundation

/// Everything that narrows `GET /api/map/markers`, as one value.
///
/// The route accepts `isFavorite` / `isArchived` / `withPartners` plus a
/// `fileCreatedAfter` … `fileCreatedBefore` window, and `MapMarkerCache` keys
/// its disk file on the filter — so a single type produces both the request's
/// query items and the cache variant. Adding a parameter later can't update one
/// and forget the other, and `Equatable` is what lets `MapViewModel` tell
/// "the filter changed" from "same filter, nothing to reload".
///
/// The map route is the **only** place a time range can travel: the timeline's
/// `GET /api/timeline/buckets` takes no date parameter at all, and
/// `takenAfter`/`takenBefore` live on the metadata *search* route, which
/// returns assets rather than markers.
struct MapMarkerFilter: Equatable, Sendable, Codable {
    /// Favorites only (`isFavorite=true`).
    var onlyFavorites: Bool = false
    /// Archived assets included (`isArchived=true`).
    var includeArchived: Bool = false
    /// Markers of partners' assets included (`withPartners=true`).
    var withPartners: Bool = false

    /// Relative preset in days — upstream's time dropdown. `0` is "All": no
    /// lower bound at all, which is why `isEmpty` treats it as unconstrained.
    var relativeDays: Int = 0
    /// Custom range start, inclusive (local start of day).
    var from: Date? = nil
    /// Custom range end, inclusive (local end of day).
    var to: Date? = nil

    /// No constraint whatsoever — the cache may then keep using the legacy
    /// `markers.json` file name.
    static let all = MapMarkerFilter()

    var isEmpty: Bool {
        !onlyFavorites && !includeArchived && !withPartners
            && relativeDays <= 0 && from == nil && to == nil
    }

    /// False only for an inverted custom range (start after end). The settings
    /// sheet refuses such a filter instead of sending it: the server would
    /// answer with an empty set and `MapMarkerCache` would write that emptiness
    /// under a variant that looks legitimate.
    var isValid: Bool {
        guard let from, let to else { return true }
        return from <= to
    }

    /// Query items for `GET /api/map/markers`. `now` is injectable so the
    /// relative presets are testable without a clock.
    ///
    /// A custom range overrides the relative preset: the two are exclusive in
    /// the sheet, but a decoded filter could carry both, and "the bounds the
    /// user picked" is the more specific intent.
    func queryItems(now: Date = Date()) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        if onlyFavorites { items.append(URLQueryItem(name: "isFavorite", value: "true")) }
        if includeArchived { items.append(URLQueryItem(name: "isArchived", value: "true")) }
        if withPartners { items.append(URLQueryItem(name: "withPartners", value: "true")) }

        if from != nil || to != nil {
            if let from {
                items.append(URLQueryItem(
                    name: "fileCreatedAfter",
                    value: Self.stamp(Self.startOfDay(from))
                ))
            }
            if let to {
                items.append(URLQueryItem(
                    name: "fileCreatedBefore",
                    value: Self.stamp(Self.endOfDay(to))
                ))
            }
        } else if relativeDays > 0 {
            items.append(URLQueryItem(
                name: "fileCreatedAfter",
                value: Self.stamp(now.addingTimeInterval(-Double(relativeDays) * 86_400))
            ))
        }
        return items
    }

    /// File-name fragment identifying the disk cache of this filter, or `nil`
    /// for the unconstrained filter (which owns the legacy `markers.json`).
    ///
    /// Deliberately free of timestamps: a relative preset must keep hitting the
    /// same file for the whole `refreshTTL` window, otherwise every map open
    /// would cold-start on a filter that never changed. The custom range is
    /// expressed in day boundaries, so re-picking the same day reuses the file.
    var cacheVariant: String? {
        guard !isEmpty else { return nil }
        let toggles = "f\(onlyFavorites ? 1 : 0)-a\(includeArchived ? 1 : 0)-p\(withPartners ? 1 : 0)"

        if from != nil || to != nil {
            let start = from.map { String(Int(Self.startOfDay($0).timeIntervalSince1970)) } ?? ""
            let end = to.map { String(Int(Self.endOfDay($0).timeIntervalSince1970)) } ?? ""
            return "\(toggles)-c\(start)-\(end)"
        }
        return "\(toggles)-r\(relativeDays)"
    }

    /// `DatePicker(.date)` hands back midnight: sending that as the upper bound
    /// would exclude the whole end day (`fileCreatedBefore` is a date-time).
    /// The bound is therefore the last second of the day the user picked.
    private static func endOfDay(_ date: Date) -> Date {
        let start = startOfDay(date)
        return Calendar.current.date(byAdding: .day, value: 1, to: start)?
            .addingTimeInterval(-1) ?? start
    }

    private static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func stamp(_ date: Date) -> String {
        ISO8601.immichFormatter.string(from: date)
    }
}
