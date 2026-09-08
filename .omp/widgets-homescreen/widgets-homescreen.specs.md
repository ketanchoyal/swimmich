# Task: widgets-homescreen

**Objectif** : Ajouter les widgets Home Screen (et Lock Screen si possible) pour ImmichSwiftUI. Le Live Activity (backup progress) existe déjà dans l'extension `ImmichWidgets`. Il manque les widgets statiques de grille + memories.

**Hypothèses** :
- `ImmichWidgets/` extension existe avec `BackupLiveActivity.swift`.
- `ImmichSharedKit` framework existe pour le partage de code entre l'app et l'extension.
- `ImmichSwiftUIApp` (Sources/) → `WidgetKit` extension dans `ImmichWidgets/`.
- WidgetKit iOS 16+ support (iOS 26 target — fully supported).
- `getMemories()` déjà wire dans ImmichClient → `[MemoryResponseDto]`.
- `getTimeBuckets()` wire → `[TimeBucketsResponseDto]`.
- Widget processus séparé de l'app → ne peut pas accéder aux VMs directement.
- Le widget doit utiliser `URLSession` + le token Keychain pour fetcher les données.
- `widgetURL` pour deep link vers l'app.

**Approche retenue** : A — widget mémoire (12x12 grid) + widget Memories. Utiliser `TimelineProvider` + `StaticConfiguration`. Données fetch via `URLSession` + Keychain. Deep links via `widgetURL`.
- **B (rejetée)** : widgets data-rich (App Group container). Sécurité + sync difficile.
- **C (rejetée)** : un seul widget. Le Flutter a 3 widgets (grid, memories, favorites).

## Étapes

1. **WidgetKit extensions** — Étendre `ImmichWidgets/` :
   - NEW `ImmichWidgets/ImmichGridWidget.swift` : widget grille de photos (derniers assets de la timeline).
   - NEW `ImmichWidgets/ImmichMemoriesWidget.swift` : widget "On this day" (memories cards).
   - NEW `ImmichWidgets/ImmichFavoritesWidget.swift` : widget favorites.
2. **Widget data provider** — NEW `ImmichWidgets/WidgetDataProvider.swift` dans ImmichSharedKit ou ImmichWidgets :
   - `func fetchTimelineAssets() async -> [AssetResponseDto]` — GET /api/timeline/buckets.
   - `func fetchMemories() async -> [MemoryResponseDto]` — GET /api/memories.
   - `func fetchFavorites() async -> [AssetResponseDto]` — GET /api/timeline/buckets?isFavorite=true.
   - Utilise le token du Keychain (shared via `keychain` protocol).
   - `WidgetTokenProvider` : lit le token et URL depuis KeychainStore.
3. **Widget views** :
   - `GridWidgetView` : LazyVGrid 3-4 cols des thumbnail des assets récents.
   - `MemoriesWidgetView` : OnThisDay card (year + date).
   - `FavoritesWidgetView` : grid de favoris récents.
   - Tous avec `.widgetURL` vers l'app pour navigation.
4. **ImmichSwiftUIApp** — register widgets dans `@main` (déjà fait pour Live Activity, ajouter les widgets).
5. **Project.yml** — xcodegen doit regénérer les targets ImmichWidgets + ImmichSharedKit.
6. **Tests** — `WidgetDataProviderTests` (fetch assets, fetch memories, fetch favorites, auth error handling).
7. **xcodegen + suite**.

## Acceptance Contract

### Approches candidates
**A (retenue)** : 3 widgets (grid, memories, favorites) + TimelineProvider + keychain access + widgetURL.
**B** : Widget data-rich (App Group). Sécurité/sync.
**C** : 1 seul widget. Insuffisant.

### Approche retenue + rationale
**A**. Parity Flutter, 3 widgets couvrant les surfaces principales (récent, memories, favoris). TimelineProvider pour refresh.

### Critères

```
### AC-WG01 [type: new]
Assertion: ImmichGridWidget + ImmichMemoriesWidget + ImmichFavoritesWidget exist dans ImmichWidgets/.
Check post-impl: sh -c 'test -f "ImmichWidgets/ImmichGridWidget.swift" && test -f "ImmichWidgets/ImmichMemoriesWidget.swift" && test -f "ImmichWidgets/ImmichFavoritesWidget.swift" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-WG02 [type: new]
Assertion: WidgetDataProvider existe avec fetchTimelineAssets, fetchMemories, fetchFavorites, utilise Keychain.
Check post-impl: sh -c 'f=ImmichWidgets/WidgetDataProvider.swift; test -f "$f" && grep -q "fetchTimelineAssets" "$f" && grep -q "fetchMemories" "$f" && grep -q "fetchFavorites" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-WG03 [type: new]
Assertion: TimelineProvider dans chaque widget (compositingTimeline).
Check post-impl: sh -c 'f=ImmichWidgets/ImmichGridWidget.swift; grep -q "TimelineProvider" "$f" && grep -q "compositingTimeline" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-WG04 [type: new]
Assertion: Widget views utilise LazyVGrid (grid) + widgetURL pour deep link.
Check post-impl: sh -c 'f=ImmichWidgets/ImmichGridWidget.swift; grep -q "LazyVGrid" "$f" && grep -q "widgetURL" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-WG05 [type: new]
Assertion: ImmichSwiftUIApp registre les widgets (pas seulement la Live Activity).
Check post-impl: sh -c 'grep -q "ImmichGridWidget\|ImmichMemoriesWidget\|ImmichFavoritesWidget" Sources/ImmichSwiftUIApp.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-WG06 [type: new]
Assertion: Tests WidgetDataProviderTests ≥ 3 (fetch timeline, fetch memories, fetch favorites).
Check post-impl: sh -c 'f=Tests/WidgetDataProviderTests.swift; test -f "$f" && n=$(grep -c "func test_" "$f"); test "$n" -ge 3 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-WG07 [type: regression]
Assertion: Suite ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_widgets_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_widgets_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
