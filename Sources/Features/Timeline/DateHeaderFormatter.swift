import Foundation

/// Human-readable relative day labels for timeline section headers.
///
/// Parses an ISO date prefix (`"2024-07-29"`, as produced by
/// `TimelineViewModel.groupedByDay`) as a **UTC noon** instant so the day
/// boundary is stable across timezones, then renders a relative label:
///
/// - Same day (per the supplied calendar) → `"Today"`
/// - Previous day                         → `"Yesterday"`
/// - Within the last 7 days               → `"Saturday, July 27"` (weekday + month/day)
/// - Older                                → `"Saturday, July 27, 2024"` (full date)
///
/// `calendar` is injectable so callers (and tests) can force a `TimeZone`
/// (e.g. `Pacific/Honolulu`) — the relative comparison and the formatted
/// output both honor it. Default is `Calendar.current`, matching device locale.
enum DateHeaderFormatter {

    // MARK: Cached formatters

    /// Stateless UTC parser for the `"YYYY-MM-DD"` → UTC-noon parse step.
    /// Allocated once, reused across every call (was per-call — audit P2).
    private static let utcParser: ISO8601DateFormatter = {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        parser.timeZone = TimeZone(identifier: "UTC")
        return parser
    }()

    /// `DateFormatter` is expensive to allocate and depends on the injected
    /// `calendar` (calendar + timeZone + locale — tests force `Pacific/Honolulu`
    /// and `fr_FR`). Cache one `DateFormatter` per distinct calendar signature
    /// + date format so we allocate at most a handful instead of one per call
    /// (was up to 4 per call — audit P2). Main-thread-only call sites, but the
    /// lock keeps it safe if that ever changes.
    private static let formatterCacheLock = NSLock()
    private static var formatterCache: [FormatterKey: DateFormatter] = [:]

    private struct FormatterKey: Hashable {
        let calendarIdentifier: String
        let timeZoneIdentifier: String
        let localeIdentifier: String
        let dateFormat: String
    }

    /// Returns a cached `DateFormatter` configured for `calendar` + `dateFormat`,
    /// creating one on first use for that signature.
    private static func formatter(calendar: Calendar, dateFormat: String) -> DateFormatter {
        let key = FormatterKey(
            calendarIdentifier: "\(calendar.identifier)",
            timeZoneIdentifier: calendar.timeZone.identifier,
            localeIdentifier: calendar.locale?.identifier ?? "",
            dateFormat: dateFormat
        )
        formatterCacheLock.lock()
        defer { formatterCacheLock.unlock() }
        if let cached = formatterCache[key] { return cached }
        let df = DateFormatter()
        df.calendar = calendar
        df.locale = calendar.locale
        df.dateFormat = dateFormat
        formatterCache[key] = df
        return df
    }

    /// Returns a human-readable label for `isoPrefix` relative to `reference`.
    ///
    /// - Parameters:
    ///   - isoPrefix: ISO-8601 date prefix `"YYYY-MM-DD"`. Falls back to the
    ///     raw string if parsing fails (defensive — never crashes the view).
    ///   - reference: The "now" to compare against. Defaults to `Date()`.
    ///   - calendar: Calendar (with `timeZone`) used for both the relative
    ///     comparison and the display formatting. Defaults to `.current`.
    /// - Returns: `"Today"`, `"Yesterday"`, `"EEEE, MMMM d"` (≤7 days),
    ///   or `"EEEE, MMMM d, yyyy"` (older).
    static func displayString(
        for isoPrefix: String,
        relativeTo reference: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let date = parseUTCPrefix(isoPrefix) else {
            return isoPrefix
        }

        // Day difference relative to `reference` (NOT to Date()) — `reference`
        // is injectable so tests can pin a fixed "now". Calendar.startOfDay
        // honors `calendar.timeZone`, so the comparison is timezone-correct.
        let dayDiff = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: reference)
        ).day ?? Int.max

        switch dayDiff {
        case 0:
            return "Today"
        case 1:
            return "Yesterday"
        case 2...7:
            return format(date: date, calendar: calendar, includeYear: false)
        default:
            // Negative (future date) or > 7 days → full date w/ year.
            return format(date: date, calendar: calendar, includeYear: true)
        }
    }

    /// Returns a localized `"yyyy"` year label for an ISO date prefix
    /// (e.g. `"2024-07-29"` → `"2024"`).
    static func yearString(
        for isoPrefix: String,
        calendar: Calendar = .current
    ) -> String {
        guard let date = parseUTCPrefix(isoPrefix) else {
            return isoPrefix
        }
        let df = Self.formatter(calendar: calendar, dateFormat: "yyyy")
        return df.string(from: date)
    }

    /// Returns a localized `"EEEE d MMMM"` weekday + day + month label for an
    /// ISO date prefix (e.g. `"2026-07-29"` → `"Wednesday 29 July"`). No
    /// relative "Today"/"Yesterday" — always the literal weekday, day number,
    /// and month. Leading weekday's first letter is capitalized (some locales
    /// emit lowercase weekday/month names).
    static func dayMonthString(
        for isoPrefix: String,
        calendar: Calendar = .current
    ) -> String {
        guard let date = parseUTCPrefix(isoPrefix) else {
            return isoPrefix
        }
        let weekdayFormatter = Self.formatter(calendar: calendar, dateFormat: "EEEE")
        let dayFormatter = Self.formatter(calendar: calendar, dateFormat: "d")
        let monthFormatter = Self.formatter(calendar: calendar, dateFormat: "MMMM")

        let weekday = Self.capitalized(weekdayFormatter.string(from: date))
        let month = Self.capitalized(monthFormatter.string(from: date))
        return "\(weekday) \(dayFormatter.string(from: date)) \(month)"
    }

    /// Formats `date` as `"EEEE, MMMM d"` or `"EEEE, MMMM d, yyyy"`, honoring
    /// the injected calendar's locale and timezone.
    private static func format(
        date: Date, calendar: Calendar, includeYear: Bool
    ) -> String {
        let df = Self.formatter(
            calendar: calendar,
            dateFormat: includeYear ? "EEEE, MMMM d, yyyy" : "EEEE, MMMM d"
        )
        return df.string(from: date)
    }

    /// Capitalizes the first letter only (month is the leading token in the
    /// labels that use this; the rest stays untouched).
    private static func capitalized(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }

    /// Parses `"YYYY-MM-DD"` as a UTC-noon `Date`.
    /// UTC noon is chosen so a single instant maps to the same calendar day
    /// in virtually every populated timezone (UTC-12..UTC+14), eliminating
    /// midnight edge cases where a photo taken "today" would display as
    /// "tomorrow" or vice-versa.
    private static func parseUTCPrefix(_ isoPrefix: String) -> Date? {
        let iso = "\(isoPrefix)T12:00:00Z"
        return utcParser.date(from: iso)
    }
}
