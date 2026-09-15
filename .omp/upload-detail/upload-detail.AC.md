# Task: upload-detail

Status: planifié — **aucune AC ouverte** (écart G5 du registre `.omp/backlog/ImmichSwiftUI-backlog.md`, ligne 780).

## Plan (résumé)

**Objectif** : après cette fiche, l'utilisateur ouvre « Upload details » depuis l'écran Backup et voit,
asset par asset, ce que le dernier run a fait de sa photothèque — ce qui descend d'iCloud avec son
pourcentage, ce qui part vers le serveur avec la taille du fichier, ce qui a été écarté et pourquoi,
ce qui a échoué et avec quel message — puis relance un asset précis d'un geste, ou tous les échecs d'un
coup, **sans payer un scan complet de la photothèque**.

**Approche retenue** : A — étendre les seams du `BackupEngine` partagé (identifiant Photos, taille et
état par asset ; une lecture par identifiant ; un run restreint à une liste d'ids), puis un
`UploadDetailViewModel` (`@MainActor @Observable`) qui **compose** l'`UploadViewModel` unique du process,
et une `UploadDetailView` stateless poussée depuis `BackupSettingsView`.

**Étapes** : (1) `BackupFailure` + `assetID` / `fileSize` ; `BackupDeferral` et `deferrals` ;
`iCloudProgress` / `iCloudRetryAttempts` par asset — EDIT `Sources/Services/BackupEngine.swift` ;
(2) `BackupCandidate.fileSize` + `fetchCandidates(ids:)` — EDIT `BackupAssetSource.swift`,
`PhotoLibraryServiceImpl.swift`, `Tests/Mocks/MockBackupAssetSource.swift` ; (3) `run(settings:manual:only:)`
— EDIT `BackupEngine.swift` ; (4) `retryAsset(id:)` / `retryAllFailed()` / `failedAssetCount` et recâblage
de `completionSummary` — EDIT `UploadViewModel.swift` ; (5) suppression de `BackupFailuresSheet` et de
`showFailuresSheet` ; (6) NEW `Sources/Features/UploadDetail/UploadDetailViewModel.swift` ; (7) NEW
`Sources/Features/UploadDetail/UploadDetailView.swift` ; (8) factory + `@State` racine + passage à
`ProfileView` ; (9) ligne d'entrée dans `backupSection` ; (10) NEW
`Tests/UploadDetailViewModelTests.swift` ; (11) `xcodegen generate` + suite.

**Incertitudes** : la taille avant export (`PHAssetResource` peut ne pas la donner sur un asset
iCloud-only → `Unknown size`) ; le moment où `currentAssetID` est posé par rapport à `applyExportState(_:)` ;
le sort d'un run d'arrière-plan (listes en mémoire) ; le tap d'une ligne d'échec (aucun équivalent serveur).
Voir `.omp/upload-detail/upload-detail.specs.md` § Incertitudes.

## Critères

```
### AC-5040 [type: new]
Assertion: les seams du moteur portent l'identité de l'asset — `BackupFailure.assetID` (le localIdentifier Photos) et `fileSize`, la liste `deferrals` des assets retenus (une entrée par asset), et la progression iCloud par identifiant — et les cinq sites d'append de `BackupFailure` sont tous mis à jour, sans quoi une ligne d'échec resterait sans clé d'action ni taille.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -qE "let assetID: String" "$f" && grep -qE "fileSize: Int64" "$f" && grep -qE "struct BackupDeferral:" "$f" && grep -qE "private\(set\) var deferrals" "$f" && grep -qE "private\(set\) var iCloudProgress" "$f" && grep -qE "private\(set\) var iCloudRetryAttempts" "$f" && n=$(grep -cE "BackupFailure\(" "$f") && m=$(grep -cE "assetID: " "$f") && test "$m" -ge "$n" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -n "let assetID\|struct BackupDeferral\|var deferrals\|var iCloudProgress" Sources/Services/BackupEngine.swift` ne renvoie rien ; seuls `struct BackupDeferralReason` et `var deferralReason` existent, et les 5 sites `BackupFailure(name:reason:)` — `:355`, `:469`, `:525`, `:558`, `:597` — ne portent ni identifiant ni taille)
Post-state attendu: PASS
Note: `struct BackupDeferral:` (avec les deux-points) est visé et non le mot seul, qui matcherait aussi `BackupDeferralReason` déjà présent. Le rapport m ≥ n vérifie que chaque site d'append reçoit son `assetID:` — c'est un site oublié qui casserait le retry ciblé.
```

```
### AC-5041 [type: new]
Assertion: la source sait rendre une taille et se lire par identifiant — `BackupCandidate.fileSize` (défaut `nil`, donc source-compatible comme `isLivePhoto`) et `fetchCandidates(ids:)` existent sur le protocole, sur `PhotoLibraryServiceImpl` (un `PHAsset.fetchAssets(withLocalIdentifiers:)` unique) et sur le mock (les ids demandés sont enregistrés pour rendre observable le run restreint).
Check post-impl: sh -c 'p=Sources/Core/Protocols/BackupAssetSource.swift; s=Sources/Services/PhotoLibraryServiceImpl.swift; m=Tests/Mocks/MockBackupAssetSource.swift; grep -qE "var fileSize: Int64" "$p" && grep -qE "func fetchCandidates\(ids" "$p" && grep -qE "func fetchCandidates\(ids" "$s" && grep -qE "func fetchCandidates\(ids" "$m" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`BackupCandidate` s'arrête à `isLivePhoto` (`BackupAssetSource.swift:23`) et le protocole ne déclare que `fetchCandidates(in:excluding:)` (`:83`) ; aucune des trois implémentations n'a de variante par identifiant)
Post-state attendu: PASS
```

```
### AC-5042 [type: new — le retry ciblé ne relance pas la photothèque]
Assertion: `run(settings:manual:)` accepte `only assetIDs: [String] = []` ; quand la liste est non vide le moteur appelle `fetchCandidates(ids:)` au lieu de l'énumération complète, saute la réconciliation du ledger et saute le filtre du ledger — un asset dont l'échec vient du lien de Live Photo (déjà sur le serveur) doit pouvoir être reclassé, sinon son avertissement survivrait à tous les retries.
Check post-impl: sh -c 'f=Sources/Services/BackupEngine.swift; grep -qE "only assetIDs: \[String\] = \[\]" "$f" && grep -qE "fetchCandidates\(ids: assetIDs\)" "$f" && grep -qE "assetIDs\.isEmpty" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -n "func run" Sources/Services/BackupEngine.swift` donne la seule signature `run(settings:manual:)` ; aucun appel `fetchCandidates(ids:)` ni paramètre `only` dans le fichier)
Post-state attendu: PASS
Note: `total = remaining.count`, le staging, `processBatch`, le ledger et les compteurs restent inchangés — c'est tout l'intérêt de l'approche A (la restriction ne touche que la source des candidats).
```

```
### AC-5043 [type: new]
Assertion: le ViewModel de backup porte les deux actions de relance — `retryAsset(id:)` (garde photo + un run restreint à `[id]`) et `retryAllFailed()` (un seul run restreint à tous les `assetID` en échec), expose `failedAssetCount` pour le badge, et le bouton « Retry failed » n'appelle plus le run complet de la photothèque.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -qE "func retryAsset\(id: String\)" "$f" && grep -qE "func retryAllFailed\(\)" "$f" && grep -qE "var failedAssetCount" "$f" && grep -qE "only: \[id\]" "$f" && n=$(grep -cE "retryAllFailed" "$f") && test "$n" -ge 2 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -n "retryAsset\|retryAllFailed\|failedAssetCount" Sources/Features/Upload/UploadViewModel.swift` ne renvoie rien ; « Retry failed » (`:882`) appelle `vm.runBackup(manual: true)`, soit une énumération complète de la photothèque)
Post-state attendu: PASS
Note: l'enveloppe du run (assertion d'arrière-plan, activité, notification, `uploadHistory` en fin de `.done`) est recopiée à l'identique de `runBackup` — deux enveloppes divergentes feraient un run sans Live Activity cohérente.
```

```
### AC-5044 [type: new — une seule surface pour les échecs]
Assertion: `BackupFailuresSheet` et `showFailuresSheet` disparaissent : la page est un sur-ensemble strict de la feuille (mêmes nom et raison, plus l'état, la taille, l'asset et le retry), et une feuille reçoit une **copie** du tableau à sa présentation, donc ne peut pas suivre des assets en vol.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; ! grep -qE "struct BackupFailuresSheet" "$f" && ! grep -qE "showFailuresSheet" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`struct BackupFailuresSheet` est déclarée en `Sources/Features/Upload/UploadViewModel.swift:1028`, `var showFailuresSheet` en `:210`, la présentation en `.sheet(isPresented: $vm.showFailuresSheet)` `:474-475`)
Post-state attendu: PASS
Note: le check vise la déclaration et la propriété, pas le mot dans un commentaire. Si un test unitaire ou XCUITest pilote encore `showFailuresSheet`, il est migré vers la page dans le même commit.
```

```
### AC-5045 [type: new — l'écran compose le ViewModel unique, aucun second moteur]
Assertion: `UploadDetailViewModel` ne crée ni `BackupEngine` ni source de photothèque — il reçoit l'`UploadViewModel` du process — et n'a **aucun état stocké** : tout est une projection calculée du moteur, plus la mise en forme de taille (`ByteCountFormatter`, `.file`, `Unknown size` si absente) et l'état de l'asset en vol.
Check post-impl: sh -c 'd=Sources/Features/UploadDetail; f=$d/UploadDetailViewModel.swift; test -f "$f" && ! grep -qE "BackupEngine\(" "$d"/*.swift && ! grep -qE "PhotoLibraryServiceImpl\(" "$d"/*.swift && grep -qE "private let upload: UploadViewModel" "$f" && grep -qE "init\(upload: UploadViewModel\)" "$f" && grep -qE "enum InFlightState" "$f" && grep -qE "func retry(id: String)" "$f" && grep -qE "formattedBytes" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Features/UploadDetail/` n'existe pas — `glob "Sources/Features/UploadDetail/**"` est introuvable)
Post-state attendu: PASS
Note: deux engines auraient des gardes `!running` indépendantes (deux passes concurrentes sur la même photothèque, double téléchargement iCloud) et `engine.onProgressUpdate` est un closure unique que le premier run à finir coupe sous l'autre — c'est le scénario documenté par le commentaire « One VM, one run, one island » (`DependencyContainer.swift:28-35`).
```

```
### AC-5046 [type: new]
Assertion: `UploadDetailView` est stateless (elle prend le ViewModel), ne déclare **aucun** `NavigationStack` — elle est poussée depuis `BackupSettingsView`, elle-même poussée depuis `ProfileView` qui porte déjà la pile — et rend l'en-tête d'état, la descente iCloud, les échecs et les retenues, avec les identifiants d'accessibilité posés sur les **boutons**.
Check post-impl: sh -c 'f=Sources/Features/UploadDetail/UploadDetailView.swift; test -f "$f" && grep -qE "struct UploadDetailView" "$f" && grep -qE "UploadDetailViewModel" "$f" && grep -qE "BackupThumbnailView" "$f" && grep -qE "uploadDetailRetryButton_" "$f" && grep -qE "uploadDetailRetryAllButton" "$f" && grep -qE "uploadDetailCancelButton" "$f" && ! grep -qE "NavigationStack \{" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: le check vise la DÉCLARATION (`NavigationStack {`) — un grep du seul mot échouerait sur le doc-comment qui explique justement l'absence de pile (piège de la carte sync-status, AC-5031).
```

```
### AC-5047 [type: new]
Assertion: le détail est câblé une seule fois — factory `makeUploadDetailViewModel(upload:)` dans le conteneur, `@State` possédé par `RootView` et passé à `ProfileView`, lui-même transmettant l'instance à `BackupSettingsView`, dont la section Backup porte la ligne « Upload details » identifiée (`uploadDetailRow`) avec le compte d'échecs en badge, et dont le bouton « N couldn't be backed up » pousse la page au lieu d'ouvrir la feuille supprimée.
Check post-impl: sh -c 'c=Sources/DependencyContainer.swift; r=Sources/RootView.swift; p=Sources/Features/Profile/ProfileView.swift; b=Sources/Features/Upload/UploadViewModel.swift; grep -qE "func makeUploadDetailViewModel" "$c" && grep -qE "makeUploadDetailViewModel" "$r" && grep -qE "uploadDetail: UploadDetailViewModel" "$r" && grep -qE "uploadDetail: uploadDetail" "$r" && grep -qE "var uploadDetail: UploadDetailViewModel" "$p" && grep -qE "detail: uploadDetail" "$p" && grep -qE "detail: UploadDetailViewModel" "$b" && grep -qE "UploadDetailView\(vm: detail\)" "$b" && grep -qE "uploadDetailRow" "$b" && grep -qE "couldn.t be backed up" "$b" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -rn "uploadDetail" Sources/DependencyContainer.swift Sources/RootView.swift Sources/Features/Profile/ProfileView.swift Sources/Features/Upload/UploadViewModel.swift` ne renvoie rien ; `ProfileView.swift:62-68` pousse `BackupSettingsView(vm: upload)` et `:868` fait `vm.showFailuresSheet = true`)
Post-state attendu: PASS
Note: le paramétrage explicite de la factory reproduit le patron `makeSharedLinkViewerViewModel(baseURL:externalDomain:)` : le conteneur ne décide pas quel moteur du process est observé, il reçoit celui de l'appelant.
```

```
### AC-5048 [type: new]
Assertion: `Tests/UploadDetailViewModelTests.swift` expose ≥ 8 cas nommés couvrant le run restreint (les seuls ids donnés, l'ignorance du filtre du ledger), la disparition de l'avertissement de lien de Live Photo, l'identifiant et la taille sur les échecs, la déduplication des retenues, la progression iCloud par asset, le `retryAllFailed` en un seul run, et la projection sans état.
Check post-impl: sh -c 'f=Tests/UploadDetailViewModelTests.swift; test -f "$f" && n=$(grep -cE "func test_" "$f") && test "$n" -ge 8 && grep -qE "test_restrictedRun_onlyTouchesTheGivenIDs" "$f" && grep -qE "test_restrictedRun_ignoresTheLedgerFilter" "$f" && grep -qE "test_retryOfALivePhotoLinkWarning_clearsTheStaleFailure" "$f" && grep -qE "test_failures_carryThePhotosIdentifierAndSize" "$f" && grep -qE "test_deferrals_listTheHeldBackAssetsOnceEach" "$f" && grep -qE "test_iCloudProgress_isTrackedPerAssetID" "$f" && grep -qE "test_retryAllFailed_sendsOneRestrictedRunWithEveryFailedID" "$f" && grep -qE "test_uploadDetailViewModel_projectsWithoutOwningState" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — `glob "Tests/UploadDetailViewModelTests.swift"` est introuvable)
Post-state attendu: PASS
Note: un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate` — sans régénération la suite passe « verte » par omission.
```

```
### AC-5049 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED — la suppression de `BackupFailuresSheet` et le nouveau paramètre `only:` du run ne doivent casser aucun test existant.
Check post-impl: sh -c 'test -f /tmp/immich_upload_detail_test.log && grep -qE "TEST SUCCEEDED" /tmp/immich_upload_detail_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_upload_detail_test.log | grep -oE "[0-9]+" | sort -n | tail -1) && test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent — la suite n'a pas encore été lancée avec ce correctif)
Post-state attendu: PASS
```
