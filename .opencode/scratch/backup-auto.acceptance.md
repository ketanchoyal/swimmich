# Task: backup-auto

Status: pending

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
### AC-BK01 [type: new]
Assertion: BackupSettingsStore expose excludeCameraRoll, excludeWhatsApp, autoDetectNewPhotos, persistés avec clés photoBackup*.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -q "excludeCameraRoll" "$f" && grep -q "excludeWhatsApp" "$f" && grep -q "autoDetectNewPhotos" "$f" && grep -q "photoBackupExcludeCameraRoll" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (ces propriétés n'existent pas)
Post-state attendu: PASS
```

```
### AC-BK02 [type: new]
Assertion: BackupSettings struct contient excludeCameraRoll, excludeWhatsApp, autoDetectNewPhotos, et BackupSettingsStore.snapshot() les inclut.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -q "excludeCameraRoll" "$f" && grep -q "excludeWhatsApp" "$f" && grep -q "autoDetectNewPhotos" "$f"; f2=Sources/Features/Upload/UploadViewModel.swift; grep -q "excludeCameraRoll" "$f2" && grep -q "excludeWhatsApp" "$f2" && grep -q "autoDetectNewPhotos" "$f2" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-BK03 [type: new]
Assertion: UploadViewModel expose runBackfill(albumId:) + showBackfillSheet + uploadHistory.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -q "func runBackfill" "$f" && grep -q "showBackfillSheet" "$f" && grep -q "UploadHistoryEntry" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-BK04 [type: new]
Assertion: BackupSettingsView intègre les 4 nouveaux toggles + bouton backfill reorganize.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; n=$(grep -cE "excludeCameraRoll|excludeWhatsApp|autoDetectNewPhotos|backfill|reorganize|camera.*roll|WhatsApp" "$f"); test "$n" -ge 12 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (seulement enable/wifi/charging/screenshots)
Post-state attendu: PASS
```

```
### AC-BK05 [type: new]
Assertion: UploadProgressBanner existe et est injecté dans TimelineView pendant l'upload actif.
Check post-impl: sh -c 'grep -q "UploadProgressBanner" Sources/Features/Timeline/TimelineView.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-BK06 [type: new]
Assertion: UploadProgressBanner utilise .scrollEdgeEffectStyle(.floating) et présente uploaded/total.
Check post-impl: sh -c 'grep -q "scrollEdgeEffectStyle" Sources/Features/Upload/UploadViewModel.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-BK07 [type: new]
Assertion: Tests UploadViewModelTests: ≥6 tests couvrant resume, backfill settings, exclude filters, snapshot persistence.
Check post-impl: sh -c 'f=Tests/UploadViewModelTests.swift; n=$(grep -cE "^[[:space:]]*func test_" "$f"); test "$n" -ge 6 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier n'existe pas)
Post-state attendu: PASS
```

```
### AC-BK08 [type: new]
Assertion: BackfillSheet existe et utilise glass morphing (Namespace/glassEffectID) pour la transition.
Check post-impl: sh -c 'grep -q "BackfillSheet" Sources/Features/Upload/UploadViewModel.swift && grep -q "@Namespace" Sources/Features/Upload/UploadViewModel.swift && grep -q "glassEffectID\|glassEffectTransition" Sources/Features/Upload/UploadViewModel.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-BK09 [type: regression]
Assertion: Suite complète ≥ baseline tests, TEST SUCCEEDED.
Check post-impl: sh -c 'cd /Users/millian/SideProjects/immich_swiftui && xcodebuild test -destination "platform=iOS Simulator,name=iPhone 17" -skipTestingSkipInCI 2>&1 | tee /tmp/immich_backup_auto_test_summary.txt | grep -q "TEST SUCCEEDED" && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_backup_auto_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1); test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
