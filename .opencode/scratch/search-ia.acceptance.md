# Task: search-ia

Status: shipped — Sources/Features/Search/ (3-mode Results/Explore/Map).

## Plan
- **Objectif**: Implémenter la feature Recherche pour PhotoVault (cahier §6 L132-141, MVP scope).
- **Scope MVP (session)**: Search tab unique (SearchViewModel + SearchView) avec 2 modes:
  - **Results**: barre de recherche + Picker (Metadata | Smart) → LazyVGrid résultats via AssetThumbnailCell. Tap → AssetDetailView.
  - **Explore**: onAppear charge GET /api/search/explore → cartes cliquables (villes/objets) tap → searchMetadata(city=value).
- **Scope DEFERRÉ** (itération 2): People/faces (L136), object detection tags (L137). Architect decision: People trop coûteux en une session (3 endpoints + thumbnail binaire + drill-down list→grid). People réutilisera searchMetadata(personIds:) quand activé.
- **Hypothèses**:
  - Immich API (vérifié specialist via immich-app/immich search.controller.ts + dto.ts):
    - `POST /api/search/metadata` body `MetadataSearchDto` → `SearchResponseDto { albums, assets:{count, items:[AssetResponseDto], nextPage:String?} }`
    - `POST /api/search/smart` body `SmartSearchDto {query, page?, size?, ...}` → `SearchResponseDto`
    - `GET /api/search/explore` → `[SearchExploreResponseDto { fieldName, items:[{value:String, data:AssetResponseDto}] }]`
    - `GET /api/people` (non utilisé cette session, mais SubPath préparé)
  - Réutilise: `AssetThumbnailCell`, `TimelineSectionBuilder.build` (pure), pattern L3 (VM @Observable @MainActor + DI via DependencyContainer).
  - Convention projet: grid spacing 0, cornerRadius 0.
- **Étapes**:
  1. NEW `Sources/Core/Types/SearchDTOs.swift` — `MetadataSearchDto` (query/make/model/lensModel/city/state/country/type/isFavorite/personIds/order/page/size/withExif), `SmartSearchDto` (query/page/size/withExif), `SearchResponseDto` {assets: SearchAssetResponseDto} **with explicit CodingKeys** (only `assets` — Immich server sends also `albums` which must be ignored), `SearchAssetResponseDto` {count, items:[AssetResponseDto], nextPage:String?} **with explicit CodingKeys** (only `count, items, nextPage` — server sends `total` + `facets` which must be ignored; Swift JSONDecoder ignores unknown keys when CodingKeys enum is explicit), `SearchExploreResponseDto` {fieldName,items:[SearchExploreItem]}, `SearchExploreItem` {value:String, data:AssetResponseDto}. NO `SearchAssetResponseDto` separate from `items: [AssetResponseDto]` — use existing AssetResponseDto directly (OBJ-11 resolved).
  2. EDIT `Sources/Core/Constants.swift` — ajouter `static let search = SubPath(root:"/search")` + `static let people = SubPath(root:"/people")`.
  3. EDIT `Sources/Core/Protocols/ImmichClient.swift` — 3 méthodes search: `searchMetadata(dto:)`, `searchSmart(dto:)`, `getExploreData()`. PAS de getAllPeople (People deferred).
  4. EDIT `Sources/Services/ImmichAPIClient.swift` — impls via `sendAuthed` privé: POST search/metadata (body dto), POST search/smart (body dto), GET search/explore.
  5. EDIT `Sources/Core/Types/AssetReactItem.swift` — ajout `init(from dto: AssetResponseDto)` adapter. Mapping EXHAUSTIF (defaults documentés): `id=dto.id`, `ownerId=dto.ownerId`, `ratio=1.0` (AssetResponseDto lacks ratio), `isFavorite=dto.isFavorite`, `visibility=dto.visibility`, `isTrashed=dto.isTrashed`, `isImage=(dto.type=="IMAGE")`, `thumbhash=dto.thumbhash`, `createdAt=dto.createdAt`, `fileCreatedAt=dto.fileCreatedAt`, `localOffsetHours=0.0` (AssetResponseDto LACKS this — only TimeBucketAssetResponseDto has it), `duration=dto.duration`, `livePhotoVideoId=dto.livePhotoVideoId`, `projectionType=dto.exifInfo?.projectionType`, `city=dto.exifInfo?.city`, `country=dto.exifInfo?.country`, `latitude=dto.exifInfo?.latitude`, `longitude=dto.exifInfo?.longitude`.
  6. EDIT `Tests/Mocks/MockImmichClient.swift` — capture vars (lastMetadataSearchDto/lastSmartSearchDto) + **response injection vars** (searchMetadataResponse: SearchResponseDto? = nil, searchMetadataError: Error? = nil, smartSearchResponse: SearchResponseDto? = nil, smartSearchError: Error? = nil, exploreResponse: [SearchExploreResponseDto]? = nil, exploreError: Error? = nil) + 3 impls: searchMetadata returns searchMetadataResponse ?? empty-default OR throws searchMetadataError/globalError ; searchSmart returns smartSearchResponse ?? empty-default OR throws ; getExploreData returns exploreResponse ?? empty-default OR throws.
  7. NEW `Sources/Features/Search/SearchViewModel.swift` — `@Observable @MainActor`. Props: `query: String`, `searchMode { .metadata, .smart }`, `viewMode { .results, .explore }`, `selectedCity: String?` (set by searchByCity, drives MetadataSearchDto.city when non-nil; free-text query flow leaves nil), `results: [AssetReactItem]` (built via adapter), `exploreData: [SearchExploreResponseDto]`, `currentPage: Int`, `nextPage: String?`, `canLoadMore`, `isLoading`, `errorMessage`, `hasSearched: Bool`. Methods:
     - `search()` (reset loadedIds+results+currentPage=1+nextPage=nil+hasSearched=true+errorMessage=nil, guard !isLoading, dispatch: metadata → MetadataSearchDto(query: selectedCity != nil ? nil : query, city: selectedCity); smart → SmartSearchDto(query: query)). Pagination loads page=currentPage.
     - `loadMore()` (guard !isLoading && canLoadMore && nextPage!=nil, ++currentPage, dispatch selon searchMode/selectedCity — construit le MÊME DTO que search() avec page=currentPage: MetadataSearchDto(query: selectedCity != nil ? nil : query, city: selectedCity, page: currentPage) OU SmartSearchDto(query: query, page: currentPage)).
     - `loadExplore()` (guard !isLoading && exploreData.isEmpty to avoid reload spam — project convention .task guarantees single execution, but defensive). Sets isLoading, calls getExploreData, populates exploreData, errorMessage on throw.
     - `searchByCity(_ city:)` (set viewMode=.results, searchMode=.metadata, selectedCity=city, query="" cleared, reset state, then call search()).
  8. NEW `Sources/Features/Search/SearchView.swift` — SearchBar TextField + Picker searchMode (segmented metadata/smart) + Picker viewMode (segmented results/explore). Results = ScrollView+LazyVGrid(cols spacing 0) AssetThumbnailCell(cornerRadius 0 hardcoded in cell — `Sources/Features/Timeline/AssetThumbnailCell.swift:52` already 0; pass baseURL from `@Environment(AuthViewModel.self)` + token from auth.token like TimelineView, onTap → NavigationLink { AssetDetailView(asset: item) } réutilise pattern TimelineView.swift:253-254). Explore = ScrollView sections `fieldName` + HScroll cards city/object (AsyncImage thumbnail + label). **`.task { await vm.loadExplore() }` on Explore view** (NOT onAppear — project convention TimelineView.swift:84, TrashView.swift:85). **Empty state**: if `vm.results.isEmpty && !vm.isLoading && vm.errorMessage == nil && vm.hasSearched` → `ContentUnavailableView("No results", systemImage: "magnifyingglass")`. `.disabled(vm.isLoading)` sur actions.
  9. EDIT `Sources/DependencyContainer.swift` — `makeSearchViewModel() -> SearchViewModel { SearchViewModel(client: client as any ImmichClient) }`.
  10. EDIT `Sources/RootView.swift` — @State search + 4e tab Search (magnifyingglass).
  11. NEW `Tests/SearchViewModelTests.swift` — AC-401 (searchMetadata success + error path), AC-401b (searchSmart success + error path), AC-402 (dto dispatched selon mode ×2), AC-404a (explore load), AC-404b (city tap → metadata dto city set + state reset verified), AC-404c (loadExplore idempotent), AC-405 (empty state), AC-406 (pagination 2 pages dedup + nextPage nil → canLoadMore false), AC-406b (loadMore no-op when nextPage nil), AC-406c (loadMore persists city filter). Total 13 tests.
  12. `xcodegen generate` + build + full test suite.

## Acceptance Contract

### Approches candidates
- **A**: Single-page Search + Picker 3 modes (Results/Explore/People) — 1 VM spaghetti 3 datasources, test difficile.
- **B**: 2 tabs Search+People — propre mais 5e tab charge la nav.
- **A' (RETENUE)**: Single-page Search 2 modes (Results/Explore), People DEFERRED. SearchVM unique 2 datasources, scope réaliste 1 session.

### Approche retenue + rationale
**A' (A simplifiée, People coupé)**. Scope MVP réaliste session. People réutilisera searchMetadata(personIds:) en itération 2. SearchVM unique gère results+explore, pagination infinie, dispatch metadata/smart. Réutilise AssetThumbnailCell + AssetReactItem adapter.

### Critères

```
### AC-400 [type: new]
Assertion: `ImmichAPI.search` et `ImmichAPI.people` SubPath existent dans Constants.swift. `ImmichAPI.search.path("/metadata")` résout vers "/api/search/metadata" et `ImmichAPI.people.path("")` résout vers "/api/people".
Check post-impl: `grep -nE 'static let (search|people) = SubPath' Sources/Core/Constants.swift | wc -l` retourne 2.
Pre-state attendu: new — commande retourne 0 (aucune entrée search/people).
Post-state attendu: new — commande retourne 2.
```

```
### AC-401 [type: new]
Assertion: SearchViewModel.search() avec searchMode=.metadata et query="Canon" appelle searchMetadata(dto:) côté client. results non vide si le mock retourne SearchResponseDto avec 2 items. errorMessage non-nil si le mock throw.
Check post-impl: `xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ImmichSwiftUITests/SearchViewModelTests/test_AC_401_searchMetadata_success -only-testing:ImmichSwiftUITests/SearchViewModelTests/test_AC_401_searchMetadata_error` 2>&1 | grep -c "passed" retourne 2.
Pre-state attendu: new — 0 tests ran (classe inexistante).
Post-state attendu: new — 2 tests passés (success path: results.count==2, loadedIds.count==2, nextPage==nil → canLoadMore false ; error path: errorMessage != nil, results vide).
```

```
### AC-402 [type: new]
Assertion: SearchViewModel.search() dispatch le bon DTO selon searchMode. Mode .metadata: MetadataSearchDto envoyé avec query="Canon" mappé (spécialiste précise: query string direct passée à dto.query pour MVP — parsing EXIF champs = V2). Mode .smart: SmartSearchDto envoyé avec query="chien sur une plage".
Check post-impl: `xcodebuild test ... -only-testing:ImmichSwiftUITests/SearchViewModelTests/test_AC_402_metadata_dto_dispatched -only-testing:ImmichSwiftUITests/SearchViewModelTests/test_AC_402_smart_dto_dispatched` 2>&1 | grep -c "passed" retourne 2.
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — 2 tests: metadata mock.lastMetadataSearchDto?.query == "Canon" ET requestCount==1 ; smart mock.lastSmartSearchDto?.query == "chien sur une plage".
```

```
### AC-401b [type: new]
Assertion: SearchViewModel.search() avec searchMode=.smart et query="chien sur une plage" peuple results (count==2 si mock retourne 2 items). Error path: errorMessage non-nil si mock throw.
Check post-impl: `xcodebuild test ... -only-testing:ImmichSwiftUITests/SearchViewModelTests/test_AC_401b_searchSmart_success -only-testing:ImmichSwiftUITests/SearchViewModelTests/test_AC_401b_searchSmart_error` 2>&1 | grep -c "passed" retourne 2.
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — 2 tests: success (results.count==2, loadedIds.count==2) ; error (errorMessage != nil, results vide).
```

```
### AC-405 [type: new]
Assertion: Empty state — search() qui retourne 0 results set hasSearched=true, garde results.isEmpty, errorMessage reste nil. SearchView affiche ContentUnavailableView quand (results.isEmpty && !isLoading && errorMessage==nil && hasSearched).
Check post-impl: (a) `xcodebuild test ... -only-testing:ImmichSwiftUITests/SearchViewModelTests/test_AC_405_empty_state` 2>&1 | grep -c "passed" retourne 1 ; (b) `grep -c "ContentUnavailableView" Sources/Features/Search/SearchView.swift` retourne ≥1.
Pre-state attendu: new — 0 tests ran, 0 ContentUnavailableView dans SearchView (inexistant).
Post-state attendu: new — test vert (vm.hasSearched==true && vm.results.isEmpty && vm.errorMessage==nil) ; grep ≥1.
```

```
### AC-404a [type: new]
Assertion: loadExplore() appelle getExploreData() et peuple exploreData. errorMessage non-nil sur erreur.
Check post-impl: `xcodebuild test ... -only-testing:ImmichSwiftUITests/SearchViewModelTests/test_AC_404a_loadExplore` 2>&1 | grep -c "passed" retourne 1.
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — 1 test: exploreData.count == 1 (mock retourne 1 section fieldName="exifInfo.city"), requestCount==1.
```

```
### AC-404b [type: new]
Assertion: searchByCity("Paris") set viewMode=.results, searchMode=.metadata, selectedCity="Paris", query="" cleared, reset state (results vides avant fetch, loadedIds vide, currentPage=1, nextPage=nil), puis appelle searchMetadata(dto:) avec dto.city == "Paris" ET dto.query == nil (pas de free-text). results peuple correctement.
Check post-impl: `xcodebuild test ... -only-testing:ImmichSwiftUITests/SearchViewModelTests/test_AC_404b_cityTapDispatchesCity` 2>&1 | grep -c "passed" retourne 1.
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — 1 test: mock.lastMetadataSearchDto?.city == "Paris" && mock.lastMetadataSearchDto?.query == nil && vm.results.count == mock items count && vm.loadedIds.count == mock items count (NOT accumulated from previous search) && vm.currentPage == 1 && vm.nextPage == nil.
```

```
### AC-404c [type: new]
Assertion: loadExplore() idempotent — appel ×2 consécutifs → requestCount == 1 (deuxième call no-op car exploreData non-vide). guard `exploreData.isEmpty && !isLoading`.
Check post-impl: `xcodebuild test ... -only-testing:ImmichSwiftUITests/SearchViewModelTests/test_AC_404c_loadExplore_idempotent` 2>&1 | grep -c "passed" retourne 1.
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — 1 test: await loadExplore(); await loadExplore(); requestCount == 1 && exploreData non-vide.
```

```
### AC-406b [type: new]
Assertion: loadMore() no-op quand nextPage == nil. canLoadMore == false, requestCount reste 1.
Check post-impl: `xcodebuild test ... -only-testing:ImmichSwiftUITests/SearchViewModelTests/test_AC_406b_loadMore_noop_when_no_nextPage` 2>&1 | grep -c "passed" retourne 1.
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — 1 test: nextPage nil → canLoadMore false, loadMore no-op (requestCount reste 1).
```

```
### AC-406c [type: new]
Assertion: loadMore() après searchByCity persiste le filtre ville. searchByCity("Paris") puis loadMore() → dto page 2 contient city == "Paris" && page == 2 && query == nil.
Check post-impl: `xcodebuild test ... -only-testing:ImmichSwiftUITests/SearchViewModelTests/test_AC_406c_loadMore_persists_city_filter` 2>&1 | grep -c "passed" retourne 1.
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — 1 test: mock.lastMetadataSearchDto?.city == "Paris" && mock.lastMetadataSearchDto?.page == 2 && mock.lastMetadataSearchDto?.query == nil && requestCount == 2.
```

```
### AC-407 [type: regression]
Assertion: Les 74 tests existants restent verts (sans nouveaux tests Search comptés). SearchViewModelTests ne casse pas la suite existante.
Check post-impl: `xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5` affiche `** TEST SUCCEEDED **` avec ≥80 tests (74 + 13 nouveaux Search per step 11 = 87).
Pre-state attendu: regression — 74 tests verts.
Post-state attendu: regression — ≥87 tests verts, 0 failure.
```

```
### AC-408 [type: new]
Assertion: RootView expose un 4e tab "Search" (Label+magnifyingglass) avec NavigationStack contenant SearchView. DependencyContainer.makeSearchViewModel() existe.
Check post-impl: `grep -nE "SearchView|makeSearchViewModel|magnifyingglass" Sources/RootView.swift Sources/DependencyContainer.swift | wc -l` retourne ≥3.
Pre-state attendu: new — 0 occurences.
Post-state attendu: new — ≥3 matches.
```

```
### AC-409 [type: new]
Assertion: SearchView affiche une LazyVGrid de AssetThumbnailCell quand results > 0 (GridItem spacing 0, cornerRadius 0 cohérent projet). AssetDetailView ouvert sur tap cell (vérification manuelle hors auto-feedback loop car navigation/sheet).
Check post-impl: `grep -nE "LazyVGrid|AssetThumbnailCell" Sources/Features/Search/SearchView.swift | wc -l` retourne ≥2.
Pre-state attendu: new — 0 (fichier inexistant).
Post-state attendu: new — ≥2 matches (LazyVGrid + AssetThumbnailCell présents).
```

```
### AC-410 [type: regression]
Assertion: AssetReactItem existant (columnar decode path) reste fonctionnel. L'ajout d'un init(from: AssetResponseDto) ne casse pas TimelineSectionBuilder ni les tests Timeline/Section existants.
Check post-impl: `xcodebuild test ... -only-testing:ImmichSwiftUITests/TimelineViewModelTests -only-testing:ImmichSwiftUITests/TimelineSectionBuilderTests 2>&1 | grep -E "TEST SUCCEEDED|Executed"` affiche TEST SUCCEEDED + 18 tests passed (12 Timeline + 6 Section).
Pre-state attendu: regression — 18 tests verts.
Post-state attendu: regression — 18 tests toujours verts.
```

### Failure modes (top 3 + quel AC les détecte)
- **FM-1**: SearchResponseDto décodage incorrect — `albums`/`total`/`facets` champs serveur non-gérés → JSONDecoder keyNotFound → tout search en error path. Mitigation: CodingKeys explicites (étape 1). Détecté: AC-401 (mock retourne SearchResponseDto structuré, test vérifie results.count==2 — si décodage faux, throw APIError.decoding, test FAIL).
- **FM-2**: Pagination infinie réentrante — `onAppear`/`.task` dernier item déclenche loadMore() en boucle car isLoading pas vérifié. Détecté: AC-406 (requestCount==2 strict, pas 10). Mitigation UI: `.disabled(vm.isLoading)` sur onAppear path + guard !isLoading dans loadMore.
- **FM-3**: AssetThumbnailCell reçoit AssetReactItem corrompu (ratio 1.0 acceptable carré, thumbhash nil OK). Détecté: AC-410 (Timeline tests verts prouvent adapter ne casse pas le columnar path + pas de crash runtime).
- **FM-4**: searchByCity ne reset pas l'état précédent → résultats append au lieu de remplacer. Détecté: AC-404b (assert loadedIds.count == mockItemsCount, currentPage==1, nextPage==nil — état non-accumulé).
- **FM-5**: loadExplore() spam serveur sur re-onAppear (race première réponse). Détecté: AC-404c (requestCount==1 strict après 2 appels).

## Vérifications manuelles (hors auto-feedback loop)
- **VM-1**: Tap cellule search → AssetDetailView ouvert (sheet ou navigation selon pattern projet actuel — à confirmer au moment impl). AssetDetailView charge le détail (loadDetail appelé).
- **VM-2**: Pagination infinie scroll — dernier item déclenche loadMore(), spinner en bas, nouveaux items ajoutés sans jump scroll.
- **VM-3**: Picker segmented Metadata/Smart réactif au tap.
- **VM-4**: Explore mode affiche cartes ville (image thumbnail + nom) HScroll horizontal, tap carte → switch Results mode + grille.
- **VM-5**: Empty state si results vide (ContentUnavailableView "No results" ou texte simple).
- **VM-6**: Haptic léger sur tap cellule (cohérent Timeline).
- **VM-7**: Search bar clé "Search photos, places, and people" (placeholder FR/EN selon locale; MVP hardcodé EN accepté).
- **VM-8**: Corner radius 0 sur toutes cells (cohérent Timeline tweak + Trash + EXIF map).
