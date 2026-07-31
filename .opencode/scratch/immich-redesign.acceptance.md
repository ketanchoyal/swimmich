# Task: immich-redesign

## Plan
**Objectif:** Redesign all 12+ screens of PhotoVault to match ORIGINAL immich design system, keeping SwiftUI native components + iOS HIG + MVVM intact.

**Hypothèses (vérifiées par lecture directe du code, m0014-m0027):**
- BrandIndigo = #4250AF CONFIRMED dans `Resources/Assets.xcassets/BrandIndigo.colorset/Contents.json:8-10` (r=0.2588≈66/255, g=0.3137≈80/255, b=0.6863≈175/255). Dark variant #6B78D9 (l.25-27). → no asset change.
- Token governance (no raw Color/hex outside DesignSystem) enforced; AssetThumbnailCell.swift:124,143,145,148,161,176,177 has documented `// DS-exempt:` exceptions — preserved.
- Logo SVGs NOT in repo (`glob Resources/**/*.svg` vide) → use SF Symbol `camera.aperture` + "Immich" wordmark in `ImmichAppBar`.
- All feature screens already use only PV tokens (verified Spacing+PhotoVault.swift values + grep on Sources/Features/).
- 145 tests green; `Tests/DesignSystemTokensTests.swift:9` class `DesignSystemTokensTests`, asserts PVSpacing (l.11-19) + PVRadius (l.21-26) concrete values → must update alongside token change. Test target = `ImmichSwiftUITests` (project.yml:50).
- RootView.swift:30 uses `TabView` w/ 5 tabs (Timeline/Albums/Search/Trash/Backup). No `.tint()` applied currently.
- Grep `placement: \.principal` in Sources/ → 0 occurrence (pre-state AC-008 correct).
- Status colors already exist as tokens: `statusSuccess`(LogoGreen), `statusError`(LogoRedPink), `accentInfo`(LogoBlue) at `Color+PhotoVault.swift:14-17`. Keep as-is — values may differ slightly from immich #1984E9/#10C14F/#FA2921 but close enough; out of scope to retune.

**Décisions design importantes (changent vs draft initial):**
- **pvBody STAYS at 17pt** (iOS HIG body). iOS users expect 17; immich body=14 too small for native iOS. New `pvBodyLarge`=16 semibold + pvH1..pvH6 added for immich heading scale. Use pvSubhead(15)/pvCaption(13) where immich uses body=14.
- **PVRadius fully realigned**: sm=8 (unchanged), md=14→12, lg=20→16 (affects PVAlbumCard cover radius — minor visual change), ADD none=0/xs=4/xl=20/xxl=24. Full immich scale.
- **PVSpacing**: ADD s0=0 + s48=48. Existing s2/s4/s8/s12/s16/s24/s32 unchanged (already match immich).
- **Large-title removal**: screens adopting ImmichAppBar drop `.navigationTitle(.large)` — flag as breaking-change in implementation.

**Étapes:**
1. Realign `PVSpacing`/`PVRadius`/`PVFont` to immich values + add missing sizes (s48, s0, radius none/xs/lg/xl/xxl, fonts pvBodyLarge/pvH1..pvH6). Update `DesignSystemTokensTests` accordingly.
2. Update `Motion+PhotoVault.swift` with immich duration scale (extraFast/fast/normal/moderate/slow/extraSlow).
3. Add immich status colors (info/success/error) to Asset Catalog + `Color+PhotoVault.swift` (info=#1984E9, success=#10C14D, error=#FA2921).
4. Create `ImmichAppBar` component (logo + wordmark) used as `.principal` toolbar item on top-level screens.
5. Apply `.tint(Color.brandIndigo)` on RootView TabView; style TabView with gray opaque background (immich bottom app bar look).
6. Replace large-title Apple-Photos headers with immich app-bar look on Timeline/Albums/Search/Trash/Backup.
7. Sweep all 12+ feature views for raw values (cornerRadius literals, font sizes) → migrate to tokens.
8. xcodegen regenerate (keep bundle id + dev team in project.yml first), build for iPhone 17 Sim, run tests.

## Acceptance Contract

### Approches candidates
- **A — ImmichTokenMirror**: new enums ImmichSpacing/Radius/etc mirroring upstream. Duplication, 40-60 site changes.
- **B — PV tokens realigned on Immich values + new immich chrome components**: single source of truth, auto-redesigns all screens via token mutation. RECOMMENDED.
- **C — New chrome components only, tokens frozen**: cosmetic only, would not look immich (spacing/radius/typo stay Apple-Photos).

### Approche retenue + rationale
**B** — Single source of truth preserved, governance rule stays intact, all 12+ screens auto-redesign via token mutation, existing DS tests update trivially, new chrome components (ImmichAppBar) layered on top.

### Critères

### AC-001 [regression]
Assertion: Le projet compile pour iPhone 17 Simulator sans erreur.
Check post-impl: `xcodebuild build -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -c "BUILD SUCCEEDED"` → `1`
Pre-state attendu: assertion satisfaite.
Post-state attendu: assertion satisfaite.

### AC-002 [regression]
Assertion: Les 145+ tests unitaires existants passent tous — aucun test de logique métier cassé par le redesign.
Check post-impl: `xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -c "TEST SUCCEEDED"` → `1`
Pre-state attendu: assertion satisfaite.
Post-state attendu: assertion satisfaite. Count total ≥ 145 (DesignSystemTokensTests updated, not removed).

### AC-003 [regression]
Assertion: Aucune vue feature (hors DesignSystem) n'utilise de couleur raw, hex literal, ou constructeur `Color(red:green:blue:)` non tokenisé.
Check post-impl: `rg 'Color\(red:|Color\(white:|Color\(hex:|Color\(uiColor:|Color\(\.system' Sources/Features/ -l` → sortie vide. Exceptions documentées `// DS-exempt` dans `AssetThumbnailCell.swift` restent autorisées.
Pre-state attendu: assertion satisfaite.
Post-state attendu: assertion satisfaite.

### AC-004 [regression]
Assertion: Zéro nouvelle dépendance lourde (MaterialComponents, Firebase, packages externes de design).
Check post-impl: `rg -c 'import MaterialComponents|import Firebase|import FirebaseAuth' Sources/` → chaque ligne = `0`.
Pre-state attendu: assertion satisfaite.
Post-state attendu: assertion satisfaite.

### AC-005 [regression]
Assertion: `project.yml` préserve `PRODUCT_BUNDLE_IDENTIFIER = fr.millianlmx.immich-ios` et `DEVELOPMENT_TEAM = 2MJF39L8VY`.
Check post-impl: `rg 'PRODUCT_BUNDLE_IDENTIFIER: fr.millianlmx.immich-ios' project.yml && rg 'DEVELOPMENT_TEAM: 2MJF39L8VY' project.yml` → 2 matches.
Pre-state attendu: assertion satisfaite.
Post-state attendu: assertion satisfaite.

### AC-006 [new]
Assertion: `PVRadius` est fully realigné sur l'échelle Immich: `none=0, xs=4, sm=8 (unchanged), md=12 (était 14), lg=16 (était 20), xl=20, xxl=24, full=999 (unchanged)`. `DesignSystemTokensTests.testRadiusValues()` mis à jour.
Check post-impl: `rg 'static let (none|xs|sm|md|lg|xl|xxl|full): CGFloat' Sources/DesignSystem/Tokens/Spacing+PhotoVault.swift` → contient lignes avec valeurs `0, 4, 8, 12, 16, 20, 24, 999`. ET `xcodebuild test ... -only-testing:ImmichSwiftUITests/DesignSystemTokensTests/testRadiusValues 2>&1 | grep -c passed` → `1`.
Pre-state attendu: NON satisfaite (`PVRadius.md == 14`, `lg == 20`, pas de none/xs/xl/xxl).
Post-state attendu: satisfaite.

### AC-007 [new]
Assertion: `PVSpacing` gagne `s0 = 0` (Immich none) et `s48 = 48` (Immich xxxl). `DesignSystemTokensTests.testSpacingValues()` mis à jour.
Check post-impl: `rg 'static let (s0|s48): CGFloat' Sources/DesignSystem/Tokens/Spacing+PhotoVault.swift` → 2 lignes `s0: CGFloat = 0` et `s48: CGFloat = 48`. ET test passes.
Pre-state attendu: NON satisfaite (PVSpacing s'arrête à s32).
Post-state attendu: satisfaite.

### AC-008 [new]
Assertion: Composant `ImmichAppBar` dans `Sources/DesignSystem/Components/ImmichAppBar.swift`. Init `init(title:)`, rend `HStack` logo + wordmark "Immich" pour `ToolbarItem(placement: .principal)`. ≥4 écrans l'utilisent.
Check post-impl: `test -f Sources/DesignSystem/Components/ImmichAppBar.swift && echo exists` → `exists`. ET `rg 'struct ImmichAppBar' Sources/DesignSystem/Components/ImmichAppBar.swift | grep -c View` → `≥1`. ET `rg 'ToolbarItem\(placement: .principal' Sources/Features/ -c | awk -F: '{s+=$2} END {print s}'` → `≥4`.
Pre-state attendu: NON satisfaite (fichier inexistant, 0 occurrence .principal).
Post-state attendu: satisfaite.

### AC-009 [new]
Assertion: `RootView.swift` applique `.tint(Color.brandIndigo)` au `TabView` (via le modifier `immichBottomBar()` qui encapsule aussi le fond gris opaque de la bottom bar).
Check post-impl: `rg 'immichBottomBar\(\)' Sources/RootView.swift` → `1`. ET `rg '\.tint\(Color\.brandIndigo\)' Sources/DesignSystem/Components/ImmichAppBar.swift` → `1`.
Pre-state attendu: NON satisfaite.
Post-state attendu: satisfaite.

### AC-010 [new]
Assertion: `Font+PhotoVault.swift` ajoute les tailles Immich heading: `pvBodyLarge`(16 semibold), `pvH6`(18 semibold), `pvH5`(20 semibold), `pvH4`(24 bold), `pvH3`(30 bold), `pvH2`(36 bold), `pvH1`(48 bold). `pvBody` RESTE à 17 (iOS HIG, ne change pas). Ces tokens sont utilisés dans ≥1 composant DesignSystem.
Check post-impl: `rg 'pvBodyLarge|pvH6|pvH5|pvH4|pvH3|pvH2|pvH1' Sources/DesignSystem/Tokens/Font+PhotoVault.swift | wc -l` → `≥7`. ET `rg 'pvBodyLarge|pvH6|pvH5|pvH4|pvH3|pvH2|pvH1' Sources/DesignSystem/Components/ -l | wc -l` → `≥1`. ET `rg 'static let pvBody ' Sources/DesignSystem/Tokens/Font+PhotoVault.swift` → contient `size: 17` (pvBody unchanged).
Pre-state attendu: NON satisfaite (seules 7 tailles existent: pvTitleXL/pvTitle/pvHeadline/pvBody/pvSubhead/pvCaption/pvNumeric).
Post-state attendu: satisfaite.

### Failure modes (top 3 + quel AC les détecte)
| # | Failure mode | AC détecteur | Notes |
|---|---|---|---|
| FM1 | Token mismatch: PVRadius.md=12 mais vue avec `.cornerRadius(14)` hardcodé échappe au grep AC-003 (couleurs seulement). Coins inconsistants. | aucun AC direct | Mitigation: vérif manuelle V3. AC-003 ne couvre que couleurs. |
| FM2 | Build cassé après xcodegen: nouveaux fichiers ImmichAppBar.swift non pickés si project.yml pas régénéré AVANT build. | AC-001 | Régénérer project.yml → xcodegen generate → build. AC-005 (bundle id/team) doit précéder xcodegen. |
| FM3 | Tests DS cassés: DesignSystemTokensTests échoue si assertions pas mises à jour avec token mutation (PVRadius.md 14→12, lg 20→16, ajout s0/s48). | AC-002 + AC-006 + AC-007 | AC-002 rattrape global; AC-006/007 forcent assertions explicites. |
| FM4 | Large-title conflict: écrans avec `.navigationTitle(.large)` + ImmichAppBar(.principal) créent double titre ou layout cassé. | aucun AC direct | Mitigation: impl note — retirer `.navigationBarTitleDisplayMode(.large)` et `.navigationTitle` sur écrans adoptant ImmichAppBar. Vérif manuelle V1. |

## Vérifications manuelles (hors auto-feedback loop)
- **V1** Immich chrome resemblance: app bar affiche logo/wordmark Immich en principal sur Timeline/Albums/Search/Trash/Backup (pas de large-title).
- **V2** Bottom bar toujours grise opaque (pas de blur translucide); onglet actif en brandIndigo, inactifs gris. Light + dark mode.
- **V3** Radius cohérence: cards/sheets/modals utilisent cornerRadius=12 (PVRadius.md), pas 14. Comparer PVAlbumCard avant/après.
- **V4** Polices Immich: body text ~14pt (était 17pt); titres section h6/h5. Cohérence typo tous écrans.
- **V5** Dark mode parity: tous composants immich rendent correctement en dark. Wordmark lisible.
- **V6** Scroll behavior app bar: navigationBar reste visuellement constante (pas de shadow qui apparaît au scroll) — compromis natif vs Material scrolledUnderElevation.
- **V7** SF Symbol wordmark fallback acceptable: `camera.aperture` + "Immich" visuellement propre.
- **V8** iOS HIG gestures intactes: swipe-back, pull-to-refresh, long-press sélection, scroll fluide.
- **V9** Pas de régression UI critique: aucun écran cassé (overlap, texte tronqué, illisible). Tester iPhone SE 3rd gen simulé.
- **V10** Animation fluide: transitions onglet/nav push-pop/scaleEffect sélection utilisent PVMotion snappy/standard.
