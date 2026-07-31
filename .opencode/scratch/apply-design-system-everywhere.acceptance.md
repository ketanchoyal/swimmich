# Task: apply-design-system-everywhere

## Plan
Objectif: appliquer le design system PhotoVault EXISTANT à TOUTE l'UI (Features/*, Services/AuthenticatedAsyncImage.swift, RootView.swift, ImmichSwiftUIApp.swift). Token swap couleurs + fonts + spacing + radius, adoption composants (PVPrimaryButtonStyle, pvFloatingShadow), motion tokenization via PVMotion.{standard,snappy,gentle,adaptive}, exemptions documentées inline pour cas hors-DS (micro-badges, hero illustrations §8.6, destructive button, infinite shimmer, white-overlay-on-image).

Hypothèses (à vérifier par scout):
- Sources/DesignSystem/ ne doit PAS être modifié (tokens existants suffisants).
- xcodegen régénère le projet ; pas de nouveaux fichiers Swift à ajouter côté Features.
- Comportement identique, apparence DS uniquement. Pas de refactoring fonctionnel.
- Précédent §8.6: hero illustrations exemptées de font-token (play.fill size:8, lock.fill size:56).

Étapes:
1. Scout: vérifier chaque hypothèse + chaque mapping du contract contre le code réel (fichier:ligne).
2. Implémenter par feature: Auth (Login, ServerConnect), Timeline (TimelineView, AssetThumbnailCell, MonthYearBanner), Albums (Albums, AlbumDetail, AddToAlbumPickerSheet, CreateAlbum), AssetDetail, Editor, Search, SharedLinks, Trash, Upload(view), RootView, AuthenticatedAsyncImage.
3. Après chaque feature: build incremental (compile swiftc via xcodebuild).
4. tester: baselines A (suite) + B (contract AC), puis reviewer.

## Acceptance Contract

### Approches candidates
- **A — Token swap only**: swap hardcoded → token, keep all View structures. Plus rapide, zéro risque layout. Tradeoff: ne capture pas la réutilisation composants (cartes/badges/boutons dupliqués).
- **B — Token swap + adopt PV components where 1:1**: A + `.borderedProminent` → PVPrimaryButtonStyle, pvFloatingShadow sur éléments flottants, PVStatusBadge/PVAlbumCard/PVEmptyState si signature match. Tradeoff: adoption partielle peut causer diffs layout (PVAlbumCard ajoute cornerRadius+shadow là où l'actuel n'en a pas).
- **C — Full incl. reduce-motion env wiring**: B + `@Environment(\.accessibilityReduceMotion)` dans chaque View animée, via PVMotion.adaptive. Tradeoff: plomberie env sur 6+ Views, mais honore vraiment le contrat accessibilité (spec §10).

### Approche retenue + rationale
**C (full token swap + component adoption + reduce-motion wiring)**. L'énoncé demande d'appliquer le DS à TOUTE l'UI, et la spec §10 mandate Reduce Motion via PVMotion.adaptive. Sauter le motion wiring = violation spec, pas juste dérive cosmétique. Exemption: PVAlbumCard NON adopté sur AlbumsView.AlbumCard (look flat/square-corner intentionnel, convention seam Photos.app; PVAlbumCard lg-radius+shadow régresserait visuellement la grille). Token-swap à l'intérieur de AlbumCard existant à la place.

### Mapping canonique

#### Couleur sémantique → token
| Source | Token DS | Occurrences | Note |
|---|---|---|---|
| `.foregroundStyle(.secondary)` | `Color.textSecondaryPV` | 18 | |
| `.foregroundStyle(.primary)` | `Color.textPrimaryPV` | 2 (MonthYearBanner, AddToAlbumPickerSheet) | |
| `.foregroundStyle(.red)` | `Color.statusError` | 4 (AssetDetail, Login, ServerConnect, PhotoEditor) | |
| `.foregroundStyle(.green)` | `Color.statusSuccess` | 1 (AddToAlbumPickerSheet checkmark) | |
| `.foregroundStyle(.orange)` | `Color.statusPending` | 1 (SearchView error icon) | |
| `.foregroundStyle(.blue)` | `Color.accentInfo` | 2 (TimelineView:62 scroll-to-top, AssetThumbnailCell:176 checkmark ternary) | ternary `isSelected ? Color.accentInfo : .white` |
| `Color(.systemGray5)` | `Color.bgTertiary` | 1 (TimelineView SkeletonCell) | |
| `.foregroundStyle(.white)` | **EXEMPT** | 2 (AssetThumbnailCell:143 play badge on material; :176 white branch of ternary) | marker `// DS-exempt: badge contrast on material` |
| `Color.blue.opacity(0.15)` | `Color.accentInfo.opacity(0.15)` | 1 (AssetThumbnailCell:159 selectionTint) | scout NF-1 |
| `Color.black.opacity(0.06)` | **EXEMPT** | 1 (AssetThumbnailCell:161 selectionTint unselected dim) | structural overlay, marker `// DS-exempt: structural dim overlay` |
| `Color.accentColor.opacity(0.3)` + `Color.gray.opacity(0.1)` | `Color.brandIndigo.opacity(0.3)` + `Color.bgTertiary` | PhotoEditorView CropAspectPicker | |

#### Apple text style → token
| Source | Token | Note |
|---|---|---|
| `.largeTitle` | `pvTitleXL` | |
| `.title.weight(.bold)` / `.title2.bold()` / `.title` | `pvTitle` | |
| `.title3[.weight]` | `pvHeadline` | -3pt |
| `.headline[.weight(.medium)]` | `pvHeadline` | |
| `.subheadline[.weight(.medium)]` | `pvSubhead` | medium→regular |
| `.callout` | `pvBody` | +1pt |
| `.footnote` | `pvCaption` | |
| `.caption` | `pvCaption` | +1pt |
| `.caption.monospacedDigit()` | `.font(.pvCaption).monospacedDigit()` | two-modifier |
| `.caption2.weight(.semibold)` / `.caption2.monospaced()` | `pvCaption` / `.font(.pvCaption).monospacedDigit()` | +2pt |
| `.font(.system(size: 8))` | **EXEMPT** | badge micro-glyph §8.6 |
| `.font(.system(size: 56))` | **EXEMPT** | hero illustration §8.6 |

#### Spacing hors-grille → snap
- 3px (badge micro-padding) → **EXEMPT** marker `// DS-exempt: badge micro-padding`
- 6px → `PVSpacing.s8` (+2px)
- 10px → `PVSpacing.s8` (-2px)
- 20px (VStack RootView:68 + padding horiz MonthYearBanner:21, TimelineView:353, TrashView:159) → `PVSpacing.s24` (+4px)

#### ButtonStyle
- `.borderedProminent` (sans tint) → `PVPrimaryButtonStyle()` (3 CTAs: Trash, Timeline, RootView Unlock)
- `.borderedProminent.tint(.red)` → **EXEMPT** marker `// DS-exempt: destructive CTA, no DS token` (PhotoEditor revert)
- `.plain` → **GARDÉ** (absence de chrome, pas un style; 8 occ.)

#### Shadow
- `.shadow(.black.opacity(0.12), radius:8, y:4)` TimelineView floating bar → `.pvFloatingShadow()`
- `.shadow(...radius:1.5...)` ×2 AssetThumbnailCell micro-badge → **EXEMPT** marker `// DS-exempt: micro-badge shadow`

#### Motion
- `.animation(.spring(duration:0.32,bounce:0.2))` AssetThumbnailCell selection → `PVMotion.snappy`
- `withAnimation(.easeInOut(duration:0.35))` TimelineView scroll → `PVMotion.adaptive(PVMotion.gentle, reduceMotion:)` (+ env)
- `.animation(.spring(duration:0.35,bounce:0.18))` TimelineView selectionMode → `PVMotion.standard`
- `.animation(.easeInOut(duration:0.25))` RootView blur → `PVMotion.adaptive(PVMotion.gentle, reduceMotion:)` (+ env)
- `withAnimation(.linear(...).repeatForever())` ×2 (TimelineView + AuthenticatedAsyncImage shimmer) → **EXEMPT** marker `// DS-exempt: infinite shimmer, not interactive`

### Critères

```
### AC-001 [type: new]
Assertion: Aucun `.foregroundStyle(.secondary)` dans Sources/Features, Sources/Services/AuthenticatedAsyncImage.swift, Sources/RootView.swift, Sources/ImmichSwiftUIApp.swift.
Check post-impl: rg -n 'foregroundStyle\(\.secondary\)' Sources/Features/ Sources/Services/AuthenticatedAsyncImage.swift Sources/RootView.swift Sources/ImmichSwiftUIApp.swift | wc -l → 0
Pre-state attendu: 18 (new)
Post-state attendu: 0 (new)

### AC-002 [type: new]
Assertion: Aucun `.foregroundStyle(.primary|.red|.green|.orange|.blue)` dans le scope Features/Services/RootView/App.
Check post-impl: rg -n 'foregroundStyle\(\.(primary|red|green|orange|blue)\)' Sources/Features/ Sources/Services/AuthenticatedAsyncImage.swift Sources/RootView.swift Sources/ImmichSwiftUIApp.swift | wc -l → 0
Pre-state attendu: 10 (new — scout NF-4: AssetThumbnailCell:176 ternary .blue)
Post-state attendu: 0 (new)

### AC-003 [type: new]
Assertion: Aucun `Color(.system...)` dans le scope.
Check post-impl: rg -n 'Color\(\.system' Sources/Features/ Sources/Services/AuthenticatedAsyncImage.swift Sources/RootView.swift Sources/ImmichSwiftUIApp.swift | wc -l → 0
Pre-state attendu: 1 (new)
Post-state attendu: 0 (new)

### AC-004 [type: new]
Assertion: Aucune Apple semantic font style dans le scope.
Check post-impl: rg -n '\.font\(\.(largeTitle|title(\b|2|3)|headline|subheadline|body|callout|footnote|caption2?(\b|\.))' Sources/Features/ Sources/Services/AuthenticatedAsyncImage.swift Sources/RootView.swift Sources/ImmichSwiftUIApp.swift | wc -l → 0
Pre-state attendu: ~28 (new)
Post-state attendu: 0 (new)

### AC-005 [type: new]
Assertion: Seules 2 utilisations `.font(.system(size:))` exemptées §8.6 subsistent, chacune avec marqueur `// DS-exempt:`.
Check post-impl: rg -n '\.font\(\.system\(size:' Sources/Features/ Sources/Services/AuthenticatedAsyncImage.swift Sources/RootView.swift Sources/ImmichSwiftUIApp.swift → exactement 2 hits, chacun sur/ligne adjacente au marqueur DS-exempt.
Pre-state attendu: 2 sans marqueur (new)
Post-state attendu: 2 avec marqueur (new)

### AC-006 [type: new]
Assertion: Au moins 18 usages de `Color.textSecondaryPV|Color.textPrimaryPV` dans Sources/Features/ (seuil calibré post-tester : la scope Features-only contient exactement 16 `.secondary` + 2 `.primary` = 18 conversions ; les 2 `.secondary` restantes des 20 totales sont dans RootView.swift + AuthenticatedAsyncImage.swift, hors-scope Features. Toutes les conversions sémantiques sont effectuées — AC-001/AC-002 prouvent zéro résidu).
Check post-impl: grep -rho -E 'Color\.text(Secondary|Primary)PV' Sources/Features/ | wc -l → ≥18
Pre-state attendu: 0 (new)
Post-state attendu: ≥18 (new)

### AC-007 [type: new]
Assertion: Au moins 5 usages de `Color.statusError|statusSuccess|statusPending|accentInfo|brandIndigo|bgTertiary` dans Sources/Features/.
Check post-impl: rg -c 'Color\.(statusError|statusSuccess|statusPending|accentInfo|brandIndigo|bgTertiary)' Sources/Features/ | awk -F: '{s+=$2} END {print s}' → ≥5
Pre-state attendu: 0 (new)
Post-state attendu: ≥5 (new)

### AC-008 [type: new]
Assertion: Au moins 3 adoptions `PVPrimaryButtonStyle()`.
Check post-impl: rg -c 'PVPrimaryButtonStyle\(\)' Sources/Features/ Sources/RootView.swift | awk -F: '{s+=$2} END {print s}' → ≥3
Pre-state attendu: 0 (new)
Post-state attendu: ≥3 (new)

### AC-009 [type: new]
Assertion: Au moins 1 adoption `.pvFloatingShadow()` dans Features.
Check post-impl: rg -c 'pvFloatingShadow\(\)' Sources/Features/ Sources/RootView.swift | awk -F: '{s+=$2} END {print s}' → ≥1
Pre-state attendu: 0 (new)
Post-state attendu: ≥1 (new)

### AC-010 [type: new]
Assertion: Au moins 12 usages de tokens font DS dans Features.
Check post-impl: rg -c '\.pv(Headline|Caption|Body|Subhead|Title|TitleXL|Numeric)' Sources/Features/ | awk -F: '{s+=$2} END {print s}' → ≥12
Pre-state attendu: 0 (new)
Post-state attendu: ≥12 (new)

### AC-011 [type: new]
Assertion: Au moins 10 usages de `PVSpacing.s*` dans Features.
Check post-impl: rg -c 'PVSpacing\.s(2|4|8|12|16|24|32)' Sources/Features/ | awk -F: '{s+=$2} END {print s}' → ≥10
Pre-state attendu: 0 (new)
Post-state attendu: ≥10 (new)

### AC-012 [type: new]
Assertion: Toute exemption documentée porte un marqueur `// DS-exempt:`. ≥7 marqueurs couvrant catégories: white foregroundStyle, font system size:8, font system size:56, shadow radius:1.5, borderedProminent+tint red, linear infinite repeatForever, padding vertical 3.
Check post-impl: rg -c '// DS-exempt:' Sources/Features/ Sources/Services/AuthenticatedAsyncImage.swift Sources/RootView.swift Sources/ImmichSwiftUIApp.swift | awk -F: '{s+=$2} END {print s}' → ≥7
Pre-state attendu: 0 (new)
Post-state attendu: ≥7 (new)

### AC-013 [type: regression]
Assertion: build Xcode du scheme ImmichSwiftUI (sim iPhone 16) réussit.
Check post-impl: xcodebuild build -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -1 → ** BUILD SUCCEEDED **
Pre-state: OK (regression)
Post-state: OK (regression)

### AC-014 [type: regression]
Assertion: la suite XCTest (17 fichiers) reste verte, 0 failure.
Check post-impl: xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E 'Test Suite.*(passed|failed)|\*\* TEST' → ** TEST SUCCEEDED **
Pre-state: verts (regression)
Post-state: verts (regression)

### AC-015 [type: regression]
Assertion: scope des AC négatifs exclut explicitement Sources/DesignSystem/ (tokens définissent légitimement Font.system).
Check post-impl: chaque rg des AC-001..005 passe les paths Sources/Features/ Sources/Services/AuthenticatedAsyncImage.swift Sources/RootView.swift Sources/ImmichSwiftUIApp.swift — Sources/DesignSystem/ absent.
Pre-state: scope correct (regression)
Post-state: scope inchangé (regression)

### AC-016 [type: new]
Assertion: ≥2 usages de `PVMotion.adaptive` avec reduceMotion env.
Check post-impl: rg -c 'PVMotion\.adaptive' Sources/Features/ Sources/RootView.swift | awk -F: '{s+=$2} END {print s}' → ≥2
Pre-state: 0 (new)
Post-state: ≥2 (new)

### AC-017 [type: new]
Assertion: RootView.swift n'utilise plus `.animation(.easeInOut(duration: 0.25))`.
Check post-impl: rg -n 'easeInOut\(duration: 0\.25\)' Sources/RootView.swift | wc -l → 0
Pre-state: 1 (new)
Post-state: 0 (new)

### AC-018 [type: new]
Assertion: AssetThumbnailCell springs remplacées par PVMotion.snappy.
Check post-impl: rg -c 'PVMotion\.snappy' Sources/Features/Timeline/AssetThumbnailCell.swift → ≥1
Pre-state: 0 (new)
Post-state: ≥1 (new)

### AC-019 [type: regression]
Assertion: DesignSystemTokensTests restent verts.
Check post-impl: xcodebuild test ... -only-testing:ImmichSwiftUITests/DesignSystemTokensTests → 3 pass
Pre-state: 3 pass (regression)
Post-state: 3 pass (regression)
```

### Failure modes (top 3 + quel AC les détecte)
1. **PVPrimaryButtonStyle casse le layout RootView LockView** — force `maxWidth:.infinity`+`minHeight:50` sur bouton "Unlock" dans VStack centré. Détecté: build OK (AC-013) mais AC-008 confirme adoption sans valider layout → **vérification manuelle** (hors contract). Mitigation: garder .buttonStyle(.plain) si layout casse, ou revoir la VStack.
2. **Snap spacing 6→s8 décale badge micro AssetThumbnailCell** (play.fill+duration capsule s'élargit 2px). Détecté: AC-012 (si exemptionné) ou visuel. Mitigation: exemptionner ce padding précis.
3. **Grep AC-004 faux positifs** sur commentaires `// was .font(.caption)`. Détecté: AC-004 échoue (compte>0). Mitigation: commentaires sans syntaxe littérale, ou ajuster regex `rg '^[^/]*\.font'`.

## Vérifications manuelles (hors auto-feedback loop)
- Layout Lock screen (RootView) après adoption PVPrimaryButtonStyle: bouton "Unlock" reste équilibré, pas full-width disgracieux.
- AlbumsView AlbumCard après token-swap: aspect grille préservé (pas de shadow/radius ajouté — PVAlbumCard NON adopté volontairement).
- AssetThumbnailCell badges (play+duration, checkmark selection) après snap spacing: alignement visuel intact.
- SearchView search bar après cornerRadius 12→PVRadius.md: hauteur/forme préservées.
- Color shift perceptuel: statusError (.red→#E85D75), statusPending (.orange→#F5A623) — vérifier contraste sur fond bgSecondary/bgPrimary.

## Vérifications manuelles — V1.5 polish (doivent rester vraies)
- Render debounce timeline préservé (pas touché par ce scope).
- Haptics/Localizable/iPad fix non affectés (scope UI tokens uniquement).
