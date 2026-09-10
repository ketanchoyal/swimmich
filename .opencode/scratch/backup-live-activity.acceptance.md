# Task: backup-live-activity

Status: shipped — AC-1050..AC-1056 PASS 2026-08-12 (405 tests, baseline 399). Lessons: attributes host-import-extension = link failure → shared framework ImmichSharedKit; public struct + public memberwise inits requis cross-module; plain grep sans -r (wrapper rtk) retourne vide sur Tests/ → rtk grep pour récursif; AC-1055 nécessitait 5 tests nommés test_liveActivity_* (4 initiaux → ajout test_liveActivity_hookClearedAfterRun).

> **Révision du 2026-09-10** — refonte « premium » de la Live Activity (glyph + anneau de progression, chips de statut, countdown d'ETA, keyline indigo) et trois checks périmés réécrits : AC-1050 (le check était **inopérant** : `grep -qA3` ne produit aucune sortie, donc le pipe ne pouvait jamais matcher), AC-1051 (les attributes vivent dans `Sources/ImmichSharedKit/` — obligatoire pour que l'app et l'extension partagent le MÊME type `Activity`), AC-1055/AC-1056 (test de hook renommé, tests de lifecycle extraits dans `UploadViewModelLiveActivityTests.swift`, summary /tmp orphelin). Nouvelle mesure : **691 tests, TEST SUCCEEDED** (iPhone 17, 2026-09-10).

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
### AC-1050 [type: new] — check réparé 2026-09-10
Assertion: project.yml déclare un target d'extension widget `ImmichWidgets` (type app-extension) avec bundle fr.millianlmx.immich-ios.widgets, embeddé dans l'app, et les clés Live Activity dans info.properties de l'app.
Note (2026-09-10) : le check était **inopérant** — `grep -qA3` supprime toute sortie, donc le pipe `| grep -q "ImmichWidgets"` recevait un flux vide et échouait toujours. La clause est réécrite avec `-A3` sans `-q`. L'assertion était déjà satisfaite : l'app cible embarque `- target: ImmichWidgets / embed: true`, et `NSSupportsLiveActivities(+FrequentUpdates)` est présent (project.yml:46-47 → Resources/Info.plist:49-52).
Check post-impl: sh -c 'f=project.yml; grep -qE "  ImmichWidgets:" "$f" && grep -qE "type: app-extension" "$f" && grep -qE "fr.millianlmx.immich-ios.widgets" "$f" && grep -qE "NSSupportsLiveActivities" "$f" && grep -A3 "^    dependencies:" "$f" | grep -q "ImmichWidgets" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1051 [type: new] — check révisé 2026-09-10
Assertion: `BackupActivityAttributes` (ContentState riche + Phase) vit dans Sources/ImmichSharedKit/, et ImmichWidgets/BackupLiveActivity.swift porte l'ActivityConfiguration (expanded/compactLeading/compactTrailing/minimal) + le WidgetBundle @main.
Note (2026-09-10) : les attributes ont DÛ quitter le target widget pour `ImmichSharedKit` — l'app les instancie et l'extension les rend ; `Activity` apparie par (module, type), donc deux copies = deux types = île qui n'apparaît jamais. Le fichier a aussi gagné la refonte « premium » (glyph + anneau de progression, chips de statut, countdown d'ETA).
Check post-impl: sh -c 'a=Sources/ImmichSharedKit/BackupActivityAttributes.swift; f=ImmichWidgets/BackupLiveActivity.swift; grep -q "struct BackupActivityAttributes: ActivityAttributes" "$a" && grep -q "var progress: Double" "$a" && grep -q "enum Phase" "$a" && grep -q "ActivityConfiguration(for: BackupActivityAttributes.self)" "$f" && grep -q "compactTrailing" "$f" && grep -q "minimal" "$f" && grep -q "WidgetBundle" "$f" && grep -q "@main" "$f" && grep -q "ImmichSharedKit" "$f" && echo PASS || echo FAIL'
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
### AC-1055 [type: new] — check révisé 2026-09-10
Assertion: Tests — MockBackupLiveActivityService + hook engine + lifecycle VM (start/update/end) couverts par ≥ 5 tests nommés test_liveActivity_* (BackupEngineTests + UploadViewModelLiveActivityTests).
Note (2026-09-10) : le test de séquence du hook s'appelle désormais `test_backupEngine_progressAdvancesDuringStagingThenUploads` (le hook avance maintenant deux fois par asset — un demi-pas au staging, un au verdict — d'où sa forme actuelle) ; les 4 tests de lifecycle VM ont été extraits dans `Tests/UploadViewModelLiveActivityTests.swift`. Compte réel : 7 tests `test_liveActivity_*`.
Check post-impl: sh -c 'grep -rl "MockBackupLiveActivityService" Tests/Mocks/ >/dev/null && grep -rq "test_backupEngine_progressAdvancesDuringStagingThenUploads" Tests/ && t=$(grep -rho "func test_liveActivity_[A-Za-z_]*" Tests/ | wc -l | tr -d " "); test "$t" -ge 5 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1056 [type: regression] — check révisé 2026-09-10
Assertion: Suite complète ≥ 399 tests verts après régression (baseline backup-engine 399).
Note (2026-09-10) : le check lisait un summary /tmp qui n'était produit par aucun run ultérieur. Il lance désormais la suite et écrit lui-même son summary. Dernière mesure : **691 tests, TEST SUCCEEDED** (iPhone 17, 2026-09-10, baseline 405 → 691).
Check post-impl: sh -c 'cd /Users/millian/SideProjects/immich_swiftui && xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination "platform=iOS Simulator,name=iPhone 17" 2>&1 | tee /tmp/immich_live_activity_test_summary.txt | grep -q "TEST SUCCEEDED" && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_live_activity_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "${n:-0}" -ge 399 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```