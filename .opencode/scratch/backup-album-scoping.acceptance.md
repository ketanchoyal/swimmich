# Task: backup-album-scoping

Status: shipped — AC-AS01–AS08 PASS le 2026-09-10 (suite 688 tests, TEST SUCCEEDED sur iPhone 17).

**Spec** : `.omp/backup-auto/backup-album-scoping.specs.md`
**Dépendances** : premier chantier backup à lancer — il retire `BackupCandidate.albumName` et les 3 filtres de `BackupEngine.run()`, donc il doit passer **avant** `backup-live-photos` (même struct `BackupCandidate`) et `backup-network-policy` (mêmes lignes de `run()`). Indépendant de `backup-ledger-reconciliation` et `backup-library-observer`.
**⚠ Ne pas greper `excludeCameraRoll`/`excludeWhatsApp`/`excludeScreenshots` comme critère de succès** : cette feature les **supprime** (cf. `ImmichSwiftUI-backlog.md`, checklist par feature).

## Plan

**Objectif** : remplacer les exclusions heuristiques par nom de fichier par une vraie sélection/exclusion d'albums, comme le `BackupSelection { none, selected, excluded }` du client Flutter (étude §5). État actuel — `Sources/Services/BackupEngine.swift:209-217` : `excludeScreenshots` compare `albumName`, `excludeCameraRoll` exclut tout ce qui commence par `IMG_` (= la quasi-totalité d'une pellicule iPhone), `excludeWhatsApp` ne filtre **rien** sur iOS (WhatsApp écrit `IMG_xxxx`).

**Hypothèses** (ground truth vérifié le 2026-09-09) :
- `BackupSettingsStore` (`Sources/Features/Upload/UploadViewModel.swift:10-80`) : clés `photoBackupEnabled`, `photoBackupOnlyWiFi`, `photoBackupOnlyCharging`, `photoBackupExcludeScreenshots` (l.48), `photoBackupSelectedAlbums`, `photoBackupExcludeCameraRoll` (l.50), `photoBackupExcludeWhatsApp` (l.51), `photoBackupAutoDetectNewPhotos` ; `snapshot() -> BackupSettings`.
- `BackupSettings` (`BackupEngine.swift:5-20`), struct figé passé à `run()`. `private let screenshotsAlbumName = "Screenshots"` (l.21).
- `BackupAssetSource.fetchAlbums()` (`PhotoLibraryServiceImpl.swift:161-173`) ne liste que `PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any)` — **smart albums absents**. `fetchCandidates(in:)` (l.178-218) : union des albums sélectionnés, dédup par `ObjectIdentifier`, sinon toute la photothèque, un `autoreleasepool` par asset.
- `BackupCandidate.albumName: String?` n'est lu **que** par le filtre screenshots de l'engine (aucune autre lecture dans `Sources/`). `assetAlbumName(asset)` (`PhotoLibraryServiceImpl.swift:315`) = un `fetchAssetCollectionsContaining` **par asset** pendant le scan complet.
- UI : `BackupSettingsView.backupSection` (`UploadViewModel.swift:452-502`) — toggles l.470-475, `NavigationLink` → `AlbumPickerView(albums:settings:)` l.476-482 ; `AlbumPickerView` l.735-771.
- `MockBackupAssetSource.lastAlbumIDs` (`Tests/Mocks/MockBackupAssetSource.swift:20,28`) ; classe existante `BackupEngineExclusionTests` (`Tests/UploadViewModelTests.swift:263`).

**Endpoints** : aucun (PhotosKit uniquement).

**Approche retenue** : **B — exclusion résolue côté source Photos par soustraction d'ensembles d'identifiants, `albumName` disparaît.**
`fetchCandidates(in:excluding:)` énumère une fois les assets des albums exclus dans un `Set<String>` de `localIdentifier`, puis saute ces assets pendant la construction des candidats : un `PHAsset.fetchAssets(in:)` par album exclu (0 par défaut) contre un `fetchAssetCollectionsContaining` par asset de la photothèque aujourd'hui — c'est donc aussi une accélération du scan.
- **A (rejetée)** : filtrage dans l'engine via `albumIDs: Set<String>` sur le candidat — conserve le coût par asset.
- **C (rejetée)** : garder les toggles nom-de-fichier à côté des albums exclus — deux mécanismes pour une intention, dont un faux.

**Étapes** :
1. **EDIT** `Sources/Core/Protocols/BackupAssetSource.swift` — `BackupAlbum.isSmart` ; **supprimer** `BackupCandidate.albumName` ; `fetchCandidates(in:excluding:)`.
2. **EDIT** `Sources/Services/PhotoLibraryServiceImpl.swift` — `fetchAlbums()` ajoute les smart albums utiles (`.smartAlbumScreenshots`, `.smartAlbumSelfPortraits`, `.smartAlbumBursts`, `.smartAlbumVideos`, `isSmart: true`, triés après les albums utilisateur) ; `fetchCandidates(in:excluding:)` construit `excludedIDs: Set<String>` (PHFetchOptions sans predicate, on ne lit que `localIdentifier` — donc pas de `prefetchProperties`) et `continue` **avant** `prefetchProperties` ; retirer `assetAlbumName` et son appel.
3. **EDIT** `Sources/Services/BackupEngine.swift` — `BackupSettings` : retirer `excludeCameraRoll`/`excludeWhatsApp`/`excludeScreenshots`, ajouter `excludedAlbumIDs: Set<String> = []` ; supprimer les 3 `filter` (l.209-217) + `screenshotsAlbumName` (l.21) ; appeler `source.fetchCandidates(in: settings.selectedAlbumIDs, excluding: settings.excludedAlbumIDs)` dans le `Task.detached` existant ; `total = remaining.count` inchangé (après le filtre ledger).
4. **EDIT** `Sources/Features/Upload/UploadViewModel.swift` — `BackupSettingsStore` : supprimer les 3 anciens booléens + clés, ajouter `excludedAlbumIDs` (clé `photoBackupExcludedAlbums`) ; **migration one-shot** dans `init` — si `photoBackupExcludeScreenshots` valait `true` et que la nouvelle clé est absente, insérer l'id du smart album Screenshots puis `defaults.removeObject(forKey:)` ; `backupSection` : retirer les 3 toggles d'exclusion (l.472-474), deux `NavigationLink` « Albums to back up » (`All`/`N selected`) et « Albums to skip » (`None`/`N excluded`) ; `AlbumPickerView` paramétré par `Binding<Set<String>>` + un titre, section séparée pour les albums `isSmart`.
5. **EDIT** `Tests/Mocks/MockBackupAssetSource.swift` — nouvelle signature + `lastExcludedAlbumIDs: Set<String>?` + `excludedAssetIDs` appliqué côté mock.
6. **EDIT** `Tests/UploadViewModelTests.swift` — `BackupEngineExclusionTests` **réécrite** (les tests des filtres nom-de-fichier tombent avec le code qu'ils pinnaient), ≥5 tests : transmission du scoping, `IMG_0001.HEIC` sauvegardé, migration, persistance, clés legacy supprimées.
7. Pas de `xcodegen` (aucun fichier nouveau).

**Risques** : un utilisateur ayant activé « Exclude camera roll » verra son périmètre s'élargir d'un coup (comportement correct, mais gros run — footer obligatoire) ; `fetchAlbums()` légèrement plus lent (4 fetchs smart albums), hors chemin chaud.

## Acceptance Contract

### Approches candidates
**A** : filtrage dans l'engine via `albumIDs: Set<String>` sur le candidat. Rejetée.
**B (retenue)** : soustraction d'ensembles côté `PhotoLibraryServiceImpl`, `albumName` supprimé du candidat.
**C** : cohabitation des heuristiques et des albums exclus. Rejetée.

### Approche retenue + rationale
**B** — corrige le cas multi-albums par construction, supprime un appel Photos par asset sur le chemin le plus chaud (scan complet), et laisse l'engine sans aucune connaissance des noms de fichiers.

### Critères

```
### AC-AS01 [type: new]
Assertion: les filtres heuristiques nom-de-fichier ont disparu de l'engine.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; ! grep -qE "fileName\.(hasPrefix|contains)" "$f" && ! grep -q "screenshotsAlbumName" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (l.21 `screenshotsAlbumName` + l.209-217 les 3 filtres)
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
Pre-state attendu: FAIL (classe existante : 2 tests aujourd'hui, qui pinnaient les filtres nom-de-fichier supprimés par cette feature)
Post-state attendu: PASS
```

```
### AC-AS08 [type: regression]
Assertion: suite complète TEST SUCCEEDED. Baseline 645 tests le 2026-09-09 ; le compte peut BAISSER, les tests qui pinnaient les filtres nom-de-fichier meurent avec le code.
Check post-impl: sh -c 'xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination "platform=iOS Simulator,name=iPhone 17" 2>&1 | grep -q "TEST SUCCEEDED" && echo PASS || echo FAIL'
Pre-state attendu: n/a
Post-state attendu: PASS
```
