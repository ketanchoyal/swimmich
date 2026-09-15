# Task: device-sessions

Status: planifié — **aucune AC ouverte** (écart G19 du registre `.omp/backlog/ImmichSwiftUI-backlog.md`).

## Plan (résumé)

**Objectif** : depuis le hub « Me », la section Security ouvre « Connected Devices » et l'utilisateur voit les
sessions du compte (`OS • type • version`, dernière activité en relatif **et** en absolu, badge de session
courante, icône par OS), révoque une session autre que la sienne (swipe, jamais plein-geste) ou toutes d'un
coup — là où l'app ne sait aujourd'hui que déconnecter l'appareil courant (`AuthViewModel.logout()`).

**Approche retenue** : A — feature dédiée `Sources/Features/Security/` : `DeviceSessionsViewModel`
(`@MainActor @Observable`, `any ImmichClient`) qui possède la liste, l'état d'élévation local et les actions,
plus une `DeviceSessionsView` stateless (sans `NavigationStack`, poussée depuis la section Security de
`ProfileView`).

**Périmètre des routes (délimitation explicite)** : cette carte ne pinne que la famille `GET/DELETE /sessions`
(liste, suppression d'une session, suppression de toutes). Les leviers d'élévation
`POST /auth/session/lock|unlock` — et les exigences `lockAuthSession()` / `unlockAuthSession(pinCode:)` qui les
portent — appartiennent à la carte frère `.omp/locked-folder/locked-folder.AC.md` (écart voisin, qui pinne aussi
`POST|PUT /auth/pin-code` et `GET /auth/status`). Ici, l'élévation n'est vérifiée qu'au niveau du **ViewModel**
(état local optimiste + garde de saisie), jamais au niveau du transport : AC-5191 vérifie que la sous-racine
`sessions` ne peut pas absorber un chemin d'élévation, et aucun critère de cette carte ne grepe `/auth/session`.

**Étapes** : (1) NEW `Sources/Core/Types/DTOs+Session.swift` (`SessionResponseDto`) ; (2) EDIT
`Sources/Core/Protocols/ImmichClient.swift` (3 exigences `/sessions`, après la section Admin API keys) ;
(3) EDIT `Sources/Core/Constants.swift` (`ImmichAPI.sessions`) ; (4) EDIT `Sources/Services/ImmichAPIClient.swift`
(GET + les deux DELETE) ; (5) NEW `Sources/Features/Security/DeviceSessionsViewModel.swift` ;
(6) NEW `Sources/Features/Security/DeviceSessionsView.swift` ; (7) EDIT `Sources/DependencyContainer.swift`
(`makeDeviceSessionsViewModel`) ; (8) EDIT `Sources/RootView.swift` (`@State` + passage à `ProfileView`) ;
(9) EDIT `Sources/Features/Profile/ProfileView.swift` (ligne dans la section Security) ; (10) NEW
`Tests/DeviceSessionsViewModelTests.swift` ; (11) `xcodegen generate` + suite complète.

**Incertitudes** : l'état d'élévation n'est exposé par aucun champ de `SessionResponseDto` (ni `pinExpiresAt` ni
booléen) ⇒ état **local optimiste**, faux au lancement ; la politique de tri de la liste (ordre serveur vs
`updatedAt` décroissant) ; le comportement en compte authentifié par clé API, où `/auth/session/*` répond 400.

## Critères

```
### AC-5190 [type: new]
Assertion: le DTO de session est décodé avec l'optionalité exacte de l'OpenAPI — `expiresAt` et `appVersion` sont les deux seuls optionnels (`required` = tout sauf `expiresAt`, `appVersion` nullable), les trois dates se déclarent en `Date` parce que `JSONDecoder.immich` applique `.immichISO8601` (`Sources/Services/JSONCoding.swift:16-21`), et `Identifiable` s'appuie sur l'`id` serveur.
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs+Session.swift; test -f "$f" && grep -qE "struct SessionResponseDto" "$f" && grep -qE "let id: String" "$f" && grep -qE "let createdAt: Date" "$f" && grep -qE "let updatedAt: Date" "$f" && grep -qE "let expiresAt: Date\?" "$f" && grep -qE "let current: Bool" "$f" && grep -qE "let deviceType: String" "$f" && grep -qE "let deviceOS: String" "$f" && grep -qE "let appVersion: String\?" "$f" && grep -qE "let isPendingSyncReset: Bool" "$f" && grep -qE "Equatable" "$f" && grep -qE "Sendable" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — `grep -rn "SessionResponseDto" Sources/` ne renvoie rien : l'API des sessions n'est pas déclarée côté iOS)
Post-state attendu: PASS
Note: `\?` est échappé pour ERE, sinon `Date?` et `String?` passeraient aussi sur les champs **non** optionnels et l'optionalité — seule information réellement contractuelle du DTO — ne serait plus vérifiée.
```

```
### AC-5191 [type: new]
Assertion: le contrat des sessions est déclaré sur `ImmichClient` (les trois exigences de la famille `/sessions`, dans une section dédiée) et adossé à une sous-racine `ImmichAPI.sessions` dont le `root` est **exactement** `/sessions` — ce qui interdit d'y loger un chemin d'élévation et matérialise la frontière avec la carte locked-folder (`/auth/session/lock|unlock`).
Check post-impl: sh -c 'p=Sources/Core/Protocols/ImmichClient.swift; c=Sources/Core/Constants.swift; grep -qE "func getSessions\(\) async throws -> \[SessionResponseDto\]" "$p" && grep -qE "func deleteSession\(id: String\) async throws" "$p" && grep -qE "func deleteAllSessions\(\) async throws" "$p" && grep -qE "static let sessions = SubPath\(root: \"/sessions\"\)" "$c" && ! grep -qE "root: \"/sessions/" "$c" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune des trois exigences sur le protocole — `grep -n "Sessions" Sources/Core/Protocols/ImmichClient.swift` ne renvoie que des commentaires sur la session d'authentification ; `ImmichAPI` s'arrête à `apiKeys`, `Sources/Core/Constants.swift:31`)
Post-state attendu: PASS
Note: la borne négative porte sur le **root** (`root: "/sessions/`) et non sur un chemin composé : un `sessionLock` éventuellement déclaré par la carte locked-folder sous `/auth/session/...` ne peut donc pas faire échouer ce critère, et l'absence de `MEMORY`/commentaire ne suffit pas à le satisfaire.
```

```
### AC-5192 [type: new]
Assertion: le transport réalise les trois routes sur les chemins et les verbes réels de l'OpenAPI — `GET /sessions` en `sendAuthed(.GET, …)` (réponse décodée), `DELETE /sessions/{id}` et `DELETE /sessions` en `sendAuthedRaw(.DELETE, …)` : les deux suppressions ne renvoient que 204, donc rien à décoder et rien à renvoyer.
Check post-impl: sh -c 'c=Sources/Services/ImmichAPIClient.swift; grep -qE "func getSessions\(\) async throws -> \[SessionResponseDto\]" "$c" && grep -qE "sendAuthed\(\.GET, path: ImmichAPI\.sessions\.path\(\"\"\)\)" "$c" && grep -qE "func deleteSession\(id: String\) async throws" "$c" && grep -qE "sendAuthedRaw\(\.DELETE, path: ImmichAPI\.sessions\.path\(\"/" "$c" && grep -qE "func deleteAllSessions\(\) async throws" "$c" && grep -qE "sendAuthedRaw\(\.DELETE, path: ImmichAPI\.sessions\.path\(\"\"\)" "$c" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (le client n'a aucune méthode de session : `grep -n "func delete.*Session\|func getSessions" Sources/Services/ImmichAPIClient.swift` est vide ; le seul DELETE voisin est `deleteAPIKey`, `:584-586`)
Post-state attendu: PASS
Note: la suppression unitaire est distinguée par le préfixe `path("/` (seule route paramétrée) et la suppression massive par `path(""")` + le verbe `DELETE` — un `deleteAllSessions()` qui réutiliserait le chemin de l'unité échouerait donc, alors qu'un simple grep du nom de méthode ne verrait rien.
```

```
### AC-5193 [type: new]
Assertion: le ViewModel est construit par injection (`any ImmichClient`, même patron que `makeDuplicatesViewModel`) et expose l'état complet demandé — liste, chargement, erreur, élévation locale — plus les deux projections `currentSession` / `otherSessions` qui portent la séparation de l'écran.
Check post-impl: sh -c 'f=Sources/Features/Security/DeviceSessionsViewModel.swift; test -f "$f" && grep -qE "@MainActor" "$f" && grep -qE "@Observable" "$f" && grep -qE "final class DeviceSessionsViewModel" "$f" && grep -qE "private let client: any ImmichClient" "$f" && grep -qE "init\(client: any ImmichClient\)" "$f" && grep -qE "var sessions: \[SessionResponseDto\] = \[\]" "$f" && grep -qE "var isLoading = false" "$f" && grep -qE "var errorMessage: String\?" "$f" && grep -qE "var isElevated = false" "$f" && grep -qE "var currentSession: SessionResponseDto\?" "$f" && grep -qE "var otherSessions: \[SessionResponseDto\]" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (le dossier `Sources/Features/Security/` n'existe pas — `Sources/Features/` s'arrête à `Settings`, `Stacks`, `Tags`, …)
Post-state attendu: PASS
Note: `isElevated` est un état **local optimiste** : `SessionResponseDto` ne porte ni `pinExpiresAt` ni booléen d'élévation (vérifié dans `/tmp/immich-openapi-main.json`), donc AC-5190 interdit de le dériver du DTO et le critère d'écran (AC-5196) ne peut pas prétendre le lire du serveur.
```

```
### AC-5194 [type: new]
Assertion: les actions tiennent le contrat de la spec — `load()` encadre l'appel et l'erreur, `revoke(_:)` refuse la session courante avant tout appel, `revokeAllOthers()`/`revoke` rechargent après suppression, `clearError()` existe, et la garde de longueur du PIN se trouve **avant** l'appel client (un PIN court ne part jamais sur le réseau).
Check post-impl: sh -c 'f=Sources/Features/Security/DeviceSessionsViewModel.swift; test -f "$f" && grep -qE "func load\(\) async" "$f" && grep -qE "isLoading = true" "$f" && grep -qE "isLoading = false" "$f" && grep -qE "client.getSessions\(\)" "$f" && grep -qE "errorMessage = error.localizedDescription" "$f" && grep -qE "func revoke\(_ session: SessionResponseDto\) async" "$f" && grep -qE "guard !session.current else \{ return \}" "$f" && grep -qE "client.deleteSession\(id:" "$f" && grep -qE "func revokeAllOthers\(\) async" "$f" && grep -qE "client.deleteAllSessions\(\)" "$f" && grep -qE "func clearError\(\)" "$f" && grep -qE "func lockCurrentSession\(\) async" "$f" && grep -qE "func unlock\(pinCode: String\) async" "$f" && a=$(grep -nE "guard pinCode.count == 6" "$f" | cut -d: -f1) && b=$(grep -nE "client.unlockAuthSession\(" "$f" | cut -d: -f1) && test -n "$a" && test -n "$b" && test "$a" -lt "$b" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: la comparaison de numéros de ligne encode « refus local avant réseau » ; sans elle, une garde posée après l'appel satisfaisait tous les greps. Les deux méthodes d'élévation sont ici **consommées** (leur déclaration de transport appartient à locked-folder) : le critère ne vérifie que leur usage par le VM, jamais un chemin `/auth/session/*`. Le pattern est `\?`-échappé nulle part ici car seuls des littéraux sans métacaractère `?` sont visés.
```

```
### AC-5195 [type: new]
Assertion: l'écran existe comme vue **poussée** — sa propre `NavigationStack` est absente (règle du dépôt : `ProfileView` en porte une, cf. `LanguageSettingsView`), il déclare ses deux sections par libellé anglais, son titre, son chargement à l'apparition, son rafraîchissement, la ligne d'erreur, et les six identifiants demandés par la spec, posés sur des éléments interactifs (liste, ligne, bouton cadenas, bouton de révocation massive, champ PIN, confirmation).
Check post-impl: sh -c 'f=Sources/Features/Security/DeviceSessionsView.swift; test -f "$f" && grep -qE "struct DeviceSessionsView: View" "$f" && grep -qE "@Bindable var vm: DeviceSessionsViewModel" "$f" && grep -qE "List \{" "$f" && grep -qE "\"This device\"" "$f" && grep -qE "\"Other devices\"" "$f" && grep -qE "deviceSessionsList" "$f" && grep -qE "deviceSessionRow_" "$f" && grep -qE "deviceSessionsLockButton" "$f" && grep -qE "deviceSessionsRevokeAllButton" "$f" && grep -qE "deviceSessionsUnlockField" "$f" && grep -qE "deviceSessionsUnlockConfirm" "$f" && grep -qE "navigationTitle\(\"Connected Devices\"\)" "$f" && grep -qE "task \{ await vm.load\(\) \}" "$f" && grep -qE "refreshable" "$f" && grep -qE "vm.errorMessage" "$f" && ! grep -qE "NavigationStack \{" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: le check vise la **déclaration** `NavigationStack {` — un grep du seul mot échouerait sur le doc-comment qui explique justement l'absence de pile (même piège que la carte download-panel). Les libellés sont les **clés anglaises** du catalogue (`Resources/Localizable.xcstrings`, `sourceLanguage = en`), pas des phrases françaises : une chaîne francisée en dur ferait échouer le critère.
```

```
### AC-5196 [type: new]
Assertion: la session courante est marquée dans sa propre section (badge « This device ») et **aucun contrôle destructif ne peut s'y attacher** — la révocation vit dans la branche `otherSessions` (section « Other devices »), en fin de swipe seulement (`allowsFullSwipe: false`), la révocation massive est armée par une confirmation et désactivée quand il n'y a rien à révoquer, et le déverrouillage passe par un alert à champ numérique.
Check post-impl: sh -c 'f=Sources/Features/Security/DeviceSessionsView.swift; test -f "$f" && grep -qE "vm.currentSession" "$f" && grep -qE "vm.otherSessions" "$f" && grep -qE "swipeActions\(edge: \.trailing, allowsFullSwipe: false\)" "$f" && grep -qE "Button\(role: \.destructive\)" "$f" && grep -qE "\"Log out other devices\"" "$f" && grep -qE "disabled\(vm.otherSessions.isEmpty\)" "$f" && grep -qE "showRevokeAllConfirm" "$f" && grep -qE "confirmationDialog" "$f" && grep -qE "showUnlock" "$f" && grep -qE "alert\(\"Unlock\"" "$f" && grep -qE "TextField\(\"PIN\"" "$f" && grep -qE "keyboardType\(\.numberPad\)" "$f" && grep -qE "vm.unlock\(pinCode: pin\)" "$f" && a=$(grep -nE "vm.otherSessions" "$f" | cut -d: -f1 | sed -n 1p) && b=$(grep -nE "Button\(role: \.destructive\)" "$f" | cut -d: -f1 | sed -n 1p) && test -n "$a" && test -n "$b" && test "$a" -lt "$b" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: l'ordre `vm.otherSessions` < premier `Button(role: .destructive)` matérialise « jamais la courante » là où un grep ne voit qu'une présence : la section « This device » est écrite avant la branche des autres sessions, donc un contrôle destructif ne peut pas exister au-dessus d'elle. `allowsFullSwipe: false` est l'autre moitié du contrat — un plein-geste révoquerait un appareil sans confirmation.
```

```
### AC-5197 [type: new]
Assertion: la fonctionnalité est atteignable depuis le hub « Me » et l'instance est unique, construite par le composition root : la ligne de la section Security de `ProfileView` pousse `DeviceSessionsView(vm:)` et porte son identifiant sur le lien, `DeviceSessionsViewModel` vient de `DependencyContainer.makeDeviceSessionsViewModel()`, et `RootView` la détient puis la passe — jamais instanciée dans une vue.
Check post-impl: sh -c 'a=Sources/Features/Profile/ProfileView.swift; b=Sources/RootView.swift; d=Sources/DependencyContainer.swift; grep -qE "DeviceSessionsView\(vm: deviceSessions\)" "$a" && grep -qE "Label\(\"Connected Devices\", systemImage:" "$a" && grep -qE "accessibilityIdentifier\(\"deviceSessionsRow\"\)" "$a" && grep -qE "var deviceSessions: DeviceSessionsViewModel" "$a" && grep -qE "func makeDeviceSessionsViewModel\(\)" "$d" && grep -qE "DeviceSessionsViewModel\(client:" "$d" && grep -qE "makeDeviceSessionsViewModel\(\)" "$b" && grep -qE "deviceSessions: deviceSessions" "$b" && x=$(grep -nE "accessibilityIdentifier\(\"appLockToggle\"\)" "$a" | cut -d: -f1); y=$(grep -nE "\"deviceSessionsRow\"" "$a" | cut -d: -f1); z=$(grep -nE "Label\(\"Log Out\"" "$a" | cut -d: -f1); test -n "$x" && test -n "$y" && test -n "$z" && test "$x" -lt "$y" && test "$y" -lt "$z" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune occurrence de `makeDeviceSessionsViewModel` dans `Sources/DependencyContainer.swift`, `Sources/RootView.swift` ni `Sources/Features/Profile/ProfileView.swift` — comptage à 0 sur les trois ; la section Security de `ProfileView` ne contient que `Toggle("Require Face ID")`, `:132-137`)
Post-state attendu: PASS
Note: l'encadrement `appLockToggle` < `deviceSessionsRow` < `Log Out` (`ProfileView.swift:147`) fixe l'**ancrage** — la session est un objet de sécurité, donc la ligne vit dans la section Security et non dans la section de déconnexion qui la suit. `RootView` passe le VM au même appel que `language`, `:234`.
```

```
### AC-5198 [type: new]
Assertion: la suite du ViewModel existe avec ses huit cas, y compris les deux qui portent un contrat non visible au grep de production — la session courante n'est pas révocable (l'appel client ne part pas) et un PIN de moins de six chiffres est refusé localement.
Check post-impl: sh -c 'f=Tests/DeviceSessionsViewModelTests.swift; test -f "$f" && n=0 && n=$(grep -cE "func test_" "$f") && test "$n" -ge 8 && grep -qE "@testable import ImmichSwiftUI" "$f" && grep -qE "@MainActor" "$f" && grep -qE "MockImmichClient" "$f" && grep -qE "test_load_populatesSessionsAndFlagsCurrent" "$f" && grep -qE "test_load_failure_surfacesErrorMessageAndKeepsListEmpty" "$f" && grep -qE "test_revoke_ignoresTheCurrentSession" "$f" && grep -qE "test_revokeAllOthers_deletesWithoutIdAndReloads" "$f" && grep -qE "test_unlock_rejectsPinShorterThanSixDigitsWithoutCallingTheClient" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — `Tests/` ne contient aucune suite de sessions ; le faux client réutilisable est `Tests/Mocks/MockImmichClient.swift`)
Post-state attendu: PASS
Note: `n=0` avant le `test -f` numérique évite le `integer expression expected` d'un `n` vide ; les greps de noms de cas suivent la spec pas à pas, pour qu'une suite « ≥ 8 cas » entièrement différente ne satisfasse pas le critère. Un `Tests/*.swift` n'est ni compilé ni exécuté sans `xcodegen generate` (étape 11).
```

```
### AC-5199 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED, les trois sources et le fichier de tests ajoutés étant bien enrôlés par la régénération du projet.
Check post-impl: sh -c 'n=0; test -f /tmp/immich_devicesessions_test.log && grep -qE "TEST SUCCEEDED" /tmp/immich_devicesessions_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_devicesessions_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log `/tmp/immich_devicesessions_test.log` absent — la suite n'a pas encore été relancée avec les nouveaux fichiers ; `n` retombe à 0)
Post-state attendu: PASS
Note: `n=0` initial permet au check de rendre FAIL sans erreur de syntaxe quand le log manque (aucun `test` sur une variable vide). Un `Sources/Features/Security/` non régénéré laisserait la suite « verte » par omission : le seuil de 886 ne suffit donc pas, c'est la régénération qui l'ancre.
```
