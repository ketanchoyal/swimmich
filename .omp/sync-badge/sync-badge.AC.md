# Task: sync-badge

Status: planifié — **aucune AC ouverte** (écart G6 du registre `.omp/backlog/ImmichSwiftUI-backlog.md`,
audit du 2026-09-15 : aucun état de sauvegarde n'est lisible par tuile).

## Plan (résumé)

**Objectif** : rendre lisible, sur chaque tuile de la timeline, si ce média est *prouvé* sauvegardé
(`checkmark.icloud`) ou *seulement local* (`icloud.slash`), l'absence d'information ne rendant rien —
badge piloté par un réglage de l'écran Backup, exactement la paire `cloud-off` / `cloud-check` du client
Flutter (`asset_list_settings`).

**Approche retenue** : A — un **index de statut cloud** `@MainActor @Observable`
(`CloudBackupStatusIndex`), alimenté par le ledger local (déjà écrit à chaque upload et à chaque
réconciliation) et lu par `AssetThumbnailCell` via l'environnement, patron exact de `offlineIndex`
(`AssetThumbnailCell.swift:22`). Le ledger gagne `serverAssetId: String?` — donnée **déjà reçue** de
`POST /api/assets/bulk-upload-check` (`AssetBulkUploadCheckResult.assetId`) et jusqu'ici jetée — ce qui
crée le pont entre l'UUID serveur d'une tuile et un identifiant de photothèque. Rejetée B :
`bulkUploadCheck` depuis `TimelineViewModel` (impossible sans SHA1, que `getTimeBucket` ne renvoie pas).
Rejetée C : comparer `asset.id` à la clé du ledger (les deux espaces de noms ne se rencontrent jamais →
badge éteint partout).

**Étapes** : (1) NEW `Sources/Core/Types/CloudBackupStatus.swift` ; (2) EDIT
`Sources/Core/Protocols/BackupLedgerStoring.swift` ; (3) EDIT `Sources/Services/BackupLedger.swift`
(v3) ; (4) EDIT `Sources/Services/BackupEngine.swift` (alimentation + rappel) ; (5) NEW
`Sources/Services/CloudBackupStatusIndex.swift` ; (6) EDIT `Sources/Features/Upload/UploadViewModel.swift`
(réglage + bascule) ; (7) EDIT `Sources/DependencyContainer.swift` + `Sources/RootView.swift`
(câblage) ; (8) EDIT `Sources/Features/Timeline/AssetThumbnailCell.swift` (rendu) ; (9) EDIT
`Resources/Localizable.xcstrings` ; (10) NEW `Tests/CloudBackupStatusIndexTests.swift` ; (11)
`xcodegen generate` puis suite complète.

**Incertitudes** : (a) `.localOnly` sur une tuile de timeline est un **mensonge** pour un asset uploadé
depuis un autre appareil (la timeline ne sert que des UUID serveur,
`TimelineViewModel.swift:161/213`) → `status(forServerAssetID:)` renvoie `nil` pour tout id inconnu du
ledger, jamais `.localOnly` (AC-5057) ; (b) libellés `fr` du catalogue à aligner sur le vocabulaire
« sauvegarde » déjà retenu ; (c) **l'étape « EDIT le mock de ledger » de la spec est sans objet** :
mesuré le 2026-09-15, `grep -rln "BackupLedgerStoring" --include=*.swift .` ne renvoie que des fichiers
de `Sources/` — aucun double de test ne conforme le protocole, les tests utilisent
`BackupLedger.inMemory()` (`Sources/Services/BackupLedger.swift:54`) ; l'ajout d'un paramètre par défaut
au protocole ne casse donc aucun test existant.

## Critères

```
### AC-5050 [type: new]
Assertion: le statut de sauvegarde est un type de domaine (et non une paire d'icônes écrite dans la vue) : `enum CloudBackupStatus` à deux cas, chacun portant son symbole SF et son libellé localisé.
Check post-impl: sh -c 'f=Sources/Core/Types/CloudBackupStatus.swift; test -f "$f" && grep -qE "enum CloudBackupStatus" "$f" && grep -qE "case uploaded" "$f" && grep -qE "case localOnly" "$f" && grep -qE "checkmark\.icloud" "$f" && grep -qE "icloud\.slash" "$f" && grep -qE "var systemImage" "$f" && grep -qE "var localizedLabel" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -rn "CloudBackupStatus" Sources Tests` → 0 occurrence le 2026-09-15 ; le seul badge de statut existant est `offlineBadge`, qui répond à la question du cache disque).
Post-state attendu: PASS
```

```
### AC-5051 [type: new]
Assertion: le ledger passe en v3 et mémorise l'UUID serveur : `markBackedUp` accepte `serverAssetId:`, `Entry` le porte, `currentVersion` vaut 3, et le protocole expose deux lectures d'ensemble (`uploadedServerAssetIDs()`, `hasUploaded(id:)`) pour un lookup O(1) par tuile.
Check post-impl: sh -c 'p=Sources/Core/Protocols/BackupLedgerStoring.swift; s=Sources/Services/BackupLedger.swift; grep -qE "serverAssetId" "$p" && grep -qE "func uploadedServerAssetIDs" "$p" && grep -qE "func hasUploaded" "$p" && grep -qE "serverAssetId" "$s" && grep -qE "currentVersion *= *3" "$s" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`serverAssetId` : 0 occurrence dans `Sources/`; `BackupLedger.swift:31` = `private static let currentVersion = 2`, `Entry` = `{signature, checksum}`).
Post-state attendu: PASS
```

```
### AC-5052 [type: new]
Assertion: le moteur **alimente** le ledger avec l'UUID serveur sur les deux chemins qui le tiennent déjà (reject de `bulk-upload-check` et accept après upload), et signale chaque écriture persistée via `onLedgerChange`.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -qE "serverAssetId:" "$f" && grep -qE "var onLedgerChange" "$f" && grep -qE "onLedgerChange\?" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -rn "onLedgerChange\|serverAssetId" Sources/Services/BackupEngine.swift` → 0 occurrence ; `markBackedUp` y est appelé sans UUID serveur alors que `AssetBulkUploadCheckResult.assetId` est déjà dans la réponse lue l.451 et que l'upload en renvoie un l.550).
Post-state attendu: PASS
```

```
### AC-5053 [type: new]
Assertion: l'index de statut cloud existe, est observable depuis l'extérieur, et son alimentation vient **du ledger** — `refresh(ledger:)` consomme les deux lectures d'ensemble et non un parcours d'entrées.
Check post-impl: sh -c 'f=Sources/Services/CloudBackupStatusIndex.swift; test -f "$f" && grep -qE "final class CloudBackupStatusIndex" "$f" && grep -qE "@Observable" "$f" && grep -qE "private\(set\) var isEnabled" "$f" && grep -qE "private\(set\) var uploadedServerIDs" "$f" && grep -qE "private\(set\) var uploadedLocalIDs" "$f" && grep -qE "func refresh\(ledger:" "$f" && grep -qE "uploadedServerAssetIDs\(\)" "$f" && grep -qE "func status\(forLocalAssetID" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — `grep -rn "CloudBackupStatusIndex" Sources` → 0 occurrence).
Post-state attendu: PASS
Note: le seul pont existant entre ledger et rendu est `entriesForReconciliation() -> [(id, checksum)]`, inutilisable par tuile (coût O(n) par cellule).
```

```
### AC-5054 [type: new — le badge ne s'allume que sur réglage]
Assertion: le réglage « Show backup status on thumbnails » est persisté (défaut éteint), présent dans `BackupSettings`, exposé par une bascule identifiée dans l'écran Backup, et poussé dans l'index — l'état du réglage est la seule garde du badge.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; n=$(grep -cE "showSyncBadge" "$f" 2>/dev/null); test "${n:-0}" -ge 4 && grep -qE "photoBackupShowSyncBadge" "$f" && grep -qE "func syncBadgeIndex" "$f" && grep -qE "syncBadgeToggle" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`showSyncBadge` : 0 occurrence dans `Sources/`).
Post-state attendu: PASS
```

```
### AC-5055 [type: new — câblage au composition root]
Assertion: l'instance unique d'index est construite par `DependencyContainer`, rafraîchie immédiatement (avant tout run) puis à chaque écriture du ledger, et injectée dans l'environnement par `RootView` — aucun écran ne construit son propre index.
Check post-impl: sh -c 'd=Sources/DependencyContainer.swift; r=Sources/RootView.swift; grep -qE "CloudBackupStatusIndex\(\)" "$d" && grep -qE "onLedgerChange =" "$d" && grep -qE "refresh\(ledger:" "$d" && grep -qE "environment\(container\.cloudStatus\)" "$r" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`cloudStatus` : 0 occurrence dans `Sources/`; `RootView.swift:173` n'injecte que `.environment(container.offlineIndex)`).
Post-state attendu: PASS
```

```
### AC-5056 [type: new]
Assertion: `AssetThumbnailCell` rend le badge depuis l'index d'environnement, avec un identifiant distinct par état posé sur le badge lui-même (jamais sur le conteneur), sans aucune requête réseau depuis la cellule.
Check post-impl: sh -c 'f=Sources/Features/Timeline/AssetThumbnailCell.swift; grep -qE "@Environment\(CloudBackupStatusIndex\.self\)" "$f" && grep -qE "cloudStatus\?\.isEnabled == true" "$f" && grep -qE "status\(forServerAssetID: asset\.id\)" "$f" && grep -qE "cloudBackedUpBadge" "$f" && grep -qE "cloudLocalOnlyBadge" "$f" && grep -qE "accessibilityElement\(children: \.ignore\)" "$f" && ! grep -qE "ImmichClient|URLSession|URLRequest|bulkUploadCheck" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (la cellule ne connaît ni `cloudStatus` ni `CloudBackupStatusIndex`; `topLeadingBadges` l.152-175 n'empile que 360° / `offlineBadge` / `stackBadge`).
Post-state attendu: PASS
Note: pas de libellé affiché en dur — l'icône et le texte viennent de `CloudBackupStatus`. Un identifiant posé sur le `VStack` écraserait celui des badges (piège documenté l.185-187 du même fichier).
```

```
### AC-5057 [type: new — jamais de badge faux pour un UUID serveur inconnu]
Assertion: pour un identifiant **serveur** absent du ledger, la réponse est `nil` (aucun badge) et jamais `.localOnly` : l'implémentation du lookup serveur retourne `nil` sans jamais citer `.localOnly`, et la cellule ne substitue aucun état par défaut.
Check post-impl: sh -c 'f=Sources/Services/CloudBackupStatusIndex.swift; c=Sources/Features/Timeline/AssetThumbnailCell.swift; test -f "$f" && sed -n "/func status(forServerAssetID/,/^    }/p" "$f" | grep -qE "nil" && ! sed -n "/func status(forServerAssetID/,/^    }/p" "$f" | grep -qE "localOnly" && ! grep -qE "\?\? \.localOnly|forServerAssetID[^)]*\) \?\?" "$c" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — aucun lookup serveur n'existe).
Post-state attendu: PASS
Note: décor « only on this device » non constructible ici — la timeline ne sert que des UUID serveur et la galerie locale du client Flutter n'existe pas dans ce dépôt (hors périmètre de la spec) : un `icloud.slash` y affirmerait que les assets venus d'un autre appareil ne sont pas sur le serveur.
```

```
### AC-5058 [type: new]
Assertion: `Tests/CloudBackupStatusIndexTests.swift` couvre les cinq cas de la spec (uploadé côté serveur, uploadé côté local, inconnu côté local, inconnu côté serveur, réglage éteint = feature muette) plus l'aller-retour de persistance v3, sur `BackupLedger.inMemory()`.
Check post-impl: sh -c 'f=Tests/CloudBackupStatusIndexTests.swift; test -f "$f" && n=$(grep -cE "func test_" "$f" 2>/dev/null) && test "${n:-0}" -ge 5 && grep -qE "test_statusForServerAssetID_isUploadedAfterRefresh" "$f" && grep -qE "test_statusForLocalAssetID_unknownIsLocalOnly" "$f" && grep -qE "test_statusForServerAssetID_unknownUUIDIsNil" "$f" && grep -qE "test_isEnabledFalse_suppressesEveryStatus" "$f" && grep -qE "BackupLedger\.inMemory\(\)" "$f" && grep -qE "uuid-inconnu" "$f" && grep -qE "jamais-vu" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent : `Tests/CloudBackupStatusIndexTests.swift` n'existe pas, `grep -rln "CloudBackupStatus" Tests` → 0).
Post-state attendu: PASS
Note: un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate` — sans régénération la suite passe « verte » par omission.
```

```
### AC-5059 [type: regression]
Assertion: la suite complète reste au-dessus de la baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et le run est TEST SUCCEEDED.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_syncbadge_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_syncbadge_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "${n:-0}" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`/tmp/immich_syncbadge_test.log` absent).
Post-state attendu: PASS
```
