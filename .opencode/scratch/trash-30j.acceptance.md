# Task: trash-30j

Status: shipped — Sources/Features/Trash/ (restore/delete-permanently, Restore All/Empty Trash).

## Plan
**Objectif**: Implémenter la Corbeille (Trash) MVP — tab dédié listant les assets trashed (isTrashed=true via filtre timeline buckets), restore single/all, permanent delete single (force:true) + empty all. Style Apple Photos "Recently Deleted".

**Hypothèses** (vérifiées specialist, fichier:ligne):
- `Sources/Core/Constants.swift:4-15` — `enum ImmichAPI` + `SubPath` struct pattern; ajout `static let trash = SubPath(root: "/trash")` trivial.
- `Sources/Services/ImmichAPIClient.swift:98-101` — `deleteAssets(ids:force:)` existe (force:true = permanent). Réutilisable pour AC-303.
- `Sources/Features/Timeline/TimelineViewModel.swift` — pattern de référence pour pagination bucket + try-then-mutate + groupedByDay + loadedIds dedup.
- `Sources/Core/Types/DTOs.swift:43-56` — `ServerConfigDto.trashDays:Int` (pas utilisé dans MVP contract mais dispo pour info banner).
- Immich trash endpoints (vérifié GitHub immich-app/immich server/src/services/trash.service.ts): `POST /api/trash/restore/assets` body `{ids}` → `{count}`; `POST /api/trash/restore` no body → restore all; `POST /api/trash/empty` no body → permanent delete all.
- `sendAuthed(.POST, path:body:)` gère nil body (vérifié specialist sendRaw:176-180).

**Étapes**:
1. `Sources/Core/Constants.swift` — add `static let trash = SubPath(root: "/trash")`.
2. `Sources/Core/Types/DTOs.swift` — add `BulkIdsDto { ids:[String] }` + `TrashResponseDto { count:Int }`.
3. `Sources/Core/Protocols/ImmichClient.swift` — add 3 methods: `restoreTrashAssets(ids:)`, `restoreAllTrash()`, `emptyTrash()`.
4. `Sources/Services/ImmichAPIClient.swift` — impl 3 methods (POST trash paths).
5. `Sources/Features/Trash/TrashViewModel.swift` (NEW) — @Observable @MainActor. État: buckets, items, bucketIndex, isLoading, errorMessage, loadedIds (copie pattern TimelineViewModel). Méthodes: `load()`, `refresh()`, `loadMore()`, `restore(id:)`, `restoreAll()`, `deletePermanently(id:)`, `emptyTrash()`. Try-then-mutate partout. `groupedByDay` computed. Filter `getTimeBuckets(isFavorite:nil, isTrashed:true)`.
6. `Sources/Features/Trash/TrashView.swift` (NEW) — Grid reuse `AssetThumbnailCell` (avec callback onRestore + onDeletePermanent) + info banner "Items in trash are permanently deleted after 30 days" (si items non vide) + toolbar items (Restore All, Empty Trash) + confirmation alerts sur actions destructives + ContentUnavailableView si vide + pull-to-refresh.
7. `Sources/DependencyContainer.swift` — add `makeTrashViewModel()`.
8. `Sources/RootView.swift` — add `@State private var trash: TrashViewModel` + 3e tab "Trash" (entre Timeline et Backup) dans NavigationStack.
9. `Sources/Features/Timeline/AssetThumbnailCell.swift` — add `var onRestore: (() -> Void)? = nil` + `var onDeletePermanent: (() -> Void)? = nil` optionnels; context menu conditionnel (si onRestore != nil → Restore + Delete Permanently; sinon menu existant Favorite+Delete). Pas de rupture callers existants (optionnels défaut nil).
10. `Tests/Mocks/MockImmichClient.swift` — add 3 trash capture vars + 3 methods impl + `lastTimeBucketsIsTrashed` capture in getTimeBuckets.
11. `Tests/TrashViewModelTests.swift` (NEW) — AC-300..AC-306 + AC-313..AC-314 (VM behavior, mock injecté).
12. `Tests/DTOEncodingTests.swift` (NEW ou append) — AC-310 (BulkIdsDto/TrashResponseDto roundtrip) + AC-311 (SubPath trash).
13. `xcodegen generate` + build + full test.

## Acceptance Contract

### Approches candidates
- **A) Réutiliser TimelineView avec filterIsTrashed=true**: ~30 lignes de conditionnelles dans TimelineView (392 lignes); casse séparation; tests interfèrent. Rejeté.
- **B) TrashViewModel + TrashView dédiés (L3 feature autonome)**: ~120 lignes VM + ~200 View + 3 methods protocol + 2 DTOs + 1 SubPath. Réutilisation TimelineSectionBuilder + AssetThumbnailCell. Isolation testabilité excellente. **RETENU**.
- **C) Wrapper TrashTabView autour de TimelineView**: peu de code mais inversion sémantique bug-prone (delete depuis corbeille → re-trash). Rejeté.

### Approche retenue + rationale
**B**. Corbeille = mode navigation distinct (tab séparé, pas filtre). Actions trash (restore/empty/permanent) n'ont pas de sens dans timeline et inversement. Pattern L3 prouvé sur 4 features (Auth/Timeline/AssetDetail/AppLock). Duplication groupedByDay (10 lignes) + réutilisation TimelineSectionBuilder + AssetThumbnailCell gardent coût bas. 49 tests existants intacts (seules nouvelles méthodes protocol ajoutées, tests existants ne les appellent pas).

### Critères

```
### AC-300 [type: new]
Assertion: TrashViewModel.load() appelle getTimeBuckets(isFavorite: nil, isTrashed: true) et peuple items avec des assets dont isTrashed == true. Try-then-mutate: error path set errorMessage, items/buckets vides.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/TrashViewModelTests/test_AC_300_load_uses_trash_filter | grep "TEST SUCCEEDED"
Pre-state attendu: new — 0 tests ran (classe TrashViewModelTests inexistante).
Post-state attendu: new — success path (mock.lastTimeBucketsIsTrashed == true + vm.items.allSatisfy(\.isTrashed)) + error path (mock.globalError injecté → vm.items.isEmpty, vm.buckets.isEmpty, vm.errorMessage != nil).
```

```
### AC-301 [type: new]
Assertion: TrashViewModel.restore(id:) appelle restoreTrashAssets(ids:[id]), puis retire l'item de items + loadedIds. Try-then-mutate: sur erreur, errorMessage setté, items inchangé.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/TrashViewModelTests/test_AC_301_restore_single | grep "TEST SUCCEEDED"
Pre-state attendu: new — 0 tests.
Post-state attendu: new — success path + error path passés.
```

```
### AC-302 [type: new]
Assertion: TrashViewModel.restoreAll() appelle restoreAllTrash(), puis vide items/loadedIds/buckets, reset bucketIndex=0. Try-then-mutate: error path préserve items/loadedIds/buckets/bucketIndex, set errorMessage.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/TrashViewModelTests/test_AC_302_restore_all | grep "TEST SUCCEEDED"
Pre-state attendu: new — 0 tests.
Post-state attendu: new — success path (vm.items.isEmpty, vm.loadedIds.isEmpty, vm.buckets.isEmpty, vm.bucketIndex==0) + error path (état inchangé, vm.errorMessage != nil) dans le même test.
```

```
### AC-303 [type: new]
Assertion: TrashViewModel.deletePermanently(id:) appelle deleteAssets(ids:[id], force:true), puis retire l'item. Try-then-mutate sur erreur.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/TrashViewModelTests/test_AC_303_delete_permanently_single | grep "TEST SUCCEEDED"
Pre-state attendu: new — 0 tests.
Post-state attendu: new — mock.lastDeleteBody?.force == true + item retiré.
```

```
### AC-304 [type: new]
Assertion: TrashViewModel.emptyTrash() appelle emptyTrash(), puis vide TOUT l'état local (items, loadedIds, buckets, bucketIndex=0). Try-then-mutate: error path préserve TOUT l'état, set errorMessage.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/TrashViewModelTests/test_AC_304_empty_trash | grep "TEST SUCCEEDED"
Pre-state attendu: new — 0 tests.
Post-state attendu: new — success path: mock.emptyTrashCallCount==1, vm.items.isEmpty, vm.loadedIds.isEmpty, vm.buckets.isEmpty, vm.bucketIndex==0. Error path: mock.emptyTrashError injecté → vm.items/loadedIds/buckets count identique avant/après, vm.bucketIndex inchangé, vm.errorMessage != nil.
```

```
### AC-305 [type: new]
Assertion: TrashViewModel.refresh() appelle getTimeBuckets(isFavorite:nil, isTrashed:true), reset bucketIndex=0, recharge uniquement le 1er bucket. Error path: set errorMessage, préserve état d'avant-refresh.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/TrashViewModelTests/test_AC_305_refresh_trash | grep "TEST SUCCEEDED"
Pre-state attendu: new — 0 tests.
Post-state attendu: new — success path (après load→loadMore tous buckets, refresh → 1er bucket only, canLoadMore == true) + error path (mock.globalError injecté pendant refresh → vm.errorMessage != nil).
```

```
### AC-306 [type: new]
Assertion: TrashViewModel.loadMore() ne duplique pas les IDs (garde loadedIds).
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/TrashViewModelTests/test_AC_306_loadMore_no_duplicates | grep "TEST SUCCEEDED"
Pre-state attendu: new — 0 tests.
Post-state attendu: new — 2 buckets → 4 items uniques → loadMore au-delà = no-op.
```

```
### AC-307 [type: new]
Assertion: ImmichAPIClient.restoreTrashAssets(ids:) envoie POST /api/trash/restore/assets avec body {"ids":[...]}. Capturé par mock.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/TrashViewModelTests/test_AC_307_api_restore_assets | grep "TEST SUCCEEDED"
Pre-state attendu: new — 0 tests.
Post-state attendu: new — mock.lastRestoreTrashAssetsIds == ["id1"].
Note: path HTTP réel vérifié par code review (ImmichAPI.trash.path("/restore/assets")) + AC-311 SubPath. Runtime HTTP = vérification manuelle.
```

```
### AC-308 [type: new]
Assertion: ImmichAPIClient.restoreAllTrash() envoie POST /api/trash/restore sans body. Capturé par mock.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/TrashViewModelTests/test_AC_308_api_restore_all | grep "TEST SUCCEEDED"
Pre-state attendu: new — 0 tests.
Post-state attendu: new — mock.restoreAllTrashCallCount == 1.
```

```
### AC-309 [type: new]
Assertion: ImmichAPIClient.emptyTrash() envoie POST /api/trash/empty sans body. Capturé par mock.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/TrashViewModelTests/test_AC_309_api_empty_trash | grep "TEST SUCCEEDED"
Pre-state attendu: new — 0 tests.
Post-state attendu: new — mock.emptyTrashCallCount == 1.
```

```
### AC-310 [type: new]
Assertion: TrashResponseDto decode {"count":3} → count==3. BulkIdsDto encode ids:["a","b"] → {"ids":["a","b"]}.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/DTOEncodingTests/test_AC_310_trash_dtos | grep "TEST SUCCEEDED"
Pre-state attendu: new — 0 tests (ou classe DTOEncodingTests inexistante).
Post-state attendu: new — roundtrip encoding/decoding OK.
```

```
### AC-311 [type: new]
Assertion: Constants.swift expose ImmichAPI.trash = SubPath(root:"/trash") et ImmichAPI.trash.path("/restore") == "/api/trash/restore".
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/DTOEncodingTests/test_AC_311_trash_subpath | grep "TEST SUCCEEDED"
Pre-state attendu: new — 0 tests.
Post-state attendu: new — résolution correcte.
```

```
### AC-312 [type: new]
Assertion: RootView affiche un 3e onglet "Trash" entre Timeline et Backup, avec NavigationStack contenant TrashView.
Check post-impl: grep -n "TrashView\|trashVM\|makeTrashViewModel" Sources/RootView.swift Sources/DependencyContainer.swift
Pre-state attendu: new — 0 références Trash dans RootView/DependencyContainer.
Post-state attendu: new — TrashView(vm:) dans RootView + makeTrashViewModel() dans DependencyContainer.
```

```
### AC-313 [type: new]
Assertion: Erreur réseau sur restore(id:) laisse items + loadedIds inchangés, errorMessage setté (try-then-mutate discipline identique à TimelineViewModel.toggleFavorite:64-76).
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/TrashViewModelTests/test_AC_313_restore_error_preserves_state | grep "TEST SUCCEEDED"
Pre-state attendu: new — 0 tests.
Post-state attendu: new — mock.restoreTrashAssetsError injecté → items count identique avant/après, vm.errorMessage != nil.
```

```
### AC-314 [type: new]
Assertion: Erreur sur deletePermanently(id:) préserve l'état (même discipline que TimelineViewModel.delete:200-208).
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/TrashViewModelTests/test_AC_314_delete_permanent_error_preserves_state | grep "TEST SUCCEEDED"
Pre-state attendu: new — 0 tests.
Post-state attendu: new — items unchanged, errorMessage set.
```

```
### AC-315 [type: regression]
Assertion: Les tests existants (49) restent verts après ajout des nouvelles méthodes ImmichClient protocol + MockImmichClient.
Check post-impl: xcodebuild test -skip-testing:ImmichSwiftUITests/TrashViewModelTests | tail -5
Pre-state attendu: regression — 49 tests verts.
Post-state attendu: regression — 49 tests toujours verts, 0 failure.
```

```
### AC-316 [type: new]
Assertion: TrashView désactive les actions destructives (Empty Trash toolbar, Restore All toolbar, context menu Restore + Delete Permanently) quand vm.isLoading == true (mitigation FM-1/FM-2).
Check post-impl: grep -c "\.disabled(vm\.isLoading\|\.disabled.*isLoading)" Sources/Features/Trash/TrashView.swift | test $(cat) -ge 1
Pre-state attendu: new — fichier TrashView.swift inexistant → grep retourne 0 / fichier absent.
Post-state attendu: new — au moins 1 match `.disabled(...isLoading...)` dans TrashView.swift.
```

### Failure modes (top 3 + quel AC les détecte)
- **FM-1 Race restore→deletePermanent pendant isLoading**: user tape Restore puis Delete Permanent avant fin réseau. Mitigation: `.disabled(vm.isLoading)` sur toolbar + context menu buttons. AC-301/303 couvrent cas isolés; cas croisé = vérif manuelle.
- **FM-2 Empty trash→UI visible avant retour réseau**: emptyTrash lent, user tente restore individuel pendant laps. Mitigation: `.disabled(isLoading)` + ProgressView overlay. AC-304 couvre nominal; concurrent = vérif manuelle.
- **FM-3 Double-tap restore→double requête**: 2e restore renvoie count:0. Mitigation: `.disabled(isLoading)` suffit. AC-301 couvre.

## Vérifications manuelles (hors auto-feedback loop)
- **Haptics**: UIFeedbackGenerator `.success` sur restore, `.warning` sur permanent delete/empty (cahier line 39).
- **Transition restore**: item disparaît animation `.easeOut` + fade (pas brutal). Cohérence Apple Photos.
- **Transition empty all**: grille → ContentUnavailableView fluide, pas de flash blanc.
- **Trash info banner**: "Items in trash are permanently deleted after 30 days" UNIQUEMENT si items non vide. Défile avec grille (pas sticky).
- **Pull-to-refresh corbeille**: rafraîchit buckets trash.
- **Tab bar badge** (optionnel MVP): count items corbeille sur badge tab Trash.
- **Confirmation alerts**: delete permanent single + empty all → Alert bouton "Delete" destructive. Restore single via context menu: pas de confirmation (non destructive).
- **Runtime HTTP trash endpoints**: POST /api/trash/restore/assets, /restore, /empty sur vrai serveur Immich (vérifier statuts 200 + body {count}).
