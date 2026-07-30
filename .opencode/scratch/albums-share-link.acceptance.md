# Task: albums-share-link

## Plan

**Objectif**: Implémenter la feature "Albums + partage par lien public" du cahier §8 (MVP scope: L156 création+ajout par sélection, L158 lien public avec mot de passe optionnel). L157 (collaboratif sharedUsers) DEFERRED per cahier summary L197 "Albums de base + partage par lien".

**Hypothèses** (vérifiées scout fichier:ligne + web fetch Immich source `server/src/dtos/album.dto.ts` + `shared-link.dto.ts`):
- `ImmichAPI` enum + `SubPath` struct pattern (`Constants.swift:4-18`). Add `static let albums = SubPath(root:"/albums")` + `static let sharedLinks = SubPath(root:"/shared-links")` après ligne 13.
- `ImmichAPIClient` privé `sendAuthed<T:Decodable>(_:path:query:body:)` (:186), `sendAuthedRaw(_:path:query:body:) -> Data` (:191), `sendRaw` (:196). Nouvelles méthodes publiques dessus.
- `ImmichClient` protocol (:10, AnyObject+Sendable). 24 méthodes actuelles (:12-59), aucune collision avec les 9 nouvelles.
- 6 DTOs ABSENTS (`AlbumResponseDto`, `CreateAlbumDto`, `SharedLinkResponseDto`, `SharedLinkCreateDto`, `BulkIdResponseDto`, `AlbumUserResponseDto`/simplified). `BulkIdsDto {ids:[String]}` EXISTE (`DTOs.swift:231-233`). `AssetResponseDto` EXISTE 32 fields (`DTOs.swift:95-129`). `MetadataSearchDto` EXISTE (`SearchDTOs.swift`) avec champ `albumIds` pour fetch assets par album.
- `RootView.swift` TabView (:28-35): Timeline, Search, Trash, Backup. Insertion 5e tab Albums entre Timeline (:29) et Search (:31). Pattern `@State` + `_xxx = State(initialValue: container.makeXxxViewModel())` (:7-9, :15-17).
- `DependencyContainer` factories pattern `makeXxxViewModel() -> Xxx { Xxx(client: client as any ImmichClient) }` (:20-34). Aucune VM paramétrée — pattern `makeAlbumDetailViewModel(albumId:)` à créer.
- `TimelineView.swift` toolbar sélection (:270-305): Cancel leading (:272-281), Favorite trailing (:284-297), Delete trailing (:299-305). `vm.selectedIds` (:37), `selectionMode` (:33). Aucun `.sheet` pattern dans tout Sources/ (grep=0) — à introduire pour album picker.
- `MockImmichClient` (:6) pattern capture-vars + response-injection + `globalError` (:79) + `bump()` (:81). 17 méthodes actuelles (:83-253). Aucun `MockClientTests` ni `AlbumsTests` n'existe.
- `Tests/DTOEncodingTests.swift` (:4, 7 tests) — append AC-500..AC-504 ici.
- `project.yml` auto-discovery (`Sources` :20, `Tests` :53) — tout .swift auto-inclus.
- Total tests: **87** (Trash:16, Search:13, Timeline:12, DTO:7, AppLock:7, Date:7, Section:6, Auth:5, Geo:5, API:3, Cache:3, Exif:2, Detail:1).
- Immich source `album.dto.ts`: `AlbumResponseDto` = {id, albumName, description, createdAt, updatedAt, albumThumbnailAssetId(nullable), shared(bool), albumUsers:[AlbumUserResponseDto] min1, hasSharedLink(bool), assetCount(int≥0), lastModifiedAssetTimestamp?(string), startDate?(string), endDate?(string), isActivityEnabled(bool), order?(enum string "asc"|"desc" — réutiliser `Constants.AssetOrder` EXISTANT `Constants.swift:51-54`), contributorCounts?(array)}. **NO `assets` field** — FM-2 confirmé.
- `Constants.AssetOrder` EXISTE déjà (`Constants.swift:51-54`: `enum AssetOrder: String, Codable, Sendable { case asc; case desc }`). **RÉUTILISER, ne PAS redéclarer** (collision compile sinon).
- `MetadataSearchDto` (`SearchDTOs.swift:8-23`) n'a **PAS** de champ `albumIds` — à AJOUTER (`var albumIds: [String]?`) pour permettre fetch assets par album (FM-2 résolution).
- Immich source `shared-link.dto.ts`: `SharedLinkCreateDto` = {type: enum "ALBUM"|"INDIVIDUAL", assetIds?, albumId?, description?, password?, slug?, expiresAt?(nullable, default null), allowUpload?, allowDownload?(default true), showMetadata?(default true)}. `SharedLinkResponseDto` = {id, description(nullable), password(nullable), userId, key(string base64url), type enum, createdAt, expiresAt(nullable), assets:[AssetResponseDto], album? AlbumResponseDto, allowUpload(bool), allowDownload(bool), showMetadata(bool), slug(nullable)}.
- Immich source `asset-ids.response.dto.ts`: `BulkIdResponseDto` = {id:String, success:Bool, error?:enum, errorMessage?:String}.

**Approche retenue**: A — Albums tab dédié + drill-down AlbumDetailView (Approche A du specialist). VMs `@Observable @MainActor` injectés via `DependencyContainer`. Assets d'album fetchés via `searchMetadata(albumIds:[id])` EXISTANT (AC-401), pas de nouvel endpoint. `.sheet` introduit pour album picker + create + share-link.

**Steps (10)**:
1. NEW `Sources/Core/Types/DTOs+Album.swift` — AlbumResponseDto (sans `assets`, albumUsers simplifié à `[AlbumUserSummaryDto]?` = {userId, role} pour éviter UserResponseDto complet inutile MVP), CreateAlbumDto {albumName, description?, assetIds?}, BulkIdResponseDto {id, success, error?, errorMessage?}. **`order` utilise `Constants.AssetOrder` EXISTANT (Constants.swift:51-54) — ne PAS redéclarer**. ~~UpdateAlbumDto~~ SUPPRIMÉ (edit name = V2, evite dead code).
2. NEW `Sources/Core/Types/DTOs+SharedLink.swift` — SharedLinkResponseDto (CodingKeys explicites pour ignorer champs non utilisés), SharedLinkCreateDto {type (rawValue string), assetIds?, albumId?, description?, password?, expiresAt?, allowUpload?, allowDownload?, showMetadata?}, enum SharedLinkType:String {ALBUM, INDIVIDUAL}.
2b. EDIT `Sources/Core/Types/SearchDTOs.swift` — **AJOUTER** `var albumIds: [String]?` dans `MetadataSearchDto` (résolution FM-2: permet fetch assets par album via searchMetadata). Ne pas toucher aux autres champs existants.
3. EDIT `Sources/Core/Constants.swift:14-15` — add `albums` + `sharedLinks` SubPath.
4. EDIT `Sources/Core/Protocols/ImmichClient.swift:40-41` (après getExploreData) — add 9 methods: `getAlbums()`, `createAlbum(dto:)`, `getAlbum(id:)`, `deleteAlbum(id:)`, `addAssetsToAlbum(albumId:dto:)`, `removeAssetsFromAlbum(albumId:dto:)`, `getSharedLinks(albumId:)` (albumId filter optional), `createSharedLink(dto:)`, `deleteSharedLink(id:)`.
5. EDIT `Sources/Services/ImmichAPIClient.swift` (après :128 search) — impl 9 méthodes. `deleteAlbum` + `deleteSharedLink` → `sendAuthedRaw` (204 No Content). Autres → `sendAuthed<T>`. `getSharedLinks(albumId:)` query param si albumId non-nil.
6. EDIT `Tests/Mocks/MockImmichClient.swift` — add capture-vars (lastCreateAlbumDto, lastAddAssetsAlbumId, lastRemoveAssetsAlbumId, lastAddAssetsIds, lastRemoveAssetsIds, lastCreateSharedLinkDto, lastDeleteSharedLinkId, lastSharedLinksAlbumId) + response-injection (albumsResponse/Error, createAlbumResponse/Error, albumResponse/Error, addAssetsResponse/Error, removeAssetsResponse/Error, sharedLinksResponse/Error, createSharedLinkResponse/Error). Defaults plausibles.
7. EDIT `Sources/DependencyContainer.swift:36-40` — `makeAlbumsViewModel()` + `makeAlbumDetailViewModel(albumId:)`.
8. NEW `Sources/Features/Albums/AlbumsViewModel.swift` — `@Observable @MainActor`. Props: albums [AlbumResponseDto], isLoading, errorMessage, isCreating. Methods: load() (getAlbums try-then-mutate), createAlbum(name:description:assetIds:) (createAlbum dto + append to albums on success), refresh().
9. NEW `Sources/Features/Albums/AlbumDetailView+VM` (`Sources/Features/Albums/AlbumDetailViewModel.swift` + `Sources/Features/Albums/AlbumDetailView.swift`). VM props: albumId, album AlbumResponseDto?, assets [AssetReactItem], loadedIds Set<String>, isLoading, errorMessage, isDeleted, sharedLinks [SharedLinkResponseDto]. Methods: load() (getAlbum + searchMetadata(albumIds:) pour assets, 2 appels try-then-mutate), addAssets(ids:) (addAssetsToAlbum + refresh assets), removeAssets(ids:) (removeAssetsFromAlbum + update local), deleteAlbum() (deleteAlbum + isDeleted=true), loadSharedLinks() (getSharedLinks(albumId:)), createSharedLink(password:description:) (createSharedLink dto type=ALBUM albumId + refresh sharedLinks), revokeSharedLink(id:) (deleteSharedLink + update local). View: NavigationStack grid (cols spacing 0, cornerRadius 0), toolbar Share+Delete album, context menu per cell Remove from album, sheet ShareLinkSheet.
10. NEW `Sources/Features/Albums/AlbumsView.swift` — grid of album cards (thumbnail via AuthenticatedAsyncImage albumThumbnailAssetId, name, assetCount), toolbar + button → CreateAlbumSheet, tap → NavigationLink AlbumDetailView(vm: makeAlbumDetailViewModel(album.id)). `.task { await vm.load() }`.
11. NEW `Sources/Features/Albums/CreateAlbumSheet.swift` — Form TextField name + description, optional assetIds preview, Create button → vm.createAlbum + dismiss.
12. NEW `Sources/Features/SharedLinks/SharedLinkSheet.swift` (ou inline dans AlbumDetailView) — create form (description TextField, password Toggle + SecureField, expiration Picker), show existing links list with revoke button, copy link URL to clipboard.
13. EDIT `Sources/RootView.swift:9,17,30-31` — `@State albums` + 5e tab Albums (rectangle.stack) entre Timeline (:29) et Search (:31).
14. EDIT `Sources/Features/Timeline/TimelineView.swift` (toolbar :283-305) — add Button "Add to Album" (rectangle.stack.badge.plus) après Delete, `.disabled(vm.selectedIds.isEmpty)`, **`.accessibilityIdentifier("addToAlbumButton")`** (AC-515 robustesse), `.sheet(isPresented:)` AddToAlbumPickerSheet (liste albums + create-new). AlbumsViewModel récupéré via `@Environment(AlbumsViewModel.self)` (FM-3 partage état).
15. NEW `Sources/Features/Albums/AddToAlbumPickerSheet.swift` — liste albums (vm.albums), tap → addAssetsToAlbum + dismiss + feedback, bouton "New Album" → CreateAlbumSheet with preselected assetIds.
16. NEW `Tests/AlbumsTests.swift` — tests VM (AC-506..AC-520 sauf DTO).
17. EDIT `Tests/DTOEncodingTests.swift` — append AC-500..AC-504 DTO roundtrip.
18. `xcodegen generate` + build + test.

## Acceptance Contract

### Approches candidates
- **A (retenue)**: Albums tab dédié + drill-down AlbumDetailView. VMs `@Observable @MainActor` injectés. Assets album via searchMetadata(albumIds:) EXISTANT. Rationale: API fit (albums + timeline sont ressources serveur séparées), testabilité (VM isolée mock), pattern-fit (prolonge Timeline/Trash/Search pattern L3), extensible V2 (collaborative via albumUsers).
- **B**: Reuse TimelineView avec albumId filter. Rejeté: TimelineViewModel ne supporte pas album filtering (columnar API = time-bucket, pas album), pollution SRP, UX confuse.
- **C**: Wrapper AlbumsList push TimelineView filtré. Rejeté: pas d'endpoint getTimeBucket(albumId:), obligerait client-side filtering O(n) sur timeline entière, pagination cassée.

### Approche retenue + rationale
**A**. Mirror Photos.app UX (user familiarity), contrôle toolbar album-spécifique, état indépendant par album (pas de contamination TimelineViewModel), extensible V2. Assets via searchMetadata reuse = zéro nouvel endpoint pour le cas critique (FM-2 résolu par design).

### Critères

```
### AC-500 [type: new]
Assertion: ImmichAPI.albums et ImmichAPI.sharedLinks SubPath résolvent correctement vers /api/albums et /api/shared-links.
Check post-impl: xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ImmichSwiftUITests/DTOEncodingTests/test_AC_500_albumsSharedLinksSubpath 2>&1 | grep -E "Test Case|TEST SUCCEEDED|0 tests"
Pre-state attendu: new — 0 tests ran (DTOEncodingTests n'a pas test_AC_500).
Post-state attendu: new — test passe: albums.path("")=="/api/albums", albums.path("/x")=="/api/albums/x", sharedLinks.path("")=="/api/shared-links", sharedLinks.path("/y")=="/api/shared-links/y".
```

```
### AC-501 [type: new]
Assertion: AlbumResponseDto décode le JSON serveur (sans champ assets) et roundtrip encode→decode→equality stable.
Check post-impl: xcodebuild test ... -only-testing:ImmichSwiftUITests/DTOEncodingTests/test_AC_501_albumResponseDtoRoundTrip 2>&1 | grep -E "Test Case|TEST SUCCEEDED|0 tests"
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — test passe. JSON serveur (sans assets) décode sans error. Fields vérifiés: id, albumName, description, albumThumbnailAssetId nullable, assetCount, hasSharedLink, shared, isActivityEnabled.
```

```
### AC-502 [type: new]
Assertion: CreateAlbumDto encode correctement {albumName, description?, assetIds?} (champs optionnels absents quand nil).
Check post-impl: xcodebuild test ... -only-testing:ImmichSwiftUITests/DTOEncodingTests/test_AC_502_createAlbumDtoEncoding 2>&1 | grep -E "Test Case|TEST SUCCEEDED|0 tests"
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — test passe. Encoded JSON contient albumName. Si description=nil+assetIds=nil, JSON n'a QUE albumName.
```

```
### AC-503 [type: new]
Assertion: SharedLinkCreateDto encode {type:"ALBUM", albumId, password?} et SharedLinkResponseDto décode {id, type, key, password nullable, album?, assets:[]}.
Check post-impl: xcodebuild test ... -only-testing:ImmichSwiftUITests/DTOEncodingTests/test_AC_503_sharedLinkDtos 2>&1 | grep -E "Test Case|TEST SUCCEEDED|0 tests"
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — test passe. SharedLinkCreateDto(type:.ALBUM, albumId:"a", password:"pw") encode JSON avec password. Sans password, password absent du JSON. SharedLinkResponseDto décode JSON serveur (key, type, album optional, assets array).
```

```
### AC-504 [type: new]
Assertion: BulkIdResponseDto décode [{id:"x", success:true}, {id:"y", success:false, error:"DUPLICATE", errorMessage:"..."}].
Check post-impl: xcodebuild test ... -only-testing:ImmichSwiftUITests/DTOEncodingTests/test_AC_504_bulkIdResponseDto 2>&1 | grep -E "Test Case|TEST SUCCEEDED|0 tests"
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — test passe. 2 éléments décodés, success true/false, error/errorMessage optionnels.
```

```
### AC-505 [type: new]
Assertion: ImmichClient protocol déclare les 9 méthodes album+shared-link et MockImmichClient y conforme sans erreur compile.
Check post-impl: xcodebuild build -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "BUILD SUCCEEDED|error:"
Pre-state attendu: new — build SUCCEEDED sans les 9 méthodes (pré-impl, elles n'existent pas encore donc pas d'erreur non plus tant que personne ne les appelle). En pratique: pré-state = build SUCCEEDED mais grep "getAlbums|createAlbum|deleteAlbum|addAssetsToAlbum|removeAssetsFromAlbum|getSharedLinks|createSharedLink|deleteSharedLink" ImmichClient.swift retourne 0.
Post-state attendu: new — BUILD SUCCEEDED + grep retourne ≥1 match par méthode dans ImmichClient.swift ET MockImmichClient.swift.
```

```
### AC-506 [type: new]
Assertion: AlbumsViewModel.load() appelle getAlbums() et peuple albums. Sur erreur globalError, errorMessage setté, albums inchangés (try-then-mutate).
Check post-impl: xcodebuild test ... -only-testing:ImmichSwiftUITests/AlbumsTests/test_AC_506_load_success -only-testing:ImmichSwiftUITests/AlbumsTests/test_AC_506b_load_error 2>&1 | grep -E "Test Case.*passed|TEST SUCCEEDED|0 tests|failed"
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — 2 tests passent. Success: vm.albums.count==3 (mock canned), isLoading false, errorMessage nil. Error: albums vide, errorMessage non-nil, isLoading false.
```

```
### AC-507 [type: new]
Assertion: AlbumsViewModel.createAlbum(name:description:assetIds:) appelle createAlbum(dto:) et append le résultat à albums sur succès. Sur erreur, albums inchangé + errorMessage.
Check post-impl: xcodebuild test ... -only-testing:ImmichSwiftUITests/AlbumsTests/test_AC_507_createAlbum_success -only-testing:ImmichSwiftUITests/AlbumsTests/test_AC_507b_createAlbum_error 2>&1 | grep -E "Test Case.*passed|TEST SUCCEEDED|0 tests|failed"
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — 2 tests passent. Success: albums.count 0→1, mock.lastCreateAlbumDto.albumName=="Test", assetIds propagés. Error: albums reste 0, errorMessage non-nil.
```

```
### AC-508 [type: new]
Assertion: AlbumDetailViewModel.load() appelle getAlbum(id:) PUIS searchMetadata(albumIds:[id]) pour peupler assets (car AlbumResponseDto n'a pas de champ assets côté serveur). Try-then-mutate: sur erreur getAlbum, album=nil + errorMessage; sur erreur searchMetadata, album populated mais assets=[] + errorMessage.
Check post-impl: xcodebuild test ... -only-testing:ImmichSwiftUITests/AlbumsTests/test_AC_508_detailLoad_success -only-testing:ImmichSwiftUITests/AlbumsTests/test_AC_508b_detailLoad_albumError -only-testing:ImmichSwiftUITests/AlbumsTests/test_AC_508c_detailLoad_assetsError 2>&1 | grep -E "Test Case.*passed|TEST SUCCEEDED|0 tests|failed"
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — 3 tests passent. Success: album non-nil + assets.count==2 (canned search response) + **mock.lastMetadataSearchDto?.albumIds == [albumId]** (prouve dispatch via albumIds). AlbumError: album==nil, assets==[], errorMessage non-nil. AssetsError: album non-nil (populated), assets==[], errorMessage non-nil (try-then-mutate: album muté AVANT le 2e appel qui throw).
```

```
### AC-509 [type: new]
Assertion: AlbumDetailViewModel.addAssets(ids:) appelle addAssetsToAlbum(albumId:dto:) puis refresh assets via searchMetadata. Try-then-mutate sur erreur.
Check post-impl: xcodebuild test ... -only-testing:ImmichSwiftUITests/AlbumsTests/test_AC_509_addAssets_success -only-testing:ImmichSwiftUITests/AlbumsTests/test_AC_509b_addAssets_error 2>&1 | grep -E "Test Case.*passed|TEST SUCCEEDED|0 tests|failed"
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — 2 tests passent. Success: mock.lastAddAssetsAlbumId==albumId, mock.lastAddAssetsIds contient ids, assets refreshed (count augmenté). Error: assets inchangés, errorMessage non-nil.
```

```
### AC-510 [type: new]
Assertion: AlbumDetailViewModel.removeAssets(ids:) appelle removeAssetsFromAlbum(albumId:dto:) et retire les items localement sur succès. Try-then-mutate sur erreur.
Check post-impl: xcodebuild test ... -only-testing:ImmichSwiftUITests/AlbumsTests/test_AC_510_removeAssets_success -only-testing:ImmichSwiftUITests/AlbumsTests/test_AC_510b_removeAssets_error 2>&1 | grep -E "Test Case.*passed|TEST SUCCEEDED|0 tests|failed"
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — 2 tests passent. Success: assets.count décrémenté du nombre retiré, mock.lastRemoveAssetsAlbumId==albumId. Error: assets inchangés.
```

```
### AC-511 [type: new]
Assertion: AlbumDetailViewModel.deleteAlbum() appelle deleteAlbum(id:) et set isDeleted=true sur succès. Sur erreur, isDeleted reste false + errorMessage.
Check post-impl: xcodebuild test ... -only-testing:ImmichSwiftUITests/AlbumsTests/test_AC_511_deleteAlbum_success -only-testing:ImmichSwiftUITests/AlbumsTests/test_AC_511b_deleteAlbum_error 2>&1 | grep -E "Test Case.*passed|TEST SUCCEEDED|0 tests|failed"
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — 2 tests passent. Success: isDeleted==true (deleteAlbum gère 204 No Content sans crash). Error: isDeleted==false, errorMessage non-nil.
```

```
### AC-512 [type: new]
Assertion: AlbumDetailViewModel.createSharedLink(password:description:) appelle createSharedLink(dto:) avec type=.ALBUM, albumId, password optionnel. Append à sharedLinks sur succès. Try-then-mutate.
Check post-impl: xcodebuild test ... -only-testing:ImmichSwiftUITests/AlbumsTests/test_AC_512_createSharedLink_noPassword -only-testing:ImmichSwiftUITests/AlbumsTests/test_AC_512b_createSharedLink_withPassword 2>&1 | grep -E "Test Case.*passed|TEST SUCCEEDED|0 tests|failed"
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — 2 tests passent. NoPassword: mock.lastCreateSharedLinkDto.type==.ALBUM, .albumId==albumId, .password==nil, sharedLinks.count 0→1. WithPassword: mock.lastCreateSharedLinkDto.password=="secret".
```

```
### AC-513 [type: new]
Assertion: AlbumDetailViewModel.loadSharedLinks() appelle getSharedLinks(albumId:) et peuple sharedLinks. revokeSharedLink(id:) appelle deleteSharedLink(id:) et retire localement. Try-then-mutate.
Check post-impl: xcodebuild test ... -only-testing:ImmichSwiftUITests/AlbumsTests/test_AC_513_loadRevokeSharedLinks 2>&1 | grep -E "Test Case.*passed|TEST SUCCEEDED|0 tests|failed"
Pre-state attendu: new — 0 tests ran.
Post-state attendu: new — 1 test passe. Load: sharedLinks.count==2 (canned), mock.lastSharedLinksAlbumId==albumId. Revoke: sharedLinks.count 2→1, mock.lastDeleteSharedLinkId==revoked id.
```

```
### AC-514 [type: new]
Assertion: RootView affiche un 5e onglet "Albums" (systemImage rectangle.stack) entre Timeline et Search. DependencyContainer expose makeAlbumsViewModel() + makeAlbumDetailViewModel(albumId:).
Check post-impl: test $(grep -c 'Label("Albums"' Sources/RootView.swift) -ge 1 && test $(grep -c 'makeAlbumsViewModel\|makeAlbumDetailViewModel' Sources/DependencyContainer.swift) -ge 2 && echo OK
Pre-state attendu: new — grep RootView retourne 0, grep DependencyContainer retourne 0.
Post-state attendu: new — RootView ≥1 occurrence Label("Albums"), DependencyContainer ≥2 occurrences factories, commande echo OK.
```

```
### AC-515 [type: new]
Assertion: TimelineView toolbar sélection affiche un bouton "Add to Album" (rectangle.stack.badge.plus) quand selectionMode actif, .disabled quand selectedIds vide, présentant une sheet picker. Le bouton porte `.accessibilityIdentifier("addToAlbumButton")` pour test robuste (pas de dépendance au nom de variable @State).
Check post-impl: test $(grep -c 'accessibilityIdentifier("addToAlbumButton")' Sources/Features/Timeline/TimelineView.swift) -ge 1 && test $(grep -c 'Add to Album' Sources/Features/Timeline/TimelineView.swift) -ge 1 && echo OK
Pre-state attendu: new — grep retourne 0.
Post-state attendu: new — TimelineView ≥1 accessibilityIdentifier("addToAlbumButton") + ≥1 "Add to Album" label, commande echo OK. Implémenteur DOIT nommer le bouton `.accessibilityIdentifier("addToAlbumButton")`.
```

```
### AC-516 [type: regression]
Assertion: TimelineViewModelTests + TimelineSectionBuilderTests restent verts après modification TimelineView (bouton Add to Album ajouté, pas de regression sur selection/delete/favorite).
Check post-impl: xcodebuild test ... -only-testing:ImmichSwiftUITests/TimelineViewModelTests -only-testing:ImmichSwiftUITests/TimelineSectionBuilderTests 2>&1 | grep -E "TEST SUCCEEDED|failed"
Pre-state attendu: regression — 12+6=18 tests verts (TimelineViewModelTests + TimelineSectionBuilderTests).
Post-state attendu: regression — TEST SUCCEEDED, 18 tests toujours verts.
```

```
### AC-517 [type: regression]
Assertion: La suite complète (87 tests pré-existants) reste verte après l'ajout d'Albums + SharedLinks.
Check post-impl: xcodebuild test ... 2>&1 | grep -E "Executed [0-9]+ tests|TEST SUCCEEDED|TEST FAILED"
Pre-state attendu: regression — 87 tests verts.
Post-state attendu: regression — TEST SUCCEEDED, ≥87 tests (87 + nouveaux AC tests), 0 failure.
```

```
### AC-518 [type: new]
Assertion: ImmichAPIClient.deleteAlbum(id:) et deleteSharedLink(id:) gèrent la réponse 204 No Content sans crash décodage (utilisent sendAuthedRaw, pas sendAuthed).
Check post-impl: grep -A5 'func deleteAlbum' Sources/Services/ImmichAPIClient.swift | grep -c 'sendAuthedRaw' | xargs test 1 -eq && grep -A5 'func deleteSharedLink' Sources/Services/ImmichAPIClient.swift | grep -c 'sendAuthedRaw' | xargs test 1 -eq
Pre-state attendu: new — fonctions inexistantes, grep retourne 0.
Post-state attendu: new — grep retourne 1 pour chaque (les 2 méthodes utilisent sendAuthedRaw).
```

```
### AC-519 [type: new]
Assertion: MetadataSearchDto a un champ `albumIds: [String]?` qui encode correctement vers JSON (clé "albumIds" array de strings, absent du JSON quand nil).
Check post-impl: xcodebuild test ... -only-testing:ImmichSwiftUITests/DTOEncodingTests/test_AC_519_metadataSearchAlbumIds 2>&1 | grep -E "Test Case.*passed|TEST SUCCEEDED|0 tests|failed"
Pre-state attendu: new — 0 tests ran (MetadataSearchDto n'a pas albumIds, grep "albumIds" SearchDTOs.swift retourne 0).
Post-state attendu: new — test passe. MetadataSearchDto(query:nil, albumIds:["a","b"]) encode JSON contenant "albumIds":["a","b"]. MetadataSearchDto(query:"x", albumIds:nil) encode JSON SANS clé albumIds.
```

```
### AC-520 [type: new]
Assertion: RootView propage AlbumsViewModel via `.environment(albums)` pour partager l'état entre tab Albums et picker Timeline (FM-3 mitigation). Au moins un consommateur (TimelineView OU AddToAlbumPickerSheet) lit via `@Environment(AlbumsViewModel.self)`.
Check post-impl: test $(grep -c 'environment(albums)\|environment(self.albums)' Sources/RootView.swift) -ge 1 && test $(grep -rE '@Environment\(AlbumsViewModel\.self\)' Sources/Features/) -ge 1 && echo OK
Pre-state attendu: new — grep RootView 0, grep Sources/Features 0.
Post-state attendu: new — RootView ≥1 `.environment(albums)`, Sources/Features ≥1 `@Environment(AlbumsViewModel.self)`, commande echo OK.
```

### Failure modes (top 3 + quel AC les détecte)

**FM-1: deleteAlbum/deleteSharedLink décodage crash sur 204 No Content**. Si impl utilise `sendAuthed<T:Decodable>` au lieu de `sendAuthedRaw`, le decoder throw sur body vide.
Détecté par: AC-518 (grep confirme sendAuthedRaw) + AC-511/AC-513 (tests réels deleteAlbum/revokeSharedLink).

**FM-2: AlbumDetailView grid vide — AlbumResponseDto n'a pas de champ assets côté serveur**. Si on suppose assets inline dans getAlbum(id:), le grid reste vide.
Détecté par: AC-508 (load success asserte assets.count==2 via searchMetadata séparé, pas via album.assets).

**FM-3: Timeline "Add to Album" capture une liste d'albums stale**. Si AlbumsViewModel est instancié séparément dans TimelineView sheet picker vs Albums tab, la liste diverge (créations/suppressions non synchronisées).
Détecté par: AC-520 (vérifie `.environment(albums)` dans RootView + `@Environment(AlbumsViewModel.self)` dans consumer). Mitigation design: AlbumsViewModel est @State au niveau RootView, injecté via `.environment(AlbumsViewModel.self)`, partagé à travers TimelineView + AlbumsView + AddToAlbumPickerSheet.

## Vérifications manuelles (hors auto-feedback loop)
- VM-A: Partage de l'état AlbumsViewModel entre tab Albums et picker Timeline (FM-3) — vérifier qu'une création dans un tab apparaît dans l'autre sans recharger.
- VM-B: SharedLinkSheet UX — copie du lien URL au presse-papier ( UIPasteboard), format URL `${baseURL}/share/${key}`, slug si défini.
- VM-C: cornerRadius 0 partout (albums cards, asset cells, shared link thumbnails) — cohérence Timeline tweak.
- VM-D: Confirmation alert avant delete album (destructive) + avant revoke shared link.
- VM-E: Transitions animations création/suppression album (fade + slide).
- VM-F: Empty states ContentUnavailableView ("No albums yet", "Album is empty", "No shared links").
- VM-G: Haptics `.success` (create album, add assets) / `.warning` (delete album, revoke link).
- VM-H: Runtime HTTP réelle — créer album sur serveur Immich réel, vérifier qu'il apparaît dans web client; créer share link, ouvrir URL en navigation privée, vérifier accès avec/sans password.
- VM-I: `expiresAt` format ISO8601 attendu par serveur (test avec expiration 24h, 7j, jamais).
- VM-J: `password` non affiché en clair dans UI après création (SharedLinkResponseDto.password retourne le hash/string — ne pas l'afficher, juste indiquer "protected").
```
