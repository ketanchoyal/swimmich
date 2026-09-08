# Task: stacks-ui

**Objectif** : Implémenter la gestion complète des stacks de photos (parité Flutter). Les endpoints stacks sont tous wire (7 méthodes : search/create/get/update/delete/removeAsset) et `StackSheet` existe dans le viewer, mais il n'y a pas de navigation dédiée ni de gestion full-stack. Le Flutter a un flux de stacking automatique + une gestion manuelle.

**Hypothèses** :
- `StackResponseDto` dans `DTOs.swift` expose `id`, `primaryAssetId`, `assets: [AssetResponseDto]`.
- `StackCreateDto` dans `DTOs.swift` expose `assetIds: [String]`.
- `StackUpdateDto` dans `DTOs.swift` expose `primaryAssetId: String`.
- `StackSheet.swift` dans PhotoViewer — permet de gérer les stacks d'un asset actuellement ouvert.
- `searchStacks(primaryAssetId:)` — recherche les stacks contenant un asset.
- `createStack(assetIds:)` — crée une nouvelle stack.
- `getStack(id:)` — details d'un stack.
- `updateStack(id:, primaryAssetId:)` — change le primary.
- `deleteStack(id:)` — supprime.
- `removeAssetFromStack(stackId:, assetId:)` — retire un asset.
- `getTimeBuckets` accepte `withStacked: Bool?` — le serveur retourne les stacks groupés.
- Le viewer a déjà un bouton "Stack" dans le menu — ouvre StackSheet.

**Approche retenue** : A — ajout d'une section de stacks dans le Me hub (comme Trash/Backup/Duplicates) + amélioration du StackSheet existant.
- **B (rejetée)** : onglet dédié. Inutile — les stacks sont secondaires.
- **C (rejetée)** : juste le StackSheet existant. Suffisant pour le viewer, mais pas pour la vue d'ensemble.

## Étapes

1. **StackView** — NEW `Sources/Features/Stacks/StackView.swift` :
   - Section dans le Me hub (accessible depuis ProfileView).
   - Liste des stacks récents / actifs.
   - Chaque stack row : thumbnail du primary asset + count d'assets.
   - Tap → montre les détails du stack (LazyVGrid des assets, changement du primary).
   - Bouton "Create stack" → picker d'assets → `createStack(assetIds:)`.
2. **StacksViewModel** — NEW `Sources/Features/Stacks/StacksViewModel.swift` :
   - `var stacks: [StackResponseDto]` — liste des stacks.
   - `var selectedStack: StackResponseDto?` — stack en cours de visualisation.
   - `func loadStacks()` — calls `searchStacks(primaryAssetId: nil)` pour tous les stacks.
   - `func createStack(assetIds: [String])` — `createStack(assetIds:)` + reload.
   - `func deleteStack(id: String)` — `deleteStack(id:)` + reload.
   - `func updatePrimary(stackId: String, assetId: String)` — `updateStack(id:primaryAssetId:)`.
   - `func removeAssetFromStack(stackId: String, assetId: String)` — `removeAssetFromStack(stackId:,assetId:)`.
3. **StackDetailSheet** — Améliorer `StackSheet.swift` existant dans PhotoViewer :
   - Affiche la pile complète des assets (pas seulement l'asset courant).
   - Bouton "Set as primary" sur chaque asset.
   - Bouton "Remove from stack".
   - Swipe to remove asset.
4. **Timeline integration** — Quand `withStacked: true`, les buckets retournent des stacks au lieu d'assets individuels. Le TimelineView doit :
   - Group les assets par stackId dans chaque bucket.
   - Afficher un composite thumbnail (primary + counter badge).
   - Tap → StackSheet avec tous les assets du stack.
5. **ProfileView** — Ajouter "Stacks" dans le Me hub (comme Trash/Backup/Duplicates).
6. **Tests** — `StacksViewModelTests` (loadStacks, create, delete, updatePrimary, removeAsset).
7. **xcodegen + suite**.

## Acceptance Contract

### Approches candidates
**A (retenue)** : StackView dans le Me hub + StackSheet amélioré + timeline groupé. Parity Flutter sans nouveau onglet.
**B** : Onglet dédié. Trop.
**C** : StackSheet uniquement. Pas de vue d'ensemble.

### Approche retenue + rationale
**A**. Gestion complète dans les surfaces existantes (Me hub + viewer), avec intégration timeline pour le groupement automatique.

### Critères

```
### AC-ST01 [type: new]
Assertion: StacksViewModel existe avec loadStacks, createStack, deleteStack, updatePrimary, removeAssetFromStack.
Check post-impl: sh -c 'f=Sources/Features/Stacks/StacksViewModel.swift; test -f "$f" && grep -q "func loadStacks" "$f" && grep -q "func createStack" "$f" && grep -q "func deleteStack" "$f" && grep -q "func updatePrimary" "$f" && grep -q "func removeAssetFromStack" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-ST02 [type: new]
Assertion: StackView existe (NEW file) — liste stacks + create + details.
Check post-impl: sh -c 'f=Sources/Features/Stacks/StackView.swift; test -f "$f" && grep -q "createStack" "$f" && grep -q "deleteStack" "$f" && grep -q "updatePrimary" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-ST03 [type: new]
Assertion: StackSheet amélioré — affiche tous les assets du stack, pas seulement l'asset courant.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/StackSheet.swift; grep -q "removeAsset\|Remove from stack\|setPrimary\|primaryAsset" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (partial)
Post-state attendu: PASS
```

```
### AC-ST04 [type: new]
Assertion: TimelineView intègre withStacked: true et groupement visuel des stacks.
Check post-impl: sh -c 'f=Sources/Features/Timeline/TimelineView.swift; grep -q "withStacked\|stackGroupId\|StackThumbnail\|composite" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-ST05 [type: new]
Assertion: ProfileView intègre un bouton "Stacks" dans le Me hub.
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfileView.swift; grep -q "Stacks\|stacks\|StackView" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-ST06 [type: new]
Assertion: Tests StacksViewModelTests ≥ 5 (loadStacks, create, delete, updatePrimary, removeAsset).
Check post-impl: sh -c 'f=Tests/StacksViewModelTests.swift; test -f "$f" && n=$(grep -c "func test_" "$f"); test "$n" -ge 5 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-ST07 [type: regression]
Assertion: Suite ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_stacks_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_stacks_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
