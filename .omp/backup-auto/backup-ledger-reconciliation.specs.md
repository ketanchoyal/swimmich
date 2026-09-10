# Task: backup-ledger-reconciliation

**Objectif** : rendre le registre local auto-réparant. Aujourd'hui
`BackupLedger` est la base de dédup du client, elle n'est **jamais** confrontée
au serveur, et elle n'a qu'un seul mode d'invalidation : le bouton destructif
« Reset backup tracking » (`Sources/Features/Upload/UploadViewModel.swift:439-449`).

Conséquence, avec un scénario reproductible : une photo est sauvegardée, puis
supprimée côté serveur (nettoyage, purge de corbeille, changement de compte,
restauration d'une instance depuis une sauvegarde plus ancienne). Le ledger
continue de répondre `isBackedUp == true`
(`Sources/Services/BackupEngine.swift:224`), l'asset est **filtré avant export**
et ne remontera jamais. Silencieusement. Le client Flutter n'a pas ce trou : sa
base de dédup est la table `remote_asset_entity` réalimentée par
`/api/sync/stream`, donc une suppression distante rend l'asset candidat à
nouveau (étude `flutter-auto-backup-study.md` §5 et §10.2).

**Hypothèses (vérifiées le 2026-09-09)** :
- `BackupLedgerStoring` (`Sources/Core/Protocols/BackupLedgerStoring.swift:12-29`) :
  `isBackedUp(id:signature:)`, `markBackedUp(id:signature:)`, `save()`,
  `trackedCount()`, `removeAll()`.
- `BackupLedger` (`Sources/Services/BackupLedger.swift`) : `entries: [String: String]`
  (`localIdentifier → signature`), JSON sous Application Support, écritures
  coalescées sur `ioQueue`, `persistent()` / `inMemory()`.
- Le checksum SHA1-base64 de chaque asset **est déjà calculé** dans le run
  (`BackupEngine.streamingSHA1Base64`, staging l.250-254) et disponible aux deux
  endroits où le ledger est alimenté : `markBackedUp` sur reject (l.362-364) et
  sur upload réussi (l.414). Il n'est simplement pas conservé.
- `ImmichClient.bulkUploadCheck(_ request:)` +
  `AssetBulkUploadCheckRequest.Item { id, checksum }` et
  `AssetBulkUploadCheckResponse.Result { id, action, reason?, assetId?, isTrashed? }`
  (`Core/Protocols/ImmichClient.swift:174`, `Core/Types/DTOs.swift:217-233`).
  `action == "accept"` signifie « le serveur ne l'a pas » ; c'est exactement le
  test de réconciliation, et il ne demande **aucun octet de média**.
- `ImmichAPIClient.uploadAsset` (l.480-491) envoie `fileCreatedAt`,
  `fileModifiedAt`, `duration`, `isFavorite`, `visibility`, `livePhotoVideoId` —
  **ni `deviceAssetId` ni `deviceId`** (grep `deviceAssetId` vide sur
  `Sources/`). Le serveur ne peut donc pas rattacher un asset à cet appareil, et
  la colonne correspondante reste vide dans l'UI web.
- `BackupEngine.run()` fait déjà du travail off-main via `Task.detached(priority: .utility)`
  (l.203-208) : c'est le pattern à réutiliser pour la passe de réconciliation.

**Approche retenue** : **A — le ledger mémorise le checksum, et une passe de
réconciliation périodique le confronte au serveur via `bulkUploadCheck`.**

- `markBackedUp(id:signature:checksum:)` stocke les trois valeurs.
- Au début d'un run, si `lastReconciliation` a plus de `reconcileInterval`
  (7 jours) et que la connectivité le permet, l'engine envoie les entrées du
  ledger à `bulkUploadCheck` par chunks de `checkChunkSize` (**100**,
  `BackupEngine.swift:124`), off-main. Toute entrée dont la réponse est `accept` est
  **retirée** du ledger : l'asset redevient candidat et sera ré-uploadé au run
  courant.
- Coût : ~1 requête / 100 assets / semaine, aucune lecture de média, aucun
  download iCloud. C'est le seul mécanisme de la feature qui n'a pas de coût en
  octets.
- Migration : le fichier JSON existant est un `[String: String]`. Décodage
  versionné — `[String: String]` (v1) est accepté et converti en entrées sans
  checksum ; une entrée sans checksum est simplement **ignorée par la
  réconciliation** (elle reste valide pour le skip). Elle acquiert son checksum
  au premier run qui la re-marque. Aucun re-download pour migrer.
- En complément (prérequis d'aucune autre étape, mais parité Flutter et
  correction d'un champ manquant) : `uploadAsset` envoie `deviceAssetId`
  (= `localIdentifier`) et `deviceId` (identifiant stable de l'installation,
  persisté en UserDefaults, généré une fois).

- **B (rejetée)** : réconcilier via `GET /api/assets/device/{deviceId}`. Plus
  direct sur le papier, mais (1) exige que `deviceAssetId`/`deviceId` aient été
  envoyés à l'upload — ce qui n'est vrai pour **aucun** asset déjà sauvegardé,
  donc inefficace là où ça compte, et (2) la présence de l'endpoint varie selon
  la version du serveur, alors que `bulk-upload-check` est déjà utilisé en
  production par ce client.
- **C (rejetée)** : porter `/api/sync/stream` et une table locale d'assets
  distants, comme Flutter. C'est la solution de fond, mais c'est un chantier
  (sync incrémentale, stockage, réconciliation d'états) hors de proportion avec
  le trou à boucher, et il faudrait de toute façon décider si la timeline passe
  par cette base locale.

## Étapes

1. **EDIT** `Sources/Core/Protocols/BackupLedgerStoring.swift`
   - `func markBackedUp(id: String, signature: String, checksum: String)`.
   - `func entriesForReconciliation() -> [(id: String, checksum: String)]`
     (n'expose que les entrées qui ont un checksum).
   - `func forget(ids: [String])`.
   - `var lastReconciliation: Date? { get }` + `func recordReconciliation(at: Date)`.
2. **EDIT** `Sources/Services/BackupLedger.swift`
   - `private struct Entry: Codable { let signature: String; var checksum: String? }`,
     `entries: [String: Entry]`.
   - Fichier persisté : `{ "version": 2, "lastReconciliation": <ISO|nil>, "entries": {...} }`.
     `ensureLoaded()` tente v2, puis retombe sur le `[String: String]` v1
     (checksum `nil`). Un fichier illisible reste traité comme un ledger vide,
     comme aujourd'hui.
   - Implémenter les nouvelles méthodes sous le même `lock` + `dirty`/`save()`.
3. **EDIT** `Sources/Services/BackupEngine.swift`
   - Passer le checksum aux deux `markBackedUp` (l.362-364 reject → le checksum
     est dans `signatureByID`… à remplacer par un `Dictionary` id → (signature,
     checksum) construit depuis `current` ; l.414 upload → `entry.checksum`).
   - `static let reconcileInterval: TimeInterval = 7 * 24 * 3600` et
     `private func reconcileLedgerIfDue() async` :
     `guard environment.isOnline`, `guard due`, chunks de
     `Self.checkChunkSize`, `bulkUploadCheck` dans un `Task.detached`,
     `ledger.forget(ids: accepted)`, `ledger.recordReconciliation(at: Date())`,
     `ledger.save()`. Une erreur réseau **n'est pas** un échec de run : on
     abandonne la passe sans toucher `lastError` ni `failures` (même règle que
     les deferrals, mem `a4702a53`).
   - Appel : dans `run()`, après `reset()`/`phase = .checking` et **avant**
     `fetchCandidates` (l.203) — les oublis doivent être visibles du run courant.
   - `statusMessage = "Checking server…"` pendant la passe (le seul retour
     visible ; elle dure une poignée de requêtes).
4. **EDIT** `Sources/Core/Protocols/ImmichClient.swift` + `Sources/Services/ImmichAPIClient.swift`
   - `uploadAsset(...)` gagne `deviceAssetId: String` et `deviceId: String`,
     ajoutés aux `fields` multipart (l.480-491).
   - **NEW** `Sources/Services/DeviceIdentity.swift` :
     `enum DeviceIdentity { static var current: String }` — UUID généré une fois,
     persisté sur la clé `immichDeviceId` (⚠ ne pas utiliser
     `identifierForVendor`, qui change à la désinstallation et casserait le
     rattachement).
   - `BackupEngine.processBatch` passe `deviceAssetId: entry.candidate.id`,
     `deviceId: DeviceIdentity.current`.
5. **EDIT** `Sources/Features/Upload/UploadViewModel.swift`
   - Section « Backup tracking » : afficher `LabeledContent("Last server check", …)`
     depuis `lastReconciliation` (ou « Never »), et un bouton non destructif
     « Check server now » qui force la passe (`vm.reconcileNow()`), à côté du
     `Reset backup tracking` existant. Le footer explique que le reset n'est
     plus la seule réponse à un ledger périmé.
6. **EDIT** `Tests/Mocks/MockImmichClient.swift` — enregistrer les requêtes
   `bulkUploadCheck` (pour compter les chunks) et les champs
   `deviceAssetId`/`deviceId` des uploads.
7. **NEW** `Tests/BackupLedgerReconciliationTests.swift` :
   - `test_ledger_v1FileLoadsWithoutChecksum`
   - `test_ledger_v2RoundTripsChecksumAndLastReconciliation`
   - `test_reconcile_forgetsEntriesTheServerNoLongerHas`
   - `test_reconcile_keepsRejectedEntries`
   - `test_reconcile_skippedWhenNotDue`
   - `test_reconcile_networkErrorDoesNotFailRunNorSetLastError`
   - `test_reconcile_chunksAtCheckChunkSize`
   - `test_forgottenAssetIsReUploadedInSameRun`
   - `test_upload_sendsDeviceAssetIdAndStableDeviceId`
   - `test_entriesWithoutChecksumAreNotReconciled`
8. `xcodegen generate` (deux fichiers NEW : `DeviceIdentity.swift`,
   `BackupLedgerReconciliationTests.swift`).

## Risques

- **Faux oubli** : si le compte connecté change (autre utilisateur sur le même
  serveur), `bulkUploadCheck` répond `accept` pour tout et le ledger se vide →
  re-backup complet. C'est le comportement correct (rien n'est sauvegardé pour
  *ce* compte), mais sur photothèque iCloud optimisée c'est très coûteux. À
  cadrer : la réconciliation ne doit tourner que si l'id utilisateur courant est
  le même que celui enregistré au dernier marquage → stocker `userId` à côté de
  `lastReconciliation` et **vider** le ledger explicitement au changement de
  compte, au lieu de laisser la réconciliation le faire à l'aveugle.
- **Corbeille serveur** : un asset dans la corbeille distante est rejeté par
  `bulk-upload-check` avec `isTrashed: true`. Il ne doit **pas** être oublié du
  ledger (sinon on le ré-upload alors que l'utilisateur l'a supprimé). Traiter
  `isTrashed == true` comme « le serveur l'a » : c'est le cas couvert par
  `test_reconcile_keepsRejectedEntries`.

## Acceptance Contract

### Approches candidates
**A (retenue)** : checksum mémorisé + réconciliation périodique par
`bulk-upload-check`.
**B** : `GET /api/assets/device/{deviceId}`. Rejetée — inutilisable sur
l'historique existant (champs device jamais envoyés) et dépendante de la version
serveur.
**C** : port de `/api/sync/stream` + base locale d'assets distants. Rejetée —
disproportionné pour ce trou, décision d'architecture séparée.

### Approche retenue + rationale
**A** — réutilise un endpoint déjà en production dans ce client, ne coûte aucun
octet de média (pas de download iCloud, c'est tout l'intérêt du ledger), se
migre depuis le fichier v1 sans re-scan, et répare l'historique existant dès le
premier run parce que le checksum est réacquis au fil des marquages.

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
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-LR08 [type: regression]
Assertion: suite complète ≥ 655 tests (645 baseline + 10), TEST SUCCEEDED.
Check post-impl: sh -c 'xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination "platform=iOS Simulator,name=iPhone 17" 2>&1 | tee /tmp/immich_lr_test.txt | grep -q "TEST SUCCEEDED" && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_lr_test.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "${n:-0}" -ge 655 && echo PASS || echo FAIL'
Pre-state attendu: n/a
Post-state attendu: PASS
```
