import SwiftUI

// MARK: - ImmichAppBar
//
// Immich-flavored app bar identity, placed in `ToolbarItem(placement: .principal)`.
// Renders the immich logo glyph + "Immich" wordmark inline — the recognizable
// immich top-of-screen identity (the upstream Flutter `ImmichSliverAppBar`
// ships `immich-logo-inline-light.svg` / `-dark.svg`). The repo does not
// currently bundle those SVGs, so we approximate with a tinted SF Symbol
// (`camera.aperture`) + wordmark text. When the official SVGs land in
// `Resources/Assets.xcassets/`, swap the body of `ImmichLogo` without
// touching call sites.
//
// Native compromise: SwiftUI toolbar background, scrolling behaviour, and
// safe-area insets remain iOS-native (no Material elevation), per the
// "Immich-flavored native SwiftUI" approach.

/// Immich top app bar identity: logo glyph + wordmark.
/// Drop into `ToolbarItem(placement: .principal)` on top-level screens.
struct ImmichAppBar: View {
    let title: String

    init(title: String = "Immich") {
        self.title = title
    }

    var body: some View {
        ImmichLogo(title: title)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
    }
}

/// Standalone immich logo + wordmark — also reusable outside toolbars
/// (auth screens, launch, empty-state headers).
struct ImmichLogo: View {
    let title: String

    var body: some View {
        HStack(spacing: PVSpacing.s4) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 22, weight: .semibold)) // DS-exempt: brand glyph §8.6
                .foregroundStyle(Color.brandIndigo)
            Text(title)
                .font(.pvH6)
                .foregroundStyle(Color.textPrimaryPV)
        }
    }
}

// MARK: - Immich gray bottom-bar styling
//
// Immich keeps the bottom app bar a constant flat gray (separate from content).
// Applied on the root TabView.

private struct ImmichBottomBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(Color.brandIndigo)
            .toolbarBackground(Color.bgSecondary, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
}

extension View {
    /// Styles a `TabView` to look like the immich flat-gray bottom app bar
    /// (opaque `bgSecondary`, indigo active tint).
    func immichBottomBar() -> some View {
        modifier(ImmichBottomBarModifier())
    }
}
