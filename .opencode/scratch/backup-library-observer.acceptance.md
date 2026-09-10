# Task: backup-library-observer

Status: shipped — AC-LO01–LO08 PASS le 2026-09-10 (suite 688 tests, TEST SUCCEEDED sur iPhone 17). AC-LO08 (vérification device) reste manuel.

**Spec** : `.omp/backup-auto/backup-library-observer.specs.md`
**Dépendances** : indépendant des quatre autres suites backup (il ne touche ni `BackupEngine.run()`, ni `BackupCandidate`, ni le ledger). Peut partir en parallèle de `backup-live-photos` / `backup-ledger-reconciliation` sans conflit de fichiers.

## Plan

**Objectif** : faire que « Auto-detect new photos » détecte réellement les nouvelles photos. Aujourd'hui le toggle ne branche **aucun** observateur : il autorise seulement un scan à l'activation de la scène.

État actuel vérifié le 2026-09-09 :
- Aucun `PHPhotoLibraryChangeObserver` dans `Sources/` (grep vide).
- `UploadViewModel.kickOffAutoBackupIfConfigured()` (`Sources/Features/Upload/UploadViewModel.swift:304-308`) : `guard settings.autoDetectNewPhotos, !running` → `runBackup(manual: false)`.
- Unique appelant : `DependencyContainer.kickOffAutoBackup()` (`Sources/DependencyContainer.swift:98-100`), appelé depuis `scenePhase == .active` (`Sources/ImmichSwiftUIApp.swift:24`).
- Le commentaire du champ est honnête (`BackupEngine.swift:9-12` : « Foreground auto-run gate: when on, app activation runs a scan ») ; **le libellé UI ne l'est pas** (`UploadViewModel.swift:475` : « Auto-detect new photos »).

**Contrainte plateforme assumée** : iOS n'a pas l'équivalent des content-URI triggers Android du Flutter (étude §3.3). Seuls déclencheurs : activation au premier plan, fenêtres `BGTaskScheduler` (déjà en place, `ImmichSwiftUIApp.swift:44-63`) et, **pendant que l'app tourne**, les callbacks `PHPhotoLibraryChangeObserver`. Périmètre = (1) un vrai observateur premier-plan, (2) un libellé qui ne promet pas ce qu'iOS ne permet pas.

**Hypothèses complémentaires** (le reste du ground truth est l'état actuel ci-dessus) :
- `PhotoLibraryServiceImpl` (`Sources/Services/PhotoLibraryServiceImpl.swift:8`) est `final class … @unchecked Sendable` et porte l'extension `BackupAssetSource` (l.158) — `PHPhotoLibrary.shared().register` exige une classe, ce qui exclut de le poser sur un struct.
- `photoLibraryDidChange` arrive sur une queue arbitraire ; tout ce qui touche `UploadViewModel` (`@MainActor`, l.118-120) doit hopper.
- `PHPhotoLibrary.shared().register` exige l'autorisation Photos ; `UploadViewModel.ensurePhotoAccess()` existe déjà (appelé l.306).
- `DependencyContainer` est un singleton `@MainActor` — point de câblage naturel du cycle de vie.

**Endpoints** : aucun (PhotosKit uniquement).

**Approche retenue** : **A — observateur dédié, réveillé par les *insertions* seulement, débounce, protocole injectable.**
`PhotoLibraryChangeMonitor` conserve un `PHFetchResult<PHAsset>` de référence (toute la photothèque, tri par date de création DESC comme `fetchCandidates`). À chaque `photoLibraryDidChange` : `changeInstance.changeDetails(for: baseline)`, **réveil uniquement si `insertedObjects` n'est pas vide**, puis baseline = `details.fetchResultAfterChanges`. Débounce de 5 s pour coalescer la rafale d'un import (burst, AirDrop de 50 fichiers, édition de masse). Sans le filtre sur `insertedObjects`, chaque édition/favori/suppression déclencherait un scan complet de la photothèque — le chemin le plus chaud du moteur.
- **B (rejetée)** : réveiller sur tout changement avec un débounce plus long — transforme n'importe quelle édition en scan complet ; le ledger amortit le coût des exports, pas celui de l'énumération.
- **C (rejetée)** : renommer le toggle sans observer — laisse un trou fonctionnel réel (app ouverte, photo prise, rien ne part avant la prochaine activation ou fenêtre BGTask).

**Étapes** :
1. **NEW** `Sources/Core/Protocols/PhotoLibraryChangeMonitoring.swift` — `protocol PhotoLibraryChangeMonitoring: AnyObject, Sendable` : `var onAssetsInserted: (@MainActor @Sendable () -> Void)? { get set }`, `func start()`, `func stop()`.
2. **NEW** `Sources/Services/PhotoLibraryChangeMonitor.swift` — `final class PhotoLibraryChangeMonitor: NSObject, PHPhotoLibraryChangeObserver, PhotoLibraryChangeMonitoring, @unchecked Sendable` ; `start()` idempotent (drapeau sous `NSLock`), pose la baseline (`PHAsset.fetchAssets(with:)`, mêmes `sortDescriptors` que `fetchCandidates`, sans le predicate d'indice de prefetch — on ne lit que les identifiants) puis `PHPhotoLibrary.shared().register(self)` ; `stop()` : `unregisterChangeObserver`, annule le `Task` de débounce, libère la baseline ; `photoLibraryDidChange` : `changeDetails(for: baseline)` → `guard !insertedObjects.isEmpty` → baseline = `fetchResultAfterChanges` → relance le `Task` de débounce (`debounce: TimeInterval = 5`, annulation du précédent) → hop `@MainActor` → `onAssetsInserted?()` ; `deinit` appelle `stop()`.
3. **EDIT** `Sources/DependencyContainer.swift` — `let libraryMonitor: PhotoLibraryChangeMonitoring` (injectable pour les tests), `onAssetsInserted = { [weak self] in self?.kickOffAutoBackup() }` ; `func syncLibraryMonitor()` : `start()` si `BackupSettingsStore().isEnabled && .autoDetectNewPhotos`, sinon `stop()` — appelée depuis `kickOffAutoBackup()` et depuis le `onChange` des deux toggles.
4. **EDIT** `Sources/ImmichSwiftUIApp.swift` — `scenePhase == .active` : `container.syncLibraryMonitor()` après `kickOffAutoBackup()` ; `scenePhase == .background` : `container.libraryMonitor.stop()` (inutile de tenir un observateur Photos hors premier plan, et ça évite un réveil concurrent de la fenêtre BGTask).
5. **EDIT** `Sources/Features/Upload/UploadViewModel.swift` — libellé l.475 → « Back up new photos automatically » ; footer de section : « While Immich is open, new photos start backing up within a few seconds. When it's closed, iOS decides when to run — usually while charging on Wi-Fi. » ; `onChange` du toggle → `DependencyContainer.shared.syncLibraryMonitor()`.
6. **NEW** `Tests/Mocks/MockLibraryMonitor.swift` + **NEW** `Tests/PhotoLibraryChangeMonitorTests.swift` — 6 tests via le mock : start quand auto-detect activé, stop quand désactivé, stop quand auto-backup désactivé, callback → un seul run, ignoré pendant un run (le garde `!running` l.305 reste la seule protection), débounce coalescant (débounce injecté à 0,05 s).
7. `xcodegen generate` — **obligatoire** : deux fichiers NEW sous `Sources/` et deux sous `Tests/` ; sans regen le fichier de test n'est jamais compilé (piège connu).

**Risques** : boucle de réveil — un run de backup ne modifie pas la photothèque, mais un download d'asset depuis le serveur écrit dans Photos et déclencherait un run (le filtre `insertedObjects` ne distingue pas ; le ledger rend le run court, garder le débounce ≥ 5 s) ; vérification device requise (AC-LO08).

## Acceptance Contract

### Approches candidates
**A (retenue)** : observateur filtrant les insertions + débounce + protocole injectable + libellé honnête.
**B** : réveil sur tout changement. Rejetée (scan complet à chaque édition).
**C** : renommer le toggle sans observer. Rejetée (trou fonctionnel réel).

### Approche retenue + rationale
**A** — c'est le seul déclencheur temps réel qu'iOS accorde, le filtre `insertedObjects` évite de transformer une édition en scan complet, et le protocole garde le câblage testable sans `PHPhotoLibrary`.

### Critères

```
### AC-LO01 [type: new]
Assertion: un observateur Photos existe, filtre les insertions et débounce.
Check post-impl: sh -c 'f=Sources/Services/PhotoLibraryChangeMonitor.swift; test -f "$f" && grep -q "PHPhotoLibraryChangeObserver" "$f" && grep -q "insertedObjects" "$f" && grep -q "debounce" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-LO02 [type: new]
Assertion: le monitor est derrière un protocole injectable, pas instancié en dur dans la vue.
Check post-impl: sh -c 'f=Sources/Core/Protocols/PhotoLibraryChangeMonitoring.swift; test -f "$f" && grep -q "onAssetsInserted" "$f" && grep -q "libraryMonitor" Sources/DependencyContainer.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-LO03 [type: new]
Assertion: le cycle de vie suit les réglages et la scène (start/stop).
Check post-impl: sh -c 'grep -q "func syncLibraryMonitor" Sources/DependencyContainer.swift && grep -q "syncLibraryMonitor" Sources/ImmichSwiftUIApp.swift && grep -q "libraryMonitor.stop" Sources/ImmichSwiftUIApp.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-LO04 [type: new]
Assertion: le libellé ne promet plus une détection permanente et le footer explique les deux régimes.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; ! grep -qE "Toggle\(\"Auto-detect" "$f" && grep -q "Back up new photos automatically" "$f" && grep -q "While Immich is open" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (l.475)
Post-state attendu: PASS
```

```
### AC-LO05 [type: new]
Assertion: le câblage est couvert par des tests avec un monitor mocké (≥6 tests) et le mock existe.
Check post-impl: sh -c 'f=Tests/PhotoLibraryChangeMonitorTests.swift; n=$(grep -c "func test_" "$f" 2>/dev/null); n=${n:-0}; test "$n" -ge 6 && test -f Tests/Mocks/MockLibraryMonitor.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichiers absents)
Post-state attendu: PASS
```

```
### AC-LO06 [type: new]
Assertion: xcodegen relancé — les fichiers NEW sont dans le projet.
Check post-impl: sh -c 'grep -q "PhotoLibraryChangeMonitor" ImmichSwiftUI.xcodeproj/project.pbxproj && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-LO07 [type: regression]
Assertion: suite complète ≥ 645 tests (baseline 2026-09-09), TEST SUCCEEDED.
Check post-impl: sh -c 'xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination "platform=iOS Simulator,name=iPhone 17" 2>&1 | tee /tmp/immich_lo_test.txt | grep -q "TEST SUCCEEDED" && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_lo_test.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "${n:-0}" -ge 645 && echo PASS || echo FAIL'
Pre-state attendu: n/a
Post-state attendu: PASS
```

```
### AC-LO08 [type: manual]
Assertion: vérification device/simulateur — app au premier plan, ajout d'une photo dans Photos, un run démarre en moins de ~10 s (anneau de progression visible autour de l'avatar du Timeline).
Check post-impl: manuel (aucun grep possible : PHPhotoLibraryChangeObserver n'est pas simulable en unitaire).
Pre-state attendu: aucun run déclenché
Post-state attendu: run déclenché
```
