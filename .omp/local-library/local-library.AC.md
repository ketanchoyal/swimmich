# Task: local-library

Status: planifié — **aucune AC ouverte** (écart G3 du registre `.omp/backlog/ImmichSwiftUI-backlog.md`).

## Plan (résumé)

**Objectif** : une surface « On this device » (poussée depuis la section Management du hub « Me ») qui
énumère la photothèque locale sans passer par le serveur : résumé local (photos / vidéos / volume) mis en
regard du résumé distant, albums PhotoKit avec leur compte, grille des médias d'un album ou de toute la
photothèque, sélection multiple, verdict « déjà sauvegardé ? » par `POST /api/assets/bulk-upload-check`,
puis envoi de la seule sélection non reconnue par le serveur.

**Approche retenue** : A — feature neuve `Sources/Features/LocalLibrary/` (ViewModel + grille + cellule +
vue), entrée par une ligne `NavigationLink` voisine d'« Offline Storage » dans `ProfileView`. B (dans
`BackupSettingsView`) et C (segment dans `TimelineView`) sont rejetées : voir `.omp/local-library/local-library.specs.md`.

**Étapes** : (1) EDIT `PhotoLibraryService` + `PhotoLibraryServiceImpl` (point de vignette `loadThumbnail`) ;
(2) NEW `LocalLibrary{ViewModel,LocalAssetCell,LocalAssetGrid,View}.swift` ; (3) EDIT
`DependencyContainer.swift` (`makeLocalLibraryViewModel()`) ; (4) EDIT `RootView.swift` (`@State
localLibrary` passé à `ProfileView`) ; (5) EDIT `ProfileView.swift` (ligne `localLibraryRow`) ;
(6) NEW `Tests/LocalLibraryViewModelTests.swift` (8 cas) ; (7) `xcodegen generate` + suite complète.

**Décisions de contrat tranchées ici** (elles lèvent deux Incertitudes de la spec) : le résumé distant
réutilise le symbole existant `ImmichClient.getServerStatistics()` (`Sources/Features/Profile/StorageStatsViewModel.swift:38`,
`ServerStatsResponseDto.photos/.videos/.usage`) — pas de second décodage de `/assets/statistics` ; l'envoi
unitaire réutilise `ImmichClient.uploadAsset(fileURL:fileCreatedAt:fileModifiedAt:filename:duration:isFavorite:visibility:livePhotoVideoId:checksum:deviceAssetId:deviceId:)`
(`Sources/Core/Protocols/ImmichClient.swift:264`), jamais un multipart réécrit dans la feature.

## Critères

```
### AC-5020 [type: new]
Assertion: la source de photothèque locale est étendue — `PhotoLibraryService` déclare le point de vignette `loadThumbnail(for:targetSize:scale:)` (rendant `nil` plutôt que de jeter) et `PhotoLibraryServiceImpl` l'implémente via un `PHImageManager` partagé, sans accès réseau.
Check post-impl: sh -c 'p=Sources/Core/Protocols/PhotoLibraryService.swift; i=Sources/Services/PhotoLibraryServiceImpl.swift; grep -qF "import UIKit" "$p" && grep -qF "func loadThumbnail(for asset: PHAsset, targetSize: CGSize, scale: CGFloat) async -> UIImage" "$p" && grep -qF "func loadThumbnail(" "$i" && grep -qF "PHImageManager" "$i" && grep -qF "requestImage(" "$i" && grep -qF "options.isNetworkAccessAllowed = false" "$i" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune `loadThumbnail` dans `PhotoLibraryService.swift` ni `PhotoLibraryServiceImpl.swift` — le seul `loadThumbnail` du dépôt est `RoadTripViewModel.swift:215` ; `grep -c "^import UIKit" Sources/Core/Protocols/PhotoLibraryService.swift` = 0 ; la classe n'a que `isNetworkAccessAllowed = true` aux lignes 93 et 350)
Post-state attendu: PASS
Note: ne pas greper `cancelImageRequest` seul — il apparaît DÉJÀ dans `PhotoLibraryServiceImpl.swift:51,57` (garde du `loadData`) et l'écrire comme critère donnerait PASS sans la moindre vignette.
```

```
### AC-5021 [type: new]
Assertion: `LocalLibraryViewModel` existe, est isolé au MainActor, reçoit exactement les trois dépendances du conteneur (photoLibrary / albumSource / client) et expose l'état de lecture : phases, albums, assets, résumé local, résumé distant par le symbole existant `getServerStatistics()`.
Check post-impl: sh -c 'f=Sources/Features/LocalLibrary/LocalLibraryViewModel.swift; test -f "$f" && grep -qF "final class LocalLibraryViewModel" "$f" && grep -qF "@MainActor" "$f" && grep -qF "init(photoLibrary: any PhotoLibraryService, albumSource: any BackupAssetSource, client: any ImmichClient)" "$f" && grep -qF "enum Phase" "$f" && grep -qF "case checking" "$f" && grep -qF "case uploading" "$f" && grep -qF "var albums: [BackupAlbum] = []" "$f" && grep -qF "var assets: [PHAsset] = []" "$f" && grep -qF "var selectedIDs: Set<String> = []" "$f" && grep -qF "var remoteSummary: MediaSummary?" "$f" && grep -qF "struct MediaSummary" "$f" && grep -qF "func loadAlbums()" "$f" && grep -qF "func loadAssets(albumID: String?)" "$f" && grep -qF "albumSource.fetchAlbums()" "$f" && grep -qF "photoLibrary.fetchAssets()" "$f" && grep -qF "client.getServerStatistics()" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (dossier `Sources/Features/LocalLibrary` absent ; `grep -rn "LocalLibrary" Sources/ Tests/` ne renvoie rien)
Post-state attendu: PASS
Note: le résumé distant n'a pas de second DTO — `getServerStatistics()` remplit `photos` / `videos` / `usage` exactement comme `StorageStatsViewModel.load()` (`:38-47`) ; un échec laisse `remoteSummary == nil` et seuls les nouveaux libellés de l'écran distinguent les deux colonnes.
```

```
### AC-5022 [type: new]
Assertion: la résolution « déjà sauvegardé » passe par `POST /api/assets/bulk-upload-check` (symbole existant `client.bulkUploadCheck`) : un seul appel par lot de `checkChunkSize`, `reject` → `savedIDs` (déjà sur le serveur), `accept` → `localOnlyIDs`, et le verdict n'est jamais persisté.
Check post-impl: sh -c 'd=Sources/Features/LocalLibrary; f=$d/LocalLibraryViewModel.swift; test -f "$f" && grep -qF "func checkSelection() async" "$f" && grep -qF "client.bulkUploadCheck(" "$f" && grep -qF "AssetBulkUploadCheckRequest.Item(" "$f" && grep -qF "checkChunkSize" "$f" && grep -qF "photoLibrary.checksum(for:" "$f" && grep -qF "var localOnlyIDs: Set<String> = []" "$f" && grep -qF "var savedIDs: Set<String> = []" "$f" && grep -qF "\"reject\"" "$f" && grep -qF "\"accept\"" "$f" && ! grep -qE "BackupLedger\(|BackupLedger\." "$d"/*.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (ViewModel absent ; aucune écriture de verdict dans le dépôt — `BackupEngine.swift:627-633` traite le même verdict mais pour alimenter le ledger d'un run, hors contrat de cet écran)
Post-state attendu: PASS
Note: le verdict est éphémère par conception (spec, « Hors périmètre ») — le check échoue si la feature écrit dans `BackupLedger`.
```

```
### AC-5023 [type: new — l'écran délègue, il ne réimplémente pas l'upload]
Assertion: `uploadSelection()` n'envoie QUE `localOnlyIDs`, un asset à la fois, via le chemin d'upload existant (`client.uploadAsset`, `photoLibrary.loadData(for:)`), met à jour `uploadProgress`, puis bascule les envoyés dans `savedIDs` ; la feature ne contient ni transport ni moteur propres.
Check post-impl: sh -c 'd=Sources/Features/LocalLibrary; f=$d/LocalLibraryViewModel.swift; test -f "$f" && grep -qF "func uploadSelection() async" "$f" && grep -qF "client.uploadAsset(" "$f" && grep -qF "photoLibrary.loadData(for:" "$f" && grep -qF "var uploadProgress: (done: Int, total: Int)?" "$f" && grep -qF "savedIDs.formUnion(localOnlyIDs)" "$f" && grep -qF "localOnlyIDs.removeAll()" "$f" && ! grep -qE "URLRequest|URLSession|ImmichAPIClient|BackupEngine\(" "$d"/*.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (dossier absent ; `grep -rn "client.uploadAsset" Sources/Features/Profile Sources/Features/Offline` ne renvoie rien — le seul consommateur est `BackupEngine`)
Post-state attendu: PASS
Note: c'est l'AC qui empêche la dérive « seconde pile d'upload » : un asset rejeté par le serveur ne repart pas, et aucune feature ne réassemble un multipart à la main (le contrat `uploadAsset` est streamé depuis `fileURL`, `ImmichClient.swift:258-262`).
```

```
### AC-5024 [type: new]
Assertion: l'accès Photos est demandé explicitement — le ViewModel lit `authorizationStatus()` et appelle `requestAuthorization(_:)` quand le statut n'est pas déterminé, et le refus se rend par un `ContentUnavailableView` dans la vue (jamais une grille vide qui se lit comme une bibliothèque vide).
Check post-impl: sh -c 'd=Sources/Features/LocalLibrary; f=$d/LocalLibraryViewModel.swift; v=$d/LocalLibraryView.swift; test -f "$f" && test -f "$v" && grep -qF "authorizationStatus()" "$f" && grep -qF "requestAuthorization(" "$f" && grep -qF "PHAuthorizationStatus" "$f" && grep -qF "ContentUnavailableView" "$v" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichiers absents ; `PhotoLibraryService.swift:6-7` déclare déjà `authorizationStatus()` / `requestAuthorization(_:)` mais aucun consommateur d'affichage ne les utilise — seul `BackupEngine` les interroge)
Post-state attendu: PASS
```

```
### AC-5025 [type: new]
Assertion: la cellule et la grille locales existent : `LocalAssetCell` prend le `PHAsset`, l'état de sélection et un verdict optionnel (`isLocalOnly == nil` n'affiche RIEN : absence de verdict ≠ sauvegardé) et porte la pastille `Not on the server` ; `LocalAssetGrid` est paresseuse, à 3 colonnes espacées de `PVSpacing.s2` comme `AssetMultiSelectGrid`, et ne connaît pas le service (la vignette arrive par closure).
Check post-impl: sh -c 'd=Sources/Features/LocalLibrary; c=$d/LocalAssetCell.swift; g=$d/LocalAssetGrid.swift; test -f "$c" && test -f "$g" && grep -qF "struct LocalAssetCell: View" "$c" && grep -qF "let asset: PHAsset" "$c" && grep -qF "isLocalOnly: Bool?" "$c" && grep -qF "isLocalOnly == true" "$c" && grep -qF "arrow.up.circle.fill" "$c" && grep -qF "Not on the server" "$c" && grep -qF "struct LocalAssetGrid: View" "$g" && grep -qF "LazyVGrid" "$g" && grep -qF "PVSpacing.s2" "$g" && grep -qF "loadThumbnail: (PHAsset) async -> UIImage?" "$g" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (dossier absent ; aucune grille du dépôt ne rend un `PHAsset` — `AssetMultiSelectGrid.swift` est typée sur `[AssetReactItem]`)
Post-state attendu: PASS
```

```
### AC-5026 [type: new]
Assertion: `LocalLibraryView` est la surface complète : barre de sélection en `safeAreaInset(edge: .bottom)`, titre `On this device`, `refreshable`, les identifiants d'accessibilité de l'écran, et AUCUN `NavigationStack` propre (elle est poussée par `ProfileView`, qui en porte un).
Check post-impl: sh -c 'v=Sources/Features/LocalLibrary/LocalLibraryView.swift; test -f "$v" && grep -qF "struct LocalLibraryView: View" "$v" && grep -qF "@Bindable var vm: LocalLibraryViewModel" "$v" && grep -qF "safeAreaInset" "$v" && grep -qF "On this device" "$v" && grep -qF "refreshable" "$v" && grep -qF "localLibrarySummary" "$v" && grep -qF "localAssetGrid" "$v" && grep -qF "checkSelectionButton" "$v" && grep -qF "uploadSelectionButton" "$v" && grep -qF "localAlbumRow" "$v" && ! grep -qE "NavigationStack \{" "$v" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent ; précédent du contrat : `OfflineAssetsView` et `BackupSettingsView` sont poussées par `ProfileView.swift:108,64` sans stack propre)
Post-state attendu: PASS
Note: le check vise la DÉCLARATION (`NavigationStack {`) — greper le seul mot échouerait sur le doc-comment qui explique l'absence de stack (piège de la carte stacks-ui).
```

```
### AC-5027 [type: new]
Assertion: la feature est assemblée par le composition root et atteignable depuis le hub « Me » : factory `makeLocalLibraryViewModel()` dans `DependencyContainer`, instance unique `@State localLibrary` dans `AuthenticatedRoot` passée à `ProfileView`, et ligne `localLibraryRow` voisine d'« Offline Storage ».
Check post-impl: sh -c 'c=Sources/DependencyContainer.swift; r=Sources/RootView.swift; p=Sources/Features/Profile/ProfileView.swift; grep -qF "func makeLocalLibraryViewModel" "$c" && grep -qF "makeLocalLibraryViewModel()" "$r" && grep -qF "localLibrary: LocalLibraryViewModel" "$r" && grep -qF "localLibrary: localLibrary" "$r" && grep -qF "var localLibrary: LocalLibraryViewModel" "$p" && grep -qF "LocalLibraryView(vm:" "$p" && grep -qF "localLibraryRow" "$p" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune factory LocalLibrary — `grep -c "makeOfflineDownloadViewModel" Sources/DependencyContainer.swift` = 1, c'est la seule factory voisine ; `RootView.swift:108` s'arrête à `@State private var offline`)
Post-state attendu: PASS
```

```
### AC-5028 [type: new]
Assertion: `Tests/LocalLibraryViewModelTests.swift` expose ≥ 8 cas nommés couvrant l'énumération (albums, photothèque entière, album ciblé), la scission accept/reject, l'envoi restreint aux local-only, le no-op, l'échec du résumé distant et l'état de sélection.
Check post-impl: sh -c 'f=Tests/LocalLibraryViewModelTests.swift; n=0; test -f "$f" && n=$(grep -cE "func test_" "$f"); test "$n" -ge 8 && grep -qF "test_loadAlbums_exposesUserAndSmartAlbums" "$f" && grep -qF "test_loadAssets_withoutAlbumID_returnsWholeLibrary" "$f" && grep -qF "test_loadAssets_withAlbumID_scopesToThatAlbum" "$f" && grep -qF "test_checkSelection_splitsAcceptedAndRejected" "$f" && grep -qF "test_uploadSelection_sendsOnlyAcceptedIDs" "$f" && grep -qF "test_uploadSelection_isNoOp_whenNothingIsLocalOnly" "$f" && grep -qF "test_loadRemoteSummary_failure_leavesRemoteNil" "$f" && grep -qF "test_selectionState_togglesAndClears" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier de test absent)
Post-state attendu: PASS
Note: un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate` (quatre sources et un test ont été ajoutés) — sans régénération la suite passe « verte » par omission.
```

```
### AC-5029 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED.
Check post-impl: sh -c 'l=/tmp/immich_locallibrary_test.log; n=0; test -f "$l" && n=$(grep -oE "Executed [0-9]+ tests" "$l" | grep -oE "[0-9]+" | sort -n | tail -1); grep -qE "TEST SUCCEEDED" "$l" 2>/dev/null && test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent)
Post-state attendu: PASS
```
