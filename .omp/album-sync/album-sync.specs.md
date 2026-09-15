# Task: album-sync

> **Audit 2026-09-15 — écart G2** (`.omp/backlog/ImmichSwiftUI-backlog.md` §2.17, phase P2) : le client Flutter miroite en **one-way** les albums **locaux de l'appareil** vers des albums **serveur de même nom** — `mobile/lib/domain/services/sync_linked_album.service.dart`, `local_sync.service.dart`, `local_album.service.dart`, contrat résumé dans `docs/docs/features/mobile-app.mdx` § Album Sync (fusion par nom, album partagé, structure figée à la création, synchronisation par utilisateur).
>
> Côté iOS, **aucun** appelant ne relie le backup aux albums : `ImmichClient` sait déjà faire le travail (`Sources/Core/Protocols/ImmichClient.swift:70-76` — `getAlbums`, `createAlbum`, `addAssetsToAlbum`), mais `grep -rn "addAssetsToAlbum" Sources/` ne renvoie que le protocole, `Sources/Services/ImmichAPIClient.swift:226` et `AddToAlbumPickerSheet` (ajout manuel multi-sélection).
>
> `BackupAlbumScope` (`Sources/Features/Upload/UploadViewModel.swift:11-18`) ne sert qu'à **filtrer** ce qui monte (`.all` / `.selected` / `.excluded`), jamais à **ranger** ce qui est monté.

**Objectif** : après cette fiche, l'utilisateur qui sauvegarde sa photothèque peut, album par album, activer un miroir device→serveur : chaque photo d'un album de l'appareil « Vacances » est ajoutée à l'album serveur « Vacances » au fil du run de backup.

L'album serveur est créé au premier run puis réutilisé par son identifiant, jamais re-résolu par nom. Une action de rattrapage « Reorganize into album » range dans ces albums les assets **déjà** uploadés lors de runs antérieurs, sans ré-uploader quoi que ce soit.

**Hors périmètre** :

- Le **sens serveur→appareil** et tout ce qui est destructif : aucun retrait d'asset d'un album (`removeAssetsFromAlbum` reste le fait de l'écran album), aucun renommage, aucune suppression.
- Aucune propagation vers Photos d'une suppression faite côté serveur.
- Le **partage** des albums miroir : `createAlbum(dto:)` est appelé sans `albumUsers`, aucun `AddUsersDto` n'est envoyé.
- L'« album partagé » de l'upstream s'entend donc au sens d'un album **déjà partagé avec** l'utilisateur : ce cas est couvert par la résolution, pas par la création.
- Les **smart albums** (Screenshots, Selfies, Bursts, Videos — `BackupAlbum.SmartID`, `Sources/Core/Protocols/BackupAssetSource.swift:36-46`) : leur appartenance change en continu côté Photos (un screenshot pris après le run entre dans le smart album sans être ré-uploadé), donc un miroir devrait se re-réconcilier à chaque lancement.
- Ces smart albums restent sélectionnables pour le *scope* de backup mais exclus du miroir.
- La **réparation d'un album serveur renommé ou supprimé à la main** : le mapping persisté pointe alors un id disparu, le run suivant reçoit `BulkIdErrorReason.not_found`, le miroir l'enregistre et ne recrée pas l'album — l'utilisateur repasse par le picker. Aucun écran de réparation n'est ajouté.
- L'**auto-backup en arrière-plan** (BGTask, Live Activity) reste inchangé : `AlbumSyncService` est appelé depuis le même `BackupEngine.run()`, aucun nouveau déclencheur n'est ajouté.

**Hypothèses** (vérifiées dans le dépôt et contre `immich-app/immich@main` = `e55ac299`, le 2026-09-15) :

- **Contrat HTTP du miroir**, relu dans `/tmp/immich-openapi-main.json` :
  - `GET /api/albums` (`operationId: getAllAlbums`, l. 2160-2222) → `AlbumResponseDto[]`.
  - `AlbumResponseDto` (`:19431`) porte `albumName` (`:19433`), `assetCount` (`:19448`) et `albumUsers` (`:19442`, « First entry is always the album owner »).
  - L'ownership se lit donc `albumUsers.first?.id` : il n'existe pas de champ `ownerId`.
  - `POST /api/albums` (`:2269-2284`) corps `CreateAlbumDto` (`:21474`) = `{ albumName, description?, assetIds?, albumUsers? }` → `AlbumResponseDto`.
  - `PUT /api/albums/{id}/assets` (`operationId: addAssetsToAlbum`) corps **`BulkIdsDto`** (corps l. 2723-2729, schéma `:21265`) = `{ ids: [uuid] }`.
  - Ce corps n'est **pas** `AddAssetsDto` : vérifié absent de `components.schemas`.
  - Réponse `[BulkIdResponseDto]` (`:19422`) = `{ id, success, error?, errorMessage? }`.
  - `error` est un `BulkIdErrorReason` = `duplicate | no_permission | not_found | unknown | validation`.
  - `POST /api/assets/bulk-upload-check` (`operationId: checkBulkUpload`) corps `AssetBulkUploadCheckDto` → `AssetBulkUploadCheckResult` : seule façon de retrouver l'id serveur d'un asset déjà monté.
- **Ce que le dépôt sait déjà faire** :
  - `Sources/Core/Protocols/ImmichClient.swift:70-76` : `getAlbums()`, `createAlbum(dto:)`, `addAssetsToAlbum(albumId:dto:) -> [BulkIdResponseDto]`.
  - `Sources/Services/ImmichAPIClient.swift:206-228` : ces trois méthodes sont implémentées (`PUT` sur `/albums/{id}/assets`, `body: AnyEncodable(dto)`).
  - `Sources/Core/Types/DTOs.swift:212` : `struct AssetMediaResponseDto { let id: String; let status: String }` — l'id serveur d'un upload frais est disponible.
  - `Sources/Core/Types/DTOs.swift:221-232` : `AssetBulkUploadCheckResponse.Result { id, action ("accept"|"reject"), reason?, assetId?, isTrashed? }`.
  - `assetId` y est renseigné sur le chemin `reject` (l'asset existe déjà), exactement ce que consomme déjà `reconcileLedgerIfDue()`.
  - `Sources/Services/BackupEngine.swift:536` : `_ = try await client.uploadAsset(…)` — **l'id rendu est jeté** ; le hook du miroir doit le capturer.
  - `Sources/Services/BackupLedger.swift:18-21` : `private struct Entry { let signature: String; var checksum: String? }` — le ledger ne persiste **aucun** id serveur.
  - Le rattrapage ne peut donc pas se faire hors ligne : il passe par `bulk-upload-check` sur `(id, checksum)` via `entriesForReconciliation()` (`:101`), comme `BackupEngine.reconcileLedgerIfDue()` (`:616-648`).
  - `Sources/Core/Protocols/BackupAssetSource.swift:27-34` : `BackupAlbum { id, name, count, isSmart }`.
  - `BackupCandidate` (`:12-25`) ne porte **aucun** nom d'album — `albumName` et `assetAlbumName` ont été retirés lors de la refonte du scan d'exclusion, parce qu'un aller-retour Photos par asset coûtait cher.
  - L'appartenance doit donc être re-dérivée **par album**, sur le modèle de `PhotoLibraryServiceImpl.excludedAssetIDs(_:)` (un `PHAsset.fetchAssets` par album, jamais un fetch par asset).
  - `Sources/Services/BackupEngine.swift:146` : `private static let checkChunkSize = 100` — la taille de lot à réutiliser, aussi bien pour `bulk-upload-check` que pour le flush des ajouts.
  - Réglages : `Sources/Features/Upload/UploadViewModel.swift:73-90` (`photoBackupEnabled`, `photoBackupAlbumScope`, `photoBackupSelectedAlbums`, `photoBackupExcludedAlbums`, `photoBackupAutoDetectNewPhotos`, clés legacy).
  - UI d'albums : `albumScopeSection` (`:589-648`), picker générique `AlbumPickerView(title:albums:selection:)` (`:444+`), helper `albumCount(_:_:)` (`:629`).
- **Ce qui rend la fiche nécessaire** : `grep -rn "AlbumSync\|Reorganize" Sources/` ne renvoie rien.
  - Aucun chemin de code ne relie un album Photos à un album serveur.
  - Le miroir n'est mentionné nulle part dans l'écran backup (`BackupSettingsView`, `UploadViewModel.swift:444-919`).

**Approche retenue** : A — un **service de miroir dédié**, `AlbumSyncService`, injecté dans `BackupEngine` et alimenté par deux points d'entrée.

Le premier est le flux du run : album serveur résolu au début du run, id d'asset bufferisé après chaque upload réussi. Le second est le rattrapage « Reorganize into album », qui résout les ids serveur par `bulk-upload-check` sur le ledger. Le mapping album-appareil → album-serveur est persisté **par utilisateur serveur** et figé à la création, conformément à l'upstream.

- **B (rejetée)** : porter le miroir dans la couche source (`BackupAssetSource`/`PhotoLibraryServiceImpl`, seule à connaître les albums) → rejetée parce que ce protocole est un adaptateur Photos **sans réseau** et `Sendable`, mocké en pur valeur.
  - Y injecter `any ImmichClient` ferait entrer HTTP dans l'adaptateur Photos.
  - Cela réintroduirait un aller-retour par asset — le coût exact que la refonte du scan d'exclusion a supprimé.
  - Cela rendrait le mock dépendant d'un client réseau.
- **C (rejetée)** : résoudre l'album serveur **par nom à chaque run** au lieu de persister le mapping → rejetée sur deux faits mesurables.
  - Deux albums homonymes sont possibles côté serveur (créé plus tard par l'utilisateur, ou album partagé homonyme reçu) : une résolution par nom peut retarger silencieusement le miroir vers l'album d'un tiers, alors que l'invariant upstream est « structure figée à la création ».
  - Le coût : un `GET /albums` complet à chaque run plus une comparaison de chaînes par album synchronisé, là où un mapping persisté est un accès `UserDefaults` par album.

## Étapes

1. **Le contrat du miroir** — NEW `Sources/Core/Protocols/AlbumSyncServicing.swift` : `protocol AlbumSyncServicing: Sendable` avec exactement quatre membres.
   - `func resolveAlbums(deviceAlbums: [BackupAlbum], syncedDeviceAlbumIDs: Set<String>, albumMembership: [String: [String]], userID: String, client: any ImmichClient) async throws -> [String: String]` — renvoie `deviceAlbumID → serverAlbumID`.
   - Ordre de résolution, par album appareil : mapping persisté quand il existe, sinon album serveur de même nom **possédé** par `userID` (`albumUsers.first?.id`), sinon album de même nom **partagé avec** lui, sinon création par `POST /api/albums` avec `albumName` seul.
   - Un smart album, ou un album absent de `syncedDeviceAlbumIDs`, n'entre jamais dans la carte.
   - `func stage(assetID: String, deviceAssetID: String) async` — bufferise un asset monté sous l'album serveur résolu pour cet album-appareil.
   - `func flush(client: any ImmichClient) async -> AlbumSyncOutcome` — envoie les buffers par `PUT /albums/{id}/assets` en lots et vide le buffer.
   - `func reorganize(entries: [(id: String, checksum: String)], albumMembership: [String: [String]], userID: String, client: any ImmichClient) async -> AlbumSyncOutcome`.
2. **Le service** — NEW `Sources/Services/AlbumSyncService.swift` : `actor AlbumSyncService: AlbumSyncServicing`.
   - État : `private let mapping: any AlbumSyncMappingStoring`, `private var deviceToServer: [String: String] = [:]`, `private var buffered: [String: Set<String>] = [:]` (serverAlbumID → assetIDs), `private var outcome = AlbumSyncOutcome()`.
   - `struct AlbumSyncOutcome: Sendable, Equatable { var added = 0; var alreadyInAlbum = 0; var failed = 0; var lastError: String? }`.
   - `alreadyInAlbum` compte les `BulkIdResponseDto` avec `success == false && error == .duplicate` : l'asset était déjà dans l'album, un re-run n'est pas une erreur.
   - `failed` compte `no_permission | not_found | unknown | validation` et retient le premier `errorMessage` dans `lastError`.
   - Corps envoyé : `BulkIdsDto(ids: Array(ids))` (`Sources/Core/Types/DTOs.swift`).
   - Taille de lot par `init(mapping:batchSize: Int = 100)` — la valeur est passée par l'appelant, alignée sur `BackupEngine.checkChunkSize`, aucune constante dupliquée.
   - `flush` sans rien de bufferisé, et `reorganize` avec un ensemble synchronisé vide, ne font **aucun** appel réseau.
   - `reorganize` : `checkBulkUpload` par lots sur `(id, checksum)`, ignore les résultats sans `assetId` et ceux marqués `isTrashed`, puis stage les paires résolues et délègue à `flush`.
3. **La persistance du mapping** — NEW `Sources/Services/AlbumSyncStore.swift` : `protocol AlbumSyncMappingStoring: AnyObject`.
   - `func serverAlbumID(userID: String, deviceAlbumID: String) -> String?`, `func record(userID: String, deviceAlbumID: String, serverAlbumID: String)`, `func forgetAll(userID: String)`.
   - Implémentation `@Observable @MainActor final class AlbumSyncStore: AlbumSyncMappingStoring` sur une suite injectable `UserDefaults(suiteName: "albumSync")` (même patron que `BackupSettingsStore`, `UploadViewModel.swift:92`).
   - Clé `albumSyncMap`, contenu `[userID: [deviceAlbumID: serverAlbumID]]`.
   - La clé par utilisateur est l'exigence upstream « synchronisation par utilisateur » : deux comptes serveur sur le même appareil ne partagent pas leurs albums.
4. **L'appartenance par album** — EDIT `Sources/Core/Protocols/BackupAssetSource.swift` : ajouter à `protocol BackupAssetSource` `func albumMembership(deviceAlbumIDs: Set<String>) -> [String: [String]]` (id d'asset local → ids d'albums appareil).
   - Le doc-comment dit que c'est un fetch **par album**, pendant exact de `excludedAssetIDs(_:)`, et que `BackupCandidate` reste volontairement sans nom d'album.
5. **L'implémentation Photos** — EDIT `Sources/Services/PhotoLibraryServiceImpl.swift` : implémenter `albumMembership(deviceAlbumIDs:)` à côté de `excludedAssetIDs(_:)`.
   - Un `PHAsset.fetchAssets(in:options:)` par `PHAssetCollection` locale, avec `options.includeHiddenAssets = false`.
   - Mêmes smart albums que `fetchAlbums()` ; une collection sans objet est simplement omise de la carte.
6. **Le mock de source** — EDIT `Tests/Mocks/MockBackupAssetSource.swift` (chemin à confirmer, cf. Incertitudes) : `var albumMembershipByDeviceAlbum: [String: [String]]` et l'implémentation de `albumMembership(deviceAlbumIDs:)`, en miroir du `excludedAssetIDs` déjà mocké.
7. **La résolution au début du run** — EDIT `Sources/Services/BackupEngine.swift` : dans `run()`, après le filtre du ledger (`remaining = remaining.filter { !ledger.isBackedUp(…) }`, `:264`), calculer la carte d'albums :
   `let albumMap = (try? await albumSync.resolveAlbums(deviceAlbums: source.fetchAlbums(), syncedDeviceAlbumIDs: settings.syncedAlbumIDs, albumMembership: source.albumMembership(deviceAlbumIDs: settings.syncedAlbumIDs), userID: userID, client: client)) ?? [:]`
   - `albumMap` est conservé pour la boucle d'upload.
   - Un échec de résolution (réseau, permission) ne doit **pas** interrompre le run : le backup continue, le miroir est simplement vide pour ce run.
8. **Le buffer après chaque upload** — EDIT `Sources/Services/BackupEngine.swift` : remplacer `_ = try await client.uploadAsset(…)` (`:536`) par `let uploaded = try await client.uploadAsset(…)`.
   - Juste après `ledger.markBackedUp` (`:550`) : `if let albumID = albumMap[deviceAlbumID(of: entry.candidate)] { await albumSync.stage(assetID: uploaded.id, deviceAssetID: entry.candidate.id) }`.
   - Le helper `deviceAlbumID(of:)` résout l'album-appareil du candidat via la carte d'appartenance déjà construite — aucun fetch Photos supplémentaire pendant la boucle.
9. **Le flush et le résultat exposé** — EDIT `Sources/Services/BackupEngine.swift` : après `ledger.save()` (`:382`), `let outcome = await albumSync.flush(client: client)`.
   - Publication sur le moteur via une propriété observée neuve `private(set) var albumSyncOutcome: AlbumSyncOutcome?`, au même titre que `failures`/`lastError`.
   - Le même `flush` est appelé dans le chemin d'annulation, pour ne pas perdre les assets déjà montés.
   - Le `userID` est passé à l'init du moteur (`String?`, fourni par `DependencyContainer` via `AuthViewModel`) ; le miroir est **inactif** (aucun appel, aucune résolution) quand il est `nil`.
10. **Les réglages** — EDIT `Sources/Features/Upload/UploadViewModel.swift` : dans `BackupSettingsStore`, `var syncedAlbumIDs: Set<String>` avec `didSet { defaults.set(Array(syncedAlbumIDs), forKey: Self.syncedAlbumsKey) }`.
    - `static let syncedAlbumsKey = "photoBackupSyncedAlbums"`, défaut vide — donc aucun comportement changé pour un utilisateur existant.
    - Le champ est inclus dans la capture `BackupSettings`/`snapshot()` (`:137-152`) et lu dans `init(suiteName:)` (`:92-131`).
11. **L'UI de sélection** — EDIT `Sources/Features/Upload/UploadViewModel.swift` (`albumScopeSection`, `:589-621`) : sous les deux `NavigationLink` d'albums, ajouter le troisième lien de miroir.
    - `NavigationLink { AlbumPickerView(title: "Albums to mirror", albums: vm.albums, selection: $vm.settings.syncedAlbumIDs) } label: { LabeledContent("Mirror into albums", value: albumCount(vm.settings.syncedAlbumIDs, "mirrored")) }`.
    - Le picker générique et `albumCount(_:_:)` sont réutilisés tels quels, aucune nouvelle vue n'est créée.
    - `albumScopeFooter` (`:637-647`) est complété d'une phrase disant que le miroir est **one-way** et ne supprime jamais rien.
12. **Le rattrapage côté ViewModel** — EDIT `Sources/Features/Upload/UploadViewModel.swift` : `func reorganizeIntoAlbums() async`.
    - Lit `engine.entriesForReconciliation()` (ledger, `:620`), appelle `await engine.reorganizeAlbums(entries:)` — méthode neuve du moteur qui réutilise la carte d'appartenance et délègue au service — puis rafraîchit `albumSyncOutcome`.
    - Expose `var albumSyncSummary: String?` (compteurs `added`/`alreadyInAlbum`/`failed` + `lastError`) et `var canReorganize: Bool { !settings.syncedAlbumIDs.isEmpty && trackedAssetCount > 0 }`.
13. **L'action dans l'écran** — EDIT `Sources/Features/Upload/UploadViewModel.swift` (`struct BackupSettingsView`) : ajouter une `reorganizeSection: some View` sur le modèle de `serverCheckSection` (`:508-525`), insérée après `albumScopeSection` dans le `Form` (`:452`).
    - `Button("Reorganize into album") { Task { await vm.reorganizeIntoAlbums() } }`, avec `.disabled(!vm.canReorganize)` et `.accessibilityIdentifier("backupReorganizeButton")`.
    - `LabeledContent("In albums", value: vm.albumSyncSummary ?? "—")` affiché quand `vm.albumSyncOutcome != nil`.
    - Un `.alert` sur `vm.albumSyncError` avec un bouton `OK` qui remet l'erreur à `nil`.
    - **Aucun `NavigationStack`** : `BackupSettingsView` est poussée depuis `ProfileView`, qui en porte déjà un ; la section ne fait que des `Section`/`Button`/`LabeledContent`.
14. **L'injection** — EDIT `Sources/DependencyContainer.swift` : `let albumSyncStore: AlbumSyncStore` et `func makeAlbumSyncService() -> AlbumSyncService`.
    - Le service est **unique par processus**, comme `upload` : deux services auraient deux buffers et le second perdrait la moitié des assets du run.
    - Le service et le `userID` courant sont passés à `UploadViewModel.init`, qui construit déjà le moteur avec `ledger`, `client` et `deviceIdentity`.
15. **Les tests du service** — NEW `Tests/AlbumSyncServiceTests.swift` (`import XCTest`, `@testable import ImmichSwiftUI`, `async` sur l'acteur), cas nommés :
    - `test_resolve_reusesPersistedMappingWithoutListingAlbums`
    - `test_resolve_mergesByNameWithOwnedAlbum`
    - `test_resolve_createsAlbumWhenNoNameMatch`
    - `test_resolve_ignoresAlbumOwnedByAnotherUser`
    - `test_mapping_isScopedPerUser`
    - `test_flush_batchesAtTheConfiguredChunkSize`
    - `test_flush_treatsDuplicateAsAlreadyInAlbum`
    - `test_flush_recordsPermissionErrorWithoutAbortingTheRun`
    - `test_flush_withEmptyBufferMakesNoRequest`
    - `test_reorganize_mapsLedgerIdsThroughBulkUploadCheck`
    - `test_reorganize_skipsEntriesWithNoRemoteAssetID`
16. **Les mocks** — EDIT le mock client des tests (`MockImmichClient`) : `getAlbums`/`createAlbum`/`addAssetsToAlbum` enregistreurs (`albumAddCalls`, `createdAlbumNames`, réponses `[BulkIdResponseDto]` programmables) ; EDIT `MockBackupAssetSource` pour `albumMembership`.
    - Aucun test d'intégration Photos : la fiche ne s'appuie que sur des valeurs (`[BackupAlbum]`, `[String: [String]]`).
17. `xcodegen generate` (trois fichiers source et un fichier de test sont ajoutés : sans régénération ils ne sont pas compilés) puis la suite complète `-only-testing:ImmichSwiftUITests`.

## Incertitudes à lever à l'implémentation

- **La stabilité de `BackupAlbum.id` (localIdentifier d'un `PHAssetCollection`) à travers une réinstallation.** Le mapping persisté utilise cet id ; s'il change, un réinstall fait perdre la paire album-appareil ↔ album-serveur et le run suivant peut retomber sur la résolution par nom (repli prévu) ou créer un doublon si l'album serveur a entre-temps été renommé.
  Trancher par : `grep -n "localIdentifier" Sources/Services/PhotoLibraryServiceImpl.swift`, puis un test manuel (réinstaller sur simulateur et relire la valeur) ; si l'id n'est pas stable, la clé de mapping doit devenir `(name, count au premier sync)`.
- **La signature exacte de l'opération d'ajout côté `ImmichClient`.** `addAssetsToAlbum(albumId:dto:)` prend un `BulkIdsDto` (`ImmichClient.swift:75`) : ne pas introduire un type `AddAssetsDto`, il n'existe pas dans le contrat.
  Trancher par : `python3 -c "import json;d=json.load(open('/tmp/immich-openapi-main.json'));print('AddAssetsDto' in d['components']['schemas'])"` → `False`.
- **La permission requise sur un album partagé.** Si `addAssetsToAlbum` déclare `x-immich-permission: albumAsset.create`, un album partagé en lecture seule renvoie `no_permission` par asset et le compteur `failed` d'`AlbumSyncOutcome` est légitime.
  Trancher par : `python3 -c "import json;d=json.load(open('/tmp/immich-openapi-main.json'));print(d['paths']['/albums/{id}/assets']['put'].get('x-immich-permission'))"`, puis ajuster le libellé d'erreur si la valeur diffère.
- **`assetId` sur un résultat `accept`.** Le rattrapage n'utilise que les résultats porteurs d'un `assetId` (`DTOs.swift:227`) ; un `accept` (asset absent du serveur) le laisse `nil` et l'entrée est ignorée — c'est le cas `test_reorganize_skipsEntriesWithNoRemoteAssetID`. Un asset `isTrashed` est ignoré aussi, même règle que `reconcileLedgerIfDue` (`BackupEngine.swift:616-648`).
  Trancher par : `python3 -c "import json;d=json.load(open('/tmp/immich-openapi-main.json'));print(json.dumps(d['components']['schemas']['AssetBulkUploadCheckResult']))"`.
- **L'emplacement exact du mock de `BackupAssetSource` et du mock client.** Les étapes 6 et 16 les modifient par nom de type ; vérifier le chemin réel avant d'éditer, ces fichiers ayant bougé lors de vagues précédentes.
  Trancher par : `grep -rln "MockBackupAssetSource" Tests/`.
- **Le libellé et les clés i18n.** Chaînes neuves : `Albums to mirror`, `Mirror into albums`, `Reorganize into album`, `In albums` et la phrase de footer. Aucune écriture manuelle dans `Resources/Localizable.xcstrings` : la clé est la chaîne anglaise et l'extraction est faite par Xcode au build.
  Trancher par : `python3 -c "import json;d=json.load(open('Resources/Localizable.xcstrings'));print([k for k in d['strings'] if 'irror' in k or 'eorganize' in k])"`.
- **La forme du sac `settings` reçu par `BackupEngine.run()`.** L'étape 10 ajoute `syncedAlbumIDs` à la capture ; si `run()` reçoit un `BackupSettings?` d'override (chemin « manual »), le champ doit y être présent sous peine d'un miroir vide sur les runs manuels.
  Trancher par : `grep -n "struct BackupSettings" -A 30 Sources/Features/Upload/UploadViewModel.swift`.
