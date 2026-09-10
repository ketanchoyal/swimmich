# Task: backup-network-policy

**Objectif** : passer d'un gate réseau tout-ou-rien à une politique par type de
média, comme le client Flutter (`useCellularForPhotos` / `useCellularForVideos`,
étude §7.1 et §9), et ne plus mentir sur l'état « hors ligne ».

État actuel — `BackupEngine.run()`
(`Sources/Services/BackupEngine.swift:182-193`) :

```swift
if settings.onlyOnWiFi && !environment.hasWiFiConnection {
    lastError = "Backup requires a Wi-Fi connection."
    return false
}
```

Deux problèmes :
1. **Tout ou rien** : en 5G, un utilisateur qui accepterait volontiers de monter
   ses photos (quelques Mo) mais pas ses vidéos (plusieurs Go) doit choisir
   entre « rien » et « tout ».
2. **Pas de notion de hors-ligne** : `hasWiFiConnection == false` couvre
   indifféremment « en cellulaire » et « aucune connectivité ». Sans
   `onlyOnWiFi`, un run hors ligne part quand même, télécharge/hashe les
   originaux, puis échoue à l'upload — et chaque asset part en `failedCount`
   avec `failures.append` (l.415-419), c'est-à-dire exactement le faux échec
   alarmant que la distinction `deferred` a été introduite pour éliminer
   (mem `a4702a53`).

**Hypothèses (vérifiées le 2026-09-09)** :
- `BackupEnvironment` (`Sources/Services/BackupEnvironment.swift:6-9`) :
  `isCharging`, `hasWiFiConnection`. `SystemBackupEnvironment` tient déjà un
  `NWPathMonitor` process-wide (l.28-42) dont le handler reçoit le `path`
  complet — `path.status` et `path.isExpensive` sont donc disponibles sans
  nouveau monitor.
- `BackupCandidate.kind: BackupAssetKind { image, video }`
  (`Core/Protocols/BackupAssetSource.swift:5-8,14`) — la discrimination par type
  existe déjà côté candidat.
- Comptabilité de progression (`BackupEngine.swift:56,83`) :
  `processedCount = uploadedCount + rejectedCount + failedCount + deferredCount`,
  `deferredCount` est incrémenté sans `lastError` ni `failures.append` et repris
  au run suivant (l.269-281) ; `stagedCount` crédite la moitié de pas
  (mem `0810015a`).
- `MockBackupEnvironment` (`Tests/Mocks/MockBackupAssetSource.swift:59-65`) :
  `isChargingValue`, `hasWiFiValue`.
- UI : toggles `Wi-Fi only` / `Charging only`
  (`Sources/Features/Upload/UploadViewModel.swift:470-471`) ; segments et
  légendes de la barre dans `BackupSettingsView.segmentBar` /
  `completionSummary` (le segment `immichWarning` + « Waiting N » existe déjà
  pour les deferrals, mem `a4702a53`).

**Approche retenue** : **A — le gate Wi-Fi devient une décision par asset, et
son résultat est un report (deferred), pas un échec.**

- `BackupSettings` : `onlyOnWiFi` conservé comme interrupteur maître, plus
  `allowCellularForPhotos` / `allowCellularForVideos`.
- Nouveau gate global unique : `guard environment.isOnline` (sinon `return false`,
  phase inchangée, aucun octet lu — le run est un no-op réarmé par la chaîne
  BGTask).
- En cellulaire, un candidat dont le type n'est pas autorisé est **reporté avant
  son export** : `deferredCount += 1`, `notifyProgress()`, `continue` — pas de
  download iCloud, pas de hash, pas d'upload, pas de `failures`. C'est
  sémantiquement le même bucket que « iCloud pas encore prêt » : non-échec,
  repris automatiquement.
- Le libellé utilisateur du bucket doit rester juste dans les deux cas :
  `BackupEngine` expose `deferralReason: BackupDeferralReason?`
  (`.waitingForICloud` / `.waitingForWiFi` / `.mixed`) posé au fil du run, et la
  légende affiche « Waiting for Wi-Fi — N » ou « Waiting for iCloud — N ».

- **B (rejetée)** : compteur `skippedCount` distinct. Il faudrait le rentrer dans
  `processedCount` pour que la barre atteigne 100 %, et on se retrouve avec deux
  buckets au comportement identique (non-échec, repris au run suivant) — un
  quatrième segment dans la barre pour aucune décision utilisateur différente.
- **C (rejetée)** : garder le gate global mais le rendre par type au niveau du
  run (« si vidéo interdite en cellulaire, ne lance rien tant qu'il reste des
  vidéos »). Bloque les photos derrière les vidéos, c'est-à-dire l'inverse du
  besoin.

## Étapes

1. **EDIT** `Sources/Services/BackupEnvironment.swift`
   - Protocole : ajouter `var isOnline: Bool { get }`.
   - `SystemBackupEnvironment` : le `pathUpdateHandler` cache aussi
     `cachedOnline = (path.status == .satisfied)`.
2. **EDIT** `Sources/Services/BackupEngine.swift`
   - `BackupSettings` : `allowCellularForPhotos = false`,
     `allowCellularForVideos = false`.
   - `run()` : remplacer le gate Wi-Fi l.186-189 par
     `guard environment.isOnline else { lastError = "Backup needs a network connection."; return false }`
     (branche `!manual` uniquement, comme les autres gates — un run manuel garde
     sa sémantique « action explicite » documentée l.160-163).
   - Nouveau helper `private func isUploadAllowedNow(_ candidate: BackupCandidate, _ settings: BackupSettings) -> Bool` :
     `true` si `environment.hasWiFiConnection || !settings.onlyOnWiFi ||
     (candidate.kind == .image ? settings.allowCellularForPhotos : settings.allowCellularForVideos)`.
   - Boucle de `run()` : tester ce helper **avant** `source.exportOriginal`
     (l.247) → `deferredCount += 1`, `deferralReason.insert(.waitingForWiFi)`,
     `notifyProgress()`, `continue`.
   - `enum BackupDeferralReason` + `private(set) var deferralReason`, remis à nil
     dans `reset()` (l.471-485).
3. **EDIT** `Sources/Features/Upload/UploadViewModel.swift`
   - `BackupSettingsStore` : `allowCellularForPhotos` /
     `allowCellularForVideos` sur les clés `photoBackupCellularPhotos` /
     `photoBackupCellularVideos`, propagées dans `snapshot()`.
   - `backupSection` : sous `Wi-Fi only`, deux toggles indentés visibles
     seulement quand `onlyOnWiFi` est actif — « Use cellular for photos », « Use
     cellular for videos » — avec un footer qui dit ce que ça coûte.
   - Légende de la barre + `completionSummary` : libellé du bucket deferred
     dérivé de `engine.deferralReason`.
4. **EDIT** `Tests/Mocks/MockBackupAssetSource.swift` — `MockBackupEnvironment`
   gagne `isOnlineValue = true`.
5. **EDIT** `Tests/BackupEngineTests.swift` — nouvelle classe `NetworkPolicyTests` :
   - `test_offline_runDoesNotEnterPipeline` (retour `false`, `phase == .idle`,
     `source.purgeCount == 0`)
   - `test_cellular_photosAllowedVideosDeferred` (un image + une vidéo :
     `uploadedCount == 1`, `deferredCount == 1`, `failedCount == 0`)
   - `test_cellular_deferredAssetIsNeverExported` (le mock n'est pas sollicité
     pour l'asset reporté)
   - `test_cellular_deferralDoesNotSetLastErrorNorFailures`
   - `test_wifi_allCandidatesUploadedRegardlessOfCellularToggles`
   - `test_manualRun_ignoresCellularPolicy`
   - `test_deferralReason_reportsWiFiVsICloud`
   - Le test existant `test_backup_wifiGateBlocksRun`
     (`Tests/BackupEngineTests.swift`) pinne l'ancien comportement tout-ou-rien :
     il est **remplacé** par `test_offline_runDoesNotEnterPipeline` +
     `test_cellular_photosAllowedVideosDeferred`, pas re-pinné.

## Risques

- Un utilisateur en cellulaire avec « Wi-Fi only » verra maintenant la barre
  monter jusqu'à 100 % en « Waiting », alors qu'avant le run ne démarrait pas du
  tout. C'est plus informatif mais c'est un changement visible : la légende doit
  nommer la cause, sinon ça ressemble à un backup qui ne fait rien.
- `isExpensive` (partage de connexion) n'est **pas** traité : un hotspot Wi-Fi
  compte comme du Wi-Fi. Hors périmètre, à documenter dans le footer.

## Acceptance Contract

### Approches candidates
**A (retenue)** : gate par asset, résultat = deferred, plus un gate `isOnline`.
**B** : compteur `skippedCount` séparé. Rejetée (bucket redondant).
**C** : gate global par type au niveau du run. Rejetée (bloque les photos
derrière les vidéos).

### Approche retenue + rationale
**A** — réutilise exactement la sémantique `deferred` déjà éprouvée (non-échec,
repris au run suivant, barre qui atteint 100 %), et le gate `isOnline` supprime
la classe de faux échecs « upload hors ligne ».

### Critères

```
### AC-NP01 [type: new]
Assertion: BackupEnvironment expose isOnline, alimenté par NWPathMonitor.
Check post-impl: sh -c 'f=Sources/Services/BackupEnvironment.swift; grep -q "var isOnline" "$f" && grep -q "path.status == .satisfied" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-NP02 [type: new]
Assertion: BackupSettings porte la politique cellulaire par type et l'engine décide par asset.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -q "allowCellularForPhotos" "$f" && grep -q "allowCellularForVideos" "$f" && grep -q "func isUploadAllowedNow" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-NP03 [type: new]
Assertion: le gate réseau global est "hors ligne", plus "pas de Wi-Fi".
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -q "environment.isOnline" "$f" && ! grep -q "Backup requires a Wi-Fi connection" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (l.187)
Post-state attendu: PASS
```

```
### AC-NP04 [type: new]
Assertion: un asset bloqué par la politique réseau est reporté (deferred) avec une raison, jamais compté en échec.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -qE "(enum|struct) BackupDeferralReason" "$f" && grep -q "deferralReason" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-NP05 [type: new]
Assertion: l'UI expose les deux toggles cellulaire et nomme la cause du report.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -q "Use cellular for photos" "$f" && grep -q "Use cellular for videos" "$f" && grep -q "Waiting for Wi-Fi" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-NP06 [type: new]
Assertion: NetworkPolicyTests couvre hors-ligne, mixte photo/vidéo en cellulaire, absence d'export de l'asset reporté, absence de lastError, run manuel, raison du report (≥7 tests) ; l'ancien test tout-ou-rien a disparu.
Check post-impl: sh -c 'f=Tests/BackupEngineTests.swift; n=$(sed -n "/final class NetworkPolicyTests/,/^}/p" "$f" | grep -c "func test_"); n=${n:-0}; test "$n" -ge 7 && ! grep -q "test_backup_wifiGateBlocksRun" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-NP07 [type: regression]
Assertion: suite complète TEST SUCCEEDED (baseline 645 tests le 2026-09-09 ; un test remplacé par sept).
Check post-impl: sh -c 'xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination "platform=iOS Simulator,name=iPhone 17" 2>&1 | tee /tmp/immich_np_test.txt | grep -q "TEST SUCCEEDED" && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_np_test.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "${n:-0}" -ge 645 && echo PASS || echo FAIL'
Pre-state attendu: n/a
Post-state attendu: PASS
```
