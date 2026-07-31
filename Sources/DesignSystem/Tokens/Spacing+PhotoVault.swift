import CoreGraphics

// MARK: - PhotoVault Spacing & Radius Tokens
//
// Spacing scale aligned to the Immich design system (4-pt grid):
//   none=0, xs=4, sm=8, md=12, lg=16, xl=24, xxl=32, xxxl=48.
// PVSpacing keeps the legacy `sN` aliases that already map 1:1 to Immich steps;
// `s0` and `s48` were added to cover Immich `none` and `xxxl`.
//
// Radius scale aligned to Immich:
//   none=0, xs=4, sm=8, md=12 (default), lg=16, xl=20, xxl=24, full=∞.

enum PVSpacing {
    static let s0: CGFloat = 0
    static let s2: CGFloat = 2
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let s48: CGFloat = 48
}

enum PVRadius {
    static let none: CGFloat = 0
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let control: CGFloat = 10
    static let full: CGFloat = 999
}
