# Task: backup-engine

Status: shipped — AC-1040..AC-1049 PASS 2026-08-12 (382 → 399 tests).

> **Révision du 2026-09-10** — quatre checks (AC-1040, AC-1045, AC-1048, AC-1049) pinnaient des surfaces que les chantiers P2 suivants ont fait évoluer *volontairement* : signatures du protocole `BackupAssetSource`, `DependencyContainer.makeUploadViewModel()` supprimé au profit d'un VM unique, chemin du mock d'environnement, summary /tmp orphelin. Les checks ont été réécrits sur l'état courant, pas le code ramené en arrière. Nouvelle mesure : **691 tests, TEST SUCCEEDED** (iPhone 17, 2026-09-10).

## Plan

**Objectif**: Remplacer le scaffold `UploadViewModel` par un vrai moteur de sauvegarde: diffing serveur via `bulkUploadCheck` (P0, inutilisé jusqu'ici), upload séquentiel multipart avec progression, conditions réseau/batterie, exclusion des captures d'écran, sélection d'albums, persistance des réglages, planification `BGTaskScheduler` (BGProcessingTask), registration au lancement + submit après chaque run. UI: BackupSettingsView avec toggles + liste albums + ligne de progression.

**Hypothèses** (ground truth vérifié):
- `UploadViewModel.swift` (92L) contient VM + BackupSettingsView; VM JAMAIS instancié en prod (seul `ProfileView:35` appelle `BackupSettingsView()`); aucun test Upload.
- `PhotoLibraryService` (Sources/Core/Protocols/PhotoLibraryService.swift:5-28) PHAsset-typé; `PHAsset` non constructible en test → **nouveau seam `BackupAssetSource` sur types valeurs** (BackupCandidate/BackupAlbum), PhotoLibraryServiceImpl conforme en extension.
- MockImmichClient (Tests/Mocks/MockImmichClient.swift): uploadAsset :641 capture lastUpload* + `uploadResponse ?? AssetMediaResponseDto(id:"new-asset", status:"created")`; bulkUploadCheck :659 retourne `bulkUploadCheckResponse ?? AssetBulkUploadCheckResponse(results: [])`; requestCount private(set) (ligne 8) + bump().
- DTOs.swift:180-201: AssetMediaResponseDto{id,status}, AssetBulkUploadCheckRequest{assets:[Item{id,checksum}]}, AssetBulkUploadCheckResponse{results:[Result{id,action:"accept"|"reject",reason?,assetId?,isTrashed?}]}.
- ImmichClient.uploadAsset(data:fileCreatedAt:fileModifiedAt:filename:duration:isFavorite:visibility:livePhotoVideoId:checksum:) -> AssetMediaResponseDto (:121-131).
- DependencyContainer (64L): client/photos @MainActor lets; `makeX` factories; pas de makeUpload.
- ImmichSwiftUIApp (27L): WindowGroup + scenePhase lock; aucune registration BG.
- project.yml: `sources: path Sources` glob mais pbxproj EXPLICITE → xcodegen requis après nouveaux fichiers; `info.properties` (génère Resources/Info.plist) → BGTaskSchedulerPermittedIdentifiers + UIBackgroundModes processing via project.yml + xcodegen.
- ISO8601.immichFormatter existe (via PhotoLibraryServiceImpl:64).
- Lessons tests: globalError après seeding; `State(initialValue:)`; order de déclaration pour init memberwise; APIError.serverError sans labels.

**Approche retenue**: A — Types valeurs (BackupCandidate/BackupAlbum) + protocole BackupAssetSource + BackupEngine @Observable @MainActor (client/source/environment/scheduler injectés, défauts concrets) + BackupSettingsStore (UserDefaults suite injectable) + UploadViewModel = glue thin (engine + store + runBackup/cancel/loadAlbums) + BackupSettingsView réécrite + registration BG dans ImmichSwiftUIApp + project.yml clés. Cancellation par flag vérifié par item; continue-on-error (failedCount); settings gating réseau/batterie dans engine.run(settings:); dédup par chunk 1000; checksum SHA1 base64 calculé une fois, data mise en cache pour l'upload.

**B (rejetée)**: Étendre PhotoLibraryService directement avec PHAsset → `PHAsset` non constructible en tests, dédup logique testable seulement à travers PHPhotoLibrary réelle (intouchable en CI/unit).
**C (rejetée)**: Tout le flux inline dans UploadViewModel → monolithe non testable, mélange UI/état/IO.

**Étapes**:
1. NEW `Sources/Core/Protocols/BackupAssetSource.swift` — BackupAssetKind{image,video}, BackupCandidate{id,kind,fileName,fileCreatedAt,fileModifiedAt,duration?,isFavorite,albumName?} Equatable/Sendable, BackupAlbum{id,name,count}, protocol BackupAssetSource{fetchAlbums() -> [BackupAlbum]; fetchCandidates(in albumIDs: Set<String>) -> [BackupCandidate]; loadData(for:) async throws -> Data}.
2. EDIT `Sources/Services/PhotoLibraryServiceImpl.swift` — extension BackupAssetSource: fetchAlbums (PHAssetCollection.fetchAssetCollections(.album, .any) → name+count, order localized), fetchCandidates (albumIDs vide → PHAsset.fetchAssets creation desc; sinon fetchAssets(in:) par album + union dédupliquée par localIdentifier), fileName via PHAssetResource.assetResources(...).first.originalFilename fallback kind, loadData = délégation existante.
3. NEW `Sources/Services/BackupEnvironment.swift` — protocol BackupEnvironment{isCharging: Bool, hasWiFiConnection: Bool}; struct SystemBackupEnvironment: @unchecked Sendable (UIDevice.current.batteryState charging|full; NWPathMonitor cache gated par NSLock, start() appelé à la création).
4. NEW `Sources/Services/BackupEngine.swift` — @Observable @MainActor final class; enum Phase{idle,checking,uploading,done,cancelled}; struct BackupSettings{isEnabled,onlyOnWiFi,onlyWhenCharging,excludeScreenshots,selectedAlbumIDs: Set<String>}; private(set) phase/total/currentIndex/uploadedCount/rejectedCount/failedCount/lastError; let client/source/environment; init(client:source:environment: = SystemBackupEnvironment()); cancel(); run(settings:) async (reset counters, gate wifi/charging → lastError msg + phase idle, candidates → filter album "Screenshots", checksums, bulkUploadCheck chunks 1000, accept set, upload séquentiel avec data cache, continue-on-error, phase done); isCancelled flag.
5. NEW `Sources/Services/BackgroundBackupScheduling.swift` — protocol{submit()}; struct BGTaskBackupScheduler{static let taskIdentifier = "app.immich.background-backup"; submit(): cancel(requestTaskWithIdentifier:) puis BGProcessingTaskRequest(requiresNetworkConnectivity: true) submit try?}.
6. REWRITE `Sources/Features/Upload/UploadViewModel.swift` — BackupSettingsStore @Observable @MainActor (init(suiteName: String = "backupSettings"), defaults injectable, vars isEnabled/onlyOnWiFi/onlyWhenCharging/excludeScreenshots didSet→defaults.set, selectedAlbumIDs Set<String>, keys "photoBackup*") + UploadViewModel(client:photos:) construit engine (source = photos as? BackupAssetSource ?? PhotoLibraryServiceImpl()), store, scheduler; API: runBackup() async (engine.run(settings.snapshot()); si phase done → scheduler.submit()), cancelBackup(), loadAlbums() (albums = engine.source.fetchAlbums()), albums publié; garder upload() hérité (AC-008 API).
7. REWRITE BackupSettingsView — sections: Server/User (existants), Auto backup (Toggle Auto backup onChange requestAuthorization + submit; Wi-Fi only; Charging only; Exclude screenshots; NavigationLink Albums → checkmark list bindée selectedAlbumIDs), Progress (phase != idle: ProgressView + LabeledContent uploaded/rejected/failed; Button Run now/Cancel; lastError immichError caption), Security Face ID (conservé).
8. EDIT `Sources/DependencyContainer.swift` — makeUploadViewModel() -> UploadViewModel (client+photos).
9. EDIT `Sources/RootView.swift` — @State upload VM + ProfileView(upload:) → ProfileView passe à BackupSettingsView(vm:)?
   → Simplification: BackupSettingsView(vm:) param; ProfileView reçoit upload de RootView.
10. EDIT `Sources/ImmichSwiftUIApp.swift` — .onAppear registration BG: BGTaskScheduler.shared.register(forTaskWithIdentifier: BGTaskBackupScheduler.taskIdentifier, using: nil) { task → expiration engine.cancel(); Task { await vm.runBackup(); task.setTaskCompleted(success: vm.engine.failedCount == 0); BGTaskBackupScheduler().submit() } }; import BackgroundTasks.
11. EDIT `project.yml` — info.properties: BGTaskSchedulerPermittedIdentifiers: [app.immich.background-backup] + UIBackgroundModes: [processing]. Puis `xcodegen generate`.
12. NEW `Tests/BackupEngineTests.swift` — MockBackupAssetSource (candidates/albums/dataProvider/loadError/lastAlbumIDs/lastRequest), MockBackupEnvironment (isCharging/hasWiFiConnection vars), tests: success dédup accept/reject; checksum envoyé = base64(SHA1) code; wifi gate; charging gate; cancel avant run; cancel pendant (closure source onFirstLoad → engine.cancel()); échec upload → failedCount + continue; filtre album "Screenshots" quand excludeScreenshots; selectedAlbumIDs transmis à source; chunking (1250 items → 2 appels bulkUploadCheck); snapshot persistence BackupSettingsStore (suite isolée UUID).
13. Build + suite complète (baseline 382) → /tmp/immich_backup_engine_test_summary.txt.
14. memory.md entry + ACs.

## Acceptance Contract

### Approches candidates
**A (retenu)**: Types valeurs + BackupAssetSource seam + BackupEngine autonome + store UserDefaults + BGTaskScheduler registration app. Testable à 100% (mocks purs), patterns codebase respectés, seule vraie salle de PHPhotoLibrary reste l'impl extension.
**B**: Étendre PhotoLibraryService (PHAsset) → non testable, PHAsset non constructible.
**C**: Tout dans UploadViewModel → monolithe UI/état/IO mélangés.

### Approche retenue + rationale
**A**. Le seam BackupAssetSource isole toute la PHPhotoLibrary derrière des types valeurs → dédup/queue/gating/cancel testables à 100% sur mocks. BGProcessingTask = basse priorité (pas de conflit avec l'usage interactif), resubmit après chaque run (une requête = un run).

### Critères

```
### AC-1040 [type: new] — check révisé 2026-09-10
Assertion: BackupCandidate/BackupAlbum/BackupAssetSource définis dans Sources/Core/Protocols/BackupAssetSource.swift (fetchCandidates, fetchAlbums, exportOriginal, exportPairedVideo).
Note (2026-09-10) : le protocole a évolué depuis la rédaction — `fetchCandidates(in:)` a reçu `excluding:` (Album Scoping, §2.12), `loadData(for:)` a été remplacé par `exportOriginal(for:onState:)` (upload streamé fichier-flux) puis complété par `exportPairedVideo` (Live Photos, §2.11). L'assertion d'origine pinnant les anciennes signatures était périmée, pas le code.
Check post-impl: sh -c 'f=Sources/Core/Protocols/BackupAssetSource.swift; grep -qE "struct BackupCandidate" "$f" && grep -qE "struct BackupAlbum" "$f" && grep -qE "protocol BackupAssetSource" "$f" && grep -qE "func fetchCandidates\(in albumIDs: Set<String>, excluding excludedAlbumIDs: Set<String>\)" "$f" && grep -qE "func fetchAlbums" "$f" && grep -qE "func exportOriginal" "$f" && grep -qE "func exportPairedVideo" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier n'existe pas)
Post-state attendu: PASS
```

```
### AC-1041 [type: new]
Assertion: PhotoLibraryServiceImpl conforme BackupAssetSource (extension), exclusion des albums nommés "Screenshots" gérée côté source, fetchCandidates déduplique par localIdentifier.
Check post-impl: sh -c 'grep -qE "extension PhotoLibraryServiceImpl: BackupAssetSource" Sources/Services/PhotoLibraryServiceImpl.swift && grep -q "Screenshots" Sources/Services/PhotoLibraryServiceImpl.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1042 [type: new]
Assertion: BackupEngine @Observable @MainActor dans Sources/Services/BackupEngine.swift: Phase{idle,checking,uploading,done,cancelled}, run(settings:) utilise bulkUploadCheck par chunks de 1000 puis uploadAsset séquentiel, cancel() flag vérifié par item, continue-on-error.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; test -f "$f" && grep -qE "final class BackupEngine" "$f" && grep -qE "case idle, checking, uploading, done, cancelled" "$f" && grep -qE "bulkUploadCheck" "$f" && grep -qE "uploadAsset" "$f" && grep -qE "func cancel\(\)" "$f" && grep -qE "failedCount" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1043 [type: new]
Assertion: BackupEngine gating: onlyOnWiFi → environment.hasWiFiConnection, onlyWhenCharging → environment.isCharging, sinon lastError + phase reste idle (aucun appel réseau).
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -qE "hasWiFiConnection" "$f" && grep -qE "isCharging" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1044 [type: new]
Assertion: BackupSettingsStore @Observable @MainActor persiste via UserDefaults suite "backupSettings", clés photoBackup* (isEnabled, onlyOnWiFi, onlyWhenCharging, excludeScreenshots, selectedAlbumIDs), init(suiteName:) injectable.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -qE "final class BackupSettingsStore" "$f" && grep -qE "photoBackupEnabled" "$f" && grep -qE "photoBackupOnlyWiFi" "$f" && grep -qE "init\(suiteName" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1045 [type: new] — check révisé 2026-09-10
Assertion: UploadViewModel expose runBackup/cancelBackup/loadAlbums/albums + engine + settings ; le conteneur possède UNE instance partagée (`upload`).
Note (2026-09-10) : `runBackup()` a reçu `overrideSettings:manual:` (gates auto vs run manuel), et `DependencyContainer.makeUploadViewModel()` a été SUPPRIMÉ au profit d'un `let upload: UploadViewModel` unique — plusieurs VM = plusieurs moteurs, donc des passes concurrentes sur la même photothèque et plusieurs Live Activities qui se marchent dessus (« pas d'île quand l'app est ouverte »).
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -qE "func runBackup\(overrideSettings:" "$f" && grep -qE "func cancelBackup\(\)" "$f" && grep -qE "func loadAlbums\(\)" "$f" && grep -qE "var albums: \[BackupAlbum\]" "$f" && grep -qE "let upload: UploadViewModel" Sources/DependencyContainer.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1046 [type: new]
Assertion: BackupSettingsView comporte toggles Auto backup/Wi-Fi only/Charging only/Exclude screenshots + liste Albums (checkmark) + ligne progression (uploaded/rejected/failed + Run now + Cancel).
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -q "Auto backup" "$f" && grep -q "Wi-Fi only" "$f" && grep -q "Charging only" "$f" && grep -q "Exclude screenshots" "$f" && grep -qE "ProgressView" "$f" && grep -qE "Run now" "$f" && grep -qE "Cancel" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1047 [type: new]
Assertion: Registration BG dans ImmichSwiftUIApp (BGTaskScheduler.shared.register w/ taskIdentifier "app.immich.background-backup", expiration → engine.cancel(), resubmit après run) + project.yml BGTaskSchedulerPermittedIdentifiers + UIBackgroundModes processing.
Check post-impl: sh -c 'grep -q "BGTaskScheduler.shared.register" Sources/ImmichSwiftUIApp.swift && grep -q "app.immich.background-backup" Sources/Services/BackgroundBackupScheduling.swift && grep -q "BGTaskSchedulerPermittedIdentifiers" project.yml && grep -qE "processing" project.yml && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1048 [type: new] — check révisé 2026-09-10
Assertion: Tests BackupEngineTests: ≥12 func test_ couvrant dédup accept/reject, checksum, gating réseau/batterie, cancel, continue-on-error, scoping d'albums, chunking, persistance des réglages; MockBackupAssetSource/MockBackupEnvironment.
Note (2026-09-10) : `MockBackupEnvironment` vit dans `Tests/Mocks/MockBackupAssetSource.swift` (le fichier `MockBackupEnvironment.swift` supposé n'a jamais existé). Le filtre Screenshots nom-de-fichier a été remplacé par le scoping d'albums (§2.12). Compte réel : 55 `func test_` dans le fichier.
Check post-impl: sh -c 'f=Tests/BackupEngineTests.swift; test -f "$f" && grep -qE "final class MockBackupAssetSource" Tests/Mocks/MockBackupAssetSource.swift && grep -qE "final class MockBackupEnvironment" Tests/Mocks/MockBackupAssetSource.swift && n=$(grep -cE "^[[:space:]]*func test_" "$f"); test "$n" -ge 12 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun de ces fichiers)
Post-state attendu: PASS
```

```
### AC-1049 [type: regression] — check révisé 2026-09-10
Assertion: Suite complète green ≥ 382 tests avec TEST SUCCEEDED.
Note (2026-09-10) : le check lisait un summary /tmp qui n'était produit par aucun run ultérieur. Il lance désormais la suite et écrit lui-même son summary (même forme que AC-BK09 / AC-NP07). Dernière mesure : **691 tests, TEST SUCCEEDED** (iPhone 17, 2026-09-10).
Check post-impl: sh -c 'cd /Users/millian/SideProjects/immich_swiftui && xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination "platform=iOS Simulator,name=iPhone 17" 2>&1 | tee /tmp/immich_backup_engine_test_summary.txt | grep -q "TEST SUCCEEDED" && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_backup_engine_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1); test "${n:-0}" -ge 382 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (pas de summary)
Post-state attendu: PASS
```