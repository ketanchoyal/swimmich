# Task: backup-live-photos

**Objectif** : sauvegarder les Live Photos comme des Live Photos. Aujourd'hui
`BackupEngine.processBatch` upload toujours avec `livePhotoVideoId: nil`
(`Sources/Services/BackupEngine.swift:410`) et n'envoie jamais la ressource
vidéo appairée : sur le serveur, une Live Photo arrive en image morte et le
`.MOV` est définitivement perdu (il n'est nulle part ailleurs que dans la
photothèque locale). Le client Flutter upstream, lui, envoie la vidéo d'abord en
`visibility=hidden`, puis la photo avec `livePhotoVideoId` (étude
`.omp/backup-auto/flutter-auto-backup-study.md` §7.1).

**Hypothèses (vérifiées dans le dépôt le 2026-09-09)** :
- `BackupCandidate` (`Sources/Core/Protocols/BackupAssetSource.swift:12-22`) :
  `id, kind, fileName, fileCreatedAt, fileModifiedAt, duration, isFavorite,
  albumName`. Aucun marqueur Live Photo.
- `BackupAssetSource` (même fichier, l.50-69) : `fetchAlbums`,
  `fetchCandidates(in:)`, `exportOriginal(for:onState:) -> URL`,
  `purgeStaleExports`.
- `PhotoLibraryServiceImpl.exportOriginal`
  (`Sources/Services/PhotoLibraryServiceImpl.swift:224-302`) choisit la ressource
  `.photo`/`.video`, sinon `.fullSizePhoto`/`.fullSizeVideo`, sinon la première ;
  écrit via `PHAssetResourceManager.writeData` dans une boucle de retry
  `cloudRetryAttempts = 2` (l.76) avec `ContinuationGate` + `StallWatchdog`, et
  throw `BackupExportError.cloudDownloadPending` sur 1005 épuisé / stall.
- `makeCandidate` (l.303-317) construit le candidat depuis un `PHAsset`.
- `AssetVisibility` (`Sources/Core/Constants.swift:54-57`) : `archive`,
  `timeline`, `hidden`.
- `ImmichClient.uploadAsset(fileURL:fileCreatedAt:fileModifiedAt:filename:duration:isFavorite:visibility:livePhotoVideoId:checksum:)
  -> AssetMediaResponseDto` (`Core/Protocols/ImmichClient.swift:169-172`) ;
  `AssetMediaResponseDto { id, status }` (`DTOs.swift:212-215`) — `status` vaut
  `"created"` ou `"duplicate"`, et l'`id` est renseigné dans les deux cas.
- `AssetBulkUploadCheckResponse.Result { id, action, reason?, assetId?, isTrashed? }`
  (`DTOs.swift:225-233`) — **un reject porte l'`assetId` distant**, ce qui permet
  de rattacher la vidéo à une photo déjà sur le serveur.
- `ImmichClient.updateAsset(id:dto:)` + `UpdateAssetDto.livePhotoVideoId`
  (`ImmichClient.swift:47`, `DTOs.swift:238-247`) existent déjà : aucun nouvel
  endpoint n'est nécessaire.
- Le pipeline `run()` stage `(candidate, checksum, fileURL)` et borne le chunk
  par `checkChunkSize = 100` (`BackupEngine.swift:124`) **ou**
  `maxBatchBytes = 512 << 20` = 512 MiB (l.128).

**Approche retenue** : **A — pair exporté au staging, uploadé avant la photo,
rattachement rétroactif via `assetId` sur reject.**

1. Au staging, si le candidat est une Live Photo, exporter *aussi* la ressource
   `.pairedVideo` dans un second fichier temporaire et le hasher. Les deux
   tailles comptent dans `batchBytes`.
2. `processBatch` : la dédup `bulkUploadCheck` reste faite sur le checksum de la
   **photo** (un seul item par asset, pas d'id synthétique).
   - `accept` → upload vidéo (`visibility: .hidden`, `duration` du pair,
     `livePhotoVideoId: nil`) → `response.id` → upload photo avec
     `livePhotoVideoId: videoID`.
   - `reject` **et** candidat Live Photo **et** `result.assetId != nil` → upload
     de la vidéo puis `updateAsset(id: assetId, dto: UpdateAssetDto(livePhotoVideoId: videoID))`.
     C'est ce qui répare les Live Photos déjà montées en images mortes par les
     runs précédents — sans ce chemin, elles restent mortes pour toujours (le
     serveur rejettera éternellement la photo par checksum, et « Reset backup
     tracking » n'y change rien).
3. Idempotence : ré-uploader une vidéo déjà présente renvoie
   `status == "duplicate"` avec l'id existant, donc un run interrompu entre la
   vidéo et la photo se répare tout seul au run suivant, sans doublon.

- **B (rejetée)** : envoyer la vidéo appairée comme item séparé du
  `bulkUploadCheck` (id synthétique `"<id>#video"`). Pollue le protocole de
  corrélation avec des ids qui ne sont pas des `localIdentifier`, pour ne gagner
  qu'un upload évité dans le cas rare « vidéo déjà là, photo pas là ».
- **C (rejetée)** : upload de la photo d'abord puis `updateAsset` systématique.
  Deux requêtes au lieu d'une sur le chemin normal, et fenêtre pendant laquelle
  la Live Photo est visible en image morte dans le timeline.

## Étapes

1. **EDIT** `Sources/Core/Protocols/BackupAssetSource.swift`
   - `BackupCandidate` : ajouter **en dernière position** `let isLivePhoto: Bool = false`
     (valeur par défaut ⇒ l'init memberwise reste compatible avec les
     constructions existantes des tests).
   - Protocole : `func exportPairedVideo(for candidate: BackupCandidate, onState: @escaping @Sendable (BackupExportState) -> Void) async throws -> URL?`
     — retourne `nil` quand l'asset n'a pas de ressource appairée ; throw
     `BackupExportError.cloudDownloadPending` comme `exportOriginal` (le pair
     d'une photothèque optimisée n'est pas local non plus).
2. **EDIT** `Sources/Services/PhotoLibraryServiceImpl.swift`
   - `makeCandidate` : `isLivePhoto: asset.mediaSubtypes.contains(.photoLive)`.
   - Extraire le corps de `exportOriginal` (l.247-302 : options, boucle de retry
     1005, gate, watchdog, nettoyage du temp partiel) dans
     `private func writeResource(_ resource: PHAssetResource, filenameHint: String, onState:) async throws -> URL`,
     puis l'appeler depuis `exportOriginal` **et** `exportPairedVideo`. Aucune
     duplication de la logique de retry : c'est elle qui porte tout le durcissement
     iCloud (mem `f58c3ae9`, `43d566e9`).
   - `exportPairedVideo` sélectionne `.pairedVideo` puis `.fullSizePairedVideo`,
     retourne `nil` si aucune.
3. **EDIT** `Sources/Services/BackupEngine.swift`
   - Type du staging : `(candidate: BackupCandidate, checksum: String, fileURL: URL, paired: (url: URL, checksum: String)?)`.
   - Dans la boucle de `run()` (l.246-294) : après l'export+hash de la photo, si
     `candidate.isLivePhoto`, exporter + hasher le pair. `batchBytes` additionne
     les deux tailles. Un `BackupExportError` sur le pair défère **l'asset
     entier** (supprimer le temp de la photo, `deferredCount += 1`) ; une erreur
     dure sur le pair compte un `failedCount` avec la raison du pair.
   - Nettoyage : **tous** les chemins qui appellent `Self.removeTempFiles` (annulation
     l.235/276/288/299, rejets l.381, échec bulk-check l.368, fin d'upload l.420,
     annulation mid-upload l.393) doivent aussi supprimer les `paired?.url`.
     Introduire `private static func removeStaged(_ entries: [StagedEntry])` et
     l'utiliser partout plutôt que `removeTempFiles(map(\.fileURL))`.
   - Chemin `accept` : vidéo (`.hidden`) puis photo avec `livePhotoVideoId`.
     Chemin `reject` d'une Live Photo avec `assetId` : vidéo puis `updateAsset`.
     Un échec du rattachement rétroactif ne doit **pas** faire basculer l'asset
     en `failed` (la photo est bien sur le serveur) : `failures.append` avec la
     raison, mais l'asset reste compté `rejected` et est marqué dans le ledger.
   - `notifyProgress()` est appelé aux mêmes points qu'aujourd'hui — un asset
     Live Photo reste **une** unité de progression, pas deux (mem `0810015a`).
4. **EDIT** `Tests/Mocks/MockBackupAssetSource.swift`
   - `livePhotoIDs: Set<String>` (le mock renvoie une URL de pair pour ces ids,
     `nil` sinon), `pairedFailIDs`, `pairedDeferIDs`,
   - `MockImmichClient` : enregistrer l'ordre des uploads avec
     `(filename, visibility, livePhotoVideoId)` et les appels `updateAsset`.
5. **EDIT** `Tests/BackupEngineTests.swift` — nouvelle classe `LivePhotoBackupTests` :
   - `test_livePhoto_uploadsVideoHiddenBeforePhotoWithPairID`
   - `test_livePhoto_photoCarriesReturnedVideoID`
   - `test_livePhoto_rejectedPhotoStillLinksPairedVideoViaUpdateAsset`
   - `test_livePhoto_pairedExportDeferredDefersWholeAsset`
   - `test_livePhoto_countsAsSingleProgressUnit`
   - `test_livePhoto_pairedTempFileDeletedOnCancel`
   - `test_stillImage_unchangedNoPairedUploadNoUpdateAsset` (non-régression)
6. Pas de `xcodegen` : aucun fichier source nouveau (tout est en EDIT).

## Risques

- **Disque** : un chunk staged peut désormais peser photo + vidéo par asset.
  `maxBatchBytes` borne déjà l'agrégat, donc la borne tient ; le nombre d'assets
  par chunk baisse simplement sur une bibliothèque à Live Photos. Ne pas
  augmenter `maxBatchBytes` (mem `2df93d54` : c'est ce budget qui évite le kill
  jetsam).
- **Coût iCloud** : sur photothèque optimisée, le pair est un second download.
  Il est déféré par le même mécanisme 1005 que la photo, donc pas de régression
  de comportement, juste plus de runs pour finir.

## Acceptance Contract

### Approches candidates
**A (retenue)** : pair exporté au staging + upload vidéo→photo + rattachement
rétroactif sur reject via `Result.assetId`.
**B** : pair comme item séparé du `bulkUploadCheck`. Rejetée (ids synthétiques).
**C** : photo puis `updateAsset` systématique. Rejetée (2 requêtes, état
transitoire visible).

### Approche retenue + rationale
**A** — un seul appel réseau sur le chemin normal, ordre identique au client
Flutter (la vidéo `hidden` n'apparaît jamais seule dans le timeline), et le
chemin `reject`+`assetId` est le seul moyen de réparer les Live Photos déjà
uploadées en images mortes.

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
Pre-state attendu: FAIL
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
