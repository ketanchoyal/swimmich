import Foundation

/// Builds an interleaved array of month-header + day-group sections from the
/// view model's `groupedByDay` output.
///
/// Extracted as a pure function so it can be unit-tested independently of
/// SwiftUI (no `View` dependency). The timeline grid renders month banners
/// only when the month changes between consecutive day groups — never two
/// banners in a row, never an orphan for the first group.
///
/// Input contract: `groupedByDay` is already sorted day-descending with
/// intra-day items time-descending (as produced by
/// `TimelineViewModel.groupedByDay`).
enum TimelineSectionBuilder {

    // MARK: Cached formatters (hoisted from build() — audit P2)

    /// Stateless UTC parser for the `"YYYY-MM-DD"` → UTC-noon parse step.
    /// Reused across every `build` call (was per-call).
    private static let utcParser: ISO8601DateFormatter = {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        parser.timeZone = TimeZone(identifier: "UTC")
        return parser
    }()

    /// Localized `"MMMM yyyy"` formatter (e.g. "July 2024"). Pinned to
    /// `.current`: every production call site passes the default calendar, and
    /// `TimelineSectionBuilderTests` asserts structure/year, not locale-specific
    /// month names. (Was allocated per `build` call.)
    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Calendar.current.locale
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    /// One renderable section in the timeline vertical stack.
    enum Section: Identifiable, Equatable {
        /// Full-width month-year banner (e.g. "July 2024").
        /// - `month`: ISO year-month key `"YYYY-MM"` used for identity/dedup.
        /// - `display`: localized display string (e.g. "July 2024").
        case monthHeader(month: String, display: String)
        /// A day's worth of assets, grouped under a day header.
        case dayGroup(day: String, items: [AssetReactItem])

        var id: String {
            switch self {
            case .monthHeader(let month, _): return "month-\(month)"
            case .dayGroup(let day, _):       return "day-\(day)"
            }
        }
    }

    /// Interleaves `.monthHeader` cases between `.dayGroup` cases whenever the
    /// ISO year-month prefix (`"YYYY-MM"`) changes.
    ///
    /// - Parameter groupedByDay: day-descending groups (from
    ///   `TimelineViewModel.groupedByDay`).
    /// - Returns: Ordered sections ready for `ForEach` in the timeline
    ///   `LazyVStack`. Empty input → empty output.
    static func build(
        from groupedByDay: [(day: String, items: [AssetReactItem])]
    ) -> [Section] {
        guard !groupedByDay.isEmpty else { return [] }

        var result: [Section] = []
        result.reserveCapacity(groupedByDay.count + 4) // rough: +1 banner per month

        var lastMonth: String?

        for group in groupedByDay {
            // Defensive: a day prefix shorter than 7 chars can't yield "YYYY-MM".
            // Skip the banner but still emit the day group so the grid stays usable.
            let monthKey: String
            if group.day.count >= 7 {
                monthKey = String(group.day.prefix(7))
            } else {
                monthKey = group.day
            }

            if monthKey != lastMonth {
                let display = Self.displayString(forMonthKey: monthKey)
                result.append(.monthHeader(month: monthKey, display: display))
                lastMonth = monthKey
            }
            result.append(.dayGroup(day: group.day, items: group.items))
        }
        return result
    }

    /// Formats an ISO `"YYYY-MM"` key as a localized `"MMMM yyyy"` display
    /// string. Falls back to the raw key if parsing fails — never crashes the
    /// grid over malformed input.
    private static func displayString(forMonthKey monthKey: String) -> String {
        // Parse as UTC noon (mid-month would also work; noon avoids DST edges).
        guard let date = utcParser.date(from: "\(monthKey)-15T12:00:00Z") else {
            return monthKey
        }
        return monthYearFormatter.string(from: date)
    }
}
