import SwiftUI

// MARK: - PVGridCell
//
// Square photo-grid cell (Photos.app abutting style, spec §8.6 / M-7).
// Cells are laid edge-to-edge with NO inter-cell gap, so cornerRadius is 0 —
// a non-zero radius would produce overlapping rounded corners at the seams.
// Empty/placeholder state shows a hero SF Symbol illustration at
// `.font(.system(size: 56))`; this is a hero illustration, NOT a text glyph,
// so it is intentionally exempt from the font-token rule (spec §8.6).

struct PVGridCell: View {
    /// Optional image content. When nil the cell shows its empty placeholder.
    var image: AnyView?

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 0))
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            image
        } else {
            // Decorative placeholder; the grid conveys info via surrounding
            // context, so the icon itself is hidden from VoiceOver (spec §10).
            Image(systemName: "photo")
                .font(.system(size: 56))
                .foregroundStyle(Color.textTertiaryPV)
                .accessibilityHidden(true)
        }
    }
}
