# Task: backup-live-activity

Status: shipped — AC-1050..AC-1056 PASS 2026-08-12 (405 tests, baseline 399). Lessons: attributes host-import-extension = link failure → shared framework ImmichSharedKit; public struct + public memberwise inits requis cross-module; plain grep sans -r (wrapper rtk) retourne vide sur Tests/ → rtk grep pour récursif; AC-1055 nécessitait 5 tests nommés test_liveActivity_* (4 initiaux → ajout test_liveActivity_hookClearedAfterRun).

## Plan
**Objectif**: Live Activity upload progress (Dynamic Island + Lock Screen) pendant les sauvegardes du backup-engine (card P2 backup-engine, AC-1040..AC-1049). Premier target d'extension du projet: widget extension partagé (servira aussi aux widgets home-screen du card P5 widgets-appintents).

**Hypothèses** (grounded):
- project.yml (82L): targets = ImmichSwiftUI + ImmichSwiftUITests; `info.properties` écrit Resources/Info.plist via xcodegen (GENERATE_INFOPLIST_FILE NO); scheme build targets liste explicites; bundle app fr.millianlmx.immich-ios (:49).
- BackupEngine.swift (P2): @Observable @MainActor; phase/uploadedCount/currentIndex/total private(set); run(settings:) loop upload; cancel() flag; MainActor-typé → hook progress sûr.
- UploadViewModel.swift (P2): runBackup() = `await engine.run(settings: settings.snapshot()); if phase == .done { scheduler.submit() }`; settings/engine injectés.
- Tests: Mock sealed (MockBackupScheduler submitCount); suite 399 verts; pattern card AC-1040..1049.
- Info.plist requis Live Activity: NSSupportsLiveActivities (+ NSSupportsLiveActivitiesFrequentUpdates pour updates fréquentes) — clé app target.
- Extension widget: NSExtensionPointIdentifier com.apple.widgetkit-extension; bundle fr.millianlmx.immich-ios.widgets; embed dans app target (dependencies embed); widget source HORS de Sources/ (sources glob app target = path: Sources — inclusion du dossier widget casserait le build app); dossier racine ImmichWidgets/.
- ActivityKit (Activity.request/update/end + ActivityAuthorizationInfo) non unit-testable de façon hermétique → service protocol + Mock injecté; tests portent sur le lifecycle VM + hook engine.

**Approche retenue**: A — service protocol `BackupLiveActivityServicing` (start/update/end) + `LiveActivityBackupService` (ActivityKit réel, areActivitiesEnabled guard, Task pour update/end async) injecté dans UploadViewModel; hook progression dans BackupEngine (`var onProgressUpdate: ((uploaded: Int, total: Int) -> Void)?` appelé MainActor après chaque item + au début du phase .uploading); widget extension ImmichWidgets/ avec BackupActivityAttributes + ActivityConfiguration (Lock Screen ProgressView + DynamicIsland expanded/compact/minimal) + WidgetBundle @main. VM: start → update via hook → end selon phase .done/.cancelled. B (tout dans VM sans hook) rejeté: aucune update intermédiaire sans poll/observation fragile. C (start/end only) rejeté: perte de la progression live (but du Live Activity).

**Étapes**:
1. `.opencode/scratch/backup-live-activity.acceptance.md` — contrats AC-1050..AC-1058.
2. BackupEngine.swift: + hook onProgressUpdate (set nil par défaut; appels: début .uploading (0, acceptedCount) + après chaque currentIndex+=1 (uploadedCount, total)); test séquence.
3. NEW `Sources/Services/BackupLiveActivityService.swift` — protocol BackupLiveActivityServicing (start(uploaded:total:), update(uploaded:total:), end(uploaded:total:success:)) + LiveActivityBackupService (Activity.request guard areActivitiesEnabled; update/end via Task await; progress = total>0 ? min(up/total,1) : 0).
4. UploadViewModel: `let activityService: any BackupLiveActivityServicing = LiveActivityBackupService()` injectable; runBackup: engine.onProgressUpdate = [weak self] → activityService.update; start(uploaded:0,total:0) avant run; après run: onProgressUpdate=nil; .done → end(success: failedCount==0); .cancelled → end(success:false); scheduler.submit inchangé.
5. NEW `ImmichWidgets/BackupLiveActivity.swift` — BackupActivityAttributes: ActivityAttributes {ContentState{progress,uploaded,total} Codable Hashable; totalCount}; BackupLiveActivity: Widget — ActivityConfiguration(for:): content v Stack (phase label? non — titre "Immich Backup", ProgressView(value:context.state.progress), "uploaded of total" texte, activityBackgroundTint); dynamicIsland: expanded (.leading pct texte, .trailing uploaded/total), compactLeading image(square.and.arrow.up), compactTrailing Text(pct), minimal Text(pct). WidgetBundle @main struct ImmichWidgetsBundle.
6. project.yml: target ImmichWidgets (type: app-extension; sources: - path: ImmichWidgets; info générée inline path ImmichWidgets/Info.plist properties NSExtension + CFBundleDisplayName; settings PRODUCT_BUNDLE_IDENTIFIER fr.millianlmx.immich-ios.widgets, base settings globaux) + app target `dependencies: - target: ImmichWidgets embed: true` + info.properties NSSupportsLiveActivities + NSSupportsLiveActivitiesFrequentUpdates (BOOLEAN true) + scheme build targets ImmichWidgets: all. `xcodegen generate`.
7. Tests: NEW Tests/Mocks/MockBackupLiveActivityService.swift (started/updated/ended captures); BackupEngineTests + test_onProgressHookSequence; UploadViewModelTests (exist?) — vérifier fichier Tests/UploadViewModelTests.swift puis ajouter 4 tests lifecycle VM (start avant upload, update pendant via hook mock, end success on done, end failure on cancelled).
8. xcodebuild build-for-testing (2 targets) + suite complète.
9. AC checks + memory.md entry + Status shipped.

## Acceptance Contract

### Approches candidates
A (retenue): Protocol service + hook engine + extension widget dédié.
B: VM polling engine — fragile, pas de chemin d'update déterministe.
C: start/end only — pas de progression live.

### Critères

```
### AC-1050 [type: new]
Assertion: project.yml déclare un target d'extension widget `ImmichWidgets` (type app-extension) avec bundle fr.millianlmx.immich-ios.widgets, embeddé dans l'app, et les clés Live Activity dans info.properties de l'app.
Check post-impl: sh -c 'f=project.yml; grep -qE "  ImmichWidgets:" "$f" && grep -qE "type: app-extension" "$f" && grep -qE "fr.millianlmx.immich-ios.widgets" "$f" && grep -qE "NSSupportsLiveActivities" "$f" && grep -qE "dependencies:" "$f" && grep -qA3 "dependencies:" "$f" | grep -q "ImmichWidgets" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1051 [type: new]
Assertion: ImmichWidgets/ contient BackupLiveActivity.swift avec ActivityAttributes (ContentState progress/uploaded/total), ActivityConfiguration(for:), DynamicIsland (expanded/compactTrailing/minimal) et un WidgetBundle @main.
Check post-impl: sh -c 'f=ImmichWidgets/BackupLiveActivity.swift; grep -q "struct BackupActivityAttributes: ActivityAttributes" "$f" && grep -q "var progress: Double" "$f" && grep -q "ActivityConfiguration(for: BackupActivityAttributes.self)" "$f" && grep -q "compactTrailing" "$f" && grep -q "WidgetBundle" "$f" && grep -q "@main" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1052 [type: new]
Assertion: Service protocol BackupLiveActivityServicing (start/update/end) + impl LiveActivityBackupService dans Sources/Services/BackupLiveActivityService.swift utilisant Activity.request/update/end + garde areActivitiesEnabled.
Check post-impl: sh -c 'f=Sources/Services/BackupLiveActivityService.swift; grep -q "protocol BackupLiveActivityServicing" "$f" && grep -q "func start" "$f" && grep -q "func update" "$f" && grep -q "func end" "$f" && grep -q "final class LiveActivityBackupService" "$f" && grep -q "Activity.request" "$f" && grep -q "areActivitiesEnabled" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1053 [type: new]
Assertion: BackupEngine expose un hook de progression onProgressUpdate appelé en fin de run (uploaded,total) — points d'appel explicites dans la boucle.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -q "onProgressUpdate" "$f" && grep -q "onProgressUpdate?(" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1054 [type: new]
Assertion: UploadViewModel reçoit activityService injectable (défaut LiveActivityBackupService), appelle start avant run, update via hook engine, end sur .done/.cancelled.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -q "BackupLiveActivityServicing" "$f" && grep -q "activityService.start" "$f" && grep -q "activityService.update" "$f" && grep -q "activityService.end" "$f" && grep -q "onProgressUpdate" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1055 [type: new]
Assertion: Tests — MockBackupLiveActivityService + hook engine + lifecycle VM (start/update/end) couverts par ≥ 5 tests nommés test_liveActivity_* (BackupEngineTests + UploadViewModelTests).
Check post-impl: sh -c 'n=$(grep -rl "test_liveActivity_" Tests/ | wc -l | tr -d " "); grep -rl "MockBackupLiveActivityService" Tests/Mocks/ >/dev/null && grep -rl "test_backupEngine_onProgressHookSequence" Tests/ >/dev/null && t=$(grep -rho "func test_liveActivity_[A-Za-z_]*" Tests/ | wc -l | tr -d " "); test "$t" -ge 5 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1056 [type: regression]
Assertion: Suite complète ≥ 399 tests verts après régression (baseline backup-engine 399).
Check post-impl: sh -c 'rtk grep -q "TEST SUCCEEDED" /tmp/immich_live_activity_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_live_activity_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 399 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```