import XCTest
@testable import ImmichSwiftUI

final class TimelineGridZoomTests: XCTestCase {

    // MARK: - effectiveScale

    func test_effectiveScale_identityAtMagnificationOne() {
        XCTAssertEqual(
            TimelineGridZoom.effectiveScale(base: 1, magnification: 1, defaultColumns: 3, minColumns: 2, maxColumns: 7),
            1.0
        )
    }

    func test_effectiveScale_zoomsInBeyondMaxScaleClampsToMaxColumns() {
        // 3/2 = max zoom (2 cols). Pinching in hard must clamp, not exceed.
        XCTAssertEqual(
            TimelineGridZoom.effectiveScale(base: 1, magnification: 3, defaultColumns: 3, minColumns: 2, maxColumns: 7),
            3.0 / 2.0
        )
    }

    func test_effectiveScale_zoomsOutBeyondMinScaleClampsToMinColumns() {
        // 3/7 = min zoom (7 cols). Pinching out hard must clamp.
        XCTAssertEqual(
            TimelineGridZoom.effectiveScale(base: 1, magnification: 0.1, defaultColumns: 3, minColumns: 2, maxColumns: 7),
            3.0 / 7.0
        )
    }

    func test_effectiveScale_compoundsWithCommittedBase() {
        // Second gesture starts from the committed base, not 1.
        XCTAssertEqual(
            TimelineGridZoom.effectiveScale(base: 3.0 / 2.0, magnification: 1.0, defaultColumns: 3, minColumns: 2, maxColumns: 7),
            3.0 / 2.0
        )
    }

    // MARK: - columns

    func test_columns_defaultZoomIsThreeColumns() {
        XCTAssertEqual(
            TimelineGridZoom.columns(forEffectiveScale: 1.0, defaultColumns: 3, minColumns: 2, maxColumns: 7),
            3
        )
    }

    func test_columns_maxZoomIsTwoColumns() {
        XCTAssertEqual(
            TimelineGridZoom.columns(forEffectiveScale: 3.0 / 2.0, defaultColumns: 3, minColumns: 2, maxColumns: 7),
            2
        )
    }

    func test_columns_minZoomIsSevenColumns() {
        XCTAssertEqual(
            TimelineGridZoom.columns(forEffectiveScale: 3.0 / 7.0, defaultColumns: 3, minColumns: 2, maxColumns: 7),
            7
        )
    }

    func test_columns_roundsToNearestThreshold() {
        XCTAssertEqual(
            TimelineGridZoom.columns(forEffectiveScale: 1.1, defaultColumns: 3, minColumns: 2, maxColumns: 7),
            3 // 3/1.1 = 2.73 → 3
        )
        XCTAssertEqual(
            TimelineGridZoom.columns(forEffectiveScale: 1.3, defaultColumns: 3, minColumns: 2, maxColumns: 7),
            2 // 3/1.3 = 2.31 → 2
        )
    }

    func test_columns_scaleEdgeOutsideRangeClampsToBounds() {
        XCTAssertEqual(
            TimelineGridZoom.columns(forEffectiveScale: 10, defaultColumns: 3, minColumns: 2, maxColumns: 7),
            2
        )
        XCTAssertEqual(
            TimelineGridZoom.columns(forEffectiveScale: 0.01, defaultColumns: 3, minColumns: 2, maxColumns: 7),
            7
        )
    }

    func test_columns_nonPositiveScaleFallsBackToDefault() {
        XCTAssertEqual(
            TimelineGridZoom.columns(forEffectiveScale: 0, defaultColumns: 3, minColumns: 2, maxColumns: 7),
            3
        )
    }

    // MARK: - scale(forColumnCount:)

    func test_scale_forColumnCountInverts() {
        XCTAssertEqual(TimelineGridZoom.scale(forColumnCount: 6, defaultColumns: 3), 0.5)
        XCTAssertEqual(TimelineGridZoom.scale(forColumnCount: 2, defaultColumns: 3), 1.5)
        XCTAssertEqual(TimelineGridZoom.scale(forColumnCount: 0, defaultColumns: 3), 1)
    }
}
