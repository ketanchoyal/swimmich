# Task: stacks-ui

> **Révision 2026-09-13 — implémenté et clôturé. La carte `.opencode/scratch/stacks-ui.acceptance.md` (AC-3700…3711, 12/12 PASS) fait foi ; ce document est conservé comme plan d'origine, avec les corrections ci-dessous.**
>
> Ce qui, dans ce plan, ne correspondait pas au dépôt :
> 1. **Pas de nom de pile.** `StackCreateDto` = `{ assetIds: [String] }`, min 2 (`server/src/dtos/stack.dto.ts`) : le serveur n'accepte aucun nom. `CreateStackSheet` n'a donc **aucun champ texte**.
> 2. **`StackSheet` n'avait rien à améliorer.** Elle listait déjà tous les membres, avec set-primary, remove et unstack (c'était l'AC-ST03 du plan — **déjà PASS avant implémentation**). Elle est restée telle quelle ; le vrai manque était la vue d'ensemble (hub) et le routage du tap timeline.
> 3. **`withStacked` n'est pas un simple « include ».** Vérifié dans `server/src/repositories/asset.repository.ts` (`getTimeBucket`) : quand il est vrai, le serveur **exclut du bucket tous les non-primaires** d'une pile et n'émet la colonne `stack` que dans ce cas, sous forme de tuples `[stackId, assetCount]` — **count sérialisé en chaîne et couverture incluse**. Conséquences encodées dans le code : le badge lit `Int(stack[1]) - 1` (jamais `stack.count`, toujours 2), et une tuile empilée **ouvre la pile** au lieu du pager plat (sinon ses membres sont inatteignables).
> 4. **Le groupement visuel n'est pas côté client.** Le serveur ne renvoie que la couverture : il n'y a rien à grouper dans le bucket, seulement un compteur à afficher et un tap à router. `TimelineView` n'a donc pas de logique de regroupement, contrairement à l'étape 4 du plan.
> 5. **`TimelineView` garde son `NavigationStack`** ; `StackView` n'en a pas (elle est poussée depuis la sheet «Me», comme `TagsView`). L'UI brief montrait l'inverse — ne pas le suivre. Les `glassEffectID`/`glassEffectTransition` proposés par l'UI brief n'ont pas été introduits : le dépôt n'en utilise nulle part.
> 6. **« Ajouter un asset à une pile » n'a aucune route dédiée.** Vérifié sur l'OpenAPI publié (`main` : 7 opérations ; `v1.135.0` : 6) et sur `stack.controller.ts` — le `POST /api/assets/:stackId/assets` de ce plan **n'existe pas**. L'ajout passe par le contrat de fusion de `POST /api/stacks` : payload avec la **couverture en tête**, réponse portant un **id neuf** que l'app doit suivre. `StackPhotoPicker` (grille partagée) + `CreateStackSheet` + `AddToStackSheet` couvrent création et extension.
> 7. **Un tap de grille ne doit pas être enveloppé dans un `Button`** : `AssetThumbnailCell` porte son propre `onTapGesture`, qui gagne et avale le tap. Le picker passe par `onTap:`.
>
> Résultat : 724 tests TEST SUCCEEDED (baseline 695) ; `Sources/Features/Stacks/` = `StacksViewModel`, `StackView`, `StackDetailView`, `StackPhotoPicker`, `CreateStackSheet`, `AddToStackSheet` ; 3 scénarios XCUITest de bout en bout (badge→détail→hub, ajout à une pile, création depuis le hub).

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
