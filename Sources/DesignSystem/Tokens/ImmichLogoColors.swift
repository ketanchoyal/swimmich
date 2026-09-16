import SwiftUI

// MARK: - Immich logo palette
//
// The five fills of the immich brand, taken verbatim from the official export
// (`immich-logo.svg`: #FA2921, #ED79B5, #FFB400, #1E83F7, #18C249). The names
// below are the flower's own seatings, because that is where the values come
// from — the mark this app draws is the system bird, not the flower, so treat
// the seating as provenance, not as geometry.
//
// These are not theme colours. The mark does not change between light and dark
// appearance — upstream only ever shipped a light/dark *wordmark* — so each one
// is a single, appearance-invariant value rather than an asset-catalog colourset
// with a `luminosity: dark` twin. That also keeps `ImmichMark` drawable in
// targets and harnesses that carry no asset catalog (the share extension, unit
// tests, previews).

extension Color {

    /// Immich red, the flower's top petal — #FA2921.
    static let immichLogoRed = Color(red: 250 / 255, green: 41 / 255, blue: 33 / 255)

    /// Immich pink, the flower's upper-left petal — #ED79B5.
    static let immichLogoPink = Color(red: 237 / 255, green: 121 / 255, blue: 181 / 255)

    /// Immich amber, the flower's upper-right petal — #FFB400.
    static let immichLogoAmber = Color(red: 1, green: 180 / 255, blue: 0)

    /// Immich blue, the flower's lower-left petal — #1E83F7.
    static let immichLogoBlue = Color(red: 30 / 255, green: 131 / 255, blue: 247 / 255)

    /// Immich green, the flower's lower-right petal — #18C249.
    static let immichLogoGreen = Color(red: 24 / 255, green: 194 / 255, blue: 73 / 255)
}

// MARK: - The mark's gradient
//
// The same five, swept across the mark's span instead of seated around a centre:
// the left side leaves in the blue, the right side arrives in the red. Spanwise
// because the mark's thick part is its middle, where a vertical sweep would bury
// its own stops. One definition, so the app bar, the badge and the icon can
// never drift apart.

extension LinearGradient {

    /// The immich five, edge to edge.
    static let immichLogo = LinearGradient(
        colors: [
            .immichLogoBlue,
            .immichLogoGreen,
            .immichLogoPink,
            .immichLogoAmber,
            .immichLogoRed,
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}
