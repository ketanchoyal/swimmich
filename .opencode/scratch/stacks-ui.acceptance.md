# Task: stacks-ui

Status: done — 10/10 AC PASS (2026-09-13). Suite complète **719 tests, TEST SUCCEEDED** (iPhone 17, baseline mesurée 695 avant implémentation) ; harnais XCUITest de bout en bout `ImmichRenderScreenshots/test_03_stacksBadgeDetailAndHub` vert (badge de pile → détail → hub «Me», captures `/tmp/shot-1{1,2,5}-*.png`).

## Résultat (2026-09-13)

| AC | Résultat | Preuve |
|----|----------|--------|
| AC-3700 | PASS | `StacksViewModel` + 5 méthodes ; `StacksViewModelTests` (13 tests) |
| AC-3701 | PASS | `StackView` (sans `NavigationStack` propre) + `CreateStackSheet` + swipe Unstack |
| AC-3702 | PASS | `StackDetailView` : cover, set primary, remove, unstack, viewer sur les membres |
| AC-3703 | PASS | `CreateStackSheet` : multi-sélection, seuil 2, aucun champ de nom (le serveur n'en accepte pas) |
| AC-3704 | PASS | `TimelineView` : `navigationDestination(item:)` → `StackDetailView` pour une tuile empilée |
| AC-3705 | PASS | `TimelineViewModel.withStacked = true` (6 sites) + badge `stackCount` dans `AssetThumbnailCell` |
| AC-3706 | PASS | Lien «Stacks» dans la section Management de `ProfileView` |
| AC-3707 | PASS | `Tests/StacksViewModelTests.swift` — 13 tests |
| AC-3708 | PASS | 719 tests, TEST SUCCEEDED |
| AC-3709 | PASS | 7 tests de transport sur les routes stacks (`ImmichAPIClientTests`) + XCUITest de bout en bout |

**Tests ajoutés (24)** : `StacksViewModelTests` (13), `ImmichAPIClientTests` stacks (7 : search, filtre `primaryAssetId`, create, update primary, delete, remove-asset, `withStacked=true` sur les deux endpoints timeline), `TimelineViewModelTests` stacks (3 : flag demandé, mapping du tuple, ordre de `stackSelected`), `DTOEncodingTests` (1 : décodage du tuple `[stackId, count]` depuis le JSON wire).

**Pièges rencontrés et corrigés**
1. **`accessibilityLabel` sur le badge masquait son texte.** Poser un label sur le HStack du badge faisait disparaître le `+2` de l'arbre d'accessibilité (les enfants sont fusionnés sous le label du conteneur) — l'assertion XCUITest ne trouvait plus rien alors que le badge s'affichait. Correctif : `.accessibilityElement(children: .ignore)` + `.accessibilityIdentifier("stackBadge")` + label parlant («3 photos in a stack»). Un seul élément, une seule phrase.
2. **La 1re rangée du timeline vit sous le header de date flottant** : la capture du badge y est illisible. Le harnais UI scrolle donc jusqu'au badge (et, de fait, prouve qu'il apparaît au défilement).
3. **`grep -q` sur un mot présent dans un commentaire** : le check «pas de NavigationStack» échouait à cause du commentaire de doc de la vue. Les checks visent désormais la déclaration (`NavigationStack {`).
4. **Le hub «Me» est une `Form` paresseuse** : les rows sous le pli n'existent pas dans l'arbre d'accessibilité — le harnais scrolle avant d'assertir.

> **Révision 2026-09-13 — la carte d'origine était dérivée par rapport au dépôt.**
> Checks rejoués verbatim avant réécriture :
> - **AC-3704 (ex) était DÉJÀ PASS en pré-état** alors que la carte annonçait « FAIL (partial) » : `StackSheet.swift:110` (`updateStack(id:primaryAssetId:)`) et `:121` (`removeAssetFromStack`) existent depuis la création de la sheet — le critère ne mesurait plus rien. Repris ci-dessous sur un comportement neuf (routage du tap timeline), la sheet existante restant inchangée.
> - **AC-3705 (ex) grepait `withStacked` dans `TimelineView.swift`** alors que le flag vit dans `TimelineViewModel.swift` (6 sites) ; le check passait avec un simple mot dans la vue, sans câblage. Repointé sur le VM + le badge réellement rendu.
> - **AC-3703 (ex) exigeait `grep stackName`** : `StackCreateDto` = `{ assetIds: string[] }` (min 2, `server/src/dtos/stack.dto.ts`) — **le serveur n'a pas de nom de pile**. Champ retiré du critère : l'UI n'offrira pas un champ qui n'existe pas.
> - **AC-3708 (ex)** bornait la suite à `-ge 200` pour une baseline réelle de 695 → garde-fou inopérant.
> - **Constat de fond** : `withStacked` n'est pas un simple « include ». Le serveur **exclut du bucket tous les non-primaires** d'une pile (`asset.repository.ts`, `getTimeBucket` : `NOT EXISTS (SELECT FROM stack WHERE stack.id = asset.stackId AND stack.primaryAssetId != asset.id)`) et n'émet la colonne `stack` que si le flag est vrai. Basculer le flag **retire donc des tuiles du timeline** : sans routage de tap vers la pile, les membres non-primaires deviennent inatteignables. D'où AC-3704 révisé.

## Plan

**Objectif** : gestion complète des piles de photos (parité Flutter) — hub dédié dans « Me », détail par pile, création, et vue timeline regroupée sur la primaire avec badge `+N`.

**Hypothèses** (vérifiées dans le dépôt et contre `immich-app/immich@main`) :
- `StackResponseDto { id, primaryAssetId, assets: [AssetResponseDto] }`, `StackCreateDto { assetIds }` (min 2, **pas de nom**), `StackUpdateDto { primaryAssetId? }` — `Sources/Core/Types/DTOs.swift:185-208`.
- 6 routes wire de bout en bout : `ImmichClient.swift:128-134` → `ImmichAPIClient.swift:366-390` (`GET/POST /api/stacks`, `GET/PUT/DELETE /api/stacks/{id}`, `DELETE /api/stacks/{id}/assets/{assetId}`). `searchStacks` et `addAssetToStack` n'ont **aucun appelant** ; `getStack`/`updateStack`/`deleteStack`/`removeAssetFromStack` ne sont appelés que par `StackSheet.swift`.
- `withStacked: Bool?` déjà sérialisé (`ImmichAPIClient.swift:116,131`) ; les 6 sites du timeline passent `nil` (`TimelineViewModel.swift:154,171,197,206,227,243`) et les 3 de la corbeille aussi (`TrashViewModel.swift:38,54,76` — **à laisser tels quels** : la corbeille doit montrer tous les assets).
- **Sémantique réelle de la colonne `stack`** (`TimeBucketAssetResponseDto.swift` côté serveur : `([string, string] | null)[]`) : chaque cellule est `["<stackId>", "<count>"]` ou `null`, et **le count inclut la primaire**. Le commentaire d'origine d'`AssetReactItem.swift:32-33` (« Ids of the other assets ») était faux : `stack.count` vaut toujours 2, le `+N` du badge doit lire `Int(stack[1]) - 1`.
- `AssetThumbnailCell` a déjà un emplacement de badge (`topLeadingBadges`, l.128-138) et un helper de capsule `.ultraThinMaterial` (`badge(_:)`, l.178).
- `TimelineView` possède son propre `NavigationStack` (l.77) → une destination de navigation peut être poussée depuis une tuile.
- `TimelineView` et `ProfileView` sont construits dans `AuthenticatedRoot` (`RootView.swift:112,173`) : un VM partagé s'y branche en une ligne par site.

**Approche retenue** : A — hub « Me » + détail poussé + timeline regroupé sur la primaire.
**B (rejetée)** : onglet dédié → 6ᵉ onglet pour une fonction secondaire.
**C (rejetée)** : ne garder que `StackSheet` → pas de vue d'ensemble, et aucune réponse au fait que `withStacked` retire les non-primaires.

**Étapes** :
1. `AssetReactItem` — `stackId`/`stackCount` calculés, commentaire corrigé, `isStacked` sur `stackId != nil`.
2. `TimelineViewModel` — propriété `withStacked` (défaut `true`) aux 6 sites + `stackMembers(id:)`.
3. `AssetThumbnailCell` — badge de pile `+N`.
4. `TimelineView` — tap sur tuile empilée → `StackDetailView` (`navigationDestination(item:)`), sinon pager inchangé.
5. NEW `Sources/Features/Stacks/StacksViewModel.swift` — liste + CRUD + chargement d'une pile.
6. NEW `Sources/Features/Stacks/StackView.swift` — liste (couverture + compteur), création, navigation.
7. NEW `Sources/Features/Stacks/StackDetailView.swift` — primaire + autres, set primary / remove / unstack, viewer sur les membres.
8. NEW `Sources/Features/Stacks/CreateStackSheet.swift` — sélecteur de photos paginé par buckets + CTA Create (≥2).
9. `DependencyContainer.makeStacksViewModel()` + `RootView` (instance unique passée à `TimelineView` et `ProfileView`) + lien « Stacks » dans le hub.
10. Mock : capture `withStacked` sur les deux appels timeline.
11. Tests : `StacksViewModelTests`, tests de transport des 5 routes stacks, tests de décodage/badge.

## Acceptance Contract

### Approches candidates
**A (retenue)** : hub « Me » + détail poussé + timeline regroupé sur la primaire, avec routage du tap vers la pile.
**B** : onglet dédié. **C** : `StackSheet` seul.

### Approche retenue + rationale
**A**. Les piles sont secondaires (pas d'onglet), mais `withStacked` **retire** des tuiles : le tap doit mener à la pile. Le détail est la même vue depuis le hub et depuis le timeline (une seule surface à maintenir).

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
Assertion: StackView (poussée depuis le hub, donc SANS NavigationStack propre) liste les piles, offre la création et pousse StackDetailView.
Check post-impl: sh -c 'f=Sources/Features/Stacks/StackView.swift; test -f "$f" && grep -qE "StacksViewModel" "$f" && grep -qE "StackDetailView" "$f" && grep -qE "CreateStackSheet" "$f" && grep -qE "onDelete|deleteStack" "$f" && ! grep -qE "NavigationStack \{" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: le check naïf `! grep -qE "NavigationStack"` échouait sur le mot cité dans le commentaire de doc de la vue — un grep de texte doit viser la déclaration (`NavigationStack {`), pas le mot.
```

```
### AC-3702 [type: new]
Assertion: StackDetailView marque la primaire, la change, retire un membre, dissout la pile, et ouvre le viewer sur les membres.
Check post-impl: sh -c 'f=Sources/Features/Stacks/StackDetailView.swift; test -f "$f" && grep -qE "primaryAssetId" "$f" && grep -qE "func setPrimary|updatePrimary" "$f" && grep -qE "removeAssetFromStack" "$f" && grep -qE "deleteStack" "$f" && grep -qE "PhotoViewerItem" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3703 [type: new]
Assertion: CreateStackSheet sélectionne des photos (multi-sélection, seuil 2) et appelle createStack(assetIds:). Aucun champ de nom : le serveur n'en accepte pas.
Check post-impl: sh -c 'f=Sources/Features/Stacks/CreateStackSheet.swift; test -f "$f" && grep -qE "createStack\(assetIds" "$f" && grep -qE "selectedIds|selection" "$f" && grep -qE "count >= 2|count < 2" "$f" && ! grep -qE "stackName|TextField" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3704 [type: new — remplace un check déjà PASS en pré-état]
Assertion: dans TimelineView, une tuile empilée route vers StackDetailView (destination de navigation) au lieu du pager plat — sinon withStacked rend les membres non-primaires inatteignables.
Check post-impl: sh -c 'f=Sources/Features/Timeline/TimelineView.swift; grep -qE "navigationDestination" "$f" && grep -qE "StackDetailView" "$f" && grep -qE "\.stack" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune destination de navigation vers une pile)
Post-state attendu: PASS
```

```
### AC-3705 [type: new]
Assertion: les appels timeline demandent le regroupement (withStacked non-nil dans TimelineViewModel) et la cellule rend le compteur de pile.
Check post-impl: sh -c 'v=Sources/Features/Timeline/TimelineViewModel.swift; c=Sources/Features/Timeline/AssetThumbnailCell.swift; grep -qE "var withStacked" "$v" && ! grep -qE "withStacked: nil" "$v" && grep -qE "stackCount" "$c" && grep -qE "stackId" Sources/Core/Types/AssetReactItem.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`withStacked: nil` aux 6 sites)
Post-state attendu: PASS
Note: la version d'origine visait `TimelineView.swift` — où le flag n'existe pas — et passait donc avec un simple mot dans la vue, sans rien câbler. Le check vise maintenant le VM **et** le rendu.
```

```
### AC-3706 [type: new]
Assertion: ProfileView expose le lien « Stacks » vers StackView dans la section Management.
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfileView.swift; grep -qE "Stacks" "$f" && grep -qE "StackView" "$f" && grep -qE "square.stack.3d.down.right" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3707 [type: new]
Assertion: StacksViewModelTests expose ≥5 tests couvrant chargement, création, suppression, changement de primaire, retrait de membre.
Check post-impl: sh -c 'f=Tests/StacksViewModelTests.swift; test -f "$f" && n=$(grep -cE "func test_" "$f"); test "$n" -ge 5 && grep -qE "test_loadStacks" "$f" && grep -qE "test_createStack" "$f" && grep -qE "test_deleteStack" "$f" && grep -qE "test_updatePrimary" "$f" && grep -qE "test_removeAssetFromStack" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3708 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (695 tests, `ImmichSwiftUITests`) et TEST SUCCEEDED.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_stacks_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_stacks_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 695 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent)
Post-state attendu: PASS
```

```
### AC-3709 [type: new — vérification d'exécution du contrat réseau]
Assertion: les 5 routes stacks sont exercées sur un transport asservi (méthode + chemin + corps réels), pas seulement greppées — leçon OAuth-404 (un AC de grep ne prouve pas qu'un enchaînement réseau fonctionne).
Check post-impl: sh -c 'f=Tests/ImmichAPIClientTests.swift; for t in test_stacks_searchStacksHitsGetStacks test_stacks_createPostsAssetIds test_stacks_updatePrimaryPutsStacksId test_stacks_deleteRemovesStack test_stacks_removeAssetHitsStackAssetsAnd test_stacks_timelineRequestsStackedPrimaries; do grep -qE "$t" "$f" || { echo FAIL-$t; exit 1; }; done; grep -qE "Executed [0-9]+ tests" /tmp/immich_stacks_test.log && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun test stack dans ImmichAPIClientTests)
Post-state attendu: PASS
```
