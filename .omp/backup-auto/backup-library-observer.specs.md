# Task: backup-library-observer

**Objectif** : faire que « Auto-detect new photos » détecte réellement les
nouvelles photos. Aujourd'hui le toggle ne branche aucun observateur : il
autorise seulement un scan à l'activation de la scène.

État actuel, vérifié le 2026-09-09 :
- Aucun `PHPhotoLibraryChangeObserver` dans `Sources/` (grep vide).
- `UploadViewModel.kickOffAutoBackupIfConfigured()`
  (`Sources/Features/Upload/UploadViewModel.swift:304-308`) :
  `guard settings.autoDetectNewPhotos, !running` → `runBackup(manual: false)`.
- Unique appelant : `DependencyContainer.kickOffAutoBackup()`
  (`Sources/DependencyContainer.swift:98-100`), lui-même appelé depuis
  `scenePhase == .active` (`Sources/ImmichSwiftUIApp.swift:24`).
- Le commentaire du champ est honnête (`BackupEngine.swift:9-12` : « Foreground
  auto-run gate: when on, app activation runs a scan ») ; **le libellé de l'UI
  ne l'est pas** (`UploadViewModel.swift:475` : « Auto-detect new photos »).

Contrainte plateforme, à assumer dans le périmètre : iOS n'offre pas
l'équivalent des content-URI triggers Android utilisés par le client Flutter
(étude §3.3). Les seuls déclencheurs disponibles sont l'activation au premier
plan, les fenêtres `BGTaskScheduler` (déjà en place,
`ImmichSwiftUIApp.swift:44-63`) et, **pendant que l'app tourne**, les callbacks
`PHPhotoLibraryChangeObserver`. Le périmètre est donc : (1) un vrai observateur
premier-plan, (2) un libellé qui ne promet pas ce qu'iOS ne permet pas.

**Hypothèses complémentaires** :
- `PhotoLibraryServiceImpl` (`Sources/Services/PhotoLibraryServiceImpl.swift:8`)
  est `final class ... @unchecked Sendable` et porte déjà l'extension
  `BackupAssetSource` (l.158) — l'enregistrement `PHPhotoLibrary.shared().register`
  exige une classe, ce qui exclut de le mettre sur un struct.
- Les callbacks `photoLibraryDidChange` arrivent sur une queue arbitraire ; tout
  ce qui touche `UploadViewModel` (`@MainActor`, l.118-120) doit hopper.
- `PHPhotoLibrary.shared().register` nécessite l'autorisation Photos ;
  `UploadViewModel.ensurePhotoAccess()` existe déjà (appelé l.306).
- `DependencyContainer` est un singleton `@MainActor` (mem `7bcff9a2`), point
  de câblage naturel du cycle de vie de l'observateur.

**Approche retenue** : **A — observateur dédié, réveillé par les *insertions*
seulement, débounce, protocole injectable.**

Un `PhotoLibraryChangeMonitor` conserve un `PHFetchResult<PHAsset>` de référence
(toute la photothèque, tri par date de création DESC comme
`fetchCandidates`). À chaque `photoLibraryDidChange`, il demande
`changeInstance.changeDetails(for: baseline)` et **ne réveille le backup que si
`insertedObjects` n'est pas vide** ; puis il remplace la baseline par
`details.fetchResultAfterChanges`. Un débounce de 5 s coalesce la rafale
d'événements que produit un import (une photo prise en mode burst, un
AirDrop de 50 fichiers, une édition de masse).

Sans le filtre sur `insertedObjects`, chaque édition, favori ou suppression
déclencherait un scan complet de la photothèque — le chemin le plus chaud du
moteur.

- **B (rejetée)** : réveiller sur tout changement avec un débounce plus long.
  Simple, mais transforme n'importe quelle édition en scan complet ; le ledger
  amortit le coût des exports, pas celui de l'énumération.
- **C (rejetée)** : ne rien observer et se contenter de renommer le toggle. Ne
  coûte rien mais laisse un trou fonctionnel réel : app ouverte, photo prise,
  rien ne part avant la prochaine activation ou fenêtre BGTask.

## Étapes

1. **NEW** `Sources/Core/Protocols/PhotoLibraryChangeMonitoring.swift`
   ```swift
   /// Réveil « nouvelles photos » pendant que l'app est au premier plan.
   protocol PhotoLibraryChangeMonitoring: AnyObject, Sendable {
       /// Appelé sur le MainActor, débouncé, uniquement après une insertion.
       var onAssetsInserted: (@MainActor @Sendable () -> Void)? { get set }
       func start()
       func stop()
   }
   ```
2. **NEW** `Sources/Services/PhotoLibraryChangeMonitor.swift`
   - `final class PhotoLibraryChangeMonitor: NSObject, PHPhotoLibraryChangeObserver, PhotoLibraryChangeMonitoring, @unchecked Sendable`.
   - `start()` : idempotent (drapeau sous `NSLock`), pose la baseline
     (`PHAsset.fetchAssets(with:)`, même `sortDescriptors` que
     `fetchCandidates`, sans le predicate d'indice de prefetch — on ne lit que
     les identifiants), puis `PHPhotoLibrary.shared().register(self)`.
   - `stop()` : `unregisterChangeObserver(self)`, annule le `Task` de débounce,
     libère la baseline.
   - `photoLibraryDidChange` : `changeDetails(for: baseline)` →
     `guard !details.insertedObjects.isEmpty` → baseline =
     `details.fetchResultAfterChanges` → relance le `Task` de débounce
     (`debounce: TimeInterval = 5`, annulation du Task précédent) → hop
     `@MainActor` → `onAssetsInserted?()`.
   - `deinit` appelle `stop()`.
3. **EDIT** `Sources/DependencyContainer.swift`
   - Propriété `let libraryMonitor: PhotoLibraryChangeMonitoring` (injectable pour
     les tests), `onAssetsInserted = { [weak self] in self?.kickOffAutoBackup() }`.
   - `func syncLibraryMonitor()` : `start()` si
     `BackupSettingsStore().isEnabled && .autoDetectNewPhotos`, sinon `stop()`.
     Appelée depuis `kickOffAutoBackup()` et depuis le `onChange` des deux
     toggles.
4. **EDIT** `Sources/ImmichSwiftUIApp.swift`
   - `scenePhase == .active` : `container.syncLibraryMonitor()` après
     `kickOffAutoBackup()`.
   - `scenePhase == .background` : `container.libraryMonitor.stop()` — inutile de
     tenir un observateur Photos hors premier plan, et ça évite un réveil
     concurrent de la fenêtre BGTask.
5. **EDIT** `Sources/Features/Upload/UploadViewModel.swift`
   - Libellé l.475 : « Back up new photos automatically ».
   - Footer de section : « While Immich is open, new photos start backing up
     within a few seconds. When it's closed, iOS decides when to run — usually
     while charging on Wi-Fi. » (dit la vérité sur les deux régimes, cf. la
     règle ActivityKit/BGTask déjà documentée, mem `f90129b1`).
   - `onChange` du toggle → `DependencyContainer.shared.syncLibraryMonitor()`.
6. **EDIT** `project.yml` non requis si les sources sont ajoutées sous
   `Sources/` (le target source le dossier) — **mais** `xcodegen generate` doit
   être relancé pour que les deux NEW entrent dans le projet, et le target de
   test source `Tests/` (piège connu, mem `d4198620`).
7. **NEW** `Tests/PhotoLibraryChangeMonitorTests.swift` — le monitor réel dépend
   de `PHPhotoLibrary`, donc les tests portent sur le **contrat de câblage** via
   un `MockLibraryMonitor` (NEW dans `Tests/Mocks/`) :
   - `test_monitor_startedWhenAutoDetectEnabled`
   - `test_monitor_stoppedWhenAutoDetectDisabled`
   - `test_monitor_stoppedWhenAutoBackupDisabled`
   - `test_insertedCallback_kicksBackupOnce`
   - `test_insertedCallback_ignoredWhileRunInFlight` (le garde `!running` de
     `kickOffAutoBackupIfConfigured` l.305 reste la seule protection)
   - `test_debounce_coalescesBurstIntoOneRun` (débounce injecté à 0,05 s)

## Risques

- **Boucle de réveil** : un run de backup ne modifie pas la photothèque, donc
  pas d'auto-déclenchement. Mais l'app peut écrire dans Photos ailleurs
  (téléchargement d'un asset depuis le serveur) : le filtre `insertedObjects`
  ne suffit pas à distinguer, et un download déclencherait un run. Le ledger
  fait que le run est court, mais le débounce doit rester ≥ 5 s.
- **Vérification device requise** : `PHPhotoLibraryChangeObserver` ne peut pas
  être testé en unitaire de façon utile. La preuve attendue est un run sur
  simulateur/device : app ouverte, ajout d'une image dans Photos, l'anneau de
  progression autour de l'avatar (`TimelineView.avatarBackupRing`, mem
  `73edbbd1`) apparaît dans les ~5 s.

## Acceptance Contract

### Approches candidates
**A (retenue)** : observateur filtrant les insertions + débounce + protocole
injectable + libellé honnête.
**B** : réveil sur tout changement. Rejetée (scan complet à chaque édition).
**C** : renommer le toggle sans observer. Rejetée (trou fonctionnel réel).

### Approche retenue + rationale
**A** — c'est le seul déclencheur temps réel qu'iOS accorde, le filtre
`insertedObjects` évite de transformer une édition en scan complet, et le
protocole garde le câblage testable sans `PHPhotoLibrary`.

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
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-LO05 [type: new]
Assertion: le câblage est couvert par des tests avec un monitor mocké (≥6 tests).
Check post-impl: sh -c 'f=Tests/PhotoLibraryChangeMonitorTests.swift; n=$(grep -c "func test_" "$f" 2>/dev/null); n=${n:-0}; test "$n" -ge 6 && test -f Tests/Mocks/MockLibraryMonitor.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
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
