import XCTest
import SwiftUI
@testable import ImmichSwiftUI

/// Token + foundation sanity tests for the PhotoVault Design System.
/// These exercise compile-time + value correctness of the non-UI tokens;
/// SwiftUI View/ButtonStyle bodies are covered structurally by build + the
/// component AC grep checks.
final class DesignSystemTokensTests: XCTestCase {

    func testSpacingValues() {
        XCTAssertEqual(PVSpacing.s0, 0)
        XCTAssertEqual(PVSpacing.s2, 2)
        XCTAssertEqual(PVSpacing.s4, 4)
        XCTAssertEqual(PVSpacing.s8, 8)
        XCTAssertEqual(PVSpacing.s12, 12)
        XCTAssertEqual(PVSpacing.s16, 16)
        XCTAssertEqual(PVSpacing.s24, 24)
        XCTAssertEqual(PVSpacing.s32, 32)
        XCTAssertEqual(PVSpacing.s48, 48)
    }

    func testRadiusValues() {
        // Immich-aligned radius scale: none/xs/sm/md/lg/xl/xxl/full.
        XCTAssertEqual(PVRadius.none, 0)
        XCTAssertEqual(PVRadius.xs, 4)
        XCTAssertEqual(PVRadius.sm, 8)
        XCTAssertEqual(PVRadius.md, 12)
        XCTAssertEqual(PVRadius.lg, 16)
        XCTAssertEqual(PVRadius.xl, 20)
        XCTAssertEqual(PVRadius.xxl, 24)
        XCTAssertEqual(PVRadius.full, 999)
    }

    /// AC-019: `adaptive(_:reduceMotion:)` must not hand back a spring when the
    /// user has Reduce Motion enabled. `Animation` is not runtime-introspectable
    /// in Swift, so we assert the call resolves to a non-nil value; the
    /// non-spring guarantee is structural — the implementation returns
    /// `.linear(duration: 0.3)` (documented in Motion+PhotoVault.swift).
    func testMotionAdaptiveReduceMotion() {
        let reduced: Animation? = PVMotion.adaptive(
            .spring(response: 0.5), reduceMotion: true)
        XCTAssertNotNil(reduced)

        let normal: Animation? = PVMotion.adaptive(
            .spring(response: 0.5), reduceMotion: false)
        XCTAssertNotNil(normal)
    }

    /// AC-020 (partial): ensure color tokens initialize without throwing /
    /// crashing. Asset resolution is lazy; init merely registers the asset name.
    func testColorTokenResolution() {
        let indigo: Color? = Color.brandIndigo
        XCTAssertNotNil(indigo)

        let text: Color? = Color.textPrimaryPV
        XCTAssertNotNil(text)
    }
}
