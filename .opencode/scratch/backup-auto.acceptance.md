# Task: backup-auto

Status: shipped — AC-BK01/BK02 (réécrits), BK03/BK04/BK07 (révisés), BK09, BK10 PASS ; AC-BK05, BK06 et BK08 OBSOLÈTES (surfaces retirées volontairement).
Dernière vérification : 2026-09-10, suite **691 tests TEST SUCCEEDED** (iPhone 17).

> **Révisions du 2026-09-10** — le `## Plan` ci-dessous est le plan d'origine (2026-09-08) et décrit deux surfaces qui ont été retirées depuis. Il est conservé comme trace de ce qui a été livré, pas comme état courant :
> - **Backfill / `BackfillSheet` / `runBackfill(albumId:)`** : retirés — doublon du scoping d'albums + « Run now », et le libellé « Reorganize » mentait (aucune réorganisation côté serveur). AC-BK08 passe OBSOLÈTE ; AC-BK10 couvre le remplacement.
> - **Toggle « Require Face ID »** : déplacé vers `ProfileView` (« Me » → Security) — l'app lock garde l'application entière, pas la sauvegarde. AC-114 suit la surface.
> - Le scoping d'albums est désormais **un mode tri-état** (`BackupAlbumScope.{all, selected, excluded}`) : les deux liens indépendants « Albums to back up » / « Albums to skip » pouvaient inclure et exclure le même album, soit un run qui ne sauvegarde rien.

## Plan

**Objectif** : Porter le backup automatique complet du client Flutter Immich upstream vers ImmichSwiftUI. Le moteur `BackupEngine` et le `BackupSettingsStore` existent déjà, mais les contrôles UI manquants (exclusions caméra/WhatsApp, auto-detect, resume), l'écran backfill reorganize et le banner de progression manquent.

**Hypothèses** (ground truth vérifié) :
- `BackupEngine.swift` implémente le pipeline : checking → upload → done/cancelled. Checksum SHA1 dedup via `bulkUploadCheck` par chunks de 1000.
- `BackupSettingsStore` (Sources/Features/Upload/UploadViewModel.swift:8) persiste : `isEnabled`, `onlyOnWiFi`, `onlyWhenCharging`, `excludeScreenshots`, `selectedAlbumIDs`. Clés `photoBackup*`.
- `BackupAssetSource` protocol (Core/Protocols/) définit `fetchCandidates(in:)` + `loadData(for:)`.
- `BackupEnvironment` protocol (Core/Protocols/) définit `hasWiFiConnection` + `isCharging`.
- `BackgroundBackupScheduling` gère le BGTaskScheduler (registerBackgroundBackup dans ImmichSwiftUIApp).
- `UploadViewModel` (Sources/Features/Upload/UploadViewModel.swift:63) expose `runBackup()`, `cancelBackup()`, `loadAlbums()`, `albums`, `engine`, `settings`.
- `BackupLiveActivityService` pilote le Live Activity.
- `BackupNotificationService` gère les notifications locales.
- `BackupSettingsView` (lignes 135-241) existe avec toggles auto-backup/Wi-Fi/charging/screenshots + album picker + progress section.
- DTOs: `AssetBulkUploadCheckRequest{assets:[Item{id,checksum}]}`, `AssetBulkUploadCheckResponse{results:[Result{id,action,reason?,assetId?,isTrashed?}]}` déjà wire dans ImmichClient.

**Endpoints concernés** : Déjà tous wire : `POST /api/assets` (multipart), `POST /api/assets/bulk-upload-check`.

**Approche retenue** : A — étendre `BackupSettingsStore` + `UploadViewModel` + `BackupSettingsView` avec les contrôles manquants + écran backfill reorganize + gestion du resume.
- **B (rejetée)** : écraser l'architecture existante du BackupEngine. Le moteur est correct.
- **C (rejetée)** : nouveau ViewModel. Inutile — `UploadViewModel` fait déjà le travail.

**Étapes** :
1. **BackupSettingsStore** — Ajouter :
   - `var excludeCameraRoll: Bool` — exclusions caméras externes
   - `var excludeWhatsApp: Bool` — exclusions WhatsApp backups
   - `var autoDetectNewPhotos: Bool` — detection push/automation
   - Persistés dans UserDefaults suite "backupSettings" avec clés `photoBackup*`.
2. **BackupSettings** — Ajouter les 3 nouveaux champs à la struct Sendable.
3. **UploadViewModel** — Ajouter :
   - `var excludeCameraRoll: Bool` + `excludeWhatsApp: Bool` + `autoDetectNewPhotos: Bool` persistés dans `BackupSettingsStore`.
   - `func runBackfill(albumId: String)` — organise les assets locaux dans un album distant.
   - `var showBackfillSheet: Bool` — état pour présenter le sheet.
   - `var uploadHistory: [UploadHistoryEntry]` — historique des runs.
4. **BackupEngine.run** — Appliquer `excludeCameraRoll` + `excludeWhatsApp` sur les candidates dans le pipeline.
5. **BackupSettingsView** — Étendre avec :
   - Toggle `Auto-detect new photos` (shimmer tactile `.glassEffect(.interactive())`)
   - Toggle `Exclude camera roll` (caméras externes Android/multi-camera)
   - Toggle `Exclude WhatsApp backups`
   - Toggle `Resume interrupted uploads`
   - Section "Backfill" : `BackfillReorganizeButton` (capsule vitrée → sheet morph via `glassEffectID`/namespace)
6. **BackfillSheet** — Nouveau écran avec liste albums d'upload, sélection d'album, bouton "Reorganize".
   - Morphing `@Namespace` du bouton → sheet header (`.glassEffectTransition(.matchedGeometry)`).
7. **UploadProgressBanner** — Floating glass bar en haut de la timeline pendant l'upload actif (`scrollEdgeEffectStyle(.floating)`).
8. **UploadHistoryEntry** — Model: date, uploaded, total, success.
9. **Integration** — Wire dans `DependencyContainer` + `BackupEngine.resume()` call.
10. **Tests** — `UploadViewModelTests` : resume, backfill settings, exclude filters, snapshot persistence.
11. **xcodegen + suite complète**.

## Acceptance Contract

### Approches candidates
**A (retenue)** : Extension `BackupSettingsStore` + `UploadViewModel` + `BackupSettingsView`. Le moteur n'est pas touché, on ajuste juste les paramètres et l'UI. Testable car les nouveaux champs sont des booléens + la logique de filtering se fait en amont du moteur.
**B** : Refactor du BackupEngine. Rupture risquée, pas justifié.
**C** : UploadViewModel écrasé. Non, il fait déjà 70% du travail.

### Approche retenue + rationale
**A**. Cible les 4 gaps identifiés (exclusions, resume, backfill, detection UI) sans toucher au moteur de backup éprouvé. Le `BackupEngine` est propre, isolé, et testé à 100% par `BackupEngineTests`.

### Critères

```
### AC-BK01 [type: new] — RÉÉCRIT 2026-09-10 (était OBSOLÈTE)
Assertion (historique): BackupSettingsStore expose excludeCameraRoll / excludeWhatsApp persistés avec clés photoBackup*.
OBSOLÈTE : ces deux booléens ont été SUPPRIMÉS par la suite Album Scoping — les heuristiques nom-de-fichier derrière eux étaient fausses sur iOS (`!hasPrefix("IMG_")` excluait presque toute la pellicule, `!contains("WhatsApp")` ne filtrait rien). Ils sont remplacés par le scoping d'albums (AC-BK10 / AC-AS01..AS08).
Assertion courante: BackupSettingsStore persiste isEnabled, onlyOnWiFi, onlyWhenCharging, autoDetectNewPhotos, le mode d'albums et les deux ensembles d'albums.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; for k in enabledKey wifiKey chargingKey autoDetectNewPhotosKey albumScopeKey albumsKey excludedAlbumsKey; do grep -q "$k" "$f" || exit 1; done; ! grep -q "excludeCameraRoll\|excludeWhatsApp" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-BK02 [type: new] — RÉÉCRIT 2026-09-10 (était OBSOLÈTE)
Assertion (historique): BackupSettings porte excludeCameraRoll / excludeWhatsApp et snapshot() les inclut.
OBSOLÈTE : BackupSettings ne porte plus ces booléens (cf. AC-BK01) ; il porte `excludedAlbumIDs` / `selectedAlbumIDs`, dont un SEUL est rempli selon le mode d'albums.
Assertion courante: BackupSettings porte autoDetectNewPhotos + les deux ensembles d'albums, et snapshot() ne transmet que celui du mode actif.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -q "autoDetectNewPhotos" "$f" && grep -qE "var excludedAlbumIDs" "$f" && grep -qE "var selectedAlbumIDs" "$f" && f2=Sources/Features/Upload/UploadViewModel.swift; grep -q "effectiveAlbumScope" "$f2" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-BK03 [type: new] — révisé 2026-09-10
Assertion: UploadViewModel expose resumeUpload() + uploadHistory (le backfill a été retiré : il ne faisait que `selectedAlbumIDs = [album]` + run manuel, soit exactement le scoping d'albums + « Run now »).
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -q "func resumeUpload" "$f" && grep -q "UploadHistoryEntry" "$f" && ! grep -q "runBackfill" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-BK04 [type: new] — révisé 2026-09-10
Assertion: BackupSettingsView intègre les toggles auto-detect + le scoping d'albums (mode tri-état + lien vers le picker).
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -q "autoDetectNewPhotos" "$f" && grep -q "BackupAlbumScope" "$f" && grep -q "AlbumPickerView" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (seulement enable/wifi/charging/screenshots)
Post-state attendu: PASS
```

```
### AC-BK05 [type: new] — OBSOLÈTE depuis 2026-09-09
Assertion (historique): UploadProgressBanner existe et est injecté dans TimelineView pendant l'upload actif.
OBSOLÈTE : la bannière a été supprimée volontairement et remplacée par l'anneau de progression autour de l'avatar (`TimelineView.avatarBackupRing`). Le critère pinne une surface UI abandonnée — ne pas le « réparer ».
```

```
### AC-BK06 [type: new] — OBSOLÈTE depuis 2026-09-09
Assertion (historique): UploadProgressBanner utilise .scrollEdgeEffectStyle(.floating) et présente uploaded/total.
OBSOLÈTE : même surface que AC-BK05, supprimée avec la bannière. La progression vit maintenant dans `BackupSettingsView.progressSection` + l'anneau du Timeline.
```

```
### AC-BK07 [type: new] — révisé 2026-09-10
Assertion: Tests UploadViewModelTests: ≥6 tests couvrant resume, scoping d'albums, persistance du snapshot.
Check post-impl: sh -c 'f=Tests/UploadViewModelTests.swift; n=$(grep -cE "^[[:space:]]*func test_" "$f"); n=${n:-0}; test "$n" -ge 6 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier n'existe pas)
Post-state attendu: PASS
```

```
### AC-BK08 [type: new] — OBSOLÈTE depuis 2026-09-10
Assertion (historique): BackfillSheet existe et utilise glass morphing (Namespace/glassEffectID) pour la transition.
OBSOLÈTE : la sheet Backfill a été SUPPRIMÉE (demande utilisateur) parce qu'elle était un doublon du scoping d'albums + « Run now » : `runBackfill(albumId:)` ne faisait que fixer `selectedAlbumIDs = [albumId]` puis lancer un run manuel, sans aucune réorganisation côté serveur malgré le libellé « Reorganize ».
Remplacement vérifié par AC-BK10.
```

```
### AC-BK10 [type: new] — ajouté 2026-09-10
Assertion: le scoping d'albums est un mode unique à trois états (all / selected / excluded) et un seul ensemble part au moteur, donc « inclure » et « exclure » ne peuvent plus se contredire.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -q "enum BackupAlbumScope" "$f" && grep -q "effectiveAlbumScope" "$f" && grep -qE "excludedAlbumIDs: inForce == .excluded" "$f" && grep -qE "selectedAlbumIDs: inForce == .selected" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (deux NavigationLink indépendants, aucun mode)
Post-state attendu: PASS
```

```
### AC-BK09 [type: regression]
Assertion: Suite complète ≥ baseline tests, TEST SUCCEEDED.
Check post-impl: sh -c 'cd /Users/millian/SideProjects/immich_swiftui && xcodebuild test -destination "platform=iOS Simulator,name=iPhone 17" -skipTestingSkipInCI 2>&1 | tee /tmp/immich_backup_auto_test_summary.txt | grep -q "TEST SUCCEEDED" && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_backup_auto_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1); test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
