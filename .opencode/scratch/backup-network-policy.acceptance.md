# Task: backup-network-policy

Status: shipped — AC-NP01–NP07 PASS le 2026-09-10 (suite 688 tests, TEST SUCCEEDED sur iPhone 17).

**Spec** : `.omp/backup-auto/backup-network-policy.specs.md`
**Dépendances** : à lancer **avant `backup-ledger-reconciliation`** (qui consomme `environment.isOnline`) ; partage `Sources/Services/BackupEngine.swift:182-193` avec `backup-album-scoping` (l.209-217) mais pas les mêmes lignes — les deux peuvent se suivre dans n'importe quel ordre, pas en parallèle. Indépendant de `backup-live-photos` et `backup-library-observer`.

## Plan

**Objectif** : passer d'un gate réseau tout-ou-rien à une politique par type de média (parité Flutter `useCellularForPhotos` / `useCellularForVideos`, étude §7.1 et §9) et ne plus mentir sur l'état « hors ligne ». État actuel — `BackupEngine.swift:182-193` :
```swift
if settings.onlyOnWiFi && !environment.hasWiFiConnection {
    lastError = "Backup requires a Wi-Fi connection."
    return false
}
```
Deux défauts : (1) tout ou rien — en 5G l'utilisateur doit choisir entre « rien » et « tout » ; (2) `hasWiFiConnection == false` couvre indifféremment « en cellulaire » et « aucune connectivité » : sans `onlyOnWiFi`, un run hors ligne part quand même, télécharge/hashe les originaux, échoue à l'upload, et **chaque asset part en `failedCount`** avec `failures.append` (l.415-419) — exactement le faux échec alarmant que le bucket `deferred` a éliminé pour l'iCloud.

**Hypothèses** (ground truth vérifié le 2026-09-09) :
- `BackupEnvironment` (`Sources/Services/BackupEnvironment.swift:6-9`) : `isCharging`, `hasWiFiConnection`. `SystemBackupEnvironment` tient déjà un `NWPathMonitor` process-wide (l.28-42) dont le handler reçoit le `path` complet — `path.status` / `path.isExpensive` disponibles sans nouveau monitor.
- `BackupCandidate.kind: BackupAssetKind { image, video }` (`Core/Protocols/BackupAssetSource.swift:5-8,14`) — la discrimination par type existe déjà.
- Comptabilité (`BackupEngine.swift:56,83`) : `processedCount = uploadedCount + rejectedCount + failedCount + deferredCount` ; `deferredCount` incrémenté sans `lastError` ni `failures` et repris au run suivant (l.269-281) ; `stagedCount` crédite la moitié de pas.
- `MockBackupEnvironment` (`Tests/Mocks/MockBackupAssetSource.swift:59-65`) : `isChargingValue`, `hasWiFiValue`.
- UI : toggles `Wi-Fi only` / `Charging only` (`UploadViewModel.swift:470-471`) ; segments + légendes dans `BackupSettingsView.segmentBar` / `completionSummary` (le segment `immichWarning` + « Waiting N » existe déjà pour les deferrals).

**Endpoints** : aucun (Network.framework).

**Approche retenue** : **A — le gate Wi-Fi devient une décision par asset, dont le résultat est un report (deferred), pas un échec.**
- `BackupSettings` : `onlyOnWiFi` conservé comme interrupteur maître + `allowCellularForPhotos` / `allowCellularForVideos`.
- Gate global unique : `guard environment.isOnline` (sinon `return false`, phase inchangée, aucun octet lu — le run est un no-op réarmé par la chaîne BGTask).
- En cellulaire, un candidat dont le type n'est pas autorisé est **reporté avant son export** : `deferredCount += 1`, `notifyProgress()`, `continue` — pas de download iCloud, pas de hash, pas d'upload, pas de `failures`. Même sémantique que « iCloud pas encore prêt ».
- `BackupEngine` expose `deferralReason: BackupDeferralReason?` (`.waitingForICloud` / `.waitingForWiFi` / `.mixed`) posé au fil du run ; la légende affiche « Waiting for Wi-Fi — N » ou « Waiting for iCloud — N ».
- **B (rejetée)** : compteur `skippedCount` distinct — bucket redondant (non-échec, repris au run suivant) pour un 4ᵉ segment sans décision utilisateur différente.
- **C (rejetée)** : gate global mais par type au niveau du run — bloque les photos derrière les vidéos, l'inverse du besoin.

**Étapes** :
1. **EDIT** `Sources/Services/BackupEnvironment.swift` — protocole : `var isOnline: Bool { get }` ; `SystemBackupEnvironment.pathUpdateHandler` cache `cachedOnline = (path.status == .satisfied)`.
2. **EDIT** `Sources/Services/BackupEngine.swift` — `BackupSettings : allowCellularForPhotos = false`, `allowCellularForVideos = false` ; remplacer le gate Wi-Fi l.186-189 par `guard environment.isOnline else { lastError = "Backup needs a network connection."; return false }` (**branche `!manual` uniquement** — un run manuel garde sa sémantique d'action explicite) ; `private func isUploadAllowedNow(_ candidate:, _ settings:) -> Bool` = `hasWiFiConnection || !onlyOnWiFi || (kind == .image ? allowCellularForPhotos : allowCellularForVideos)` ; tester ce helper **avant** `source.exportOriginal` (l.247) → `deferredCount += 1`, `deferralReason.insert(.waitingForWiFi)`, `notifyProgress()`, `continue` ; `enum BackupDeferralReason` + `private(set) var deferralReason`, remis à nil dans `reset()` (l.471-485).
3. **EDIT** `Sources/Features/Upload/UploadViewModel.swift` — `BackupSettingsStore` : `allowCellularForPhotos`/`allowCellularForVideos` (clés `photoBackupCellularPhotos`/`photoBackupCellularVideos`) propagées dans `snapshot()` ; sous `Wi-Fi only`, deux toggles indentés visibles seulement quand `onlyOnWiFi` est actif — « Use cellular for photos », « Use cellular for videos » — avec un footer qui dit ce que ça coûte ; légende + `completionSummary` dérivés de `engine.deferralReason`.
4. **EDIT** `Tests/Mocks/MockBackupAssetSource.swift` — `MockBackupEnvironment.isOnlineValue = true`.
5. **EDIT** `Tests/BackupEngineTests.swift` — `final class NetworkPolicyTests`, 7 tests : hors-ligne = pipeline non entré (retour `false`, `phase == .idle`, `source.purgeCount == 0`), photo uploadée / vidéo reportée en cellulaire, asset reporté **jamais exporté**, pas de `lastError` ni `failures`, Wi-Fi ignore les toggles, run manuel ignore la politique, raison du report. `test_backup_wifiGateBlocksRun` pinne l'ancien contrat tout-ou-rien : **remplacé**, pas re-pinné.

**Risques** : en cellulaire avec « Wi-Fi only », la barre montera désormais à 100 % en « Waiting » au lieu de ne pas démarrer — la légende doit nommer la cause ; `isExpensive` (partage de connexion) hors périmètre, à documenter dans le footer.

## Acceptance Contract

### Approches candidates
**A (retenue)** : gate par asset, résultat = deferred, plus un gate `isOnline`.
**B** : compteur `skippedCount` séparé. Rejetée (bucket redondant).
**C** : gate global par type au niveau du run. Rejetée (bloque les photos derrière les vidéos).

### Approche retenue + rationale
**A** — réutilise exactement la sémantique `deferred` déjà éprouvée (non-échec, repris au run suivant, barre qui atteint 100 %), et le gate `isOnline` supprime la classe de faux échecs « upload hors ligne ».

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
