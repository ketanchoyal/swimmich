# Task: backup-album-scoping

**Objectif** : remplacer les exclusions heuristiques par nom de fichier par une
vraie sélection/exclusion d'albums, comme le `BackupSelection { none, selected,
excluded }` du client Flutter (étude `flutter-auto-backup-study.md` §5).

État actuel — `BackupEngine.run()`
(`Sources/Services/BackupEngine.swift:209-217`) :

```swift
if settings.excludeScreenshots { remaining = remaining.filter { $0.albumName != screenshotsAlbumName } }
if settings.excludeCameraRoll  { remaining = remaining.filter { !$0.fileName.hasPrefix("IMG_") } }
if settings.excludeWhatsApp    { remaining = remaining.filter { !$0.fileName.contains("WhatsApp") } }
```

Trois défauts mesurables :
1. `excludeCameraRoll` exclut tout ce qui commence par `IMG_`, c'est-à-dire la
   quasi-totalité d'une pellicule iPhone : le toggle est un « ne sauvegarde
   presque rien ».
2. `excludeWhatsApp` ne filtre rien sur iOS : WhatsApp enregistre dans la
   pellicule sous `IMG_xxxx`, jamais avec « WhatsApp » dans le nom.
3. `excludeScreenshots` compare `albumName`, et `albumName` est **un seul**
   album (`assetAlbumName(asset)`,
   `Sources/Services/PhotoLibraryServiceImpl.swift:315`) : un asset présent dans
   plusieurs albums peut passer à travers, et le calcul coûte un
   `fetchAssetCollectionsContaining` par asset pendant le scan de toute la
   photothèque.

**Hypothèses (vérifiées le 2026-09-09)** :
- `BackupSettingsStore` (`Sources/Features/Upload/UploadViewModel.swift:10-80`) :
  clés `photoBackupEnabled`, `photoBackupOnlyWiFi`, `photoBackupOnlyCharging`,
  `photoBackupExcludeScreenshots`, `photoBackupSelectedAlbums`,
  `photoBackupExcludeCameraRoll`, `photoBackupExcludeWhatsApp`,
  `photoBackupAutoDetectNewPhotos` ; `snapshot() -> BackupSettings`.
- `BackupSettings` (`BackupEngine.swift:5-20`) est le struct figé passé à `run`.
- `BackupAssetSource.fetchAlbums()` (`PhotoLibraryServiceImpl.swift:161-173`) ne
  liste que `PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any)`
  — **les smart albums (dont « Screenshots ») sont absents**.
- `fetchCandidates(in:)` (l.178-218) : union des albums sélectionnés, dédup par
  `ObjectIdentifier`, sinon toute la photothèque ; un `autoreleasepool` par asset
  autour de `prefetchProperties` + `makeCandidate`.
- `BackupCandidate.albumName: String?` n'est lu **que** par le filtre
  screenshots de l'engine (vérifié : aucune autre lecture dans `Sources/`).
- UI : `BackupSettingsView.backupSection`
  (`UploadViewModel.swift:452-502`) porte les toggles l.470-475 et le
  `NavigationLink` → `AlbumPickerView(albums:settings:)` l.476-482 ;
  `AlbumPickerView` est défini l.735-771.
- `MockBackupAssetSource.lastAlbumIDs` (`Tests/Mocks/MockBackupAssetSource.swift:20,28`)
  est le point d'observation des tests pour le scoping ; classe de tests
  existante `BackupEngineExclusionTests` (`Tests/UploadViewModelTests.swift:263`).

**Approche retenue** : **B — l'exclusion est résolue côté source Photos, par
soustraction d'ensembles d'identifiants, et `albumName` disparaît.**

`fetchCandidates(in selectedAlbumIDs: Set<String>, excluding excludedAlbumIDs: Set<String>)` :
énumère une fois les assets des albums exclus dans un `Set<String>` de
`localIdentifier`, puis saute ces assets pendant la construction des candidats.
Coût : un `PHAsset.fetchAssets(in:)` par album exclu (0 dans le cas par défaut),
contre un `fetchAssetCollectionsContaining` **par asset de la photothèque**
aujourd'hui — c'est donc aussi une accélération du scan, et ça règle le cas
multi-albums par construction.

- **A (rejetée)** : garder le filtrage dans l'engine en remplaçant
  `albumName: String?` par `albumIDs: Set<String>`. Plus testable en pur Swift,
  mais conserve le `fetchAssetCollectionsContaining` par asset — le coût que la
  mémoire projet identifie déjà comme un gros stall de scan.
- **C (rejetée)** : garder les toggles nom-de-fichier et ajouter les albums
  exclus à côté. Deux mécanismes concurrents pour la même intention, dont un
  faux : interdit par la règle de cutover propre du dépôt.

## Étapes

1. **EDIT** `Sources/Core/Protocols/BackupAssetSource.swift`
   - `BackupAlbum` : ajouter `let isSmart: Bool` (regroupement UI + libellé).
   - `BackupCandidate` : **supprimer** `albumName`.
   - `fetchCandidates(in:excluding:)` remplace `fetchCandidates(in:)`.
2. **EDIT** `Sources/Services/PhotoLibraryServiceImpl.swift`
   - `fetchAlbums()` : ajouter les smart albums utiles à l'exclusion —
     `PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots)`,
     `.smartAlbumSelfPortraits`, `.smartAlbumBursts`, `.smartAlbumVideos`
     (`isSmart: true`), triés après les albums utilisateur.
   - `fetchCandidates(in:excluding:)` : construire `excludedIDs: Set<String>` en
     énumérant les albums exclus (`PHFetchOptions` sans predicate, on ne lit que
     `localIdentifier` — pas de `prefetchProperties`, donc pas de coût metadata),
     puis `continue` sur `excludedIDs.contains(asset.localIdentifier)` **avant**
     `prefetchProperties`.
   - `makeCandidate` : retirer l'appel `assetAlbumName(asset)` et la fonction
     `assetAlbumName` elle-même si elle n'a plus d'appelant.
3. **EDIT** `Sources/Services/BackupEngine.swift`
   - `BackupSettings` : retirer `excludeCameraRoll`, `excludeWhatsApp`,
     `excludeScreenshots` ; ajouter `excludedAlbumIDs: Set<String> = []`.
   - `run()` : supprimer les trois `filter` l.209-217 et la constante
     `screenshotsAlbumName` ; appeler
     `source.fetchCandidates(in: settings.selectedAlbumIDs, excluding: settings.excludedAlbumIDs)`
     dans le `Task.detached` existant. `total = remaining.count` reste calculé
     après le filtre ledger, inchangé (mem `72a1dbc8`).
4. **EDIT** `Sources/Features/Upload/UploadViewModel.swift`
   - `BackupSettingsStore` : supprimer `excludeCameraRoll`/`excludeWhatsApp`/
     `excludeScreenshots` et leurs clés ; ajouter
     `excludedAlbumIDs: Set<String>` sur la clé `photoBackupExcludedAlbums`.
   - **Migration one-shot** dans `init` : si `photoBackupExcludeScreenshots`
     valait `true` et que `photoBackupExcludedAlbums` est absent, insérer l'id du
     smart album Screenshots dans `excludedAlbumIDs` puis supprimer l'ancienne
     clé (`defaults.removeObject(forKey:)`). Les deux autres clés sont supprimées
     sans équivalent : elles ne faisaient pas ce que leur libellé promettait.
   - `BackupSettingsView.backupSection` : retirer les trois `Toggle` d'exclusion
     (l.472-474) ; deux `NavigationLink` — « Albums to back up » (valeur
     `All`/`N selected`) et « Albums to skip » (valeur `None`/`N excluded`).
   - `AlbumPickerView` : paramétrer par un `Binding<Set<String>>` + un titre au
     lieu de lire `settings.selectedAlbumIDs` en dur, de façon à servir les deux
     écrans. Section séparée pour les albums `isSmart`.
5. **EDIT** `Tests/Mocks/MockBackupAssetSource.swift` — nouvelle signature +
   `lastExcludedAlbumIDs: Set<String>?`, et un `excludedAssetIDs` que le mock
   applique lui-même pour tester le contrat côté engine.
6. **EDIT** `Tests/UploadViewModelTests.swift` — `BackupEngineExclusionTests` est
   réécrite (les tests des filtres nom-de-fichier tombent avec le code qu'ils
   pinnaient) :
   - `test_run_passesSelectedAndExcludedAlbumIDsToSource`
   - `test_run_hasNoFilenameHeuristicFilters` (assertion : un candidat nommé
     `IMG_0001.HEIC` est sauvegardé)
   - `test_store_migratesExcludeScreenshotsToExcludedAlbum`
   - `test_store_persistsExcludedAlbumIDs`
   - `test_store_dropsLegacyExclusionKeys`
7. Pas de `xcodegen` (aucun fichier nouveau).

## Risques

- **Rupture de préférence utilisateur** : quiconque avait activé « Exclude
  camera roll » verra son périmètre de backup s'élargir d'un coup au prochain
  lancement (et donc un gros run). C'est le comportement correct — le toggle
  excluait par erreur presque toute la photothèque — mais ça mérite le footer de
  la section Albums qui explique le nouveau modèle.
- `fetchAlbums()` devient un peu plus lent (4 fetchs de smart albums + leur
  `count`). Négligeable : appelé au chargement de l'écran de réglages, pas dans
  le run.

## Acceptance Contract

### Approches candidates
**A** : filtrage dans l'engine via `albumIDs: Set<String>` sur le candidat.
Rejetée — garde le `fetchAssetCollectionsContaining` par asset.
**B (retenue)** : soustraction d'ensembles côté `PhotoLibraryServiceImpl`,
`albumName` supprimé du candidat.
**C** : cohabitation des heuristiques et des albums exclus. Rejetée — deux
mécanismes pour une intention, dont un faux.

### Approche retenue + rationale
**B** — corrige le cas multi-albums par construction, supprime un appel Photos
par asset sur le chemin le plus chaud (scan complet), et laisse l'engine sans
aucune connaissance des noms de fichiers.

### Critères

```
### AC-AS01 [type: new]
Assertion: les filtres heuristiques nom-de-fichier ont disparu de l'engine.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; ! grep -qE "fileName\.(hasPrefix|contains)" "$f" && ! grep -q "screenshotsAlbumName" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (l.210-216)
Post-state attendu: PASS
```

```
### AC-AS02 [type: new]
Assertion: BackupSettings porte excludedAlbumIDs et l'engine le transmet à la source.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -q "excludedAlbumIDs" "$f" && grep -q "excluding:" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-AS03 [type: new]
Assertion: BackupCandidate n'a plus albumName ; le protocole expose fetchCandidates(in:excluding:) ; BackupAlbum porte isSmart.
Check post-impl: sh -c 'f=Sources/Core/Protocols/BackupAssetSource.swift; ! grep -q "albumName" "$f" && grep -q "excluding excludedAlbumIDs" "$f" && grep -q "isSmart" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-AS04 [type: new]
Assertion: la source résout l'exclusion par ensemble d'identifiants et expose les smart albums ; plus aucun album par asset.
Check post-impl: sh -c 'f=Sources/Services/PhotoLibraryServiceImpl.swift; grep -q "smartAlbumScreenshots" "$f" && grep -q "excludedIDs" "$f" && ! grep -q "assetAlbumName" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-AS05 [type: new]
Assertion: les anciennes clés d'exclusion sont supprimées du store et excludeScreenshots est migré en album exclu.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; ! grep -q "excludeCameraRollKey\|excludeWhatsAppKey" "$f" && grep -q "photoBackupExcludedAlbums" "$f" && grep -q "removeObject(forKey:" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-AS06 [type: new]
Assertion: l'écran de réglages offre deux périmètres d'albums et plus aucun toggle d'exclusion heuristique.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -q "Albums to back up" "$f" && grep -q "Albums to skip" "$f" && ! grep -qE "Toggle\(\"Exclude" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-AS07 [type: new]
Assertion: BackupEngineExclusionTests couvre la transmission du scoping, l'absence d'heuristique, le défaut « tout » et le changement de scoping entre deux runs (≥5 tests).
Check post-impl: sh -c 'f=Tests/UploadViewModelTests.swift; n=$(sed -n "/final class BackupEngineExclusionTests/,/^}/p" "$f" | grep -c "func test_"); n=${n:-0}; test "$n" -ge 5 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-AS08 [type: regression]
Assertion: suite complète TEST SUCCEEDED. Baseline 645 tests le 2026-09-09 ; le compte peut BAISSER légèrement, les tests qui pinnaient les filtres nom-de-fichier étant supprimés avec le code.
Check post-impl: sh -c 'xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination "platform=iOS Simulator,name=iPhone 17" 2>&1 | grep -q "TEST SUCCEEDED" && echo PASS || echo FAIL'
Pre-state attendu: n/a
Post-state attendu: PASS
```
