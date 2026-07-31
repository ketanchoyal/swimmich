import SwiftUI

// MARK: - PVFieldSurface
//
// Input row surface for custom input fields: comfortable row padding so rows
// inside a `PVInputGroup` card read as inset grouped cells. No focus treatment —
// the cursor and keyboard are the only focus cues, per native iOS.

extension View {
    /// Applies the input-field surface: comfortable row padding.
    func pvFieldSurface() -> some View {
        modifier(PVFieldSurface())
    }
}

private struct PVFieldSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PVSpacing.s16)
    }
}
