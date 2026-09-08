# Task: partner-sharing

Status: shipped — AC-1070..AC-1076 PASS 2026-08-12 (426 tests, suite verte).

## Plan
**Objectif**: Partner sharing (Flutter parity): list partners in the Shared tab, per-partner "show in timeline" toggle + remove, and a "Shared with you" timeline filter (partner photos interleaved in the timeline).

**Hypothèses**:
- Client P0 ready: `getPartners()`, `updatePartner(id:isInTimeline:)` (PUT /api/partners/{id}), `removePartner(id:)` (DELETE) — ImmichClient + MockImmichClient stubs (:554-575, captures :131-135).
- `getTimeBuckets`/`getTimeBucket` accept `withPartners: Bool?` (P0 expansion) — TimelineViewModel currently passes literal `nil` at 2 + 1 call sites (refresh :147, load :163, loadNextBucket :185).
- `TimelineViewModel.setFilter(isFavorite:visibility:)` (:62) guards no-op on unchanged values; extend with `withPartners` while keeping a default so existing call sites/tests compile untouched.
- SharedLinksView lists links in a `List`; empty/error/loading branches (:20-48). Partner section goes into the list when the list is shown, and replaces the "empty" ContentUnavailable when links are empty but partners exist.
- Partner avatar = initials circle on `Color(hex: avatarColor)` (UserAvatarCircle pattern, but PartnerResponseDto ≠ UserResponseDto — inline local helper).

**Approche retenue**: A — extend `setFilter` (default nil) + `filterWithPartners` state wired into all three bucket calls; SharedLinksViewModel gains partners state + 3 methods (try-then-mutate); SharedLinksView adds a "Shared with you" List Section (toggle + trash per row, confirmation dialog on remove). **B** (partner Assets tab séparé) rejeté: per-partner asset fetch n'existe pas côté serveur (timeline API booléen, pas par-partner). **C** (suppression toggle, simple liste) rejeté: inTimeline est le cœur de la fonctionnalité.

**Étapes**:
1. `TimelineViewModel.swift` — `var filterWithPartners: Bool?`; `setFilter(isFavorite:visibility:withPartners: = nil)` no-op guard `filterWithPartners != withPartners || filterIsFavorite != isFavorite || filterVisibility != visibility`; refresh/load/loadNextBucket pass `withPartners: filterWithPartners`.
2. `TimelineView.swift` — énième item Menu "Shared with you" (person.2), `setFilter(isFavorite: nil, visibility: nil, withPartners: true)`, checkmark si `filterWithPartners == true`.
3. `SharedLinksViewModel.swift` — `partners: [PartnerResponseDto]`, `isPartnersLoading`, `partnersError`; `loadPartners()`; `togglePartnerTimeline(id:enabled:)` (updatePartner + replace row); `removePartner(id:)` (delete puis removeAll).
4. `SharedLinksView.swift` — `.task` charge partners; `linkList` : Section "Shared with you" au-dessus des liens (si partners non vides); branche "empty" → List avec partners seuls s'il y en a, sinon ContentUnavailable; PartnerRow (avatar initials + name + Toggle + trash → confirmationDialog); `.refreshable` recharge partners.
5. `MockImmichClient.swift` — captures `lastTimeBucketsWithPartners` + `lastTimeBucketWithPartners`.
6. Tests — `SharedLinksViewModelTests` +4 (loadPartners, failure, toggle envoie updatePartner + row remplacé, remove); `TimelineViewModelTests` +2 (sharedWithYou → lastTimeBucketsWithPartners true; no-op extension).
7. Build + suite complète (baseline 419) → summary /tmp/immich_partner_test_summary.txt.
8. AC checks → Status shipped + entry memory.md.

## Acceptance Contract

### Approches candidates
- **A (retenue)**: extension filter existence + section partners dans Shared tab. Couvre le booléen serveur, zéro nouveau endpoint, tout testable.
- **B**: onglet/écran partner dédié avec assets par partner. Serveur ne supporte pas le filtre par-partner → non faisable proprement.
- **C**: liste partners statique sans toggle inTimeline. Moitié de la feature.

### Critères

```
### AC-1070 [type: new]
Assertion: TimelineViewModel expose filterWithPartners et le passe aux 3 appels bucket (refresh, load, loadNextBucket).
Check post-impl: sh -c 'f=Sources/Features/Timeline/TimelineViewModel.swift; n=$(grep -c "filterWithPartners" "$f"); test "$n" -ge 4 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1071 [type: new]
Assertion: Menu de filtre Timeline propose "Shared with you" (withPartners: true).
Check post-impl: sh -c 'f=Sources/Features/Timeline/TimelineView.swift; grep -q "Shared with you" "$f" && grep -q "withPartners: true" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1072 [type: new]
Assertion: SharedLinksViewModel expose partners + loadPartners/togglePartnerTimeline/removePartner.
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/SharedLinksViewModel.swift; grep -q "var partners" "$f" && grep -q "func loadPartners" "$f" && grep -q "func togglePartnerTimeline" "$f" && grep -q "func removePartner" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1073 [type: new]
Assertion: SharedLinksView affiche une section "Shared with you" avec toggle inTimeline + confirmation de retrait.
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/SharedLinksView.swift; grep -q "Shared with you" "$f" && grep -q "removePartner" "$f" && grep -q "confirmationDialog" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1074 [type: new]
Assertion: MockImmichClient capture lastTimeBucketsWithPartners + lastTimeBucketWithPartners.
Check post-impl: sh -c 'f=Tests/Mocks/MockImmichClient.swift; grep -q "lastTimeBucketsWithPartners" "$f" && grep -q "lastTimeBucketWithPartners" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1075 [type: new]
Assertion: Tests couvrent partners (VM) + filtre withPartners (timeline).
Check post-impl: sh -c 'n=$(grep -rl "test_partner\|test_filter_shared" Tests/ | wc -l | tr -d " "); m=$(grep -c "func test_" Tests/SharedLinksViewModelTests.swift); test "$n" -ge 2 && test "$m" -ge 8 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1076 [type: regression]
Assertion: Suite complète verte, ≥ baseline 419.
Check post-impl: sh -c 'rtk grep -q "TEST SUCCEEDED" /tmp/immich_partner_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_partner_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 419 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (pas de summary)
Post-state attendu: PASS
```