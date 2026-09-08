# Task: people-faces

Status: shipped — P3 card 1/5. AC-1060..AC-1067 PASS 2026-08-12. Suite 405 → 419.

## Plan
**Objectif**: People & faces module (parity with Flutter Immich): person list with face thumbnails, asset counts, featured section, rename / favorite / hide, merge persons, faces drill-down grid (assets of one person) with full viewer. New People tab in the root TabView.

**Hypothèses**:
- Client methods P0 (ImmichClient.swift): `getPeople(page:withHidden:)`, `updatePerson(id:dto:)`, `mergePeople(ids:into:)` (POST /people/{id}/merge), `getPersonStatistics(id:)`; drill-down = `searchMetadata(dto:)` with `personIds` (SearchDTOs.swift:18, SearchViewModel.swift:32 comment).
- DTOs+People.swift: `PersonResponseDto` full (var name/birthDate/thumbnailPath/isHidden/color/isFavorite/updatedAt), `PeopleResponseDto{people,hidden,total,hasNextPage?}`, `PersonUpdateDto` (all optional vars), `MergePersonDto{ids}`, `PersonStatisticsResponseDto{assets}`.
- `ImmichAPI.people` group exists (Constants.swift:14, unused). Person thumbnail endpoint `GET /api/people/{id}/thumbnail` → new `ImmichAssetURL.personThumbnail` (pattern ImmichAssetURL.swift:8).
- `AuthenticatedAsyncImage(url:token:)` (AuthenticatedAsyncImage.swift:11) loads Bearer images — reuse for face thumbnails.
- Root tabs (RootView.swift:82-99): Photos/Albums/Shared/Me + search bubble; RootTab enum :165-171; bubbleIcon :144-151; handleBubbleTap :153-161.
- MockImmichClient people stubs exist (:519-550) — add getPeople param captures (lastPeoplePage/lastPeopleWithHidden).
- Person thumbnail endpoint exists on server (OpenAPI verified P0: GET /people/{id}/thumbnail octet-stream; /people/{id}/assets removed → personIds search).

**Approche retenue**: A — dédié `PeopleViewModel` (@Observable @MainActor, client injecté, stats fan-out concurrency 6 mirroring SearchViewModel explore enrichment) + `PeopleView` (NavigationStack path-driven: list → person detail) + tab People dans RootView. Drill-down = searchMetadata(personIds:). **Merge = taille-safe: Menu dans le détail, les autres personnes listées → mergePeople([other], into: current) puis reload** (direction unique, pas de picker bidir).
**B** (rejetée): folds tout dans SearchView — onglet People distinct demandé par parity; SearchViewModel déjà 458L.
**C** (rejetée): grid de faces serveur (GET /people/{id}/face) — endpoint n'existe plus (OpenAPI P0).

**Étapes**:
1. `ImmichAssetURL.personThumbnail(personId:baseURL:size:)` — `{base}/api/people/{id}/thumbnail` (+ size query si non-default).
2. NEW `Sources/Features/People/PeopleViewModel.swift` — load(force:)/toggleShowHidden/loadStatistics (taskGroup concurrency 6)/assetCount(for:)/toggleFavorite/toggleHidden/rename/merge/select/loadAssets(personIds)/refreshAssets/clearSelection; captures test lastMergeIds/lastMergeTarget; states people/hiddenCount/total/showingHidden/isLoading/errorMessage/statsByID/personAssets/assetsLoading/assetsError/selectedPersonID.
3. NEW `Sources/Features/People/PeopleView.swift` — NavigationStack(path:): List with Section "Featured" (isFavorite==true, tri count desc) + Section "People" (reste, tri count desc) + footer hidden-count toggle row; avatar 48 Circle AuthenticatedAsyncImage(personThumbnail); rows NavigationLink value: PersonResponseDto → `personDetail`: ScrollView header (avatar 96, name pvTitle, "N photos" pvCaption) + toolbar actions (favorite star, rename pencil, hide eye.slash, Menu Merge arrow.triangle.merge disabled si count<2 — Button par autre personne "Merge <name>" → vm.merge + path.removeLast) + rename .alert TextField + LazyVGrid 3 col AssetThumbnailCell + .photoViewer(item:$viewerItem...) onDataChanged → refreshAssets; navigationTitle inline; .task load+stats; .refreshable.
4. `DependencyContainer.makePeopleViewModel()`.
5. RootView: RootTab.people (entre albums et shared), Tab("People", systemImage: "person.2", value: .people), @State people + State(initialValue:), bubbleIcon case .people → "magnifyingglass", handleBubbleTap case .people → break (pas d'action contextuelle).
6. MockImmichClient: captures lastPeoplePage/lastPeopleWithHidden dans getPeople.
7. NEW `Tests/PeopleViewModelTests.swift` — ~11 tests (voir carte ACs).
8. xcodegen generate (3 nouveaux fichiers Sources) + build-for-testing + suite complète + summary /tmp/immich_people_test_summary.txt.
9. ACs + memory.md entrée + Status shipped.

## Acceptance Contract

### Critères

```
### AC-1060 [type: new]
Assertion: ImmichAssetURL expose personThumbnail(personId:baseURL:) pointant vers /api/people/{id}/thumbnail.
Check post-impl: sh -c 'grep -q "personThumbnail" Sources/Services/ImmichAssetURL.swift && grep -q "people.path" Sources/Services/ImmichAssetURL.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (pas de builder personne)
Post-state attendu: PASS
```

```
### AC-1061 [type: new]
Assertion: PeopleViewModel existe avec load(force:), toggleShowHidden, rename, toggleFavorite, toggleHidden, merge(_:into:), loadAssets/personIds drill-down, stats fan-out.
Check post-impl: sh -c 'f=Sources/Features/People/PeopleViewModel.swift; test -f "$f" && grep -q "func load" "$f" && grep -q "func rename" "$f" && grep -q "func toggleFavorite" "$f" && grep -q "func toggleHidden" "$f" && grep -q "func merge" "$f" && grep -q "personIds" "$f" && grep -q "func loadStatistics" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier n'existe pas)
Post-state attendu: PASS
```

```
### AC-1062 [type: new]
Assertion: PeopleView existe avec sections Featured/People, footer hidden-count, détail personne (grille faces + rename/favorite/hide/merge) et photoViewer.
Check post-impl: sh -c 'f=Sources/Features/People/PeopleView.swift; test -f "$f" && grep -q "Featured" "$f" && grep -q "navigationDestination" "$f" && grep -q "photoViewer" "$f" && grep -q "Merge" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1063 [type: new]
Assertion: RootView gagne un onglet People entre Albums et Shared, VM wires dans l'init.
Check post-impl: sh -c 'grep -q "Tab(\"People\"" Sources/RootView.swift && grep -q "case people" Sources/RootView.swift && grep -q "makePeopleViewModel" Sources/RootView.swift && grep -q "makePeopleViewModel" Sources/DependencyContainer.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (3 sur 4 absents)
Post-state attendu: PASS
```

```
### AC-1064 [type: new]
Assertion: MockImmichClient capture les params getPeople (page/withHidden).
Check post-impl: sh -c 'grep -q "lastPeoplePage" Tests/Mocks/MockImmichClient.swift && grep -q "lastPeopleWithHidden" Tests/Mocks/MockImmichClient.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1065 [type: new]
Assertion: Tests PeopleViewModelTests couvrent load, stats fan-out, rename, favorite, hide, merge, drill-down personIds, erreurs — ≥ 9 test funcs.
Check post-impl: sh -c 'n=$(grep -c "func test_" Tests/PeopleViewModelTests.swift); test "$n" -ge 9 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier n'existe pas)
Post-state attendu: PASS
```

```
### AC-1066 [type: new]
Assertion: Le drill-down faces envoie searchMetadata avec personIds exacts + assets mappés en AssetReactItem.
Check post-impl: sh -c 'grep -q "personIds = \[id\]" Sources/Features/People/PeopleViewModel.swift && grep -q "AssetReactItem(from:" Sources/Features/People/PeopleViewModel.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1067 [type: regression]
Assertion: Suite complète ≥ 405 tests, TEST SUCCEEDED.
Check post-impl: sh -c 'rtk grep -q "TEST SUCCEEDED" /tmp/immich_people_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_people_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 405 && echo PASS || echo FAIL'
Pre-state attendu: PASS (405)
Post-state attendu: PASS
```