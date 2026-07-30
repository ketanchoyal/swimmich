import SwiftUI

/// Thumbnail image cell for the timeline grid — Apple-Photos-grade.
///
/// Premium visual layers:
/// - **Uniform 1:1 square cells** (no ragged grid). Image fills + clips.
/// - **Uniform material-pill badges**: favorite (heart), video (play + mm:ss),
///   360° (equirectangular projection) — all share one capsule treatment.
/// - **Pro selection**: cell scales to 0.96, blue-tint overlay on selected,
///   near-imperceptible 0.08 dim on unselected, checkmark morphs via
///   `.contentTransition(.symbolEffect(.replace))` + `.symbolEffect(.bounce)`.
/// - `scrollTransition` parallax on cell CONTENT only (FM-3 mitigation).
/// - Context menu (Favorite toggle / Delete).
struct AssetThumbnailCell: View {
    let asset: AssetReactItem
    let baseURL: URL
    let token: String?

    var selectionMode: Bool = false
    var isSelected: Bool = false
    var onTap: () -> Void = {}
    var onToggleFavorite: () -> Void = {}
    var onDelete: () -> Void = {}
    /// Trash-only callbacks. When `onRestore` is set, the context menu switches
    /// to Restore + Delete Permanently (AC-301 / AC-303). Callers that leave
    /// these `nil` keep the existing Favorite + Delete menu (TimelineView).
    var onRestore: (() -> Void)? = nil
    var onDeletePermanent: (() -> Void)? = nil

    var body: some View {
        let url = asset.thumbnailURL(base: baseURL)

        // Square frame: Color.clear w/ aspectRatio(1,.fit) becomes a perfect
        // square sized to the column width. Image overlays fill + clip.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AuthenticatedAsyncImage(url: url, token: token)
                    .scrollTransition { content, phase in
                        // Parallax: scale + fade slightly as the cell exits viewport.
                        // Applied to image CONTENT only (FM-3), never the Section.
                        content
                            .scaleEffect(phase.isIdentity ? 1.0 : 0.94)
                            .opacity(phase.isIdentity ? 1.0 : 0.9)
                    }
            }
            .overlay { selectionTint }
            .overlay { favoriteBadge }
            .overlay(alignment: .topLeading) { projectionBadge }
            .overlay(alignment: .bottomTrailing) { videoBadge }
            .overlay(alignment: .topTrailing) { checkmark }
            .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
            // Pro selection: selected cells recede slightly (scale 0.96) w/ spring.
            .scaleEffect(selectionMode && isSelected ? 0.96 : 1.0)
            .animation(.spring(duration: 0.32, bounce: 0.2), value: isSelected)
            .animation(.spring(duration: 0.32, bounce: 0.2), value: selectionMode)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .contextMenu {
                if let onRestore {
                    // Trash tab menu (AC-301 / AC-303).
                    Button {
                        onRestore()
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    Button(role: .destructive) {
                        onDeletePermanent?()
                    } label: {
                        Label("Delete Permanently", systemImage: "trash")
                    }
                } else {
                    // Timeline menu (existing behaviour, AC-202 / AC-203).
                    Button {
                        onToggleFavorite()
                    } label: {
                        Label(
                            asset.isFavorite ? "Unfavorite" : "Favorite",
                            systemImage: asset.isFavorite ? "heart.slash" : "heart"
                        )
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
    }

    // MARK: - Badges (uniform material-pill treatment, V4)

    /// Favorite heart — small material pill, top-trailing.
    /// Hidden in selection mode to avoid colliding w/ the checkmark (D1).
    @ViewBuilder
    private var favoriteBadge: some View {
        if asset.isFavorite && !selectionMode {
            badge {
                Image(systemName: "heart.fill")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(4)
        }
    }

    /// 360° pill for equirectangular projections — top-leading.
    @ViewBuilder
    private var projectionBadge: some View {
        if asset.projectionType == "equirectangular" {
            badge {
                Text("360°")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(4)
        }
    }

    /// Video play + duration — bottom-trailing.
    @ViewBuilder
    private var videoBadge: some View {
        if asset.isVideo {
            badge {
                HStack(spacing: 3) {
                    Image(systemName: "play.fill").font(.system(size: 8))
                    if let d = asset.duration, d > 0 {
                        Text(Self.formattedDuration(d)).monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(4)
        }
    }

    /// Shared capsule treatment — `.ultraThinMaterial` + thin border.
    /// All badges share this for visual consistency (V4 uniformity).
    @ViewBuilder
    private func badge<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
    }

    // MARK: - Selection (V5)

    /// Blue tint on selected, near-imperceptible dim on unselected (not the
    /// old 0.35 black crush).
    @ViewBuilder
    private var selectionTint: some View {
        if selectionMode {
            if isSelected {
                Color.blue.opacity(0.15)
            } else {
                Color.black.opacity(0.06)
            }
        }
    }

    /// Checkmark morphs circle → checkmark.circle.fill via symbol replace.
    /// The bare `"circle"` SF Symbol is already a clean outline ring — no
    /// custom stroke overlay (avoids the double-circle defect D2).
    @ViewBuilder
    private var checkmark: some View {
        if selectionMode {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .symbolEffect(.bounce, value: isSelected)
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(isSelected ? .blue : .white)
                .shadow(color: .black.opacity(0.25), radius: 1.5)
                .padding(8)
                .accessibilityLabel(isSelected ? "Selected" : "Not selected")
        }
    }

    /// mm:ss if ≥60s, else 0:ss (V11).
    static func formattedDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
