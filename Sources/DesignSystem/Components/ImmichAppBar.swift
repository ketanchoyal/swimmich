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
    /// A key, not a `String`: a literal passed to a `String` property is never
    /// extracted by the compiler and never translated (it rendered verbatim).
    let title: LocalizedStringKey

    init(title: LocalizedStringKey = "Immich") {
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
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: PVSpacing.s4) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 22, weight: .semibold)) // DS-exempt: brand glyph §8.6
                .foregroundStyle(Color.immichPrimary)
            Text(title)
                .font(.pvH6)
                .foregroundStyle(Color.textPrimaryPV)
        }
    }
}

// MARK: - Immich bottom-bar styling
//
// Native iOS 26 Liquid Glass floating tab bar (adaptive to content), with the
// Immich indigo active-tab tint. Applied on the root TabView.

private struct ImmichBottomBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(Color.immichPrimary)
    }
}

extension View {
    /// Styles the root `TabView` with the native floating Liquid Glass tab bar
    /// (adaptive) and the Immich indigo active-tab tint.
    func immichBottomBar() -> some View {
        modifier(ImmichBottomBarModifier())
    }
}
