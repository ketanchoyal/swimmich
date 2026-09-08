# Task: memories-redesign

Status: shipped — AC-1184..AC-1190 PASS 2026-08-13 (517 tests, +10).

## Plan
**Objectif**: Élever l'onglet Memories de "liste de grilles froides" à une expérience cinématique native SwiftUI Liquid Glass. On garde **uniquement l'onglet Memories** (pas de lane dans Photos — décision utilisateur). Deux livrables : (1) `MemoryCard` plein-écran immersif (héro + chips verre) en remplacement de la grille 3×3 ; (2) un `MemoryMomentView` plein écran (le "shot de dopamine") qui surface **toutes** les infos d'un memory : année, date exacte, «N years ago», comptes photo/vidéo, localisation, personnes, tags, `isSaved`, type. Nostalgie = photo héro plein écran + Ken Burns lent + verre liquide flottant + révélation progressive.

**Hypothèses** (vérifiées par lecture source):
- `MemoryResponseDto` (Sources/Core/Types/DTOs+Social.swift:48-62) porte déjà `id, memoryAt, type, data.year, assets[AssetResponseDto], isSaved, showAt/hideAt/seenAt/deletedAt`. Rien à changer côté DTO/client (`getMemories()` ImmichClient.swift:122 existe).
- `AssetResponseDto` (DTOs.swift:95-129) porte `people: [PersonResponseDto]?`, `tags: [TagResponseDto]?`, `exifInfo` (city/state/country), `isFavorite`, `duration`, `thumbhash`, `type`. Tout est dispo pour le surfacage riche, inutilisé aujourd'hui.
- `ImmichAssetURL.thumbnail(assetId:thumbhash:baseURL:size:)` + `.preview` (AssetMediaSize) pour l'héro ; `ImmichAssetURL.personThumbnail(personId:baseURL:size:)` pour les avatars de personnes.
- `AuthenticatedAsyncImage` (pattern existant `AssetThumbnailCell`/`MemoryCard`) pour charger héro/thumbs avec token.
- Viewer: `.photoViewer(item:baseURL:token:onDataChanged:)` + `PhotoViewerItem(assets: [AssetReactItem], index:)` (MemoriesView.swift:69-91).
- Target iOS 26 → `.glassEffect(_:in:)` + `GlassEffectContainer` dispo (skill swiftui-liquid-glass) ; pas de fallback matériel.
- `PVMotion.adaptive(_:reduceMotion:)` + `@Environment(\.accessibilityReduceMotion)` = mécanisme Reduce Motion codebase (PhotoVault-DesignSystem.md §6).
- Baseline suite: 486 tests (i18n-catalog AC-1180..1183, 2026-08-12). `MemoriesViewModelTests` = 19 tests, ne doit pas casser.
- `MemoriesViewModel` reste inchangé (présentation pure — pas de nouveau comportement réseau).

**Hors scope (backlog explicite, repris de memory.md:488)**: save/unsave (`PUT /memories/{id}/save` non exposé client) ; «View in timeline» (jump to date vers Photos — cross-tab, card séparée) ; lane dans Photos ; widgets. `MemoryType.year_in_review` reste décodé `.unknown` (pas rendu, comme aujourd'hui).

**Approche retenue**: A — redesign visuel + moment dédié, VM intact. **B** (rejetée): lane carousel dans Photos (user refuse). **C** (rejetée): fusionner le moment dans le photoViewer générique (perd les métadonnées mémoires, pas de place pour chips/lieu/personnes).

**Étapes**:
1. Card écrite (ce fichier).
2. NEW `Sources/Features/Memories/MemoryMomentPresentation.swift` — helpers purs testables (fullDateLabel, peopleLabel, tagsLabel, réutilisation MemoryCardPresentation).
3. NEW `Sources/Features/Memories/MemoryMomentView.swift` — plein écran : héro Ken Burns + `GlassEffectContainer` (chips année/date/«N years ago»/comptes/lieu/personnes/tags/isSaved/type) + filmstrip horizontal + intégration photoViewer.
4. MODIFY `Sources/Features/Memories/MemoriesView.swift` — `MemoryCard` full-bleed (héro + chips verre, suppression `LazyVGrid` 3×3) + présentation du moment via `fullScreenCover`.
5. NEW `Tests/MemoryMomentPresentationTests.swift`.
6. xcodegen generate (2 nouveaux fichiers) + build-for-testing + suite complète → `/tmp/immich_memories_redesign_test_summary.txt`.
7. Checks AC (grep ^Check post-impl: | sed | eval) + memory.md + Status shipped.

## Acceptance Contract

### Approches candidates
**A (retenue)**: Moment plein écran dédié + cartes full-bleed. Héro Ken Burns, verre liquide, surfacage riche (personnes/tags/lieu/isSaved), VM intact, photoViewer réutilisé en "voir tout".
**B**: Lane carousel en tête de Timeline (Photos). Refusé par l'utilisateur (onglet uniquement).
**C**: Étendre le photoViewer générique avec un header mémoire. Perd la place d'un layout mémoire, mélange les responsabilités.

### Approche retenue + rationale
**A**. Shot de dopamine = une photo plein écran, pas une grille 3×3. Toutes les infos déjà présentes dans le DTO sont enfin surfacées. VM/DTO/client intacts → risque nul côté réseau.

### Critères

```
### AC-1184 [type: new]
Assertion: MemoryMomentView existe avec un héro Ken Burns (scaleEffect + repeatForever) honorant Reduce Motion via PVMotion.adaptive / accessibilityReduceMotion.
Check post-impl: sh -c 'f=Sources/Features/Memories/MemoryMomentView.swift; test -f "$f" && grep -q "scaleEffect" "$f" && grep -q "repeatForever" "$f" && (grep -q "PVMotion.adaptive" "$f" || grep -q "accessibilityReduceMotion" "$f") && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-1185 [type: new]
Assertion: MemoryMomentView utilise Liquid Glass (glassEffect + GlassEffectContainer) et intègre le photoViewer (PhotoViewerItem + photoViewer).
Check post-impl: sh -c 'f=Sources/Features/Memories/MemoryMomentView.swift; test -f "$f" && grep -q "glassEffect" "$f" && grep -q "GlassEffectContainer" "$f" && grep -q "photoViewer" "$f" && grep -q "PhotoViewerItem" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-1186 [type: new]
Assertion: MemoryMomentView surface toutes les infos du memory — personnes (personThumbnail), tags, isSaved, localisation (exifInfo/city), type.
Check post-impl: sh -c 'f=Sources/Features/Memories/MemoryMomentView.swift; test -f "$f" && grep -q "personThumbnail" "$f" && grep -q "tags" "$f" && grep -q "isSaved" "$f" && grep -q "exifInfo" "$f" && grep -q "memory.type\|\.type" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-1187 [type: new]
Assertion: MemoryMomentPresentation pur (fullDateLabel, peopleLabel, tagsLabel) + MemoryMomentPresentationTests ≥ 4 tests.
Check post-impl: sh -c 'p=Sources/Features/Memories/MemoryMomentPresentation.swift; t=Tests/MemoryMomentPresentationTests.swift; test -f "$p" && grep -q "fullDateLabel" "$p" && grep -q "peopleLabel" "$p" && grep -q "tagsLabel" "$p" && test -f "$t" && n=$(grep -c "func test_" "$t"); test "$n" -ge 4 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichiers absents)
Post-state attendu: PASS
```

```
### AC-1188 [type: new]
Assertion: MemoryCard full-bleed dans MemoriesView.swift — héro AuthenticatedAsyncImage, verre (glassEffect), suppression de la grille 3×3 (LazyVGrid absent).
Check post-impl: sh -c 'f=Sources/Features/Memories/MemoriesView.swift; test -f "$f" && grep -qE "glassEffect|GlassEffectContainer" "$f" && grep -q "AuthenticatedAsyncImage" "$f" && ! grep -q "LazyVGrid" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (glassEffect 0, LazyVGrid présent ligne 138)
Post-state attendu: PASS
```

```
### AC-1189 [type: new]
Assertion: MemoriesView présente MemoryMomentView (fullScreenCover + MemoryMomentView( — wire-up carte → moment).
Check post-impl: sh -c 'f=Sources/Features/Memories/MemoriesView.swift; test -f "$f" && grep -q "fullScreenCover" "$f" && grep -q "MemoryMomentView" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun fullScreenCover/MemoryMomentView)
Post-state attendu: PASS
```

```
### AC-1190 [type: regression]
Assertion: Suite complète ≥ 486 tests, TEST SUCCEEDED, MemoriesViewModelTests (19) toujours vert.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_memories_redesign_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_memories_redesign_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1); test "$n" -ge 486 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (pas de summary)
Post-state attendu: PASS
```

### Failure modes (top 3 + quel AC les détecte)
1. **Ken Burns saccadé / batterie** sur appareils réels — animation continue sur héro coûteuse. AC-1184 (garde Reduce Motion) + V2. Mitigation : `.drawingGroup()` si nécessaire, gated par `PVMotion.adaptive`.
2. **Héro flou** — `ImmichAssetURL.thumbnail` avec `size: .thumbnail` par défaut trop basse résolution en plein écran. Détecté V1. Mitigation : `size: .preview` pour l'héro.
3. **Legibility verre sur héro clair** — `glassEffect(.clear)`/`.regular` sans dimming sur photo lumineuse → texte illisible. AC-1185/1186 + V3. Mitigation : scrim gradient bas (transparent→noir) sous les chips.

## Vérifications manuelles (hors auto-feedback loop)
- V1 héro net plein écran (`.preview`, pas thumbnail).
- V2 Ken Burns fluide (scale 1.0→1.08, 20s linear, repeatForever) — figé sous Reduce Motion.
- V3 contraste chips verre sur héro clair + sombre (scrim + tint).
- V4 filmstrip horizontal : tap change l'héro, «voir tout» ouvre le pager photoViewer au bon index.
- V5 métadonnées complètes (année, date exacte, «N years ago», photos·vidéos, lieu, avatars personnes, tags, isSaved) — librairie avec EXIF/personnes/tags.
- V6 morph verre année carte → moment (`glassEffectID` + `@Namespace`) si retenu.
- V7 haptique `.sensoryFeedback(.impact)` à l'ouverture du moment.
- V8 dark/light + Reduce Transparency (dégradé auto via API système).

## Files
- NEW `Sources/Features/Memories/MemoryMomentPresentation.swift`
- NEW `Sources/Features/Memories/MemoryMomentView.swift`
- NEW `Tests/MemoryMomentPresentationTests.swift`
- MODIFY `Sources/Features/Memories/MemoriesView.swift` (MemoryCard full-bleed, fullScreenCover)
- NOT TOUCHED: `MemoriesViewModel.swift`, `DTOs+Social.swift`, `ImmichClient.swift`, `RootView.swift`, `PhotoViewer.swift`.
