import XCTest
@testable import ImmichSwiftUI

/// The shared-link edit sheet round-trips a link's `expiresAt` through this
/// parser. Immich sends milliseconds (`"2024-07-29T14:30:00.000Z"`), which the
/// plain `ISO8601DateFormatter` REJECTS — a nil there is indistinguishable from
/// "never expires", so editing any other field of a link that had an expiry used
/// to clear it silently.
final class LongDateFormatterTests: XCTestCase {

    func test_parse_serverMillisecondTimestamp() throws {
        let date = try XCTUnwrap(
            LongDateFormatter.parse(isoTimestamp: "2024-07-29T14:30:00.000Z"),
            "the server's own timestamp shape must parse"
        )
        XCTAssertEqual(date.timeIntervalSince1970, 1722263400, accuracy: 1)
    }

    func test_parse_plainTimestampWithoutFraction() {
        // Not what Immich sends, but a hand-written DTO or an older server may.
        XCTAssertNotNil(LongDateFormatter.parse(isoTimestamp: "2024-07-29T14:30:00Z"))
    }

    func test_parse_malformedIsNil() {
        XCTAssertNil(LongDateFormatter.parse(isoTimestamp: ""))
        XCTAssertNil(LongDateFormatter.parse(isoTimestamp: "not-a-date"))
    }

    func test_format_prefixFallsBackToTheRawPrefix() {
        // `format` is date-only and forgiving; it must never lose the prefix.
        XCTAssertEqual(LongDateFormatter.format(isoPrefix: "nope"), "nope")
        // Locale-independent: the simulator renders this in French, so pinning an
        // English string here would only test the device's language setting.
        let formatted = LongDateFormatter.format(isoPrefix: "2024-07-29T14:30:00.000Z")
        XCTAssertNotEqual(formatted, "2024-07-29T14:30:00.000Z", "a valid prefix must be formatted, not echoed")
        XCTAssertTrue(formatted.contains("2024"), "the year must survive localization: \(formatted)")
    }
}
