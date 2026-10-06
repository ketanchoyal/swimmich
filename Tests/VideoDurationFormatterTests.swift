import XCTest
@testable import ImmichSwiftUI

/// Table tests for `VideoDurationFormatter` — the single conversion point of the
/// video-duration fix (AC-1, AC-2).
final class VideoDurationFormatterTests: XCTestCase {

    /// AC-1: the report's video. Its wire duration is `7173` ms — a 7-second
    /// clip — and it must read "0:07", never the "119:33" the raw cell produced.
    func test_AC_1_reportedVideo_readsSevenSeconds() {
        XCTAssertEqual(VideoDurationFormatter.string(milliseconds: 7173), "0:07")
        // The player's own clock for the same media: 7.173 s.
        XCTAssertEqual(VideoDurationFormatter.string(seconds: 7.173), "0:07")
        // One rendering rule for both entries: a badge and a player can never
        // show two different durations for one video.
        XCTAssertEqual(
            VideoDurationFormatter.string(milliseconds: 7173),
            VideoDurationFormatter.string(seconds: 7.173)
        )
    }

    /// AC-2: millisecond table — nearest-second rounding, minutes unbounded,
    /// two-digit seconds (the grid badge convention, "V11").
    func test_AC_2_millisecondsTable() {
        let table: [(ms: Int, expected: String)] = [
            (-5000, "0:00"),            // negative guards to zero, never a crash
            (0, "0:00"),
            (999, "0:01"),              // sub-second rounds up to 1
            (1000, "0:01"),
            (7499, "0:07"),             // rounds down...
            (7500, "0:08"),             // ...and a half rounds away from zero
            (60_000, "1:00"),
            (300_000, "5:00"),          // a 5-minute clip, never "3000:00"
            (3_599_000, "59:59"),
            (3_600_000, "60:00"),       // minutes unbounded, no hour component
            (2_147_483_647, "35791:24") // int32 server bound: renders, no trap
        ]
        for row in table {
            XCTAssertEqual(
                VideoDurationFormatter.string(milliseconds: row.ms), row.expected,
                "\(row.ms) ms"
            )
        }
    }

    /// AC-2: seconds table for the player clock, plus the non-finite inputs an
    /// indefinite media hands over — `Int(NaN)` traps without the guard.
    func test_AC_2_secondsTable() {
        XCTAssertEqual(VideoDurationFormatter.string(seconds: 30.0), "0:30")
        XCTAssertEqual(VideoDurationFormatter.string(seconds: 0), "0:00")
        XCTAssertEqual(VideoDurationFormatter.string(seconds: -1), "0:00")
        XCTAssertEqual(VideoDurationFormatter.string(seconds: .nan), "0:00")
        XCTAssertEqual(VideoDurationFormatter.string(seconds: .infinity), "0:00")
        XCTAssertEqual(VideoDurationFormatter.string(seconds: -.infinity), "0:00")
        // A finite value past Int.max must render, not trap.
        XCTAssertEqual(
            VideoDurationFormatter.string(seconds: .greatestFiniteMagnitude),
            "76861433640456465:04"
        )
    }
}
