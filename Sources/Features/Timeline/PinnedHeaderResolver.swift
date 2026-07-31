import Foundation

/// Picks the "current" day group for the sticky month/day header.
///
/// The timeline grid reports each day's `LazyVGrid` top edge (`minY` in the
/// scroll coordinate space) through a preference. Scrolling pushes earlier
/// groups above the viewport top (`minY <= 0`); the header must reflect the
/// most recent group that has crossed it — the one with the **largest** `minY`
/// among those already scrolled past. Before anything has crossed (top of the
/// timeline), the topmost visible group (smallest `minY`) wins.
///
/// Extracted as a pure function so the selection logic is unit-testable
/// without SwiftUI.
enum PinnedHeaderResolver {

    /// Returns the day key to display, given each visible day group's frame.
    ///
    /// - Parameter frames: `[dayKey: topEdgeMinY]` from visible grids only
    ///   (LazyVStack lazily measures just the on-screen groups).
    /// - Returns: The day to pin, or `nil` when no group is measurable.
    static func currentDay(from frames: [String: CGFloat]) -> String? {
        guard !frames.isEmpty else { return nil }

        // Most recent group scrolled past the top (largest minY <= 0).
        if let scrolled = frames
            .filter({ $0.value <= 0 })
            .max(by: { $0.value < $1.value }) {
            return scrolled.key
        }

        // Nothing crossed yet — topmost visible group (smallest minY).
        return frames.min(by: { $0.value < $1.value })?.key
    }
}
