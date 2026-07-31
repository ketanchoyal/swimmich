import XCTest
@testable import ImmichSwiftUI

/// PinnedHeaderResolver picks the day the sticky month/day header must show.
final class PinnedHeaderResolverTests: XCTestCase {

    func test_emptyFrames_returnsNil() {
        XCTAssertNil(PinnedHeaderResolver.currentDay(from: [:]))
    }

    func test_nothingScrolled_topmostVisibleWins() {
        // All groups below the viewport top (positive minY) → smallest minY.
        let frames: [String: CGFloat] = ["2024-07-29": 300, "2024-07-28": 900, "2024-07-27": 1500]
        XCTAssertEqual(PinnedHeaderResolver.currentDay(from: frames), "2024-07-29")
    }

    func test_mixed_mostRecentScrolledWins() {
        // Two groups past the top (<= 0); the later one (larger minY) wins.
        let frames: [String: CGFloat] = ["2024-07-29": -1200, "2024-07-28": -400, "2024-07-27": 600]
        XCTAssertEqual(PinnedHeaderResolver.currentDay(from: frames), "2024-07-28")
    }

    func test_exactlyAtTop_wins() {
        // minY == 0 counts as scrolled past; it's the most recent crossing.
        let frames: [String: CGFloat] = ["2024-07-29": 0, "2024-07-28": 800]
        XCTAssertEqual(PinnedHeaderResolver.currentDay(from: frames), "2024-07-29")
    }

    func test_singleFrame_alwaysSelected() {
        XCTAssertEqual(PinnedHeaderResolver.currentDay(from: ["2024-07-29": CGFloat(-50)]), "2024-07-29")
        XCTAssertEqual(PinnedHeaderResolver.currentDay(from: ["2024-07-29": CGFloat(250)]), "2024-07-29")
    }

    func test_tie_equalMinY_anyScrolledDay() {
        // Equal minY — selection is order-dependent; assert one of the two
        // scrolled days wins rather than pinning a specific key.
        let frames: [String: CGFloat] = ["2024-07-29": -100, "2024-07-28": -100]
        let result = PinnedHeaderResolver.currentDay(from: frames)
        XCTAssertTrue(result == "2024-07-29" || result == "2024-07-28")
    }
}
