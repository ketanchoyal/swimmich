# PhotoVault Design System

Single source of truth for the visual language of the Immich SwiftUI app
(PhotoVault). Tokens live in `Sources/DesignSystem/Tokens/`; components in
`Sources/DesignSystem/Components/`; raw color values live as Asset Catalog
colorsets under `Resources/Assets.xcassets/`.

## §2 Color tokens

| Swift token              | Asset name        | Light hex | Dark hex |
|--------------------------|-------------------|-----------|----------|
| `Color.brandIndigo`      | BrandIndigo       | #4250AF   | #6B78D9  |
| `Color.brandIndigoMuted` | BrandIndigoMuted  | #6B78D9   | #8B96E8  |
| `Color.statusSuccess`    | LogoGreen         | #2E9C4B   | #4FCB6E  |
| `Color.statusPending`    | LogoYellow        | #F5A623   | #FFB84D  |
| `Color.statusError`      | LogoRedPink       | #E85D75   | #F47A8E  |
| `Color.accentInfo`       | LogoBlue          | #3DA9FC   | #5BC8FF  |
| `Color.bgPrimary`        | BgPrimary         | #FFFFFF   | #000000  |
| `Color.bgSecondary`      | BgSecondary       | #F2F2F7   | #1C1C1E  |
| `Color.bgTertiary`       | BgTertiary        | #E5E5EA   | #2C2C2E  |
| `Color.separatorPV`      | SeparatorColor    | #C6C6C8   | #38383A  |
| `Color.textPrimaryPV`    | TextPrimary       | #1D1D1F   | #F5F5F7  |
| `Color.textSecondaryPV`  | TextSecondary     | #6E6E73   | #AEAEB2  |
| `Color.textTertiaryPV`   | TextTertiary      | #A1A1A6   | #636366  |

Each colorset carries a light entry (no `appearances`) plus a dark entry
(`appearances: [{appearance:"luminosity", value:"dark"}]`). Components use the
sRGB components expressed as decimals in 0–1.

## §4 Font tokens

| Token         | Definition                                            |
|---------------|-------------------------------------------------------|
| `pvTitleXL`   | `.system(size: 34, weight: .bold, design: .rounded)`  |
| `pvTitle`     | `.system(size: 28, weight: .bold)`                    |
| `pvHeadline`  | `.system(size: 17, weight: .semibold)`                |
| `pvBody`      | `.system(size: 17, weight: .regular)`                 |
| `pvSubhead`   | `.system(size: 15, weight: .regular)`                 |
| `pvCaption`   | `.system(size: 13, weight: .regular)`                 |
| `pvNumeric`   | `.system(size: 17, weight: .semibold).monospacedDigit()` |

## §5 Spacing & Radius tokens

`PVSpacing` (4-pt grid): `s2, s4, s8, s12, s16, s24, s32` — all `CGFloat`.
`PVRadius`: `sm=8, md=14, lg=20, full=999` — all `CGFloat`.

## §6 Motion tokens

`PVMotion`:
- `standard` = `.spring(response: 0.35, dampingFraction: 0.86)`
- `snappy`   = `.spring(response: 0.25, dampingFraction: 0.75)`
- `gentle`   = `.easeInOut(duration: 0.5)`
- `adaptive(_ animation:reduceMotion:)` — when `reduceMotion == true`, returns
  `.linear(duration: 0.3)` (a non-spring fallback, honoring Reduce Motion).
  Otherwise returns the requested animation unchanged. Caller passes
  `@Environment(\.accessibilityReduceMotion)`.

## §7 Shadow modifier

`View.pvFloatingShadow()` → `shadow(color: .black.opacity(0.18), radius: 12,
x: 0, y: 4)`. Applied to cards/sheets that must lift off the background.

## §8 Components

### §8.1 PVPrimaryButtonStyle
`ButtonStyle`. Label `pvHeadline` white on `Color.brandIndigo`, full-width,
`minHeight: 50`, `Capsule()`. Press → `scaleEffect(0.97)` with `PVMotion.snappy`.

### §8.2 PVSubtleButtonStyle
`ButtonStyle`. Label `pvSubhead` in `textPrimaryPV` on `Color.bgTertiary`,
`minHeight: 44`, `Capsule()`, horizontal padding `PVSpacing.s16`. Same press
scale animation.

### §8.3 PVGridCell
`View`. Square (1:1) photo-grid cell, Photos.app abutting style — **no inter-cell
gap, `cornerRadius: 0`** so adjacent cells seam cleanly. Accepts an optional
`image: AnyView`. Empty placeholder shows `Image(systemName: "photo")` rendered
at **`.font(.system(size: 56))`** in `textTertiaryPV`. That 56pt size is a **hero
illustration, not a text glyph** — it is intentionally exempt from the font-token
rule (same exemption as §8.6). Placeholder icon is `accessibilityHidden(true)`.

### §8.4 PVAlbumCard
`View`. `VStack(alignment: .leading)` of square cover (clipped to
`PVRadius.lg`), title (`pvHeadline` / `textPrimaryPV`), count (`pvCaption` /
`textSecondaryPV`). Whole card gets `pvFloatingShadow()` and combined into one
accessibility element.

### §8.5 PVStatusBadge
`View(text: String, color: Color, symbol: String)`. `Label` (glyph + text) in
`pvCaption`, foreground `color`, background `color.opacity(0.15)`, `Capsule()`,
padding `s8`/`s4`. Children combined into one accessibility element.

### §8.6 PVEmptyState
`View(symbol: String, title: String, message: String)`. `VStack(spacing: s16)`:
hero SF Symbol at **`.font(.system(size: 48))`** in `textTertiaryPV` (hero
illustration — exempt from font-token rule), title `pvTitle` / `textPrimaryPV`,
message `pvBody` / `textTertiaryPV` centered. References `textTertiaryPV`
(AC-013).

## §10 Accessibility
- Decorative icons (purely visual, no information) → `.accessibilityHidden(true)`.
- Informative icons / cells → `.accessibilityLabel(...)` (or combined element).
- Reduce Motion honored via `PVMotion.adaptive(_:reduceMotion:)`.

## §11 Governance
Every color used inside `Sources/DesignSystem/` MUST originate from a token in
`Color+PhotoVault.swift`. Code review MUST reject any `Color(.systemBlue)`,
raw hex literal, or `Color(red:green:blue:)` inside the design-system module.
The only permitted font sizes outside `Font+PhotoVault.swift` are hero
**illustration** sizes (SF Symbols rendered as artwork, not text) — documented
inline where used.
