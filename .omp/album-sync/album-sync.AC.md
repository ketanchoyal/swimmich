# Task: album-sync

Status: planifié — 9 AC neuves + 1 régression (bande AC-5010 → AC-5019, écart G2 du registre
`.omp/backlog/ImmichSwiftUI-backlog.md` §2.17).

## Plan (résumé)

**Objectif** : miroir one-way device→serveur des albums locaux vers des albums serveur, au fil du run de
backup, plus une action de rattrapage « Reorganize into album » pour les assets déjà montés.

**Approche retenue** : A — service de miroir dédié `AlbumSyncService` (acteur), alimenté par deux points
d'entrée : le flux du run (résolution en tête de `run()`, `stage` après chaque upload accepté, `flush` en fin
de run et sur le chemin d'annulation) et le rattrapage par `checkBulkUpload` sur le ledger. Le mapping
album-appareil → album-serveur est persisté **par utilisateur serveur** (`AlbumSyncStore`), jamais re-résolu
par nom une fois écrit.

**Étapes** : (1) NEW `Sources/Core/Protocols/AlbumSyncServicing.swift` ; (2) NEW
`Sources/Services/AlbumSyncService.swift` ; (3) NEW `Sources/Services/AlbumSyncStore.swift` ; (4) EDIT
`BackupAssetSource` + `PhotoLibraryServiceImpl` (`albumMembership(deviceAlbumIDs:)`, un fetch par album) ;
(5) EDIT `BackupEngine` (capture de `uploadAsset(...).id`, `albumMap`, `resolveAlbums`, `flush`,
`reorganizeAlbums`, `albumSyncOutcome`) ; (6) EDIT `UploadViewModel.swift` (`syncedAlbumIDs`, lien picker
« Mirror into albums », `reorganizeIntoAlbums()`, section + bouton) ; (7) EDIT `DependencyContainer.swift`
(factory et service unique par processus) ; (8) NEW `Tests/AlbumSyncServiceTests.swift` + mocks ; (9)
`xcodegen generate` puis suite complète.

**Incertitudes** : stabilité de `BackupAlbum.id` (`localIdentifier` d'un `PHAssetCollection`) à travers une
réinstallation ; permission `albumAsset.create` sur un album partagé en lecture seule ; présence de
`syncedAlbumIDs` dans le sac `BackupSettings` des runs manuels ; chemin réel de `MockBackupAssetSource`
(cf. `.omp/album-sync/album-sync.specs.md` § Incertitudes).

## Critères

```
### AC-5010 [type: new]
Assertion: le contrat du miroir existe comme protocole `Sendable` avec exactement ses quatre membres (résolution, bufferisation, flush, rattrapage), et rien d'autre n'est ajouté au contrat.
Check post-impl: sh -c 'f=Sources/Core/Protocols/AlbumSyncServicing.swift; test -f "$f" && grep -qE "protocol AlbumSyncServicing" "$f" && grep -qE "func resolveAlbums" "$f" && grep -qE "func stage" "$f" && grep -qE "func flush" "$f" && grep -qE "func reorganize" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -rn "AlbumSync" Sources/` ne renvoie rien — aucun contrat, aucun service)
Post-state attendu: PASS
```

```
### AC-5011 [type: new]
Assertion: `AlbumSyncService` est un acteur qui porte l'état du miroir (mapping, buffer par album serveur, outcome) et compose le corps de requête existant `BulkIdsDto` avec une taille de lot injectée — aucune constante de taille dupliquée.
Check post-impl: sh -c 'f=Sources/Services/AlbumSyncService.swift; test -f "$f" && grep -qE "actor AlbumSyncService" "$f" && grep -qE "struct AlbumSyncOutcome" "$f" && grep -qE "var alreadyInAlbum" "$f" && grep -qE "var lastError" "$f" && grep -qE "BulkIdsDto" "$f" && grep -qE "batchSize" "$f" && grep -qE "buffered" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-5012 [type: new]
Assertion: le mapping device→serveur est persisté par compte serveur dans une suite `UserDefaults` dédiée (deux comptes sur le même appareil ne partagent pas leurs albums), avec lecture, écriture et oubli ciblés par utilisateur.
Check post-impl: sh -c 'f=Sources/Services/AlbumSyncStore.swift; test -f "$f" && grep -qE "protocol AlbumSyncMappingStoring" "$f" && grep -qE "func serverAlbumID" "$f" && grep -qE "func record" "$f" && grep -qE "func forgetAll" "$f" && grep -qE "albumSyncMap" "$f" && grep -qE "final class AlbumSyncStore" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent ; `grep -rn "albumSyncMap" Sources/` vide)
Post-state attendu: PASS
```

```
### AC-5013 [type: new — l'id serveur d'un upload frais n'est plus jeté]
Assertion: `BackupEngine` capture l'`id` rendu par `uploadAsset` et bufferise l'asset sous l'album serveur résolu pour son album-appareil ; le motif `_ = try await client.uploadAsset(` a disparu.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -qE "let uploaded = try await client.uploadAsset" "$f" && ! grep -qE "_ = try await client.uploadAsset" "$f" && grep -qE "await albumSync.stage" "$f" && grep -qE "uploaded.id" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Services/BackupEngine.swift:536` = `_ = try await client.uploadAsset(` — l'id est jeté, vérifié le 2026-09-15)
Post-state attendu: PASS
```

```
### AC-5014 [type: new]
Assertion: le run résout la carte d'albums une fois en tête, et le miroir expose son résultat sur le moteur ; un échec de résolution ne doit pas interrompre le backup (repli sur une carte vide).
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -qE "albumSync.resolveAlbums" "$f" && grep -qE "albumSync.flush" "$f" && grep -qE "var albumSyncOutcome" "$f" && grep -qF "?? [:]" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -rn "AlbumSync\|albumSyncOutcome" Sources/Services/BackupEngine.swift` vide)
Post-state attendu: PASS
```

```
### AC-5015 [type: new — le rattrapage passe par le ledger, pas par un ré-upload]
Assertion: le rattrapage résout les ids serveur des assets déjà montés par `checkBulkUpload` sur les paires du ledger, ignore les résultats sans `assetId` et ceux marqués `isTrashed`, puis délègue au flush ; le moteur expose la méthode qui alimente ce chemin depuis `entriesForReconciliation()`.
Check post-impl: sh -c 'f=Sources/Services/AlbumSyncService.swift; g=Sources/Services/BackupEngine.swift; grep -qE "checkBulkUpload" "$f" && grep -qE "isTrashed" "$f" && grep -qE "func reorganize" "$f" && grep -qE "func reorganizeAlbums" "$g" && grep -qE "func entriesForReconciliation" "$g" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`AlbumSyncService.swift` absent ; aucun `reorganize` dans `Sources/` — `grep -rn "Reorganize" Sources/` vide)
Post-state attendu: PASS
```

```
### AC-5016 [type: new — `BackupEngine` reste le seul point d'envoi]
Assertion: la couche vue ne parle ni à `addAssetsToAlbum` ni à `createAlbum` : le ViewModel relit le ledger et délègue au moteur, et le service de miroir est construit par le composition root (instance unique par processus, comme `upload`).
Check post-impl: sh -c 'a=Sources/Features/Upload/UploadViewModel.swift; c=Sources/DependencyContainer.swift; ! grep -qE "addAssetsToAlbum|createAlbum" "$a" && grep -qE "reorganizeAlbums" "$a" && grep -qE "func reorganizeIntoAlbums" "$a" && grep -qE "func makeAlbumSyncService" "$c" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`reorganizeIntoAlbums` et `makeAlbumSyncService` absents ; `addAssetsToAlbum` n'est appelé que depuis `AddToAlbumPickerSheet`, jamais depuis `UploadViewModel`)
Post-state attendu: PASS
```

```
### AC-5017 [type: new]
Assertion: les albums à mirroir sont un réglage persisté à part du scope de backup (défaut vide : aucun comportement changé pour un utilisateur existant), sélectionnables via le picker générique, et l'action de rattrapage est atteignable avec son identifiant d'accessibilité et son garde-fou.
Check post-impl: sh -c 'a=Sources/Features/Upload/UploadViewModel.swift; grep -qE "var syncedAlbumIDs" "$a" && grep -qE "photoBackupSyncedAlbums" "$a" && grep -qE "Albums to mirror" "$a" && grep -qE "Mirror into albums" "$a" && grep -qE "Reorganize into album" "$a" && grep -qE "backupReorganizeButton" "$a" && grep -qE "var canReorganize" "$a" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -n "syncedAlbumIDs\|Mirror\|Reorganize" Sources/Features/Upload/UploadViewModel.swift` vide ; le picker d'albums n'existe que pour `photoBackupSelectedAlbums` / `photoBackupExcludedAlbums`)
Post-state attendu: PASS
Note: l'identifiant est posé sur le `Button` (élément interactif), pas sur la `Section`. Le check ne peut pas prouver l'absence de `NavigationStack` dans la vue (le fichier en porte deux ailleurs, l. 451 et 1033) : `reorganizeSection` se limite à `Section`/`Button`/`LabeledContent`, `BackupSettingsView` étant déjà poussée par `ProfileView`.
```

```
### AC-5018 [type: new]
Assertion: `Tests/AlbumSyncServiceTests.swift` couvre les cas nommés de la fiche : réutilisation du mapping sans listing, fusion par nom, création, exclusion d'un album d'autrui, cloisonnement par utilisateur, lots, doublon, erreur de permission, buffer vide sans requête, et rattrapage par le ledger.
Check post-impl: sh -c 'f=Tests/AlbumSyncServiceTests.swift; test -f "$f" && n=$(grep -cE "func test_" "$f"); test "$n" -ge 11 && grep -qE "test_resolve_reusesPersistedMappingWithoutListingAlbums" "$f" && grep -qE "test_mapping_isScopedPerUser" "$f" && grep -qE "test_flush_batchesAtTheConfiguredChunkSize" "$f" && grep -qE "test_flush_withEmptyBufferMakesNoRequest" "$f" && grep -qE "test_reorganize_mapsLedgerIdsThroughBulkUploadCheck" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate` — sans régénération la suite passe « verte » par omission.
```

```
### AC-5019 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_albumsync_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_albumsync_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent)
Post-state attendu: PASS
```
