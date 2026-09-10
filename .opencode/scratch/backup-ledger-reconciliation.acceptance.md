# Task: backup-ledger-reconciliation

Status: shipped — AC-LR01–LR08 PASS le 2026-09-10 (suite 688 tests, TEST SUCCEEDED sur iPhone 17).

**Spec** : `.omp/backup-auto/backup-ledger-reconciliation.specs.md`
**Dépendances** : **dépend de `backup-network-policy`** (`guard environment.isOnline` dans `reconcileLedgerIfDue()` — `isOnline` est introduit par AC-NP01) et doit passer **après `backup-live-photos`** (celui-ci multiplie les appels `uploadAsset`, auxquels cette feature ajoute `deviceAssetId`/`deviceId`). Indépendant de `backup-album-scoping` et `backup-library-observer`.

## Plan

**Objectif** : rendre le registre local auto-réparant. `BackupLedger` n'est **jamais** confronté au serveur et n'a qu'un mode d'invalidation : le bouton destructif « Reset backup tracking » (`Sources/Features/Upload/UploadViewModel.swift:439-449`). Scénario reproductible : photo sauvegardée, puis supprimée côté serveur → le ledger répond toujours `isBackedUp == true` (`BackupEngine.swift:224`), l'asset est **filtré avant export** et ne remonte **jamais**, silencieusement. Le Flutter n'a pas ce trou (dédup = `remote_asset_entity` réalimentée par `/api/sync/stream`).

**Hypothèses** (ground truth vérifié le 2026-09-09) :
- `BackupLedgerStoring` (`Sources/Core/Protocols/BackupLedgerStoring.swift:12-29`) : `isBackedUp(id:signature:)`, `markBackedUp(id:signature:)`, `save()`, `trackedCount()`, `removeAll()`.
- `BackupLedger` (`Sources/Services/BackupLedger.swift`) : `entries: [String: String]` (`localIdentifier → signature`), JSON sous Application Support, écritures coalescées sur `ioQueue`, `persistent()` / `inMemory()`.
- Le checksum SHA1-base64 **est déjà calculé** dans le run (`BackupEngine.streamingSHA1Base64`, staging l.250-254) et disponible aux deux alimentations du ledger : reject l.362-364, upload réussi l.414 — il n'est simplement pas conservé.
- `ImmichClient.bulkUploadCheck(_:)` + `AssetBulkUploadCheckRequest.Item { id, checksum }` / `AssetBulkUploadCheckResponse.Result { id, action, reason?, assetId?, isTrashed? }` (`ImmichClient.swift:174`, `DTOs.swift:217-233`). `action == "accept"` = « le serveur ne l'a pas » : exactement le test de réconciliation, **sans un octet de média**.
- `ImmichAPIClient.uploadAsset` (l.480-491) envoie `fileCreatedAt`, `fileModifiedAt`, `duration`, `isFavorite`, `visibility`, `livePhotoVideoId` — **ni `deviceAssetId` ni `deviceId`** (grep vide sur `Sources/`).
- `BackupEngine.run()` fait déjà le travail off-main via `Task.detached(priority: .utility)` (l.203-208) — pattern à réutiliser.

**Endpoints** : `POST /api/assets/bulk-upload-check` — existant (réconciliation). `GET /api/assets/device/:deviceId` — **écarté** (inutilisable sur l'historique : champs device jamais envoyés) ; dépend de la version serveur.

**Approche retenue** : **A — le ledger mémorise le checksum, une passe périodique le confronte au serveur via `bulkUploadCheck`.**
- `markBackedUp(id:signature:checksum:)` stocke les trois valeurs.
- En début de run, si `lastReconciliation` a plus de `reconcileInterval` (7 jours) et que `environment.isOnline`, l'engine envoie les entrées à `bulkUploadCheck` par chunks de `checkChunkSize` (**100**, `BackupEngine.swift:124`), off-main ; toute réponse `accept` → entrée **retirée** du ledger, l'asset redevient candidat au run courant.
- Coût ~1 requête / 100 assets / semaine, aucune lecture de média, aucun download iCloud.
- Migration : le JSON v1 (`[String: String]`) reste lisible → entrées sans checksum, **ignorées par la réconciliation** mais valides pour le skip ; elles acquièrent leur checksum au premier run qui les re-marque. Aucun re-download pour migrer.
- Complément (parité Flutter, champ manquant) : `uploadAsset` envoie `deviceAssetId` (= `localIdentifier`) et `deviceId` (identifiant stable d'installation, persisté en UserDefaults, généré une fois).
- **B (rejetée)** : `GET /api/assets/device/{deviceId}` — inefficace là où ça compte, dépend de la version serveur.
- **C (rejetée)** : porter `/api/sync/stream` + table locale d'assets distants — solution de fond, chantier disproportionné (sync incrémentale, stockage, états) et décision d'architecture séparée.

**Étapes** :
1. **EDIT** `Sources/Core/Protocols/BackupLedgerStoring.swift` — `markBackedUp(id:signature:checksum:)`, `entriesForReconciliation() -> [(id, checksum)]`, `forget(ids:)`, `var lastReconciliation: Date?`, `recordReconciliation(at:)`.
2. **EDIT** `Sources/Services/BackupLedger.swift` — `private struct Entry: Codable { let signature: String; var checksum: String? }`, `entries: [String: Entry]` ; fichier `{ "version": 2, "lastReconciliation": <ISO|nil>, "entries": {...} }` ; `ensureLoaded()` tente v2 puis retombe sur le `[String: String]` v1 (checksum `nil`) ; fichier illisible = ledger vide (comportement actuel) ; mêmes `lock`/`dirty`/`save()`.
3. **EDIT** `Sources/Services/BackupEngine.swift` — passer le checksum aux deux `markBackedUp` (remplacer `signatureByID` par un `[String: (signature, checksum)]` construit depuis `current` pour le reject ; `entry.checksum` pour l'upload) ; `static let reconcileInterval: TimeInterval = 7 * 24 * 3600` ; `private func reconcileLedgerIfDue() async` : `guard environment.isOnline`, `guard due`, chunks de `Self.checkChunkSize`, `bulkUploadCheck` en `Task.detached`, `ledger.forget(ids: accepted)`, `ledger.recordReconciliation(at: Date())`, `ledger.save()` — **une erreur réseau n'est pas un échec de run** (ni `lastError` ni `failures`, même règle que les deferrals) ; appel dans `run()` après `reset()`/`phase = .checking` et **avant** `fetchCandidates` (l.203) ; `statusMessage = "Checking server…"` pendant la passe.
4. **EDIT** `Sources/Core/Protocols/ImmichClient.swift` + `Sources/Services/ImmichAPIClient.swift` — `uploadAsset(...)` gagne `deviceAssetId`/`deviceId` dans les `fields` multipart (l.480-491) ; **NEW** `Sources/Services/DeviceIdentity.swift` (`enum DeviceIdentity { static var current: String }`, UUID persisté sur la clé `immichDeviceId`, ⚠ **pas** `identifierForVendor`) ; `processBatch` passe `deviceAssetId: entry.candidate.id`, `deviceId: DeviceIdentity.current`.
5. **EDIT** `Sources/Features/Upload/UploadViewModel.swift` — section « Backup tracking » : `LabeledContent("Last server check", …)` (ou « Never ») + bouton non destructif « Check server now » (`vm.reconcileNow()`) à côté de `Reset backup tracking` ; footer expliquant que le reset n'est plus la seule réponse à un ledger périmé.
6. **EDIT** `Tests/Mocks/MockImmichClient.swift` — enregistrer les requêtes `bulkUploadCheck` (comptage des chunks) et les champs `deviceAssetId`/`deviceId` des uploads.
7. **NEW** `Tests/BackupLedgerReconciliationTests.swift` — 10 tests : migration v1, round-trip v2, oubli des entrées absentes du serveur, conservation des rejects, `isTrashed` conservé, throttle, erreur réseau silencieuse, chunking à `checkChunkSize` (`test_reconcile_chunksAtCheckChunkSize`), ré-upload dans le même run, entrées sans checksum ignorées, `deviceAssetId`/`deviceId` envoyés.
8. `xcodegen generate` (deux fichiers NEW — piège connu : sans regen, `Tests/*.swift` n'est pas compilé).

**Pièges cadrés** : `isTrashed == true` ⇒ le serveur l'a, **ne pas** oublier l'entrée (sinon on ré-upload un asset que l'utilisateur a supprimé) ; changement de compte ⇒ vider le ledger explicitement (sinon la réconciliation le vide à l'aveugle → re-backup complet d'une photothèque iCloud).

## Acceptance Contract

### Approches candidates
**A (retenue)** : checksum mémorisé + réconciliation périodique par `bulk-upload-check`.
**B** : `GET /api/assets/device/{deviceId}`. Rejetée.
**C** : port de `/api/sync/stream` + base locale d'assets distants. Rejetée.

### Approche retenue + rationale
**A** — réutilise un endpoint déjà en production dans ce client, ne coûte aucun octet de média (pas de download iCloud, c'est tout l'intérêt du ledger), se migre depuis le fichier v1 sans re-scan, et répare l'historique existant dès le premier run parce que le checksum est réacquis au fil des marquages.

### Critères

```
### AC-LR01 [type: new]
Assertion: le ledger mémorise le checksum, la date de réconciliation, et sait oublier des ids.
Check post-impl: sh -c 'f=Sources/Core/Protocols/BackupLedgerStoring.swift; grep -q "checksum: String" "$f" && grep -q "func forget" "$f" && grep -q "lastReconciliation" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-LR02 [type: new]
Assertion: le fichier ledger est versionné et le format v1 ([String: String]) reste lisible.
Check post-impl: sh -c 'f=Sources/Services/BackupLedger.swift; grep -q "version" "$f" && grep -q "\[String: String\]" "$f" && grep -q "struct Entry" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-LR03 [type: new]
Assertion: l'engine réconcilie avant fetchCandidates, par chunks, sans faire échouer le run en cas d'erreur réseau.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -q "func reconcileLedgerIfDue" "$f" && grep -q "reconcileInterval" "$f" && grep -q "ledger.forget" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-LR04 [type: new]
Assertion: un asset dans la corbeille distante n'est pas oublié du ledger.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -q "isTrashed" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-LR05 [type: new]
Assertion: l'upload envoie deviceAssetId et un deviceId stable persisté (pas identifierForVendor).
Check post-impl: sh -c 'grep -q "deviceAssetId" Sources/Services/ImmichAPIClient.swift && grep -q "deviceId" Sources/Services/ImmichAPIClient.swift && test -f Sources/Services/DeviceIdentity.swift && ! grep -q "UIDevice.current.identifierForVendor" Sources/Services/DeviceIdentity.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun deviceAssetId dans Sources/)
Post-state attendu: PASS
```

```
### AC-LR06 [type: new]
Assertion: l'écran Backup tracking montre la dernière vérification serveur et offre une action non destructive.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -q "Last server check" "$f" && grep -q "Check server now" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-LR07 [type: new]
Assertion: tests de réconciliation et de migration (≥10 tests).
Check post-impl: sh -c 'f=Tests/BackupLedgerReconciliationTests.swift; n=$(grep -c "func test_" "$f" 2>/dev/null); n=${n:-0}; test "$n" -ge 10 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-LR08 [type: regression]
Assertion: suite complète ≥ 655 tests (645 baseline + 10), TEST SUCCEEDED.
Check post-impl: sh -c 'xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination "platform=iOS Simulator,name=iPhone 17" 2>&1 | tee /tmp/immich_lr_test.txt | grep -q "TEST SUCCEEDED" && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_lr_test.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "${n:-0}" -ge 655 && echo PASS || echo FAIL'
Pre-state attendu: n/a
Post-state attendu: PASS
```
