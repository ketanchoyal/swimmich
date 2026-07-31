import CoreGraphics

/// Pure zoom→column mapping for the Photos-style pinch-to-zoom timeline grid.
///
/// Model: thumbnail size is inversely proportional to column count, so a
/// pinch-in (magnification > 1) shows fewer, larger thumbnails and a pinch-out
/// shows more, smaller ones. `effectiveScale` clamps the live gesture scale
/// into the range implied by `minColumns`/`maxColumns`; `columns(for:)` snaps
/// it to the nearest integer column count. Extracted for testability (same
/// pattern as `TimelineSectionBuilder`).
enum TimelineGridZoom {

    /// Scale implied by the requested column count (`defaultColumns / count`).
    static func scale(forColumnCount count: Int, defaultColumns: Int) -> CGFloat {
        guard count > 0 else { return 1 }
        return CGFloat(defaultColumns) / CGFloat(count)
    }

    /// Clamps a live gesture scale into `[scale(for: maxColumns), scale(for: minColumns)]`.
    static func effectiveScale(
        base: CGFloat,
        magnification: CGFloat,
        defaultColumns: Int,
        minColumns: Int,
        maxColumns: Int
    ) -> CGFloat {
        let raw = base * magnification
        let minScale = scale(forColumnCount: maxColumns, defaultColumns: defaultColumns)
        let maxScale = scale(forColumnCount: minColumns, defaultColumns: defaultColumns)
        return min(max(raw, minScale), maxScale)
    }

    /// Snaps an effective scale to the nearest column count, clamped to bounds.
    static func columns(
        forEffectiveScale scale: CGFloat,
        defaultColumns: Int,
        minColumns: Int,
        maxColumns: Int
    ) -> Int {
        guard scale > 0 else { return defaultColumns }
        let raw = Int((CGFloat(defaultColumns) / scale).rounded())
        return min(max(raw, minColumns), maxColumns)
    }
}
