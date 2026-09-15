import XCTest
@testable import ImmichSwiftUI

/// The date-only wire format of a person's birthday (gap G15, AC-5150).
///
/// The failure this file guards against is a one-day drift: the repo's
/// timestamp formatters (`JSONCoding`, `LongDateFormatter`) parse ISO-8601
/// instants, and reusing one of them for a `format: date` value shifts the day
/// in every time zone whose offset is not zero. Nothing else in the feature can
/// be wrong in a way a hundred other tests would not catch.
final class PersonBirthdayTests: XCTestCase {

    func test_wireRoundTrip_isIdentity() throws {
        // `"2000-01-01"` is the trap: it is exactly midnight local, so a parser
        // that drops or adds a UTC offset lands on 1999-12-31.
        for wire in ["1990-05-12", "2000-01-01", "2024-12-31"] {
            let date = try XCTUnwrap(PersonBirthday.date(from: wire), "\(wire) did not parse")
            XCTAssertEqual(PersonBirthday.wire(from: date), wire)
        }
    }

    func test_parse_rejectsMalformed() {
        XCTAssertNil(PersonBirthday.date(from: nil))
        for wire in [
            "",
            "12/05/1990",
            "1990-13-01",
            "1990-02-30",
            "1990-5-12",
            "1990-05-12T00:00:00.000Z",
        ] {
            XCTAssertNil(PersonBirthday.date(from: wire), "\(wire) should not parse")
        }
    }

    func test_display_isNilForNilAndMalformed() {
        XCTAssertNil(PersonBirthday.display(nil))
        XCTAssertNil(PersonBirthday.display(""))
        XCTAssertNil(PersonBirthday.display("1990-02-30"))
    }

    func test_display_isNonEmptyForValidWire() {
        XCTAssertFalse(PersonBirthday.display("1990-05-12")?.isEmpty ?? true)
    }
}
