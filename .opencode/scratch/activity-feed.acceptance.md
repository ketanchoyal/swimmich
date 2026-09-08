# Task: activity-feed

Status: shipped — P3 3/5, AC-1080..AC-1086 PASS 2026-08-12 (436 tests, +10 vs 426). Test fix: 3 Boom assertions en contains (localizedDescription enveloppé par NSError); reentrancy flaky fix: statisticsGate dans MockImmichClient + sleep 200ms (async-let racy).

## Plan
**Objectif**: Album partagé — activité (comments + likes par asset), fill Feed planner P3. Composer commentaire, like/unlike par asset (reaction), suppression du sien, horodatage relatif. Native SwiftUI, testé, documenté.

**Hypothèses** (ground truth vérifié):
- Client P0 prêt: `getActivities(albumId:assetId:)` GET /api/activities, `createActivity(dto:)` POST (ActivityCreateDto{albumId,type comment|like,assetId?,comment?}), `deleteActivity(id:)` DELETE → 204 (ImmichClient.swift).
- `ActivityResponseDto{id,createdAt,type,user,assetId,comment?}` + `ReactionType{comment,like}` (DTOs+Social.swift:5-26); ActivityResponseDto NON Hashable.
- MockImmichClient :579-602 (activitiesResponse/activitiesError/lastActivitiesAlbumId/lastActivitiesAssetId/lastCreateActivityDto/lastDeleteActivityId).
- AlbumDetailView.swift (541L): menu ellipsis :165-220, sheet(item:) AlbumShareSheetItem pattern :6-9/227-231; auth.userId dispo; vm.albumId let:13.
- `UserAvatarCircle(user:size:)` réutilisable (DesignSystem/Components).
- AlbumDetailViewModel.client est **private** — pas d'accès direct: construire ActivityFeedViewModel via DependencyContainer.shared.client dans AlbumDetailView.

**Approche retenue**: A — VM dédié `ActivityFeedViewModel` (client, albumId, currentUserId) + sheet `ActivityFeedSheet` présentée par AlbumDetailView via item wrapper (.sheet(item:)); composer + rows + like toggle + delete propre; try-then-mutate discipline (comment est ensuite supprimé du state); feed complet (sans assetId) trié createdAt desc; `hasMyLike(_:)` par currentUserId; delete limité (serveur garde l'autorisation). Feed = pas de fichier dans AlbumDetailViewModel (déjà 298L).
**B** (rejeté): intégration in AlbumDetailViewModel — gonfle le VM existant, mélange des responsabilités.
**C** (rejeté): slot feed inline sous la grille — coût scroll, pas le pattern Flutter (feed = detail).

**Étapes**:
1. `Sources/Core/Protocols/…` rien (protocole saturé).
2. NEW `Sources/Features/Albums/ActivityFeedViewModel.swift` — @Observable @MainActor: activities sorted desc (chronologique), isLoading, errorMessage (propre), load(), addComment(_:), like(assetId:), unlike(activityId:), toggleLike(activity:), deleteActivity(id:), hasMyLike. Like avec try-then-mutate: post create → refresh (pas de splice hasard).
3. NEW `Sources/Features/Albums/ActivityFeedSheet.swift` — composer (TextField "Add a comment…" + send arrow.up.circle.fill immichPrimary, disabled si vide/busy/saving), Section rows: avatar user + name pvBody + comment pvCaption (ou heart.fill si like) + mini thumbnail asset (AuthenticatedAsyncImage 28) si assetId non-vide + temps relatif (RelativeDateTimeFormatter) + heart toggle (hasMyLike) + trash (deleteActivity, couleur immichError) — accessibilityIdentifier activityLikeToggle-<id>/activityDelete-<id>; ContentUnavailableView si vide.
4. AlbumDetailView.swift: `@State activityFeedItem: ActivityFeedSheetItem?` + NEW private struct ActivityFeedSheetItem: Identifiable (id UUID + vm) + menu ellipsis Button "Activity" (bubble.left.and.bubble.right) avant Divider Shared Links? — après "Select", avant "Shared Links"; .sheet(item: $activityFeedItem) { ActivityFeedSheet(vm: $0.vm) } (detents .medium/.large + .presentationDragIndicator(.visible)); construction: ActivityFeedViewModel(client: DependencyContainer.shared.client, albumId: vm.albumId, currentUserId: auth.userId ?? "").
5. Tests — NEW `Tests/ActivityFeedViewModelTests.swift`: @MainActor class, helper makeActivity(id:createdAt:type:comment:assetId:userId:) + makeUser helper (UserResponseDto 5 champs ordinal: id,name,email,profileImagePath,avatarColor,profileChangedAt) + mock; tests: load_mapsSortedByCreatedAtDesc, load_failure_setsError, addComment_sendsAlbumCommentDto (lastCreateActivityDto albumId/type .comment/comment + activities prepend + composed), addComment_emptyIsNoOp (requestCount), addComment_failure_keepsClean (errorMessage, 0 row), like_createsLikeForAsset (dto type .like + assetId + hasMyLike vrai), like_removesOwnLike (deleteActivity id + hasMyLike faux), toggleLike_sendsDeleteWhenMine (like existant → deleteActivityCallCount), deleteOwnComment_callsAndRemoves (lastDeleteActivityId), delete_failure_keepsRow.
6. `xcodegen generate` (3 nouveaux fichiers) + build-for-testing.
7. Suite complète (baseline 426) → /tmp/immich_activity_test_summary.txt.
8. ACs + memory.md entry + Status shipped.

## Acceptance Contract

### Approches candidates
**A (retenue)**: VM dédié + sheet(item:). Découplé, pattern sheet existant (AlbumShareSheetItem), testable pur (mock client, pas de UI).
**B**: Tout dans AlbumDetailViewModel + section inline — VM existant gonflé 30%, feed perdu dans le scroll.
**C**: Sheet géant tout-en-un (VM + vue même fichier) — convié antipattern codebase.

### Approche retenue + rationale
**A**. Sheet = pattern éprouvé (SharedLinks/AlbumShare), VM dédié testable 10 cas, réponse serveur sans tri local fragile — sort desc VM-side. currentUserId injecté pour hasMyLike sans reach auth global.

### Critères

```
### AC-1080 [type: new]
Assertion: `ActivityFeedViewModel` existe avec load(), addComment(_:), toggleLike(activity:), deleteActivity(id:) + errorMessage propre; activités triées createdAt desc.
Check post-impl: sh -c 'f=Sources/Features/Albums/ActivityFeedViewModel.swift; test -f "$f" && grep -qE "func (load|addComment|toggleLike|deleteActivity)" "$f" && grep -q "sorted" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-1081 [type: new]
Assertion: addComment envoie ActivityCreateDto(albumId:type:.comment,comment:) et toggleLike envoie type .like + assetId; createActivity/deleteActivity appelés sur le client.
Check post-impl: sh -c 'f=Sources/Features/Albums/ActivityFeedViewModel.swift; grep -qE "type: \.comment" "$f" && grep -qE "type: \.like" "$f" && grep -qE "createActivity|deleteActivity" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1082 [type: new]
Assertion: ActivityFeedSheet existe avec composer TextField + bouton send, toggle like/delete par row, thumbnail asset si assetId non vide.
Check post-impl: sh -c 'f=Sources/Features/Albums/ActivityFeedSheet.swift; test -f "$f" && grep -q "TextField" "$f" && grep -qE "heart|toggleLike" "$f" && grep -qE "AuthenticatedAsyncImage" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-1083 [type: new]
Assertion: AlbumDetailView expose "Activity" dans le menu ellipsis + présente ActivityFeedSheet via .sheet(item:).
Check post-impl: sh -c 'f=Sources/Features/Albums/AlbumDetailView.swift; grep -q "Activity" "$f" && grep -qE "activityFeedItem" "$f" && grep -qE "ActivityFeedSheet" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1084 [type: new]
Assertion: Tests ActivityFeedViewModel >= 9 funcs test_ (load/sort/failure/addComment/like/unlike/delete).
Check post-impl: sh -c 'test -f Tests/ActivityFeedViewModelTests.swift && n=$(grep -cE "^    func test_" Tests/ActivityFeedViewModelTests.swift); test "${n:-0}" -ge 9 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-1085 [type: new]
Assertion: ReactionType comment|like déjà dans le modèle partagé (utilisé par le VM, pas de réécriture locale).
Check post-impl: sh -c 'grep -q "case comment" Sources/Core/Types/DTOs+Social.swift && grep -q "case like" Sources/Core/Types/DTOs+Social.swift && echo PASS || echo FAIL'
Pre-state attendu: PASS (P0)
Post-state attendu: PASS
```

```
### AC-1086 [type: regression]
Assertion: suite complète >= 426 tests, 0 échec (TEST SUCCEEDED).
Check post-impl: sh -c 'rtk grep -q "TEST SUCCEEDED" /tmp/immich_activity_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_activity_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1); test "${n:-0}" -ge 426 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (résumé inexistant)
Post-state attendu: PASS
```