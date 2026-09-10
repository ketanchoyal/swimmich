# Task: backup-live-photos

Status: shipped — AC-LP01–LP07 PASS le 2026-09-10 (suite 688 tests, TEST SUCCEEDED sur iPhone 17).

**Spec** : `.omp/backup-auto/backup-live-photos.specs.md`
**Dépendances** : à implémenter **après** `backup-album-scoping` et `backup-network-policy`, **avant** `backup-ledger-reconciliation` (qui ajoute `deviceAssetId`/`deviceId` aux appels `uploadAsset` que cette feature multiplie : un upload vidéo + un upload photo par Live Photo). Indépendant de `backup-library-observer`.

## Plan

**Objectif** : sauvegarder les Live Photos **comme des Live Photos**. Aujourd'hui `BackupEngine.processBatch` upload toujours avec `livePhotoVideoId: nil` en dur (`Sources/Services/BackupEngine.swift:410`) et n'exporte jamais la ressource `.pairedVideo` : le serveur reçoit une image morte et le `.MOV` n'existe nulle part ailleurs que sur l'appareil. Le client Flutter envoie la vidéo d'abord en `visibility=hidden`, puis la photo avec `livePhotoVideoId` (`.omp/backup-auto/flutter-auto-backup-study.md` §7.1).

**Hypothèses** (ground truth vérifié le 2026-09-09) :
- `BackupCandidate` (`Sources/Core/Protocols/BackupAssetSource.swift:12-22`) : `id, kind, fileName, fileCreatedAt, fileModifiedAt, duration, isFavorite, albumName` — aucun marqueur Live Photo.
- `BackupAssetSource` (même fichier, l.50-69) : `fetchAlbums`, `fetchCandidates(in:)`, `exportOriginal(for:onState:) -> URL`, `purgeStaleExports`.
- `PhotoLibraryServiceImpl.exportOriginal` (`Sources/Services/PhotoLibraryServiceImpl.swift:224-302`) choisit `.photo`/`.video`, puis `.fullSizePhoto`/`.fullSizeVideo`, puis la première ressource ; écrit via `PHAssetResourceManager.writeData` dans la boucle de retry `cloudRetryAttempts = 2` (l.76) avec `ContinuationGate` + `StallWatchdog`, et throw `BackupExportError.cloudDownloadPending` sur 1005 épuisé / stall. `makeCandidate` l.303-317.
- `AssetVisibility` (`Sources/Core/Constants.swift:54-57`) : `archive`, `timeline`, `hidden`.
- `ImmichClient.uploadAsset(...) -> AssetMediaResponseDto` (`Core/Protocols/ImmichClient.swift:169-172`) ; `AssetMediaResponseDto { id, status }` (`DTOs.swift:212-215`) — `status` = `"created"` ou `"duplicate"`, `id` renseigné dans les deux cas.
- `AssetBulkUploadCheckResponse.Result { id, action, reason?, assetId?, isTrashed? }` (`DTOs.swift:225-233`) — **un reject porte l'`assetId` distant**.
- `ImmichClient.updateAsset(id:dto:)` + `UpdateAssetDto.livePhotoVideoId` (`ImmichClient.swift:47`, `DTOs.swift:238-247`) existent déjà.
- Le pipeline `run()` stage `(candidate, checksum, fileURL)` et borne le chunk par `checkChunkSize = 100` (`BackupEngine.swift:124`) **ou** `maxBatchBytes = 512 << 20` = 512 MiB (l.128).

**Endpoints** : aucun nouveau. `POST /api/assets` (existants : `visibility`, `livePhotoVideoId`) et `PATCH /api/assets/:id` (`updateAsset` + `UpdateAssetDto.livePhotoVideoId`).

**Approche retenue** : **A — pair exporté au staging, uploadé avant la photo, rattachement rétroactif via `assetId` sur reject.**
- **B (rejetée)** : vidéo appairée comme item séparé du `bulkUploadCheck` (id synthétique `"<id>#video"`) — pollue le protocole de corrélation avec des ids qui ne sont pas des `localIdentifier` pour ne gagner qu'un cas rare.
- **C (rejetée)** : photo d'abord puis `updateAsset` systématique — deux requêtes sur le chemin normal, et fenêtre pendant laquelle la Live Photo est visible en image morte.

**Étapes** :
1. **EDIT** `Sources/Core/Protocols/BackupAssetSource.swift` — `BackupCandidate` : ajouter **en dernière position** `let isLivePhoto: Bool = false` (init memberwise préservé pour les tests) ; protocole : `func exportPairedVideo(for:onState:) async throws -> URL?` (`nil` quand pas de ressource appairée ; throw `BackupExportError.cloudDownloadPending` comme `exportOriginal`).
2. **EDIT** `Sources/Services/PhotoLibraryServiceImpl.swift` — `makeCandidate` : `isLivePhoto: asset.mediaSubtypes.contains(.photoLive)` ; extraire le corps de `exportOriginal` (l.247-302 : options, retry 1005, gate, watchdog, nettoyage du temp partiel) dans `private func writeResource(_:filenameHint:onState:) async throws -> URL` appelé par `exportOriginal` **et** `exportPairedVideo` — **aucune duplication** du durcissement iCloud ; `exportPairedVideo` sélectionne `.pairedVideo` puis `.fullSizePairedVideo`.
3. **EDIT** `Sources/Services/BackupEngine.swift` — staging `(candidate, checksum, fileURL, paired: (url, checksum)?)` ; dans la boucle de `run()` (l.246-294) exporter+hasher le pair si `isLivePhoto` (`batchBytes` additionne les deux tailles) ; un `BackupExportError` sur le pair **défère l'asset entier** ; `accept` → vidéo `.hidden` puis photo avec `livePhotoVideoId` ; `reject` + `assetId` → vidéo puis `updateAsset(livePhotoVideoId:)` ; un échec du rattachement rétroactif **ne bascule pas** l'asset en `failed` ; `notifyProgress()` inchangé (un asset = **une** unité de progression) ; `private static func removeStaged(_ entries:)` remplace les 7 appels `removeTempFiles(map(\.fileURL))` (l.235, 276, 288, 308, 368, 381, 393) et supprime **aussi** les temps du pair.
4. **EDIT** `Tests/Mocks/MockBackupAssetSource.swift` — `livePhotoIDs`, `pairedFailIDs`, `pairedDeferIDs` ; `MockImmichClient` : enregistrer l'ordre des uploads `(filename, visibility, livePhotoVideoId)` + les appels `updateAsset`.
5. **EDIT** `Tests/BackupEngineTests.swift` — `final class LivePhotoBackupTests`, 7 tests : ordre d'upload, id renvoyé, rattachement rétroactif, defer du pair, unité de progression, nettoyage temp à l'annulation, non-régression image simple.
6. Pas de `xcodegen` : aucun fichier source nouveau (tout est en EDIT).

**Risques** : disque (un chunk pèse photo + vidéo par asset — `maxBatchBytes` borne déjà l'agrégat, **ne pas** l'augmenter) ; coût iCloud (second download sur photothèque optimisée, déferré par le même mécanisme 1005).

## Acceptance Contract

### Approches candidates
**A (retenue)** : pair exporté au staging + upload vidéo→photo + rattachement rétroactif via `Result.assetId`.
**B** : pair comme item séparé du `bulkUploadCheck`. Rejetée (ids synthétiques).
**C** : photo puis `updateAsset` systématique. Rejetée (2 requêtes, état transitoire visible).

### Approche retenue + rationale
**A** — un seul appel réseau sur le chemin normal, ordre identique au client Flutter (la vidéo `hidden` n'apparaît jamais seule dans le timeline), et le chemin `reject`+`assetId` est le seul moyen de réparer les Live Photos déjà montées en images mortes.

### Critères

```
### AC-LP01 [type: new]
Assertion: BackupCandidate porte isLivePhoto et le protocole expose exportPairedVideo.
Check post-impl: sh -c 'f=Sources/Core/Protocols/BackupAssetSource.swift; grep -q "isLivePhoto" "$f" && grep -q "func exportPairedVideo" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-LP02 [type: new]
Assertion: PhotoLibraryServiceImpl remplit isLivePhoto depuis mediaSubtypes et exporte la ressource pairedVideo via le même chemin de retry iCloud.
Check post-impl: sh -c 'f=Sources/Services/PhotoLibraryServiceImpl.swift; grep -q "photoLive" "$f" && grep -q "pairedVideo" "$f" && grep -q "func writeResource" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-LP03 [type: new]
Assertion: la photo d'une Live Photo porte l'id de sa vidéo appairée (plus de `livePhotoVideoId: nil` sur le chemin photo) ; la vidéo part en `.hidden` avant elle.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -q "livePhotoVideoId: livePhotoVideoID" "$f" && grep -q "visibility: .hidden" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (l.410 livePhotoVideoId: nil sur TOUT upload)
Post-state attendu: PASS
```

```
### AC-LP04 [type: new]
Assertion: le reject d'une Live Photo déjà présente rattache la vidéo via updateAsset(assetId).
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -q "updateAsset" "$f" && grep -q "assetId" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-LP05 [type: new]
Assertion: aucun chemin de sortie ne fuit le fichier temporaire du pair — le nettoyage passe par un helper unique.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -q "func removeStaged" "$f" && test "$(grep -c "removeTempFiles(.*map(..fileURL))" "$f")" -eq 0 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (7 appels directs l.235/276/288/308/368/381/393)
Post-state attendu: PASS
```

```
### AC-LP06 [type: new]
Assertion: LivePhotoBackupTests couvre ordre d'upload, id renvoyé, rattachement rétroactif, defer du pair, unité de progression, nettoyage temp, non-régression image simple (≥7 tests).
Check post-impl: sh -c 'f=Tests/BackupEngineTests.swift; grep -q "final class LivePhotoBackupTests" "$f" && n=$(sed -n "/final class LivePhotoBackupTests/,/^}/p" "$f" | grep -c "func test_"); n=${n:-0}; test "$n" -ge 7 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-LP07 [type: regression]
Assertion: suite complète ≥ 645 tests (baseline mesurée le 2026-09-09), TEST SUCCEEDED.
Check post-impl: sh -c 'xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination "platform=iOS Simulator,name=iPhone 17" 2>&1 | tee /tmp/immich_lp_test.txt | grep -q "TEST SUCCEEDED" && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_lp_test.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "${n:-0}" -ge 645 && echo PASS || echo FAIL'
Pre-state attendu: n/a
Post-state attendu: PASS
```
