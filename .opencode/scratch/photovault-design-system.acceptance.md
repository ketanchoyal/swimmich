# PhotoVault Design System — Acceptance Contract

Status: shipped — Sources/DesignSystem/ (tokens, modifiers, components) + matching Asset Catalog colorsets present; zero edits to Sources/Features/ (regression guard AC-022).

Source spec: `PhotoVault-DesignSystem.md`.

Legend: `type` = `new` (feature added) | `regression` (must stay green).

---

## AC-001 [new] — 13 colorsets exist, AccentColor intact
**Assert:** all 13 named colorsets present under `Resources/Assets.xcassets/`,
`AccentColor.colorset` + `AppIcon.appiconset` + `Contents.json` unchanged.
**Check:**
```bash
for n in BrandIndigo BrandIndigoMuted LogoGreen LogoYellow LogoRedPink LogoBlue \
         BgPrimary BgSecondary BgTertiary SeparatorColor TextPrimary \
         TextSecondary TextTertiary; do
  test -d "Resources/Assets.xcassets/$n.colorset" || echo "MISSING $n"
done
test -d Resources/Assets.xcassets/AccentColor.colorset && echo "AccentColor OK"
```

## AC-002 [new] — each Contents.json valid + has dark luminosity entry
**Assert:** every `Contents.json` parses as JSON and has >=1 entry whose
`appearances` array contains `{appearance:luminosity, value:dark}`.
**Check:**
```bash
for f in Resources/Assets.xcassets/*.colorset/Contents.json; do
  python3 -m json.tool "$f" >/dev/null || echo "BAD JSON $f"
  jq -e '.colors[] | select(.appearances[0].appearance=="luminosity" and .appearances[0].value=="dark")' "$f" >/dev/null \
    || echo "NO DARK $f"
done
```

## AC-003 [new] — Color tokens map to exact asset names
**Assert:** `Color+PhotoVault.swift` declares 13 `static let` referencing the
exact case-sensitive colorset names.
**Check:**
```bash
test -f Sources/DesignSystem/Tokens/Color+PhotoVault.swift
grep -c 'static let' Sources/DesignSystem/Tokens/Color+PhotoVault.swift   # == 13
grep -q 'Color("BrandIndigo")'   Sources/DesignSystem/Tokens/Color+PhotoVault.swift
grep -q 'Color("TextTertiary")'  Sources/DesignSystem/Tokens/Color+PhotoVault.swift
```

## AC-004 [new] — Font tokens incl. monospacedDigit + rounded
**Assert:** 7 font tokens; `pvNumeric` uses `.monospacedDigit()`; `pvTitleXL`
uses `.rounded` design.
**Check:**
```bash
test -f Sources/DesignSystem/Tokens/Font+PhotoVault.swift
grep -c 'static let' Sources/DesignSystem/Tokens/Font+PhotoVault.swift    # == 7
grep -q 'monospacedDigit()' Sources/DesignSystem/Tokens/Font+PhotoVault.swift
grep -q 'design: .rounded'  Sources/DesignSystem/Tokens/Font+PhotoVault.swift
```

## AC-005 [new] — Spacing + Radius tokens
**Assert:** `PVSpacing` (7) + `PVRadius` (4) as `CGFloat`.
**Check:**
```bash
test -f Sources/DesignSystem/Tokens/Spacing+PhotoVault.swift
grep -q 'enum PVSpacing' Sources/DesignSystem/Tokens/Spacing+PhotoVault.swift
grep -q 'enum PVRadius'  Sources/DesignSystem/Tokens/Spacing+PhotoVault.swift
grep -q 'CGFloat'        Sources/DesignSystem/Tokens/Spacing+PhotoVault.swift
```

## AC-006 [new] — Motion tokens + adaptive
**Assert:** `PVMotion.standard/snappy/gentle` + `adaptive(_:reduceMotion:)`
with exact spring params (0.35/0.86, 0.25/0.75).
**Check:**
```bash
test -f Sources/DesignSystem/Tokens/Motion+PhotoVault.swift
grep -q 'response: 0.35, dampingFraction: 0.86' Sources/DesignSystem/Tokens/Motion+PhotoVault.swift
grep -q 'response: 0.25, dampingFraction: 0.75' Sources/DesignSystem/Tokens/Motion+PhotoVault.swift
grep -q 'func adaptive' Sources/DesignSystem/Tokens/Motion+PhotoVault.swift
```

## AC-007 [new] — Floating shadow modifier
**Assert:** `pvFloatingShadow()` with `black.opacity(0.18)`, radius 12, y 4.
**Check:**
```bash
test -f Sources/DesignSystem/Tokens/View+Shadow.swift
grep -q 'black.opacity(0.18)' Sources/DesignSystem/Tokens/View+Shadow.swift
grep -q 'radius: 12'          Sources/DesignSystem/Tokens/View+Shadow.swift
grep -q 'y: 4'                Sources/DesignSystem/Tokens/View+Shadow.swift
```

## AC-008 [new] — PVPrimaryButtonStyle
**Assert:** `PVPrimaryButtonStyle: ButtonStyle`, brandIndigo bg, Capsule,
scaleEffect on press, minHeight 50.
**Check:**
```bash
grep -q 'struct PVPrimaryButtonStyle: ButtonStyle' Sources/DesignSystem/Components/PVButtonStyle.swift
grep -q 'Color.brandIndigo' Sources/DesignSystem/Components/PVButtonStyle.swift
grep -q 'minHeight: 50'     Sources/DesignSystem/Components/PVButtonStyle.swift
```

## AC-009 [new] — PVSubtleButtonStyle
**Assert:** `PVSubtleButtonStyle: ButtonStyle`, bgTertiary bg, Capsule.
**Check:**
```bash
grep -q 'struct PVSubtleButtonStyle: ButtonStyle' Sources/DesignSystem/Components/PVButtonStyle.swift
grep -q 'Color.bgTertiary' Sources/DesignSystem/Components/PVButtonStyle.swift
```

## AC-010 [new] — PVGridCell
**Assert:** `struct PVGridCell: View` with a body.
**Check:**
```bash
test -f Sources/DesignSystem/Components/PVGridCell.swift
grep -q 'struct PVGridCell: View' Sources/DesignSystem/Components/PVGridCell.swift
grep -q 'var body: some View'    Sources/DesignSystem/Components/PVGridCell.swift
```

## AC-011 [new] — PVAlbumCard
**Assert:** `struct PVAlbumCard: View`.
**Check:**
```bash
test -f Sources/DesignSystem/Components/PVAlbumCard.swift
grep -q 'struct PVAlbumCard: View' Sources/DesignSystem/Components/PVAlbumCard.swift
```

## AC-012 [new] — PVStatusBadge
**Assert:** `struct PVStatusBadge: View` with `(text:color:symbol:)`, Label +
pvCaption + Capsule.
**Check:**
```bash
grep -q 'struct PVStatusBadge: View' Sources/DesignSystem/Components/PVStatusBadge.swift
grep -q 'let text: String'   Sources/DesignSystem/Components/PVStatusBadge.swift
grep -q 'let color: Color'   Sources/DesignSystem/Components/PVStatusBadge.swift
grep -q 'let symbol: String' Sources/DesignSystem/Components/PVStatusBadge.swift
grep -q '.font(.pvCaption)'  Sources/DesignSystem/Components/PVStatusBadge.swift
grep -q 'Capsule()'          Sources/DesignSystem/Components/PVStatusBadge.swift
```

## AC-013 [new] — PVEmptyState references textTertiaryPV
**Assert:** `struct PVEmptyState: View` referencing `Color.textTertiaryPV`.
**Check:**
```bash
grep -q 'struct PVEmptyState: View' Sources/DesignSystem/Components/PVEmptyState.swift
grep -q 'textTertiaryPV'            Sources/DesignSystem/Components/PVEmptyState.swift
```

## AC-014 [new] — xcodegen regenerates cleanly
**Assert:** `xcodegen --spec project.yml` exits 0, no error.
**Check:**
```bash
/opt/homebrew/bin/xcodegen --spec project.yml; echo "xcodegen exit $?"
```

## AC-015 [new] — app builds
**Assert:** `xcodebuild build` exit 0.
**Check:**
```bash
xcodebuild build -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  | tail -5; echo "build pipe ${PIPESTATUS[0]}"
```

## AC-016 [new] — testSpacingValues passes
## AC-017 [new] — testRadiusValues passes
## AC-019 [new] — testMotionAdaptiveReduceMotion passes
## AC-020 [new] — testColorTokenResolution passes
**Check (each):**
```bash
xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:ImmichSwiftUITests/DesignSystemTokensTests/<METHOD>
```

## AC-018 [new] — pvNumeric declares monospacedDigit (structural)
**Assert:** `pvNumeric` token chain includes `.monospacedDigit()`.
**Check:**
```bash
grep -q 'pvNumeric.*monospacedDigit' Sources/DesignSystem/Tokens/Font+PhotoVault.swift
```

## AC-020 [new] — BrandIndigo light = #4250AF (decimal ±0.001)
**Assert:** `BrandIndigo.colorset/Contents.json` light entry red≈0.2588,
green≈0.3137, blue≈0.6863.
**Check:**
```bash
jq '.colors[0].color.components' Resources/Assets.xcassets/BrandIndigo.colorset/Contents.json
```

## AC-021 [regression] — pre-existing test suite stays green
**Assert:** the 16 pre-existing XCTest classes/files all pass unchanged.
**Check:**
```bash
xcodebuild test ... ; echo "exit $?"
```

## AC-022 [regression] — Sources/Features untouched
**Assert:** no file under `Sources/Features/` modified.
**Check:**
```bash
test -z "$(git diff --name-only HEAD -- Sources/Features/)" && echo "Features clean"
```
