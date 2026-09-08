# Task: duplicates

Status: shipped — AC-1120..AC-1124 PASS 2026-08-12 (454 tests, +8). Note: deleteGroup drops locally without reload (server duplicate job may re-return group until re-run).

## Plan
**Objectif**: Détection + nettoyage des doublons (parity Flutter). `GET /api/duplicates` → groupes; chaque groupe garde `suggestedKeepAssetIds`, suppression du reste via `deleteAssets(force:false)`. Entrée: NavigationLink "Duplicates" dans ProfileView.

**Hypothèses**:
- Client P0 ready: `getDuplicates()` → `[DuplicateResponseDto{duplicateId, assets: [AssetResponseDto], suggestedKeepAssetIds: [String]}]` (DTOs+Social.swift:58-61); MockImmichClient.getDuplicates :614-618 (`duplicatesResponse ?? []`, throw sharedLinksError).
- ProfileView (60L, réécrit P1): Form sections Compte/Stockage/Gestion (Trash, Backup) — NavigationLink pattern existant (Trash/Backup).
- `deleteAssets(ids:force:)` client + mock (captures lastDeleteBody, deleteError).
- Convention: try-then-mutate; mock globalError APRÈS seed load.

**Approche retenue**: A — DuplicatesViewModel @Observable @MainActor (load/deleteGroup: ids = assets − suggestedKeep, reload après succès) + DuplicatesView (groupes en cartes, grid assets avec badge "Keep" sur suggested, bouton delete par groupe + confirmationDialog) + NavigationLink ProfileView "Duplicates" (photo.on.rectangle.angled). **B** (rejetée): auto-delete sans confirm. **C** (rejetée): section dans Search.

**Étapes**:
1. Card écrite.
2. NEW `Sources/Features/Duplicates/DuplicatesViewModel.swift`.
3. NEW `Sources/Features/Duplicates/DuplicatesView.swift`.
4. ProfileView: NavigationLink "Duplicates" (menu Gestion).
5. NEW `Tests/DuplicatesViewModelTests.swift`.
6. xcodegen generate + build-for-testing + suite → /tmp/immich_duplicates_test_summary.txt.
7. Checks AC + memory.md + Status shipped.

## Acceptance Contract

### Approches candidates
**A (retenue)**: VM dédié + vue groupes + confirm delete. Testable, safe.
**B**: Auto-delete. Risqué.
**C**: Dans Search. Mauvais slot.

### Approche retenue + rationale
**A**. Pattern codebase; try-then-mutate; confirmation utilisateur.

### Critères

```
### AC-1120 [type: new]
Assertion: DuplicatesViewModel existe: groups, load(), deleteGroup(id:) qui supprime assets hors suggestedKeepAssetIds.
Check post-impl: sh -c 'f=Sources/Features/Duplicates/DuplicatesViewModel.swift; test -f "$f" && grep -q "func load() async" "$f" && grep -q "func deleteGroup" "$f" && grep -q "suggestedKeepAssetIds" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1121 [type: new]
Assertion: DuplicatesView existe: groupes + grid assets + badge Keep sur suggested + delete confirm.
Check post-impl: sh -c 'f=Sources/Features/Duplicates/DuplicatesView.swift; test -f "$f" && grep -q "confirmationDialog" "$f" && grep -q "Keep" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1122 [type: new]
Assertion: ProfileView contient NavigationLink "Duplicates".
Check post-impl: sh -c 'grep -q "Duplicates" Sources/Features/Profile/ProfileView.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1123 [type: new]
Assertion: Tests DuplicatesViewModelTests ≥ 4 (load/failure/deleteGroup envoie ids corrects/keep).
Check post-impl: sh -c 'f=Tests/DuplicatesViewModelTests.swift; n=$(grep -c "func test_" "$f"); test "$n" -ge 4 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1124 [type: regression]
Assertion: Suite complète ≥ 446 tests, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_duplicates_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_duplicates_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 446 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
