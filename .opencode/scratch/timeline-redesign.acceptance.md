# Task: timeline-redesign

Status: shipped — Sources/Features/Timeline/.

## Plan
**Objectif**: Redesign TimelineView.swift + AssetThumbnailCell.swift pour rendre la grille élégante et professionnelle (l'utilisateur juge l'UI actuelle "ugly"). Approche A retenue: Apple Photos Refinement.

**Hypothèses**:
- VM @Observable inchangé (aucun champ public ni signature ajoutés/modifiés).
- Comportements préservés: selection mode, favorite/delete via contextMenu, pull-to-refresh, scroll-to-top, loadMore sur dernière cellule, error/empty/skeleton states, navigation vers AssetDetailView, alerts (×3), contextMenu.
- Build Xcode 26.6 + iPhone 17 Pro simulator.
- iOS 17+ requis.
- Tests TimelineViewModelTests existants restent verts.

**Étapes**:
1. Créer `Sources/Features/Timeline/TimelineSectionBuilder.swift` (pure func testable, interleave monthHeader + dayGroup).
2. Créer `Sources/Features/Timeline/MonthYearBanner.swift` (Vue full-width mois-année).
3. Écrire `Tests/TimelineSectionBuilderTests.swift` (prouve AC-N02 avant impl View).
4. Modifier `TimelineView.swift`:
   - Colonnes grid spacing 2→4, suppr min/max.
   - Content: LazyVStack spacing 0 + ForEach(timelineSections) + switch enum.
   - Paddings horizontal 2→4 sur skeleton/grid.
   - Header jour: `.headline.weight(.medium)`, `.secondary`, `.regularMaterial`, padding 20/10.
   - Skeleton grid spacing 2→4, cornerRadius 3→8 (×2).
   - Scroll-to-top: condition `showScrollToTop && !vm.selectionMode`, style raffiné.
   - Toolbar logout: `Menu` + `person.circle` (au lieu de bouton direct).
   - Ajouter `private enum TimelineSectionItem` / typealias vers `TimelineSectionBuilder.Section`.
5. Modifier `AssetThumbnailCell.swift`:
   - cornerRadius 3→8.
   - Tints: blue 0.18→0.15, black 0.08→0.06.
   - Badge margins: padding 6→4.
6. Ajouter nouveaux fichiers à project.yml si nécessaire + `xcodegen generate`.
7. Vérifier build + tests.

## Acceptance Contract

### Approches candidates
**A — Apple Photos Refinement (retenu)**: garde LazyVGrid 3 cols, injecte respiration (spacing 4pt, cornerRadius 8pt continuous), headers hiérarchisés mois/jour, typographie Apple-HIG. Risque régression quasi nul, fidélité max iOS 17+, pattern familier aux utilisateurs.
**B — Grille hauteur variable (Pinterest-like)**: `.adaptive(minimum:100)` + cellules hauteur variable selon aspectRatio. Engageant mais complexe, gaps visuels, badges difficiles à aligner, surface régression élevée.
**C — Cards & Shadows (editorial luxe)**: cornerRadius 16pt + ombres radius 3 + fond systemGray6. Premium "magazine" mais coût rendu sur >100 cellules, s'éloigne du HIG, gaspille espace sur petit écran.

### Approche retenue + rationale
**A — Apple Photos Refinement**. Fidélité HIG (zéro courbe apprentissage), risque régression minimal (VM + moteur layout inchangés), élégance par typographie + espacement (secret Apple Photos), implémentation rapide (~50 lignes + 2 nouveaux fichiers courts).

### Critères

```
### AC-R01 [type: regression]
Assertion: Le projet compile sans erreur après le redesign (toutes les références de VM, vues, services restent valides).
Check post-impl: xcodebuild build -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E '(BUILD SUCCEEDED|BUILD FAILED)'
Pre-state attendu: BUILD SUCCEEDED (le build actuel passe)
Post-state attendu: BUILD SUCCEEDED
```

```
### AC-R02 [type: regression]
Assertion: Tous les tests TimelineViewModelTests passent (12 méthodes: AC-006 bucket pagination, AC-009 testability, AC-013 columnar zip, AC-013b malformed reject, AC-007 thumbnail URL, AC-100 groupedByDay, AC-201 selection, AC-202 toggleFavorite, AC-203 deleteSelected, AC-203b deleteSelected error, AC-204 refresh, AC-205 with(isFavorite:)).
Check post-impl: xcodebuild test -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ImmichSwiftUITests/TimelineViewModelTests 2>&1 | grep -E '(TEST SUCCEEDED|TEST FAILED|\*\* TEST)'
Pre-state attendu: ** TEST SUCCEEDED ** (12 tests, 0 failures)
Post-state attendu: ** TEST SUCCEEDED ** (12 tests, 0 failures)
```

```
### AC-R03 [type: regression]
Assertion: Aucun champ public ni signature de méthode n'est ajouté ou modifié dans TimelineViewModel par CETTE tâche (redesign purement View-layer, VM invariant — isolé de l'état dirty préexistant).
Check post-impl: sh -c 'before=$(cat /Users/20015659/immich_swiftui/.opencode/scratch/TimelineViewModel.baseline.swift | shasum | cut -d" " -f1); after=$(shasum /Users/20015659/immich_swiftui/Sources/Features/Timeline/TimelineViewModel.swift | cut -d" " -f1); test "$before" = "$after" && echo PASS || echo FAIL'
Pre-state attendu: PASS (snapshot baseline == VM courant avant tâche)
Post-state attendu: PASS (VM inchangé après tâche)
```

Note: baseline snapshot créé en Phase 3 par build via `cp Sources/Features/Timeline/TimelineViewModel.swift .opencode/scratch/TimelineViewModel.baseline.swift`.

```
### AC-N01 [type: new]
Assertion: Le bouton scroll-to-top est masqué quand le mode sélection est actif (`vm.selectionMode == true`). Il réapparaît quand le mode sélection est quitté et que l'utilisateur a scrollé au-delà du sentinel "top".
Check post-impl: grep -E 'showScrollToTop.*selectionMode|selectionMode.*showScrollToTop|showScrollToTop && !' Sources/Features/Timeline/TimelineView.swift
Pre-state attendu: Aucune correspondance (la condition n'existe pas encore)
Post-state attendu: Au moins 1 ligne trouvée montrant la conjonction `showScrollToTop && !vm.selectionMode` (ou équivalent sémantique dans l'overlay)
```

```
### AC-R04 [type: regression]
Assertion: Les 3 dialogues d'alerte (.alert) sont préservés dans TimelineView: (1) confirmation batch delete "Delete N asset(s)?", (2) confirmation single delete "Delete this asset?", (3) surface d'erreur "Something went wrong".
Check post-impl: sh -c 'n=$(grep -c "\.alert(" Sources/Features/Timeline/TimelineView.swift); test "$n" -ge 3 && echo PASS || echo FAIL'
Pre-state attendu: PASS (3 alerts, lignes 88/100/109 actuelles)
Post-state attendu: PASS (≥3)
```

```
### AC-R05 [type: regression]
Assertion: Le NavigationLink vers AssetDetailView est préservé (hors mode sélection, tap cellule navigue).
Check post-impl: sh -c 'n=$(grep -c "NavigationLink" Sources/Features/Timeline/TimelineView.swift); test "$n" -ge 1 && echo PASS || echo FAIL'
Pre-state attendu: PASS (1 NavigationLink ligne 228)
Post-state attendu: PASS (≥1)
```

```
### AC-R06 [type: regression]
Assertion: Le `.contextMenu` sur AssetThumbnailCell avec Favorite/Unfavorite + Delete est préservé.
Check post-impl: sh -c 'n=$(grep -c "\.contextMenu" Sources/Features/Timeline/AssetThumbnailCell.swift); test "$n" -ge 1 && echo PASS || echo FAIL'
Pre-state attendu: PASS (1 contextMenu ligne 54)
Post-state attendu: PASS (≥1)
```

```
### AC-R07 [type: regression]
Assertion: Skeleton grid initiale (4 rows × 3 cols) + skeleton row loadMore (1 row) préservées avec shimmer.
Check post-impl: sh -c 'n=$(grep -c "SkeletonShimmerGrid" Sources/Features/Timeline/TimelineView.swift); test "$n" -ge 2 && echo PASS || echo FAIL'
Pre-state attendu: PASS (2 occurrences lignes 134/180)
Post-state attendu: PASS (≥2)
```

```
### AC-N02 [type: new]
Assertion: TimelineSectionBuilder.build(from:) intercale correctement les .monthHeader entre .dayGroup quand le mois change. Tests XCTest couvrent: (a) liste vide → [], (b) 1 jour → [monthHeader, dayGroup], (c) 3 jours même mois → [monthHeader, dayGroup×3], (d) jours mois différents → intercalage correct avec nom du mois formaté.
Check post-impl: xcodebuild test -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ImmichSwiftUITests/TimelineSectionBuilderTests 2>&1 | grep -E '(TEST SUCCEEDED|TEST FAILED|\*\* TEST)'
Pre-state attendu: 0 tests ran (TimelineSectionBuilder n'existe pas encore)
Post-state attendu: ** TEST SUCCEEDED ** (≥4 cas de test, 0 failures)
```

### Failure modes (top 3 + quel AC les détecte)
**FM1 — Rupture du loadMore trigger**: restructuration sections modifie identité cellules; si `.task { if item.id == vm.items.last?.id }` mal attaché → infinite scroll casse silencieusement. Détection: vérif manuelle (scroll bas, observer loadMore trigger). Mitigation: `.task` reste attaché à chaque `cellView(for:)` via `ForEach(group.items)` — identité globale `vm.items.last?.id` inchangée donc trigger reste correct.
**FM2 — Mois orphelin/déséquilibré**: bannière mois gros titre suivie de très peu de contenu visuel disproportionné. Détection: vérif manuelle. Mitigation: padding banner top 32pt reasonable, espacement respiratoire.
**FM3 — Clipping badges cornerRadius 8pt**: padding badge 6pt + cornerRadius 8pt pourrait clipper sur très petits écrans (<80pt colonne). Détection: AC-R01 build passe (pas d'erreur compile), vérif manuelle iPhone SE. Mitigation: réduction padding badge 6→4pt compense larger radius.

## Vérifications manuelles (hors auto-feedback loop)
1. Grille: spacing 4pt uniforme, `.padding(.horizontal, 4)` sur bords écran.
2. Corner radius: 8pt continuous visible toutes cellules, pas artefact clipping.
3. Header jour: `.headline.weight(.medium)` + `.secondary` + `.regularMaterial` lisible sans dominer.
4. Bannière mois: `.title.weight(.bold)` + `.primary`, UNIQUEMENT au premier jour de chaque mois, pas doublon, pas orpheline.
5. Scroll-to-top: visible si (a) scrollé vers bas ET (b) mode sélection inactif. Transition spring entrée/sortie sélection.
6. Mode sélection: checkmark cercle/coche + tint blue 0.15 + dim black 0.06, transition spring .scaleEffect(0.96) fluide.
7. Badges: favorite/360°/video capsules `.ultraThinMaterial`, pas collision checkmark.
8. Context menu: appui long cellule hors sélection → menu Favorite/Delete. En sélection → pas menu, long press toggle sélection.
9. Pull-to-refresh: spinner Apple standard, appelle `vm.refresh()`.
10. État vide: ContentUnavailableView "No Photos" + bouton Refresh.
11. État erreur: ContentUnavailableView "Couldn't load photos" + message + Try Again.
12. Skeleton: 4×3 initial, 1×3 loadMore, cornerRadius 8pt.
13. Navigation title: "Photos" normal / "X selected" sélection, `.large` display.
14. Toolbar: logout via `Menu` + `person.circle` icône → bouton "Log Out" role `.destructive`. En sélection: Cancel (leading) + Favorite + Delete (trailing).
15. DateHeaderFormatter: "Today" / "Yesterday" / "Saturday, July 27" / "Saturday, July 27, 2024" inchangés.
16. Transitions: push vers AssetDetailView fluide, retour fluide. Parallax scrollTransition scale 0.94 / opacity 0.9 préservé.

## Détail du redesign (spécifications implémentation)

### Fichiers modifiés
| Fichier | Changement |
|---|---|
| `TimelineView.swift` | Restructure content (LazyVStack spacing 0 + enum sections), columns spacing 2→4, paddings 2→4, header jour redesign, skeleton corner 3→8 spacing 2→4, scroll-to-top conditionnel, toolbar Menu logout |
| `AssetThumbnailCell.swift` | cornerRadius 3→8, tints blue 0.18→0.15 / black 0.08→0.06, badge padding 6→4 |
| **NEW** `MonthYearBanner.swift` | Vue full-width mois-année |
| **NEW** `TimelineSectionBuilder.swift` | Logique pure testable (interleave monthHeader/dayGroup) |
| **NEW** `Tests/TimelineSectionBuilderTests.swift` | Tests AC-N02 |

### Valeurs numériques clés
| Prop | Avant | Après | Lieu |
|---|---|---|---|
| Grid column spacing | 2 | 4 | TimelineView.swift |
| Grid horizontal padding | 2 | 4 | TimelineView.swift |
| Cell corner radius | 3 | 8 | AssetThumbnailCell.swift |
| Skeleton corner radius | 3 | 8 | TimelineView.swift ×2 |
| Skeleton grid spacing | 2 | 4 | TimelineView.swift |
| Day header font | subheadline.semibold | headline.medium | TimelineView.swift |
| Day header foreground | primary | secondary | TimelineView.swift |
| Day header H-padding | 16 | 20 | TimelineView.swift |
| Day header V-padding | 8 | 10 | TimelineView.swift |
| Day header background | .bar | .regularMaterial | TimelineView.swift |
| Month banner font | — | title.bold | MonthYearBanner.swift |
| Month banner top padding | — | 32 | MonthYearBanner.swift |
| Selection tint selected | blue 0.18 | blue 0.15 | AssetThumbnailCell.swift |
| Selection tint unselected | black 0.08 | black 0.06 | AssetThumbnailCell.swift |
| Badge margin | 6 | 4 | AssetThumbnailCell.swift |
| Scroll-to-top material | ultraThinMaterial | regularMaterial | TimelineView.swift |
| LazyVStack spacing | 18 | 0 | TimelineView.swift |

### AssetThumbnailCell overlays (inchangé)
```
Color.clear.aspectRatio(1)
  .overlay { AuthenticatedAsyncImage w/ scrollTransition parallax }
  .overlay { selectionTint }
  .overlay { favoriteBadge topTrailing }
  .overlay(topLeading) { projectionBadge }
  .overlay(bottomTrailing) { videoBadge }
  .overlay(topTrailing) { checkmark }
  .clipShape(RoundedRectangle(cornerRadius: 8))
  .scaleEffect(selectionMode && isSelected ? 0.96 : 1.0)
```
