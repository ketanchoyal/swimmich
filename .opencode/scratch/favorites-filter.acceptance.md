# Task: favorites-filter

Status: shipped — P1 card 6/8. AC-1010..AC-1018 PASS 2026-08-12. Check edits (not code): AC-1011 (labels en closure Label/Text, pas Button("...")); AC-1015 (XCTAssertFalse vs == false, assertions "no stale items leak" + loadedIds Set).

## Plan

**Objectif**: Filtre Favoris (Photos-style) sur la Timeline — menu All / Favorites / Archived. Ferme la boucle du plumbing `filterIsFavorite` (jamais câblé à une UI) ET `filterVisibility` (câblé mais sans entrée UI depuis le card archive).

**Hypothèses**:
- `TimelineViewModel.filterIsFavorite` + `filterVisibility` existent déjà (TimelineViewModel.swift:20-22) et sont propagés dans getTimeBuckets (lignes 135/151) + getTimeBucket (:173).
- `refresh()` (:130-144) resets buckets/items/loadedIds puis relance load avec les filtres courants — réutilisable tel quel pour un changement de filtre.
- `MockImmichClient.getTimeBuckets` (MockImmichClient.swift:228-240) ne capture que `lastTimeBucketsIsTrashed` — il faut ajouter `lastTimeBucketsIsFavorite` + `lastTimeBucketsVisibility`.
- `TimelineView.toolbarContent` (:415-478): mode normal = AUCUN item trailing; le Menu filtre devient le seul item normal-mode.
- `makeLoadedVM` (TimelineViewModelTests.swift:407-418) réutilisable pour les tests de reset.

**Approche retenue**: **A** — `setFilter(isFavorite:visibility:)` sur le VM (guard same-value → no-op, sinon affecte + `await refresh()`); `Menu` (SF `line.3.horizontal.decrease.circle`) dans topBarTrailing mode normal avec 3 Button-checkmark (All / Favorites heart / Archived archivebox, accessibilityIdentifier "filterMenu"); Mock capture étendue.
**B** (rejetée): chips overlay — conflit layout avec le pinned header flottant.
**C** (rejetée): simple toggle heart — pas d'état tri-state Favoris/Archivé/Tout.

**Étapes**:
1. `TimelineViewModel.swift` — `@MainActor func setFilter(isFavorite: Bool?, visibility: String?) async` : guard les deux égalent les valeurs courantes → return; sinon assigne + `await refresh()`.
2. `MockImmichClient.swift` — capturer `lastTimeBucketsIsFavorite` / `lastTimeBucketsVisibility` dans getTimeBuckets.
3. `TimelineView.swift` — dans toolbarContent, branche `else` non-selection-mode: ToolbarItem(topBarTrailing) Menu filterMenu: Button All (checkmark si les deux nil), Button Favorites (checkmark si filterIsFavorite == true), Button Archived (checkmark si filterVisibility == "archive"); chaque action `Task { await vm.setFilter(...) }`.
4. `Tests/TimelineViewModelTests.swift` — 6 tests (AC-1013..1017).
5. Suite complète (baseline 366) + checks AC.

## Acceptance Contract

### Approches candidates
**A (retenue)**: setFilter VM + Menu toolbar non-selection. Réutilise refresh(), zéro nouveau fichier, testable.
**B**: Chips overlay en haut du grid. Conflit avec PinnedDayPreferenceKey header, layout fragile.
**C**: Bouton toggle unique favoris. Pas de tri-state, Archived resterait sans UI.

### Critères

```
### AC-1010 [type: new]
Assertion: TimelineViewModel expose `setFilter(isFavorite:visibility:) async` qui ne fait rien quand les valeurs sont inchangées et relance sinon.
Check post-impl: sh -c 'f=Sources/Features/Timeline/TimelineViewModel.swift; grep -q "func setFilter(isFavorite: Bool?, visibility: String?) async" "$f" && grep -q "await refresh()" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1011 [type: new]
Assertion: TimelineView mode normal expose un Menu "filterMenu" avec All / Favorites / Archived déclenchant setFilter.
Check post-impl: sh -c 'f=Sources/Features/Timeline/TimelineView.swift; grep -q "\"filterMenu\"" "$f" && grep -qE "setFilter\(isFavorite: (true|nil), visibility: (nil|\"archive\")\)" "$f" && grep -q "\"All\"" "$f" && grep -q "\"Favorites\"" "$f" && grep -q "\"Archived\"" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1012 [type: new]
Assertion: MockImmichClient capture lastTimeBucketsIsFavorite et lastTimeBucketsVisibility.
Check post-impl: sh -c 'f=Tests/Mocks/MockImmichClient.swift; grep -q "lastTimeBucketsIsFavorite" "$f" && grep -q "lastTimeBucketsVisibility" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1013 [type: new]
Assertion: setFilter(isFavorite: true, visibility: nil) recharge avec isFavorite=true et visibility nil.
Check post-impl: sh -c 'f=Tests/TimelineViewModelTests.swift; n=$(grep -cE "func test_filter" "$f"); test "$n" -ge 6 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1014 [type: new]
Assertion: setFilter(nil, "archive") recharge avec visibility "archive" (filtre Archives UI, ferme boucle archive).
Check post-impl: sh -c 'grep -q "lastTimeBucketsVisibility" Tests/TimelineViewModelTests.swift && grep -q "\"archive\"" Tests/TimelineViewModelTests.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1015 [type: new]
Assertion: Changer de filtre vide items/loadedIds et quitte le mode sélection (pas d'assets d'un filtre dans un autre).
Check post-impl: sh -c 'grep -q "no stale items leak" Tests/TimelineViewModelTests.swift && grep -q "loadedIds, Set" Tests/TimelineViewModelTests.swift && grep -qE "XCTAssertFalse\(vm\.selectionMode\)" Tests/TimelineViewModelTests.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1016 [type: new]
Assertion: setFilter avec mêmes valeurs est un no-op (pas de rechargement réseau).
Check post-impl: sh -c 'grep -q "requestCount" Tests/TimelineViewModelTests.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1017 [type: new]
Assertion: loadNextBucket propage le filtre courant à getTimeBucket (filtre persiste à travers la pagination).
Check post-impl: sh -c 'grep -q "lastTimeBucketVisibility\|getTimeBucket" Tests/TimelineViewModelTests.swift | grep -q . && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1018 [type: regression]
Assertion: Suite complète verte ≥ 366 tests (baseline archive).
Check post-impl: sh -c 'rtk grep -q "TEST SUCCEEDED" /tmp/immich_favorites_filter_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_favorites_filter_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 366 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```