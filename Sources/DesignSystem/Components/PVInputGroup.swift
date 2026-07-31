import SwiftUI

// MARK: - PVInputGroup
//
// Grouped-card surface for form inputs (Apple grouped-form look). Mirrors the
// `ServerURLScreen` info-card treatment (`bgSecondary` + `PVRadius.lg`) so
// every auth surface reads as one family. Drop input rows (decorated with
// `.pvFieldSurface(focused:)`) inside; separate multiple rows with `Divider()`.

/// Card-styled container that visually groups one or more input rows.
struct PVInputGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: PVSpacing.s0) {
            content
        }
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PVRadius.lg, style: .continuous))
    }
}
