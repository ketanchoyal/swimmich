# Task: timeline-premium-enhancement

## Plan
Enhance timeline to Apple-Photos-grade premium SwiftUI experience. iOS 17 target.

### Objective
- Fix #1 non-premium smell: image cache (no refetch/flicker on scroll).
- Add interaction premium: selection mode (long-press → batch favorite/delete), context menus, pull-to-refresh, scroll-to-top.
- Add motion polish: pinned section headers, scrollTransition parallax, sensoryFeedback haptics, video duration badge, 360° badge.

### Hypotheses (to be confirmed by scout)
1. iOS 17 supports: `LazyVStack(pinnedViews:)`, `.scrollTransition`, `.sensoryFeedback`, `.refreshable`, `ScrollViewReader`, `.contextMenu`, `NSCache`, `URLCache`, `PhaseAnimator`/`.contentTransition(.opacity)`. NOT `.navigationTransition(.zoom)` (iOS 18) — avoid.
2. `AssetReactItem.duration` is in seconds (Int?). `projectionType == "equirectangular"` ⇒ 360°.
3. `thumbhash` is a base64 string of the thumbhash binary format (needs a decoder). RISK: no decoder in repo. Decision: implement a small pure-Swift thumbhash decoder (well-documented algorithm, ~120 LOC) OR fallback to tinted shimmer placeholder. Mark V10 best-effort; not an AC.
4. No new ImmichClient endpoints required. `updateAsset` + `deleteAssets` already exist for selection actions.
5. `MockImmichClient` supports `updateAssetResponse`, `lastUpdateAssetId`, `lastUpdateAssetBody`, `deleteError`, `requestCount`.

### Steps
1. `ImageCache.swift` (actor, NSCache + URLCache-backed URLSession).
2. `AuthenticatedAsyncImage` uses cache; thumbhash/shimmer placeholder.
3. `AssetReactItem.with(isFavorite:)`.
4. `TimelineViewModel`: selection state + `toggleFavorite(id:)` + `deleteSelected()` + `refresh()`.
5. `TimelineView`: pinned headers, refreshable, scroll-to-top, selection UI, context menus, sensoryFeedback.
6. `AssetThumbnailCell`: selection checkmark, duration badge, 360° badge, context menu, scrollTransition.
7. Tests: `ImageCacheTests` (AC-200), `TimelineViewModelTests` additions (AC-201..205).

## Acceptance Contract

### Approaches candidates
- A "Silky Scroll" (perf-first): cache + thumbhash + refresh + scroll-to-top + badges.
- B "Interactive Grid" (interaction-first): cache + selection mode + context menus + refresh.
- C "Apple Photos Clone" (full): A + B + iOS 17 motion (pinned headers, scrollTransition, sensoryFeedback).

### Approche retenue + rationale
**C**. Cache is the hard prereq in all approaches (risk concentrated there). Selection mode is what makes a photo grid feel alive (uses existing endpoints, no backend). iOS 17 modifiers are declarative + compile-time safe + 3-10 lines each — best premium-per-risk. Additive only: existing tests untouched.

### Critères

```
### AC-100 [type: new]
Assertion: a passing test asserts groupedByDay semantics — groups by fileCreatedAt.prefix(10), day-sorted desc, items within day sorted desc by fileCreatedAt. (Behavior pre-exists but had ZERO test coverage — challenger found test_AC_013 never touches groupedByDay. Adding real coverage now.)
Check post-impl: xcodebuild test -only-testing:.../TimelineViewModelTests/test_AC_100_groupedByDay → PASS (test seeds 2 buckets across 3 distinct days out of order, asserts group keys, day order desc, intra-day order desc)
Pre-state attendu: 0 tests ran (test_AC_100_groupedByDay does not exist; groupedByDay untested)
Post-state attendu: PASS

### AC-101 [type: regression]
Assertion: bucket-level pagination accumulates with no dup IDs; loadMore past last bucket no-op; canLoadMore == bucketIndex < buckets.count.
Check post-impl: xcodebuild test -only-testing:.../test_AC_006_bucketPaginationNoDuplicates → PASS
Pre-state attendu: PASS
Post-state attendu: PASS

### AC-102 [type: regression]
Assertion: TimelineViewModel constructable with MockImmichClient; load() populates items; requestCount > 0.
Check post-impl: xcodebuild test -only-testing:.../test_AC_009_MVVMTestability → PASS
Pre-state attendu: PASS
Post-state attendu: PASS

### AC-103 [type: regression]
Assertion: thumbnailURL canonical /api/assets/{id}/thumbnail?size=thumbnail&c={thumbhash}.
Check post-impl: xcodebuild test -only-testing:.../test_AC_007_thumbnailURL → PASS
Pre-state attendu: PASS
Post-state attendu: PASS

### AC-104 [type: regression]
Assertion: AssetReactItem.zip() returns [] on length-mismatched required arrays.
Check post-impl: xcodebuild test -only-testing:.../test_AC_013b_zipRejectsMalformed → PASS
Pre-state attendu: PASS
Post-state attendu: PASS

### AC-200 [type: new]
Assertion: ImageCache is a thread-safe store. store(img,url) then retrieve(url) returns the same UIImage. Miss returns nil. Concurrent access safe.
Check post-impl: xcodebuild test -only-testing:.../ImageCacheTests → PASS (test_cacheStoreAndRetrieve, test_cacheMissReturnsNil, test_cacheThreadSafety)
Pre-state attendu: 0 tests ran (ImageCacheTests does not exist)
Post-state attendu: PASS

### AC-201 [type: new]
Assertion: TimelineViewModel exposes selectedIds:Set<String> (initially empty). toggleSelection(id:) toggles membership. selectionMode default false; enterSelectionMode()→true; exitSelectionMode()→false AND clears selectedIds.
Check post-impl: xcodebuild test -only-testing:.../TimelineViewModelTests/test_AC_201_selectionState → PASS
Pre-state attendu: FAIL (symbols do not exist → compile error)
Post-state attendu: PASS

### AC-202 [type: new]
Assertion: toggleFavorite(id:) calls client.updateAsset(id:dto:) with isFavorite toggled vs current item.isFavorite, then replaces the item in items via with(isFavorite:).
Check post-impl: xcodebuild test -only-testing:.../TimelineViewModelTests/test_AC_202_toggleFavorite → PASS
Pre-state attendu: FAIL (compile error)
Post-state attendu: PASS (verifies lastUpdateAssetId, lastUpdateAssetBody.isFavorite, items reflects new value)

### AC-203 [type: new]
Assertion: deleteSelected() on SUCCESS calls client.deleteAssets(ids:selectedIds, force:false), then removes those ids from items + loadedIds, then exits selection mode. Empty selectedIds ⇒ no call, state unchanged.
Check post-impl: xcodebuild test -only-testing:.../TimelineViewModelTests/test_AC_203_deleteSelected → PASS
Pre-state attendu: FAIL (compile error)
Post-state attendu: PASS (verifies: 2/4 selected → deleteAssets called with exactly those 2 ids, force=false; items.count==2; loadedIds no longer contains them; remaining ids correct; selectionMode false after)

### AC-203b [type: new]
Assertion: deleteSelected() on THROW leaves items + loadedIds UNCHANGED, sets errorMessage from the thrown error, preserves selectedIds (so user can retry), does NOT exit selection mode.
Check post-impl: xcodebuild test -only-testing:.../TimelineViewModelTests/test_AC_203b_deleteSelectedError → PASS
Pre-state attendu: FAIL (compile error)
Post-state attendu: PASS (verifies: mock.deleteError set → deleteSelected leaves items.count unchanged, loadedIds unchanged, errorMessage non-nil, selectedIds preserved, selectionMode still true)
Implementation note: MUST call deleteAssets BEFORE mutating arrays (try-then-mutate, never mutate-then-try).

### AC-204 [type: new]
Assertion: refresh() re-fetches buckets then first bucket only (items reset); requestCount increases; canLoadMore true again. Implicitly exits selection mode.
Check post-impl: xcodebuild test -only-testing:.../TimelineViewModelTests/test_AC_204_refresh → PASS
Pre-state attendu: FAIL (compile error)
Post-state attendu: PASS

### AC-205 [type: new]
Assertion: AssetReactItem.with(isFavorite:) returns new instance with new isFavorite, all else identical; original unchanged; Equatable/Hashable intact.
Check post-impl: xcodebuild test -only-testing:.../TimelineViewModelTests/test_AC_205_withIsFavorite_copy → PASS
Pre-state attendu: FAIL (compile error)
Post-state attendu: PASS
```

### Failure modes (top 3 + quel AC les détecte)
1. **Cache returns stale image after server-side thumbnail change.** Cache key = full URL incl `?c={thumbhash}` query (already in thumbnailURL). Server changing thumbhash → new URL → natural invalidation. AC-200 proves cache mechanics. Out-of-scope: server reusing same thumbhash after edit.
2. **Selection + pagination/refresh race.** selectedIds keyed by id survives loadMore (Set semantics). refresh() calls exitSelectionMode() → no orphan selections. AC-201 (exit clears) + AC-204 (refresh resets) cover it.
3. **scrollTransition + pinned headers layout clash (iOS 17 known edge).** Mitigation: scrollTransition on cell content only, not Section container. Caught by manual verification V3/V13.

## Vérifications manuelles (hors auto-feedback loop)
- V1 pull-to-refresh spinner + reload.
- V2 scroll-to-top floating button hides at top.
- V3 pinned section headers stick.
- V4 long-press → selection haptic + checkmarks + toolbar.
- V5 tap toggle checkmark + count + haptic.
- V6 cancel / background-tap exits selection, clears selectedIds.
- V7 batch favorite: toolbar heart → API → overlay update + haptic .success.
- V8 batch delete: trash → confirm alert → cells animate out + haptic .warning.
- V9 context menu Favorite/Delete.
- V10 thumbhash/shimmer placeholder before load (best-effort; fallback tinted shimmer if thumbhash decoder not feasible).
- V11 video duration badge mm:ss / 0:ss.
- V12 360° badge for projectionType == "equirectangular".
- V13 scrollTransition parallax smooth, no judder.
- V14 no refetch on scroll-back (network proxy confirms zero new requests for cached URLs).
- V15 existing tests still green.

## Files
- NEW Sources/Services/ImageCache.swift
- NEW Tests/ImageCacheTests.swift
- MODIFY Sources/Services/AuthenticatedAsyncImage.swift (cache + placeholder)
- MODIFY Sources/Core/Types/AssetReactItem.swift (with(isFavorite:))
- MODIFY Sources/Features/Timeline/TimelineViewModel.swift (selection, toggleFavorite, deleteSelected, refresh)
- MODIFY Sources/Features/Timeline/TimelineView.swift (pinned headers, refreshable, scroll-to-top, selection UI, context menus, sensoryFeedback)
- MODIFY Sources/Features/Timeline/AssetThumbnailCell.swift (checkmark, badges, context menu, scrollTransition)
- MODIFY Tests/TimelineViewModelTests.swift (AC-201..205)

## Scout verification (Phase 1, post-approval)
All 5 contract hypotheses PASS. 4 impl-detail corrections (test-fixture level, NO AC-structure impact):
1. `MockImmichClient.getAssetResponse` is `[String: AssetResponseDto]` (dict), not single. AC-202 fixture: `mock.getAssetResponse[id] = base`.
2. `MockImmichClient.lastUpdateMethod` is `HTTPMethod?` enum, not `String?`. No AC asserts on it.
3. `MockImmichClient.deleteAssets` mutates `requestCount`+`lastDeleteBody` BEFORE throwing. AC-203b tests VM-side state (items/loadedIds/selectedIds/selectionMode) — mock internals irrelevant. VM still does try-then-mutate.
4. `columnar()` helper returns `TimeBucketAssetResponseDto`, not `[AssetReactItem]`. AC-100 fixture: `let items = AssetReactItem.zip(columnar(...))`.
