import XCTest
@testable import ImmichSwiftUI

/// Thresholds shared by the viewer's swipe-down dismiss and the info panel's
/// swipe-up reveal / swipe-down close.
final class PhotoViewerSwipeDecisionTests: XCTestCase {

    // MARK: - shouldClose (downward)

    func testCloseBelowThresholdStaysOpen() {
        XCTAssertFalse(PhotoViewerSwipeDecision.shouldClose(progress: 0.24, velocity: 0))
    }

    func testCloseAtProgressThresholdStaysOpen() {
        XCTAssertFalse(PhotoViewerSwipeDecision.shouldClose(progress: 0.25, velocity: 0))
    }

    func testCloseJustAboveProgressThresholdCloses() {
        XCTAssertTrue(PhotoViewerSwipeDecision.shouldClose(progress: 0.26, velocity: 0))
    }

    func testCloseAtVelocityThresholdStaysOpen() {
        XCTAssertFalse(PhotoViewerSwipeDecision.shouldClose(progress: 0, velocity: 900))
    }

    func testCloseJustAboveVelocityThresholdCloses() {
        XCTAssertTrue(PhotoViewerSwipeDecision.shouldClose(progress: 0, velocity: 901))
    }

    func testCloseSlowShortDragStaysOpen() {
        XCTAssertFalse(PhotoViewerSwipeDecision.shouldClose(progress: 0.10, velocity: 100))
    }

    func testCloseZeroDoesNothing() {
        XCTAssertFalse(PhotoViewerSwipeDecision.shouldClose(progress: 0, velocity: 0))
    }

    // MARK: - shouldOpen (upward)

    func testOpenBelowThresholdStaysClosed() {
        XCTAssertFalse(PhotoViewerSwipeDecision.shouldOpen(progress: -0.24, velocity: 0))
    }

    func testOpenAtProgressThresholdStaysClosed() {
        XCTAssertFalse(PhotoViewerSwipeDecision.shouldOpen(progress: -0.25, velocity: 0))
    }

    func testOpenJustAboveProgressThresholdOpens() {
        XCTAssertTrue(PhotoViewerSwipeDecision.shouldOpen(progress: -0.26, velocity: 0))
    }

    func testOpenAtVelocityThresholdStaysClosed() {
        XCTAssertFalse(PhotoViewerSwipeDecision.shouldOpen(progress: 0, velocity: -900))
    }

    func testOpenJustAboveVelocityThresholdOpens() {
        XCTAssertTrue(PhotoViewerSwipeDecision.shouldOpen(progress: 0, velocity: -901))
    }

    func testOpenFastShortFlickOpens() {
        XCTAssertTrue(PhotoViewerSwipeDecision.shouldOpen(progress: -0.05, velocity: -1200))
    }

    func testOpenZeroDoesNothing() {
        XCTAssertFalse(PhotoViewerSwipeDecision.shouldOpen(progress: 0, velocity: 0))
    }

    // MARK: - Directional exclusivity

    func testDownwardProgressNeverOpens() {
        XCTAssertFalse(PhotoViewerSwipeDecision.shouldOpen(progress: 0.5, velocity: 500))
    }

    func testUpwardProgressNeverCloses() {
        XCTAssertFalse(PhotoViewerSwipeDecision.shouldClose(progress: -0.5, velocity: -500))
    }
}
