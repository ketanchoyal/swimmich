import Foundation

/// Long-form localized date rendering for a single photo's `fileCreatedAt`
/// (e.g. `"July 29, 2024"`).
///
/// Shared by `PhotoInfoPanel.dateLabel` and `PhotoViewer.headerDate(for:)`,
/// which were byte-for-byte identical before this helper existed (audit P2).
/// Formatters are hoisted to `static let` so we allocate once, not per render.
enum LongDateFormatter {

    /// Stateless UTC parser for the `"YYYY-MM-DD"` → UTC-noon parse step.
    private static let utcParser: ISO8601DateFormatter = {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        parser.timeZone = TimeZone(identifier: "UTC")
        return parser
    }()

    /// `.long` date style (e.g. "July 29, 2024"), no time, current locale.
    private static let longFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    /// Formats an ISO-8601 `"YYYY-MM-DD..."` prefix as a long localized date.
    /// Falls back to the 10-char prefix if parsing fails — never crashes the
    /// view over malformed input.
    static func format(isoPrefix: String) -> String {
        let prefix = String(isoPrefix.prefix(10))
        guard let date = utcParser.date(from: "\(prefix)T12:00:00Z") else {
            return prefix
        }
        return longFormatter.string(from: date)
    }

    /// Parses a full ISO timestamp (`"2024-07-29T14:30:00.000Z"`) to a Date;
    /// nil when malformed. Needed for relative-time rendering (activity feed).
    static func parse(isoTimestamp: String) -> Date? {
        ISO8601DateFormatter().date(from: isoTimestamp)
    }
}
