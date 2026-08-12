import SwiftUI

// MARK: - PhotoVault Color Tokens
//
// Two layers coexist for PRD Phase 0 alignment (§5.2):
//
// 1. Canonical Immich brand tokens (`Color.immich*`) — defined in
//    `ImmichColors.swift`, dynamic light/dark via UIColor(dynamicProvider:),
//    the single source of truth for the Immich visual identity.
//
// 2. Asset Catalog colorsets (`Resources/Assets.xcassets/*.colorset`) — carry
//    structural surface colors (bg / text / separator) whose values were retuned
//    to PRD §5.2 (BgSecondary, TextPrimary) or left native (BgPrimary, BgTertiary,
//    separators, secondary/tertiary text).
//
// The legacy brand/status token names below (brandIndigo, statusSuccess, …) are
// soft-deprecated aliases that now resolve to the canonical `immich*` tokens.
// New code MUST use `Color.immich*` directly. Governance (spec §11): any color
// inside Sources/DesignSystem/ MUST come from a token.

extension Color {
    /// Deprecated: use `Color.immichPrimary`.
    static let brandIndigo      = Color.immichPrimary
    /// Deprecated: use `Color.immichPrimary`. (PRD defines no muted brand variant;
    /// the legacy BrandIndigoMuted colorset is collapsed into the primary token.)
    static let brandIndigoMuted = Color.immichPrimary
    /// Deprecated: use `Color.immichSuccess`.
    static let statusSuccess    = Color.immichSuccess
    /// Deprecated: use `Color.immichWarning`.
    static let statusPending    = Color.immichWarning
    /// Deprecated: use `Color.immichError`.
    static let statusError      = Color.immichError
    /// Deprecated: use `Color.immichPrimary`.
    static let accentInfo       = Color.immichPrimary

    // Structural surface colors — backed by Asset Catalog colorsets.
    static let bgPrimary        = Color("BgPrimary")
    static let bgSecondary      = Color("BgSecondary")
    static let bgTertiary       = Color("BgTertiary")
    static let separatorPV      = Color("SeparatorColor")
    static let textPrimaryPV    = Color("TextPrimary")
    static let textSecondaryPV  = Color("TextSecondary")
    static let textTertiaryPV   = Color("TextTertiary")

    /// Parses "#RRGGBB" (or "#RGB") hex strings used by Immich `avatarColor`.
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&int) else { return nil }
        let r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}
