# Task: widgets-homescreen

Status: plan

## Plan

**Objectif**: Ajouter les widgets Home Screen (et Lock Screen si possible) pour ImmichSwiftUI. Live Activity (backup progress) existe déjà dans ImmichWidgets.

**Hypothèses** (ground truth vérifié):
- `ImmichWidgets/` extension existe avec `BackupLiveActivity.swift`.
- `ImmichSharedKit` framework existe.
- WidgetKit iOS 16+ support (iOS 26 target — fully supported).
- `getMemories()` wire → `[MemoryResponseDto]`.
- `getTimeBuckets()` wire → `[TimeBucketsResponseDto]`.
- WidgetKit processus séparé → `URLSession` + Keychain pour data.

**Approche retenue**: A — 3 widgets (Grid, Memories, Favorites) + TimelineProvider + keychain access + widgetURL.
**B**: Widget data-rich (App Group container) → sécurité/sync difficile.
**C**: 1 seul widget → insuffisant.

**Étapes**:
1. NEW `ImmichGridWidget.swift` (ImmichWidgets/) — SystemSmall + SystemMedium, photo grid widget.
2. NEW `ImmichMemoriesWidget.swift` (ImmichWidgets/) — SystemSmall + SystemMedium, OnThisDay card widget.
3. NEW `ImmichFavoritesWidget.swift` (ImmichWidgets/) — SystemSmall + SystemMedium, favorites grid widget.
4. NEW `WidgetDataProvider.swift` (ImmichWidgets/ ou ImmichSharedKit/) — fetchTimelineAssets(), fetchMemories(), fetchFavorites(), utilise Keychain + URLSession.
5. EDIT `ImmichSwiftUIApp.swift` — Register widgets dans `@main` (déjà fait pour Live Activity, ajouter les widgets).
6. Tests — `WidgetDataProviderTests` +3 (fetch timeline, fetch memories, fetch favorites).
7. Build + suite complète.

## Acceptance Contract

### Approches candidates
**A (retenue)**: 3 widgets (grid, memories, favorites) + TimelineProvider + keychain access + widgetURL.
**B**: Widget data-rich → sécurité/sync.
**C**: 1 seul widget → insuffisant.

### Approche retenue + rationale
**A**. Parité Flutter, 3 widgets couvrant les surfaces principales. TimelineProvider pour refresh.

### Critères

```
### AC-3600 [type: new]
Assertion: ImmichGridWidget, ImmichMemoriesWidget, ImmichFavoritesWidget existent dans ImmichWidgets/.
Check post-impl: sh -c 'test -f "ImmichWidgets/ImmichGridWidget.swift" && test -f "ImmichWidgets/ImmichMemoriesWidget.swift" && test -f "ImmichWidgets/ImmichFavoritesWidget.swift" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3601 [type: new]
Assertion: WidgetDataProvider expose fetchTimelineAssets(), fetchMemories(), fetchFavorites(), utilise Keychain pour token dans ImmichWidgets/WidgetDataProvider.swift.
Check post-impl: sh -c 'f=ImmichWidgets/WidgetDataProvider.swift; test -f "$f" && grep -qE "fetchTimelineAssets" "$f" && grep -qE "fetchMemories" "$f" && grep -qE "fetchFavorites" "$f" && grep -qE "keychain\|Keychain" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3602 [type: new]
Assertion: ImmichGridWidget expose TimelineProvider avec config système small (2x2) + medium (4x2), LazyVGrid photos.
Check post-impl: sh -c 'f=ImmichWidgets/ImmichGridWidget.swift; grep -qE "TimelineProvider" "$f" && grep -qE "systemSmall" "$f" && grep -qE "systemMedium" "$f" && grep -qE "LazyVGrid" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3603 [type: new]
Assertion: ImmichMemoriesWidget expose OnThisDay card avec year badge + asset grid (2x2), widgetURL pour deep link.
Check post-impl: sh -c 'f=ImmichWidgets/ImmichMemoriesWidget.swift; grep -qE "On This Day\|calendar\|OnThisDay" "$f" && grep -qE "widgetURL" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3604 [type: new]
Assertion: ImmichFavoritesWidget expose grid de favoris avec heart watermark + widgetURL.
Check post-impl: sh -c 'f=ImmichWidgets/ImmichFavoritesWidget.swift; grep -qE "favorite\|heart\|favorites" "$f" && grep -qE "widgetURL" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3605 [type: new]
Assertion: ImmichSwiftUIApp expose .widgetURL handler pour deep links widgets (app.immich://asset/{id}).
Check post-impl: sh -c 'grep -qE "widgetURL\|immich://asset" Sources/ImmichSwiftUIApp.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3606 [type: new]
Assertion: WidgetDataProviderTests expose ≥3 tests (fetch timeline, fetch memories, fetch favorites).
Check post-impl: sh -c 'f=Tests/WidgetDataProviderTests.swift; test -f "$f" && n=$(grep -cE "func test_" "$f"); test "$n" -ge 3 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3607 [type: new]
Assertion: ImmichWidgetsBundle expose ImmichGridWidget, ImmichMemoriesWidget, ImmichFavoritesWidget, BackupLiveActivity.
Check post-impl: sh -c 'f=ImmichWidgets/ImmichWidgetsBundle.swift; grep -qE "ImmichGridWidget" "$f" && grep -qE "ImmichMemoriesWidget" "$f" && grep -qE "ImmichFavoritesWidget" "$f" && grep -qE "BackupLiveActivity" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3608 [type: regression]
Assertion: Suite complète ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_widgets_test_summary.txt && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_widgets_test_summary.txt | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
