import XCTest
@testable import ImmichSwiftUI

/// AC-V01 — DateHeaderFormatter produces human-readable relative day labels.
///
/// Forces `TimeZone(identifier: "Pacific/Honolulu")` (GMT-10) via the injected
/// `calendar:` parameter to prove timezone determinism (FM-2): the formatter
/// must parse the ISO prefix as UTC noon and compare via the supplied calendar,
/// not naively against `Calendar.current`.
final class DateHeaderFormatterTests: XCTestCase {

    /// Honolulu calendar (GMT-10). Used for every case so the suite is
    /// deterministic regardless of the simulator's local timezone.
    private var honoluluCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Pacific/Honolulu")!
        cal.locale = Locale(identifier: "en_US")
        return cal
    }

    // MARK: - Same day

    func test_AC_V01_today() {
        // ISO prefix 2024-07-29, reference 2024-07-29 12:00 Honolulu → "Today".
        let ref = makeReference(year: 2024, month: 7, day: 29, hour: 12, minute: 0)
        let result = DateHeaderFormatter.displayString(
            for: "2024-07-29",
            relativeTo: ref,
            calendar: honoluluCalendar
        )
        XCTAssertEqual(result, "Today")
    }

    // MARK: - Previous day

    func test_AC_V01_yesterday() {
        let ref = makeReference(year: 2024, month: 7, day: 29, hour: 12, minute: 0)
        let result = DateHeaderFormatter.displayString(
            for: "2024-07-28",
            relativeTo: ref,
            calendar: honoluluCalendar
        )
        XCTAssertEqual(result, "Yesterday")
    }

    // MARK: - Within 7 days → weekday + month/day

    func test_AC_V01_withinSevenDays() {
        let ref = makeReference(year: 2024, month: 7, day: 29, hour: 12, minute: 0)
        // 2024-07-27 is 2 days before → "Saturday, July 27".
        let result = DateHeaderFormatter.displayString(
            for: "2024-07-27",
            relativeTo: ref,
            calendar: honoluluCalendar
        )
        XCTAssertEqual(result, "Saturday, July 27")
    }

    // MARK: - Older than 7 days → full date with year

    func test_AC_V01_eightDaysAgo_fullDate() {
        let ref = makeReference(year: 2024, month: 7, day: 29, hour: 12, minute: 0)
        // 2024-07-20 is 9 days before → "Saturday, July 20, 2024".
        let result = DateHeaderFormatter.displayString(
            for: "2024-07-20",
            relativeTo: ref,
            calendar: honoluluCalendar
        )
        XCTAssertEqual(result, "Saturday, July 20, 2024")
    }

    func test_AC_V01_differentYear_fullDate() {
        let ref = makeReference(year: 2024, month: 7, day: 29, hour: 12, minute: 0)
        let result = DateHeaderFormatter.displayString(
            for: "2023-12-25",
            relativeTo: ref,
            calendar: honoluluCalendar
        )
        XCTAssertEqual(result, "Monday, December 25, 2023")
    }

    // MARK: - FM-2 timezone edge: Honolulu near-midnight

    func test_AC_V01_honoluluMidnightEdge() {
        // Reference is 2024-07-29 23:30 Honolulu (late evening, still "today").
        // ISO prefix "2024-07-29" parses to UTC noon = 2024-07-29 02:00 Honolulu,
        // which is the same calendar day → MUST return "Today", not "Tomorrow".
        let ref = makeReference(year: 2024, month: 7, day: 29, hour: 23, minute: 30)
        let result = DateHeaderFormatter.displayString(
            for: "2024-07-29",
            relativeTo: ref,
            calendar: honoluluCalendar
        )
        XCTAssertEqual(result, "Today")
    }

    // MARK: - Defensive fallback

    func test_AC_V01_malformedPrefixReturnsRaw() {
        let result = DateHeaderFormatter.displayString(for: "not-a-date")
        // Falls back to the raw string rather than crashing.
        XCTAssertEqual(result, "not-a-date")
    }

    // MARK: - Helpers

    /// Builds a `Date` in the Honolulu calendar from the supplied components.
    private func makeReference(
        year: Int, month: Int, day: Int, hour: Int, minute: Int
    ) -> Date {
        var cal = honoluluCalendar
        cal.timeZone = TimeZone(identifier: "Pacific/Honolulu")!
        let comps = DateComponents(
            timeZone: TimeZone(identifier: "Pacific/Honolulu"),
            year: year, month: month, day: day, hour: hour, minute: minute
        )
        return cal.date(from: comps)!
    }
}
