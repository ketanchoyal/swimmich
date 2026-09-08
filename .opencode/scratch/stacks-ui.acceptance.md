# Task: stacks-ui

Status: plan

## Plan

**Objectif**: Implémenter la gestion complète des stacks. Endpoints stacks 100% wire (7 méthodes), `StackSheet` dans viewer, mais pas de navigation dédiée.

**Hypothèses** (ground truth vérifié):
- `StackResponseDto`, `StackCreateDto`, `StackUpdateDto` dans DTOs.swift.
- `searchStacks`, `createStack`, `getStack`, `updateStack`, `deleteStack`, `removeAssetFromStack` wire dans ImmichClient.
- `StackSheet.swift` existe dans PhotoViewer.
- `getTimeBuckets`/`getTimeBucket` acceptent `withStacked: Bool?`.
- TimelineView affiche les buckets existants.

**Approche retenue**: A — StackView dans Me hub + StackSheet amélioré + timeline group stacking.
**B (rejetée)**: Onglet dédié → inutile.
**C (rejetée)**: StackSheet uniquement → pas de vue d'ensemble.

**Étapes**:
1. NEW `StacksViewModel.swift` (Features/Stacks/) — loadStacks(), createStack(assetIds:), deleteStack(id:), updatePrimary(stackId:,assetId:), removeAssetFromStack(stackId:,assetId:), stacks, selectedStack.
2. NEW `StackView.swift` (Features/Stacks/) — Liste stacks récents, FAB "+" pour create, navigation vers StackDetailView.
3. NEW `StackDetailView.swift` (Features/Stacks/) — Détails stack (primary asset + autres assets), update primary, remove asset.
4. NEW `CreateStackSheet.swift` (Features/Stacks/) — Choose photos + optional name → createStack.
5. EDIT `StackSheet.swift` (PhotoViewer) — Affiche pile complète des assets, "Set as primary" + "Remove from stack" par asset.
6. EDIT `TimelineView.swift` — Quand withStacked: true, group assets par stackId → composite thumbnail + "+N" badge.
7. EDIT `ProfileView.swift` — Ajouter "Stacks" navigation link dans Me hub.
8. Tests — `StacksViewModelTests` +5 (loadStacks, create, delete, updatePrimary, removeAsset).
9. Build + suite complète.

## Acceptance Contract

### Approches candidates
**A (retenue)**: StackView dans Me hub + StackSheet amélioré + timeline group stacking.
**B**: Onglet dédié → trop.
**C**: StackSheet uniquement → pas de vue d'ensemble.

### Approche retenue + rationale
**A**. Gestion complète dans surfaces existantes (Me hub + viewer).

### Critères

```
### AC-3700 [type: new]
Assertion: StacksViewModel expose loadStacks(), createStack(assetIds:), deleteStack(id:), updatePrimary(stackId:,assetId:), removeAssetFromStack(stackId:,assetId:) dans Sources/Features/Stacks/StacksViewModel.swift.
Check post-impl: sh -c 'f=Sources/Features/Stacks/StacksViewModel.swift; test -f "$f" && grep -qE "func loadStacks" "$f" && grep -qE "func createStack" "$f" && grep -qE "func deleteStack" "$f" && grep -qE "func updatePrimary" "$f" && grep -qE "func removeAssetFromStack" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3701 [type: new]
Assertion: StackView expose liste stacks récents, FAB "+" create, navigation vers StackDetailView dans Sources/Features/Stacks/StackView.swift.
Check post-impl: sh -c 'f=Sources/Features/Stacks/StackView.swift; test -f "$f" && grep -qE "createStack" "$f" && grep -qE "deleteStack" "$f" && grep -qE "updatePrimary" "$f" && grep -qE "plus" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3702 [type: new]
Assertion: StackDetailView expose primary asset (large), autres assets (small), update primary, remove from stack dans Sources/Features/Stacks/StackDetailView.swift.
Check post-impl: sh -c 'f=Sources/Features/Stacks/StackDetailView.swift; test -f "$f" && grep -qE "isPrimary" "$f" && grep -qE "updatePrimary\|setPrimary" "$f" && grep -qE "removeAssetFromStack" "$f" && grep -qE "deleteStack" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3703 [type: new]
Assertion: CreateStackSheet expose choose photos + optional stack name + CTA Create dans Sources/Features/Stacks/CreateStackSheet.swift.
Check post-impl: sh -c 'f=Sources/Features/Stacks/CreateStackSheet.swift; test -f "$f" && grep -qE "Choose Photos" "$f" && grep -qE "stackName" "$f" && grep -qE "Create" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3704 [type: new]
Assertion: StackSheet (PhotoViewer) expose tous les assets du stack (pas juste l'asset courant), "Set as primary" + "Remove from stack" par asset.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/StackSheet.swift; grep -qE "removeAssetFromStack\|Remove from stack" "$f" && grep -qE "setPrimary\|primaryAsset\|Set as primary" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (partial)
Post-state attendu: PASS
```

```
### AC-3705 [type: new]
Assertion: TimelineView intègre withStacked: true et groupement visuel des stacks (composite thumbnail + "+N" badge) dans TimelineView.swift.
Check post-impl: sh -c 'f=Sources/Features/Timeline/TimelineView.swift; grep -qE "withStacked" "$f" && grep -qE "stackGroupId\|composite\|stackThumbnail\|\\\\+\\d" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3706 [type: new]
Assertion: ProfileView expose "Stacks" navigation link vers StackView avec label "Stacks" et systemImage "square.stack.3d.down.right".
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfileView.swift; grep -qE "Stacks" "$f" && grep -qE "StackView" "$f" && grep -qE "square.stack.3d.down.right" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3707 [type: new]
Assertion: StacksViewModelTests expose ≥5 tests (loadStacks, create, delete, updatePrimary, removeAsset).
Check post-impl: sh -c 'f=Tests/StacksViewModelTests.swift; test -f "$f" && n=$(grep -cE "func test_" "$f"); test "$n" -ge 5 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3708 [type: regression]
Assertion: Suite complète ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_stacks_test_summary.txt && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_stacks_test_summary.txt | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
