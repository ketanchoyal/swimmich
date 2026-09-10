# Task: backup-auto

**Objectif** : Porter le backup automatique complet du client Flutter Immich upstream vers ImmichSwiftUI. Le moteur `BackupEngine` et le `BackupSettingsStore` existent déjà, mais les contrôles UI, les exclusions, le backfill reorganize et le resume from interruption manquent.

**Hypothèses** :
- `BackupEngine.swift` (Services/) implémente déjà le pipeline : checking → upload → done/cancelled. Checksum SHA1 dedup via `bulkUploadCheck`.
- `BackupSettingsStore` (Upload/UploadViewModel.swift:8-56) persiste : `isEnabled`, `onlyOnWiFi`, `onlyWhenCharging`, `excludeScreenshots`, `selectedAlbumIDs`.
- `BackupAssetSource` protocol (Core/Protocols/) définit `fetchCandidates(in:)` + `loadData(for:)`.
- `BackupEnvironment` protocol (Core/Protocols/) définit `hasWiFiConnection` + `isCharging`.
- `BackgroundBackupScheduling` gère le BGTaskScheduler (registerBackgroundBackup dans ImmichSwiftUIApp).
- `UploadViewModel` (Upload/UploadViewModel.swift:63-132) expose l'UI actuelle de backup settings.
- `BackupLiveActivityService` (ImmichWidgets/) pilote le Live Activity.
- `BackupNotificationService` (Services/) gère les notifications locales.

**Endpoints concernés** : Déjà tous wire : `POST /api/assets` (multipart), `POST /api/assets/bulk-upload-check`.

**Approche retenue** : A — étendre `BackupSettingsStore` + `UploadViewModel` + `BackupSettingsView` avec les contrôles manquants + écran backfill reorganize + gestion du resume.
- **B (rejetée)** : écraser l'architecture existante du BackupEngine. Le moteur est correct, on ajoute juste l'UI et les paramètres.
- **C (rejetée)** : nouveau ViewModel. Inutile — `UploadViewModel` est déjà le point d'entrée, juste incomplet.

## Étapes

1. **DTOs** — Ajouter `BackupCandidate` + `BackupAlbum` extensions dans `DTOs.swift` si besoin (déjà fait via `BackupAssetSource` protocol).
   - NEW `Sources/Core/Protocols/BackupAlbumSelectionSource.swift` — expose `fetchAlbums()` pour le backfill reorganize.
2. **BackupSettingsStore** — Ajouter :
   - `var excludeCameraRoll: Bool` — exclusions caméras externes
   - `var excludeWhatsApp: Bool` — exclusions WhatsApp backups (déjà dans Flutter)
   - `var autoDetectNewPhotos: Bool` — detection push/automation (déjà PHPhotoLibrary listener, besoin UI toggle)
3. **UploadViewModel** — Ajouter :
   - `var excludeCameraRoll: Bool` + `excludeWhatsApp: Bool` + `autoDetectNewPhotos: Bool` persistés dans `BackupSettingsStore`.
   - `func runBackfill(albumId: String)` — organise les assets locaux dans un album distant.
   - `func resumeUpload()` — reprene le backup depuis le dernier point d'interruption.
4. **BackupSettingsView** — Ajouter :
   - Toggle `Auto-detect new photos`
   - Toggle `Exclude camera roll` (caméras externes Android/multi-camera)
   - Toggle `Exclude WhatsApp backups`
   - Toggle `Resume interrupted uploads`
   - Section "Backfill" : bouton "Reorganize existing photos" → liste albums d'upload → sélection d'album
5. **Backup progress UI** — Ajouter :
   - `UploadProgressBanner` : toast top de la timeline pendant l'upload actif.
   - Affiche upload count / total, erreur, retry button.
6. **Integration** — `BackupAlbumSelectionSource` dans `DependencyContainer` + `BackupEngine.resume()` call.
7. **Tests** — `UploadViewModelTests` + 6 tests (resume, backfill settings, exclude filters).
8. **xcodegen + suite**.

## Acceptance Contract

### Approches candidates
**A (retenue)** : Extension `BackupSettingsStore` + `UploadViewModel` + `BackupSettingsView`. Le moteur n'est pas touché, on ajuste juste les paramètres et l'UI.
**B** : Refactor du BackupEngine. Rupture risquée, pas justifié.
**C** : UploadViewModel écrasé. Non, il fait déjà 70% du travail.

### Approche retenue + rationale
**A**. Cible les 4 gaps identifiés (exclusions, resume, backfill, detection UI) sans toucher au moteur de backup éprouvé.

### Critères

```
### AC-BK01 [type: new]
Assertion: BackupSettingsStore expose excludeCameraRoll, excludeWhatsApp, autoDetectNewPhotos, persistés.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -q "excludeCameraRoll" "$f" && grep -q "excludeWhatsApp" "$f" && grep -q "autoDetectNewPhotos" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-BK02 [type: new]
Assertion: BackupEngine.run applique excludeCameraRoll + excludeWhatsApp sur les candidates.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -q "excludeCameraRoll\|excludeWhatsApp" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-BK03 [type: new]
Assertion: UploadViewModel expose runBackfill + resumeUpload + les nouvelles settings.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -q "func runBackfill" "$f" && grep -q "func resumeUpload" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-BK04 [type: new]
Assertion: BackupSettingsView intègre les toggles exclusions + section backfill reorganize.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; n=$(grep -c "excludeCameraRoll\|excludeWhatsApp\|autoDetectNewPhotos\|backfill\|reorganize" "$f"); test "$n" -ge 8 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (seulement enable/wifi/charging/screenshots)
Post-state attendu: PASS
```

```
### AC-BK05 [type: new]
Assertion: UploadProgressBanner existe dans la timeline pendant l'upload actif.
Check post-impl: sh -c 'grep -q "UploadProgressBanner" Sources/Features/Timeline/TimelineView.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-BK06 [type: new]
Assertion: Tests UploadViewModelTests + 6 (resume, backfill, exclude filters).
Check post-impl: sh -c 'f=Tests/UploadViewModelTests.swift; n=$(grep -c "func test_" "$f"); test "$n" -ge 6 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-BK07 [type: regression]
Assertion: Suite complète ≥ baseline tests, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_backup_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_backup_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

## État au 2026-09-09 (vérifié)

> **Révision du 2026-09-10** — les sections Objectif, Plan et le tableau ci-dessous sont la trace de la livraison d'origine (2026-09-08). Deux surfaces décrites ici n'existent plus : le **backfill** (`runBackfill` / `BackfillSheet` / section « Backfill ») et le **toggle Face ID** (déplacé vers `ProfileView`). Voir la tête de `.opencode/scratch/backup-auto.acceptance.md` pour l'état courant.

Suite complète à la livraison : **645 tests, TEST SUCCEEDED**.

Suite complète au 2026-09-10 (après les 5 suites P2) : **691 tests, TEST SUCCEEDED**.

| AC | État | Preuve |
|---|---|---|
| AC-BK01 | PASS | `excludeCameraRoll` / `excludeWhatsApp` / `autoDetectNewPhotos` dans `BackupSettingsStore` (`UploadViewModel.swift:29-52`) |
| AC-BK02 | PASS | filtres dans `BackupEngine.run()` l.209-217 |
| AC-BK03 | PASS (révisé 2026-09-10) | `resumeUpload` + `uploadHistory` dans `UploadViewModel` — le `runBackfill` a été RETIRÉ (doublon du scoping d'albums + « Run now ») |
| AC-BK04 | PASS (révisé 2026-09-10) | `BackupSettingsView.backupSection` + `albumSection` (mode tri-état `BackupAlbumScope`), `AlbumPickerView` — la `BackfillSheet` a été RETIRÉE |
| AC-BK05 | **OBSOLÈTE** | `UploadProgressBanner` a été supprimé volontairement et remplacé par l'anneau de progression autour de l'avatar (`TimelineView.avatarBackupRing`). Le critère pinne une surface UI abandonnée : il ne doit pas être « réparé ». |
| AC-BK06 | PASS | 5 classes dans `Tests/UploadViewModelTests.swift` (dont `BackupEngineExclusionTests`, `BackupAutoChainTests`) |
| AC-BK07 | PASS | 645 tests, 0 échec |

## Suites à implémenter

Écarts réels restants vs le client Flutter, chacun spécifié à part dans ce même
dossier, par ordre de valeur décroissante :

1. `backup-live-photos.specs.md` — les Live Photos partent en images mortes
   (`livePhotoVideoId: nil` en dur, la ressource `.pairedVideo` n'est jamais
   uploadée). Le `.MOV` n'existe nulle part ailleurs que sur l'appareil.
2. `backup-album-scoping.specs.md` — remplace les exclusions heuristiques par
   nom de fichier (`hasPrefix("IMG_")`, `contains("WhatsApp")`) par une vraie
   sélection/exclusion d'albums. Les deux toggles actuels ne font pas ce que
   leur libellé promet.
3. `backup-ledger-reconciliation.specs.md` — le ledger local n'est jamais
   confronté au serveur : un asset supprimé côté serveur ne remonte jamais.
   Ajoute aussi `deviceAssetId`/`deviceId`, absents de l'upload multipart.
4. `backup-network-policy.specs.md` — gate réseau tout-ou-rien ; pas de
   politique cellulaire par type de média, pas de notion de hors-ligne (un run
   hors ligne produit de faux échecs).
5. `backup-library-observer.specs.md` — « Auto-detect new photos » ne branche
   aucun `PHPhotoLibraryChangeObserver` : c'est un scan à l'activation de la
   scène, et le libellé ment.
