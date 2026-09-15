# Task: locked-folder

Status: planifié — **aucune AC ouverte** (écart G12 du registre `.omp/backlog/ImmichSwiftUI-backlog.md`).

## Plan (résumé)

**Objectif** : l'utilisateur déplace les photos/vidéos sélectionnées dans un dossier verrouillé depuis la
timeline (`PUT /api/assets` avec `AssetVisibility.locked`), puis rouvre ce dossier depuis « Me » → Security
après avoir saisi son PIN Immich à 6 chiffres — ou validé Face ID s'il a autorisé la mémorisation du PIN.
Le dossier affiche sa propre grille (`GET /api/timeline/buckets?visibility=locked`), permet de resélectionner
des éléments pour les remettre dans la timeline, et se reverrouille au passage en arrière-plan.

**Approche retenue** : A — gate local adossé à l'élévation **serveur**. `LockedFolderViewModel` interroge
`GET /api/auth/status`, pose le PIN (`POST /api/auth/pin-code`) si `pinCode == false`, appelle
`POST /api/auth/session/unlock`, puis lit la grille filtrée. Face ID ne sert qu'à **rejouer un PIN mémorisé**
dans le Keychain — jamais un accès direct.

**Étapes** : (1) EDIT `DTOs.swift` (4 DTOs d'auth) ; (2) EDIT `ImmichClient.swift` (5 méthodes) ; (3) EDIT
`ImmichAPIClient.swift` (5 corps sur `ImmichAPI.auth.path`) ; (4) NEW `LockedFolderPINStoring.swift` ;
(5) NEW `KeychainLockedFolderPINStore.swift` ; (6) NEW `LockedFolderViewModel.swift` ; (7) NEW
`LockedFolderView.swift` + reverrouillage `scenePhase` ; (8) EDIT `TimelineViewModel.swift` /
`TimelineView.swift` / `AssetThumbnailCell.swift` (sortie vers le dossier) ; (9) EDIT `ProfileView.swift`
(ligne `lockedFolderRow`) ; (10) EDIT `DependencyContainer.swift` + `RootView.swift` (injection) ;
(11) EDIT `Localizable.xcstrings` ; (12) EDIT `MockImmichClient.swift` + NEW
`Tests/LockedFolderViewModelTests.swift` ; (13) `xcodegen generate` + suite.

**Incertitudes** : route exacte du reset de PIN (`PinCodeResetDto` existe, route non vérifiée) ; réponse
serveur à `visibility=locked` hors session élevée (403 ou liste vide — le gate reste piloté par
`AuthStatusResponseDto.isElevated`, jamais par le contenu de la réponse) ; portée de `accessibilityIdentifier`
sur un `SecureField` en XCUITest (voir `.omp/locked-folder/locked-folder.specs.md` § Incertitudes).

## Critères

```
### AC-5110 [type: new]
Assertion: contrat client complet — les quatre DTOs d'authentification du dossier verrouillé (champs requis par l'OpenAPI non optionnels) et les cinq méthodes du protocole ImmichClient qui portent les routes /api/auth/status, /api/auth/pin-code et /api/auth/session/{unlock,lock}.
Check post-impl: sh -c 'd=Sources/Core/Types/DTOs.swift; p=Sources/Core/Protocols/ImmichClient.swift; grep -qE "struct AuthStatusResponseDto" "$d" && grep -qE "let isElevated: Bool" "$d" && grep -qE "let pinCode: Bool" "$d" && grep -qE "struct PinCodeSetupDto" "$d" && grep -qE "struct PinCodeChangeDto" "$d" && grep -qE "struct SessionUnlockDto" "$d" && grep -qE "func getAuthStatus\(\) async throws -> AuthStatusResponseDto" "$p" && grep -qE "func setupPinCode\(_ pinCode: String\) async throws" "$p" && grep -qE "func changePinCode\(dto: PinCodeChangeDto\) async throws" "$p" && grep -qE "func unlockAuthSession\(pinCode: String\) async throws" "$p" && grep -qE "func lockAuthSession\(\) async throws" "$p" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun des symboles n'existe — `grep -rn "AuthStatusResponseDto\|PinCodeSetupDto\|SessionUnlockDto\|getAuthStatus" Sources/` ne renvoie rien ; `ImmichClient` ne déclare que `login` / `logout` / `validateToken`)
Post-state attendu: PASS
```

```
### AC-5111 [type: new]
Assertion: ImmichAPIClient route réellement les cinq appels sous ImmichAPI.auth.path — GET /status, POST /pin-code (corps PinCodeSetupDto), PUT /pin-code (corps PinCodeChangeDto), POST /session/unlock (corps SessionUnlockDto) et POST /session/lock sans corps.
Check post-impl: sh -c 'f=Sources/Services/ImmichAPIClient.swift; grep -qE "ImmichAPI.auth.path\(\"/status\"\)" "$f" && grep -qE "PinCodeSetupDto\(pinCode:" "$f" && grep -qE "PinCodeChangeDto" "$f" && grep -qE "SessionUnlockDto" "$f" && grep -qE "ImmichAPI.auth.path\(\"/session/unlock\"\)" "$f" && grep -qE "ImmichAPI.auth.path\(\"/session/lock\"\)" "$f" && n=$(grep -cE "ImmichAPI.auth.path\(\"/pin-code\"\)" "$f"); test "$n" -ge 2 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (les seuls appels existants sont `ImmichAPI.auth.path("/login")` l.78, `"/logout"` l.82 et `"/validateToken"` l.86 — `grep -c "auth.path" Sources/Services/ImmichAPIClient.swift` en compte 3)
Post-state attendu: PASS
Note: `/pin-code` doit apparaître DEUX fois (POST puis PUT) — un seul site signifierait qu'une des deux routes manque.
```

```
### AC-5112 [type: new]
Assertion: le PIN mémorisé vit derrière un protocole dédié et une implémentation Keychain qui délègue au KeychainStore existant (elle hérite ainsi de `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` et de la purge idempotente), distinct du stockage de tokens.
Check post-impl: sh -c 'p=Sources/Core/Protocols/LockedFolderPINStoring.swift; i=Sources/Services/KeychainLockedFolderPINStore.swift; test -f "$p" && test -f "$i" && grep -qE "protocol LockedFolderPINStoring" "$p" && grep -qE "func storedPIN\(for account: String\) -> String\?" "$p" && grep -qE "func storePIN\(_ pin: String, for account: String\) -> Bool" "$p" && grep -qE "func clearPIN\(for account: String\) -> Bool" "$p" && grep -qE "final class KeychainLockedFolderPINStore: LockedFolderPINStoring" "$i" && grep -qE "keychain.saveToken" "$i" && grep -qE "keychain.getToken" "$i" && grep -qE "keychain.deleteToken" "$i" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (les deux fichiers sont absents — `grep -rn "LockedFolderPINStoring" Sources/` ne renvoie rien)
Post-state attendu: PASS
```

```
### AC-5113 [type: new]
Assertion: LockedFolderViewModel porte l'état de gate (needsSetup / locked / unlocked) et les huit méthodes du flux, construit par le composition root sur le compte actif.
Check post-impl: sh -c 'f=Sources/Features/LockedFolder/LockedFolderViewModel.swift; c=Sources/DependencyContainer.swift; test -f "$f" && grep -qE "@Observable" "$f" && grep -qE "enum Gate" "$f" && grep -qE "var gate: Gate" "$f" && grep -qE "func refreshGate\(\) async" "$f" && grep -qE "func setupPIN\(\) async" "$f" && grep -qE "func submitPIN\(\) async" "$f" && grep -qE "func unlockWithBiometrics\(\) async" "$f" && grep -qE "func relock\(\) async" "$f" && grep -qE "func loadFirstPage\(\) async" "$f" && grep -qE "func loadMore\(\) async" "$f" && grep -qE "func restoreSelectionToTimeline\(\) async" "$f" && grep -qE "func makeLockedFolderViewModel\(accountID: String\) -> LockedFolderViewModel" "$c" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun dossier `Sources/Features/LockedFolder`, aucune fabrique `makeLockedFolderViewModel` dans DependencyContainer)
Post-state attendu: PASS
```

```
### AC-5114 [type: new — aucun déverrouillage sans PIN ni Face ID valide]
Assertion: les trois chemins d'ouverture sont gardés — création refusée hors 6 chiffres ou confirmation divergente, Face ID subordonné à un PIN mémorisé ET à un évaluateur biométrique qui répond vrai, et dans les deux cas le dossier ne bascule en unlocked qu'après un `unlockAuthSession` accepté par le serveur.
Check post-impl: sh -c 'f=Sources/Features/LockedFolder/LockedFolderViewModel.swift; grep -qE "pinEntry.count == 6" "$f" && grep -qE "pinEntry == confirmationEntry" "$f" && grep -qE "guard let [A-Za-z]+ = pins.storedPIN\(for: accountID\)" "$f" && grep -qE "await evaluator\(\)" "$f" && n=$(grep -cE "try await client.unlockAuthSession\(pinCode: " "$f"); test "$n" -ge 2 && m=$(grep -cE "failedAttempts" "$f"); test "$m" -ge 3 && grep -qE "gate = .locked" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — aucune garde de ce type dans Sources/, le seul évaluateur biométrique est `AppLockViewModel.systemEvaluator`)
Post-state attendu: PASS
Note: la preuve comportementale (« un PIN refusé ne change pas de gate, l'évaluateur est appelé une fois et le PIN du stub est rejoué ») est portée par AC-5118 — ce check ne constate que la présence des gardes.
```

```
### AC-5115 [type: new]
Assertion: LockedFolderView est stateless, sans NavigationStack (elle est poussée dans la pile de la sheet « Me »), ses identifiants sont posés sur les contrôles, et ProfileView la pousse depuis la section Security.
Check post-impl: sh -c 'v=Sources/Features/LockedFolder/LockedFolderView.swift; p=Sources/Features/Profile/ProfileView.swift; test -f "$v" && grep -qE "struct LockedFolderView" "$v" && grep -qE "let vm: LockedFolderViewModel" "$v" && grep -qE "lockedFolderCreatePINButton" "$v" && grep -qE "lockedFolderUnlockButton" "$v" && grep -qE "lockedFolderBiometricButton" "$v" && grep -qE "lockNowButton" "$v" && grep -qE "scenePhase" "$v" && ! grep -qE "NavigationStack \{" "$v" && grep -qE "let lockedFolder: LockedFolderViewModel" "$p" && grep -qE "LockedFolderView\(vm:" "$p" && grep -qE "lockedFolderRow" "$p" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent ; `grep -n "Locked Folder" Sources/Features/Profile/ProfileView.swift` ne renvoie rien — la section Security ne porte que le toggle d'App Lock)
Post-state attendu: PASS
Note: le check vise la DÉCLARATION (`NavigationStack {`) — un grep du seul mot échouerait sur le doc-comment qui explique justement l'absence de stack (piège de la carte stacks-ui).
```

```
### AC-5116 [type: new — écriture de la visibilité locked]
Assertion: sortir des éléments de la timeline écrit la visibilité `locked` depuis les deux points d'entrée (barre de sélection et menu contextuel d'une vignette), sans toucher au chemin Archive existant.
Check post-impl: sh -c 'v=Sources/Features/Timeline/TimelineViewModel.swift; t=Sources/Features/Timeline/TimelineView.swift; c=Sources/Features/Timeline/AssetThumbnailCell.swift; grep -qE "func moveSelectedToLockedFolder\(\) async" "$v" && grep -qE "func moveToLockedFolder\(id: String\) async" "$v" && grep -qE "visibility: .locked" "$v" && grep -qE "moveToLockedFolderButton" "$t" && grep -qE "onMoveToLockedFolder" "$t" && grep -qE "var onMoveToLockedFolder" "$c" && grep -qE "onMoveToLockedFolder\?" "$c" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -rn "\.locked" Sources/ Tests/` ne renvoie rien : le seul `locked` est le cas déclaré `case locked`, `Sources/Core/Constants.swift:70` — aucun appelant n'écrit cette visibilité)
Post-state attendu: PASS
Note: le menu de filtre de la timeline (All / Favorites / Archived / Shared with you, `TimelineView.swift:588-621`) ne doit PAS gagner d'entrée `locked` — le dossier verrouillé n'est pas un filtre de la timeline.
```

```
### AC-5117 [type: new — lecture filtrée du dossier et retour timeline]
Assertion: la grille lit le dossier en remontant le filtre locked aux DEUX appels de buckets, et l'action « Move back to timeline » émet bien `AssetBulkUpdateDto(visibility: .timeline)`.
Check post-impl: sh -c 'f=Sources/Features/LockedFolder/LockedFolderViewModel.swift; grep -qE "filterVisibility" "$f" && n=$(grep -cE "visibility: \"locked\"|visibility: filterVisibility" "$f"); test "$n" -ge 2 && grep -qE "getTimeBuckets\(" "$f" && grep -qE "getTimeBucket\(" "$f" && grep -qE "visibility: .timeline" "$f" && grep -qE "bulkUpdateAssets" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun appelant ne fixe `filterVisibility` — `grep -rn "filterVisibility" Sources/` ne renvoie que la déclaration et les deux transmissions de `TimelineViewModel`)
Post-state attendu: PASS
Note: les DEUX appels (première page et page suivante) doivent porter le filtre — un seul site ferait remonter des assets de la timeline en scrollant.
```

```
### AC-5118 [type: new]
Assertion: LockedFolderViewModelTests expose ≥ 8 cas couvrant les trois états du gate, les gardes de saisie, le succès/échec de déverrouillage, le rejeu du PIN mémorisé et la sortie vers la timeline, et MockImmichClient implémente les cinq méthodes neuves avec état capturé.
Check post-impl: sh -c 'f=Tests/LockedFolderViewModelTests.swift; m=Tests/Mocks/MockImmichClient.swift; test -f "$f" && n=$(grep -cE "func test_" "$f"); test "$n" -ge 8 && grep -qE "StubPINStore" "$f" && grep -qE "test_refreshGate_needsSetupWhenNoPinCode" "$f" && grep -qE "test_setupPIN_rejectsMismatchedConfirmation" "$f" && grep -qE "test_submitPIN_successUnlocksAndLoadsLockedItems" "$f" && grep -qE "test_submitPIN_failureKeepsGateLocked" "$f" && grep -qE "test_unlockWithBiometrics_replaysStoredPIN" "$f" && grep -qE "test_restoreSelectionToTimeline_sendsTimelineVisibility" "$f" && grep -qE "func getAuthStatus" "$m" && grep -qE "unlockedPINs" "$m" && grep -qE "func lockAuthSession" "$m" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier de tests absent ; MockImmichClient ne déclare ni `getAuthStatus` ni `unlockedPINs` — ses seules méthodes d'auth sont `logout` l.311 et `validateToken` l.317)
Post-state attendu: PASS
Note: un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate` — sans régénération la suite passe « verte » par omission.
```

```
### AC-5119 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_lockedfolder_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_lockedfolder_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent)
Post-state attendu: PASS
```
