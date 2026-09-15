# Task: recently-taken

Status: planifié — écart G13 du registre `.omp/backlog/ImmichSwiftUI-backlog.md` §2.17 (P4 découverte).
L'upstream expose `RecentlyTakenRoute` et `RecentlyAddedRoute` (`mobile/lib/routing/router.dart`, `e55ac299`) ;
côté iOS ni `Sources/Features/Recent/` ni `Sources/Features/RecentlyTaken/` n'existent, et le seul ordre de tri
disponible sur une grille d'assets est celui de la timeline (aucun appelant ne passe l'axe de tri).

## Plan (résumé)

**Objectif** : deux écrans poussés depuis le hub « Me » — *Recently Taken* (buckets triés par date de prise de vue)
et *Recently Added* (triés par date de mise en ligne) — en grille paginée par jour, lecture seule, avec état vide,
erreur, pull-to-refresh et chargement progressif en fin de grille.

**Approche retenue** : A — étendre `ImmichClient.getTimeBuckets` d'un `orderBy: AssetOrderBy?` (l'enum
`Sources/Core/Constants.swift:85` existe déjà, branché nulle part), puis **un seul** `RecentAssetsViewModel`
paramétré par `RecentAssetsMode` (`.taken` / `.added`) et **une seule** `RecentAssetsView`, poussés deux fois
depuis `ProfileView`. B (deux `TimelineView` supplémentaires) est rejetée par trois faits mesurés :
`TimelineView.swift:219` masque la barre hors sélection (le Retour disparaît), `:110-118` présente la feuille
« Me » depuis son propre overlay (feuille depuis elle-même), `:222` exige un troisième `StacksViewModel`.

**Étapes** : (1) EDIT `Sources/Core/Protocols/ImmichClient.swift` (`orderBy` avant `withStacked`, doc-comment) ;
(2) EDIT `Sources/Services/ImmichAPIClient.swift` (`URLQueryItem(name: "orderBy", value: orderBy.rawValue)`) ;
(3) EDIT `Tests/Mocks/MockImmichClient.swift` (`lastTimeBucketsOrderBy`) ; (4) EDIT `TimelineViewModel.swift`
(`:161`, `:178`, `:204`) et `TrashViewModel.swift` (`:38`, `:54`) en `orderBy: nil`, plus les deux appels de
`Tests/ImmichAPIClientTests.swift` (`:854`, `:1044`) ; (5) NEW `Sources/Features/Recent/RecentAssetsMode.swift` ;
(6) NEW `RecentAssetsViewModel.swift` ; (7) NEW `RecentAssetsView.swift` ; (8) EDIT `Sources/DependencyContainer.swift`
(factory) ; (9) EDIT `Sources/RootView.swift` (deux `@State`) ; (10) EDIT `Sources/Features/Profile/ProfileView.swift`
(section « Recently ») ; (11) NEW `Tests/RecentAssetsViewModelTests.swift` ; (12) `xcodegen generate` + suite.

**Incertitudes** : ouverture du viewer depuis un écran poussé par la feuille « Me » (SwiftUI sérialise les
présentations d'un même présentateur — `Sources/RootView.swift:74-78`) ; lisibilité des en-têtes relatifs
(`DateHeaderFormatter`, `Sources/Features/Timeline/DateHeaderFormatter.swift:21`) pour des jours de *mise en ligne*,
où « Today » signifie « ajouté aujourd'hui » ; utilité du paramètre `order` (`AssetOrder`, défaut `desc`).

## Critères

```
### AC-5120 [type: new]
Assertion: le protocole `ImmichClient.getTimeBuckets` accepte `orderBy: AssetOrderBy?` dans sa déclaration — l'enum `AssetOrderBy` (Sources/Core/Constants.swift:85) cesse d'être orphelin et le tri est demandé au serveur, pas recalculé côté client.
Check post-impl: sh -c 'p=Sources/Core/Protocols/ImmichClient.swift; n=$(grep -A9 "func getTimeBuckets(" "$p" | grep -cE "orderBy: AssetOrderBy\?"); grep -qE "func getTimeBucket\(" "$p" && test "$n" -ge 1 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (grep -rn "AssetOrderBy" Sources/ Tests/ ne renvoie que Sources/Core/Constants.swift:85, et la signature du protocole ne porte que isFavorite/isTrashed/personId/withPartners/visibility/withStacked)
Post-state attendu: PASS
Note: le check est borné à la DÉCLARATION (`grep -A9` à partir de `func getTimeBuckets(`) — le doc-comment qui cite `orderBy: .createdAt` ne peut pas le satisfaire.
```

```
### AC-5121 [type: new]
Assertion: `ImmichAPIClient.getTimeBuckets` encode le paramètre `orderBy` dans la requête `GET /api/timeline/buckets`, sans table de conversion (`AssetOrderBy.rawValue` vaut déjà `takenAt`/`createdAt`, exactement l'enum de `components.schemas.AssetOrderBy`).
Check post-impl: sh -c 'f=Sources/Services/ImmichAPIClient.swift; n=$(grep -A20 "func getTimeBuckets(" "$f" | grep -cE "URLQueryItem\(name: \"orderBy\""); m=$(grep -A20 "func getTimeBuckets(" "$f" | grep -cE "orderBy\.rawValue"); test "$n" -ge 1 && test "$m" -ge 1 && grep -qE "timeline\.path\(\"/buckets\"\)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (le corps actuel n'encode que isFavorite/isTrashed/personId/withPartners/visibility/withStacked)
Post-state attendu: PASS
```

```
### AC-5122 [type: new — migration des appelants]
Assertion: tous les conformateurs et appelants existants compilent avec la nouvelle exigence de protocole — le mock mémorise la valeur reçue, les deux ViewModels de listes passent `orderBy: nil` (comportement inchangé, ordre serveur par défaut), les appels directs des tests d'API sont alignés.
Check post-impl: sh -c 'm=Tests/Mocks/MockImmichClient.swift; t=Sources/Features/Timeline/TimelineViewModel.swift; r=Sources/Features/Trash/TrashViewModel.swift; a=Tests/ImmichAPIClientTests.swift; grep -qE "lastTimeBucketsOrderBy" "$m" && test $(grep -A9 "func getTimeBuckets(" "$m" | grep -cE "orderBy: AssetOrderBy\?") -ge 1 && test $(grep -cE "orderBy: nil" "$t") -ge 3 && test $(grep -cE "orderBy: nil" "$r") -ge 2 && test $(grep -cE "orderBy: nil" "$a") -ge 2 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune occurrence de `orderBy` dans Sources/ ni Tests/ ; la signature n'existe nulle part)
Post-state attendu: PASS
Note: `Sources/ImmichSharedKit/WidgetDataProvider.swift:268-272` appelle /api/timeline/buckets en direct, hors protocole — non concerné. Le mock est la seule preuve d'encodage hors serveur : `lastTimeBucketsOrderBy` est ce que lisent les cas de AC-5127.
```

```
### AC-5123 [type: new]
Assertion: `RecentAssetsMode` porte exactement les trois différences des deux pages upstream (ordre de tri, titre, message vide), ce qui justifie de n'avoir qu'une seule vue et qu'un seul ViewModel.
Check post-impl: sh -c 'f=Sources/Features/Recent/RecentAssetsMode.swift; test -f "$f" && grep -qE "^enum RecentAssetsMode" "$f" && grep -qE "case taken" "$f" && grep -qE "case added" "$f" && grep -qE "var orderBy: AssetOrderBy" "$f" && grep -qE "\.takenAt" "$f" && grep -qE "\.createdAt" "$f" && grep -qE "var title" "$f" && grep -qE "var emptyMessage" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Features/Recent/` n'existe pas — grep -rn "Recently" Sources/ ne renvoie que le commentaire de Sources/Features/Trash/TrashView.swift:3)
Post-state attendu: PASS
```

```
### AC-5124 [type: new]
Assertion: `RecentAssetsViewModel` est paramétré par le mode, demande les buckets avec `orderBy: mode.orderBy` et `withStacked: true` (le badge « +N » de `AssetThumbnailCell.swift:148-151` suppose des buckets sans les secondaires), groupe par jour, et empile les buckets suivants en FIN de liste (contrairement à `TimelineViewModel.loadOlder()` qui préfixe), avec déduplication par `loadedIds`.
Check post-impl: sh -c 'f=Sources/Features/Recent/RecentAssetsViewModel.swift; test -f "$f" && grep -qE "final class RecentAssetsViewModel" "$f" && grep -qE "let mode: RecentAssetsMode" "$f" && grep -qE "init\(client: any ImmichClient, mode: RecentAssetsMode\)" "$f" && grep -qE "orderBy: mode\.orderBy" "$f" && grep -qE "withStacked: true" "$f" && grep -qE "struct RecentDayGroup" "$f" && grep -qE "loadedIds" "$f" && grep -qE "func loadMore" "$f" && grep -qE "func refresh" "$f" && grep -qE "hasMore" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: le groupement par jour vient de la clé du bucket (`TimeBucketsResponseDto.timeBucket`, déjà une date ISO) — aucune requête supplémentaire n'est nécessaire pour les en-têtes.
```

```
### AC-5125 [type: new]
Assertion: `RecentAssetsView` est une galerie consultative poussée par le hub : aucune sélection, aucun `NavigationStack` propre (ProfileView en porte un, `ProfileView.swift:24`), la cellule est celle de la timeline, et les trois états portent leurs identifiants sur les éléments concernés — jamais sur un conteneur.
Check post-impl: sh -c 'f=Sources/Features/Recent/RecentAssetsView.swift; test -f "$f" && grep -qE "struct RecentAssetsView" "$f" && grep -qE "AssetThumbnailCell\(" "$f" && grep -qE "ContentUnavailableView" "$f" && grep -qE "refreshable" "$f" && grep -qE "recentGrid" "$f" && grep -qE "recentEmptyState" "$f" && grep -qE "recentError" "$f" && ! grep -qE "NavigationStack \{" "$f" && ! grep -qE "selectionMode" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: le check vise la DÉCLARATION `NavigationStack {` — la vue porte un doc-comment expliquant l'absence de stack ; greper le seul mot échouerait sur ce commentaire (piège de la carte stacks-ui).
```

```
### AC-5126 [type: new — câblage]
Assertion: les deux instances viennent du composition root (factory dans `DependencyContainer`, à côté de `makeTimelineViewModel()`), vivent dans `AuthenticatedRoot` et sont passées à `ProfileView`, qui expose deux lignes dans une section « Recently » avec leurs identifiants.
Check post-impl: sh -c 'c=Sources/DependencyContainer.swift; r=Sources/RootView.swift; p=Sources/Features/Profile/ProfileView.swift; grep -qE "func makeRecentAssetsViewModel\(mode: RecentAssetsMode\)" "$c" && grep -qE "RecentAssetsViewModel\(client:" "$c" && grep -qE "recentTaken: RecentAssetsViewModel" "$r" && grep -qE "recentAdded: RecentAssetsViewModel" "$r" && grep -qE "makeRecentAssetsViewModel\(mode: \.taken\)" "$r" && grep -qE "makeRecentAssetsViewModel\(mode: \.added\)" "$r" && grep -qE "recentTaken: recentTaken" "$r" && grep -qE "var recentTaken: RecentAssetsViewModel" "$p" && grep -qE "var recentAdded: RecentAssetsViewModel" "$p" && grep -qE "RecentAssetsView\(vm: recentTaken\)" "$p" && grep -qE "RecentAssetsView\(vm: recentAdded\)" "$p" && grep -qE "recentTakenRow" "$p" && grep -qE "recentAddedRow" "$p" && grep -qE "Text\(\"Recently\"\)" "$p" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune factory, aucun état, aucune occurrence de `Recent` dans ProfileView)
Post-state attendu: PASS
Note: la section « Recently » est insérée AVANT la section « Management » (`ProfileView.swift:55`), qui porte des réglages ; le précédent d'une vue poussée sans stack est `OfflineAssetsView` (`:107-111`).
```

```
### AC-5127 [type: new]
Assertion: `Tests/RecentAssetsViewModelTests.swift` couvre les deux ordres demandés, le groupement par jour, l'empilement en fin de liste, la déduplication, l'arrêt sur dernier bucket, l'échec et le refresh — sans pinner un libellé d'interface.
Check post-impl: sh -c 'f=Tests/RecentAssetsViewModelTests.swift; test -f "$f" && test $(grep -cE "func test_" "$f") -ge 8 && grep -qE "test_takenMode_requestsBucketsOrderedByTakenAt" "$f" && grep -qE "test_addedMode_requestsBucketsOrderedByCreatedAt" "$f" && grep -qE "test_loadMore_appendsOlderBucketsAtTheEnd" "$f" && grep -qE "test_loadMore_dedupesAssetsAlreadyLoaded" "$f" && grep -qE "test_loadMore_stopsAtTheLastBucket" "$f" && grep -qE "test_load_failure_surfacesMessageAndKeepsEmptyGrid" "$f" && grep -qE "test_refresh_replacesTheGrid" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate` — sans régénération la suite passerait « verte » par omission, et les deux cas d'ordre liraient `lastTimeBucketsOrderBy` du mock sans jamais l'alimenter.
```

```
### AC-5128 [type: new — la route de recherche est structurellement inapte]
Assertion: la feature ne passe QUE par `/timeline/buckets` : `POST /api/search/metadata` ne peut pas produire « récemment ajoutés », car `SearchOrderField.enum` vaut `["fileCreatedAt","localDateTime","fileSizeInBytes","rating"]` (aucune date de mise en ligne), son `order`/`page` sont `deprecated` au profit d'un `cursor`, et `MetadataSearchDto` ne modélise ni `orderBy` ni `cursor`.
Check post-impl: sh -c 'd=Sources/Features/Recent; test -d "$d" && ! grep -qE "search/metadata|MetadataSearchDto|SearchOrder" "$d"/*.swift && grep -qE "getTimeBuckets" "$d/RecentAssetsViewModel.swift" && ! grep -qE "orderBy|cursor|SearchOrder" Sources/Core/Types/SearchDTOs.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (dossier `Sources/Features/Recent` absent — l'écran « Recently Added » n'existe sous aucune forme)
Post-state attendu: PASS
Note: le grep sur `Sources/Core/Types/SearchDTOs.swift` documente la preuve par le code (aucun champ de tri par date d'ajout modélisé) ; la preuve upstream est l'enum de `components.schemas.SearchOrderField` relevé dans `/tmp/immich-openapi-main.json` le 2026-09-15. Seule `/timeline/buckets` accepte `orderBy` → `AssetOrderBy`.
```

```
### AC-5129 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED — la signature `getTimeBuckets` change, donc tout le module recompile d'un bloc et tout appelant oublié casse le build.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_recently_taken_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_recently_taken_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent)
Post-state attendu: PASS
```
