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
///
/// Every rendered label goes through `AppDateFormat`, so the formatters are
/// cached per locale — the app's current language is read at render time, not
/// frozen when this enum is first used.
enum DateHeaderFormatter {

    // MARK: Cached parser

    /// Stateless UTC parser for the `"YYYY-MM-DD"` → UTC-noon parse step.
    /// Allocated once, reused across every call (was per-call — audit P2).
    private static let utcParser: ISO8601DateFormatter = {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        parser.timeZone = TimeZone(identifier: "UTC")
        return parser
    }()

    /// The locale every label is spoken in. `Calendar` carries an optional
    /// locale (tests inject `en_US`/`fr_FR`); when it has none we use the
    /// autoupdating current locale, so an in-app language change reaches the
    /// next render instead of being frozen at first use. `AppDateFormat` owns
    /// the `DateFormatter`s themselves, cached per locale + calendar.
    private static func locale(for calendar: Calendar) -> Locale {
        calendar.locale ?? .autoupdatingCurrent
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
        return AppDateFormat.string(
            from: date,
            style: .year,
            locale: locale(for: calendar),
            calendar: calendar
        )
    }

    /// Returns a localized `"EEEE d MMMM"` weekday + day + month label for an
    /// ISO date prefix (e.g. `"2026-07-29"` → `"Wednesday 29 July"`). No
    /// relative "Today"/"Yesterday" — always the literal weekday, day number,
    /// and month. `AppDateFormat` capitalizes the weekday and month (some
    /// locales emit lowercase names) and owns the cached formatters.
    static func dayMonthString(
        for isoPrefix: String,
        calendar: Calendar = .current
    ) -> String {
        guard let date = parseUTCPrefix(isoPrefix) else {
            return isoPrefix
        }
        return AppDateFormat.string(
            from: date,
            style: .dayMonth,
            locale: locale(for: calendar),
            calendar: calendar
        )
    }

    /// Formats `date` as `"EEEE, MMMM d"` or `"EEEE, MMMM d, yyyy"`, honoring
    /// the injected calendar's locale and timezone.
    private static func format(
        date: Date, calendar: Calendar, includeYear: Bool
    ) -> String {
        AppDateFormat.string(
            from: date,
            style: .dayHeader(includeYear: includeYear),
            locale: locale(for: calendar),
            calendar: calendar
        )
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
