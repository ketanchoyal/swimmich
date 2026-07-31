import SwiftUI

// MARK: - PVStatusBadge
//
// Pill-shaped status indicator. The colored glyph + label share one tint,
// backed by a 15%-opacity wash of the same color.

struct PVStatusBadge: View {
    let text: String
    let color: Color
    let symbol: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.pvCaption)
        .foregroundStyle(color)
        .padding(.horizontal, PVSpacing.s8)
        .padding(.vertical, PVSpacing.s4)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}
