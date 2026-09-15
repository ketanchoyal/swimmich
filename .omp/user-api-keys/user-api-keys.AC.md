# Task: user-api-keys

Status: planifié — **aucune AC ouverte** (écart G20 du registre `.omp/backlog/ImmichSwiftUI-backlog.md:795`).

## Plan (résumé)

**Objectif** : tout compte — administrateur ou non — ouvre « API Keys » depuis la section Management du hub
« Me » et gère lui-même ses clés : liste (nom, date de création, étendue des permissions), création avec choix des
permissions (accès complet ou sélection par catégorie) et lecture du secret **une seule fois**, rotation (l'ancien
secret meurt immédiatement) et révocation confirmée.

**Approche retenue** : A — un `UserApiKeysViewModel` + `UserApiKeysView` neufs dans `Sources/Features/UserApiKeys/`,
deux méthodes ajoutées au protocole `ImmichClient` (`getMyAPIKey()`, `rotateAPIKey(id:)`) et `createAPIKey` élargie
à `permissions:` ; la section clés d'`AdminView` est **supprimée** (elle montrait en réalité les clés de l'admin
lui-même), pas dupliquée.

- **B (rejetée)** : garder la section d'`AdminView` et n'y ajouter que la rotation → la surface reste gardée par
  `if auth.isAdmin` (`Sources/Features/Profile/ProfileView.swift:117`), donc l'objectif (« gérer SES clés ») reste
  hors d'atteinte de tout compte non administrateur, et le formulaire de création/suppression devrait malgré tout en
  sortir : deux propriétaires pour un même état.
- **C (rejetée)** : pousser une vue qui réutilise `AdminViewModel` tel quel → son `load()` émet trois requêtes
  inutiles ici (users, jobs, libraries, `Sources/Features/Admin/AdminViewModel.swift:36-42`) et expose à une
  surface non-admin des mutations d'administration (`createUser`, `deleteUser`, `updateUser`, `deleteLibrary`).

**Étapes** : (1) NEW `Sources/Core/Types/APIKeyPermission.swift` (146 permissions régénérées, `grouped`,
`summary(for:)`) ; (2) EDIT `ImmichClient.swift:244-246` (les deux méthodes neuves + `createAPIKey(name:permissions:)`) ;
(3) EDIT `Sources/Services/ImmichAPIClient.swift:576-586` (corps `sendAuthed` des trois routes) ;
(4) NEW `Sources/Features/UserApiKeys/UserApiKeysViewModel.swift` (état + actions + projections) ;
(5) NEW `Sources/Features/UserApiKeys/UserApiKeysView.swift` (liste, ligne « Current session », alertes, dialogue de
révocation) ; (6) NEW `Sources/Features/UserApiKeys/APIKeyCreateView.swift` (feuille, sélecteur de permissions) ;
(7) EDIT `Sources/DependencyContainer.swift:179-181` (`makeUserApiKeysViewModel()`) ; (8) EDIT `Sources/RootView.swift`
(`@State apiKeys` + passage à `ProfileView`) ; (9) EDIT `ProfileView.swift` (ligne `apiKeysRow` **hors** du bloc admin) ;
(10) EDIT `AdminView.swift` et `AdminViewModel.swift` (retrait de la surface clés) ; (11) EDIT
`Tests/Mocks/MockImmichClient.swift:1100-1103,1176-1196` ; (12) NEW `Tests/UserApiKeysViewModelTests.swift` (8 cas) ;
(13) `xcodegen generate` puis `-only-testing:ImmichSwiftUITests`.

**Incertitudes** : réponse réelle de `GET /api/api-keys/me` sous jeton de session (la section « Current session » tombe
si c'est une erreur) ; liste exacte des 146 permissions (à régénérer, jamais recopiée) ; nom/signature du formateur
ISO-8601 du dépôt ; libellé `API Keys` éventuellement attendu par une capture XCUITest de l'ancienne section admin.
Voir `.omp/user-api-keys/user-api-keys.specs.md` § Incertitudes.

## Critères

```
### AC-5200 [type: new]
Assertion: le protocole ImmichClient expose les deux méthodes neuves sous les noms exacts de la fiche (`getMyAPIKey()`, `rotateAPIKey(id:)`), la signature élargie `createAPIKey(name:permissions:)`, et conserve `getAPIKeys()`/`deleteAPIKey(id:)` inchangées.
Check post-impl: sh -c 'f=Sources/Core/Protocols/ImmichClient.swift; grep -qE "func getMyAPIKey\(\) async throws -> ApiKeyResponseDto" "$f" && grep -qE "func rotateAPIKey\(id: String\) async throws -> ApiKeyCreateResponseDto" "$f" && grep -qE "func createAPIKey\(name: String, permissions: \[String\]\) async throws -> ApiKeyCreateResponseDto" "$f" && grep -qE "func getAPIKeys\(\) async throws -> \[ApiKeyResponseDto\]" "$f" && grep -qE "func deleteAPIKey\(id: String\) async throws" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -n "getMyAPIKey\|rotateAPIKey" Sources/Core/Protocols/ImmichClient.swift` ne renvoie rien ; `:245` porte encore `func createAPIKey(name: String) async throws -> ApiKeyCreateResponseDto`, sans `permissions`)
Post-state attendu: PASS
Note: `getAPIKeys()` (`:244`) reste : c'est la seule route de liste, non-admin (`operationId: getApiKeys`, « Retrieve all API keys of the current user »). `getMyAPIKey()` ne la remplace pas — elle renvoie un `ApiKeyResponseDto` au singulier, pas un tableau.
```

```
### AC-5201 [type: new]
Assertion: les trois routes passent par la constante existante `ImmichAPI.apiKeys` (`/me`, `/{id}/rotate`, `PATCH`-free), la rotation est un POST, la suppression est réutilisée telle quelle et la création transmet `permissions` dans le corps.
Check post-impl: sh -c 'f=Sources/Services/ImmichAPIClient.swift; grep -qE "func getMyAPIKey" "$f" && grep -qF "apiKeys.path(\"/me\")" "$f" && grep -qE "func rotateAPIKey" "$f" && grep -qF "(id)/rotate" "$f" && grep -qE "\.POST, path: ImmichAPI\.apiKeys" "$f" && grep -qF "\"permissions\"" "$f" && grep -qF "AnyEncodable(permissions)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -n "getMyAPIKey\|rotateAPIKey\|/me" Sources/Services/ImmichAPIClient.swift` ne renvoie rien ; le corps de `createAPIKey` (`:580-582`) est `AnyEncodable(["name": name])`)
Post-state attendu: PASS
Note: la route de rotation est `POST /api/api-keys/{id}/rotate` (`added('v3')`), PAS `PUT` comme l'annonçait l'audit du backlog — le check exige donc `.POST` sur un chemin composé depuis `ImmichAPI.apiKeys`, jamais une seconde constante.
Note (arbitrage du 2026-09-15) : la clause de création demandait le littéral exact `"permissions": permissions` dans le corps. Aucune implémentation qui compile ne peut l'écrire : un dictionnaire littéral Swift ne peut pas mêler un `String` et un `[String]` (`[String: Any]` n'est pas `Encodable`), le corps passe donc par l'effacement de type du dépôt — `["name": AnyEncodable(name), "permissions": AnyEncodable(permissions)]`. Remplacée par deux clauses satisfaisables qui gardent le fond (le corps nomme `"permissions"` et il transmet bien le **paramètre**, pas une liste figée). Le comportement est prouvé par le test de transport du même commit, qui lit le corps JSON capturé. Même classe de défaut que AC-5045 (parenthèses non échappées) et AC-5081 (`isRouteDetectionEnabled`) : la carte est antérieure au code, c'est la carte qui cède, sur preuve.
```

```
### AC-5202 [type: new — la surface clés n'a qu'un seul propriétaire]
Assertion: la section clés est retirée de la console d'admin (vue ET ViewModel) et la nouvelle feature ne dépend d'aucun symbole d'`AdminViewModel` : les clés de l'utilisateur ne sont plus rendues par un écran gardé par le rôle admin.
Check post-impl: sh -c 'f=Sources/Features/Admin/AdminViewModel.swift; g=Sources/Features/Admin/AdminView.swift; d=Sources/Features/UserApiKeys; test -f "$f" && test -f "$g" && test -d "$d" && ! grep -qE "private var apiKeysSection" "$g" && ! grep -qF "alert(\"API Key Secret\"" "$g" && ! grep -qE "var apiKeys" "$f" && ! grep -qE "lastAPIKeySecret" "$f" && ! grep -qE "func createAPIKey|func deleteAPIKey" "$f" && ! grep -qE "AdminViewModel" "$d"/*.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Features/Admin/AdminViewModel.swift:14` déclare `var apiKeys`, `:20` `lastAPIKeySecret`, `:125-142` les deux méthodes ; `AdminView.swift:31,59-67,218-250` portent la section et l'alerte ; `Sources/Features/UserApiKeys/` n'existe pas)
Post-state attendu: PASS
Note: le check vise les DÉCLARATIONS (`private var apiKeysSection`, `var apiKeys`, `func createAPIKey`), pas les mots seuls — un doc-comment expliquant la coupe ne doit pas faire échouer la carte.
```

```
### AC-5203 [type: new]
Assertion: le ViewModel dédié porte le client par protocole, l'état complet de l'écran et les actions/projections de la fiche, sans hériter d'un ViewModel d'administration.
Check post-impl: sh -c 'f=Sources/Features/UserApiKeys/UserApiKeysViewModel.swift; test -f "$f" && grep -qE "final class UserApiKeysViewModel" "$f" && grep -qE "private let client: any ImmichClient" "$f" && grep -qE "var keys: \[ApiKeyResponseDto\]" "$f" && grep -qE "var myKey: ApiKeyResponseDto\?" "$f" && grep -qE "var isLoading" "$f" && grep -qE "var errorMessage" "$f" && grep -qE "var pendingSecret" "$f" && grep -qE "var rotationTarget" "$f" && grep -qE "var deletionTarget" "$f" && grep -qE "func load\(\)" "$f" && grep -qE "func loadMyKey\(\)" "$f" && grep -qE "func create\(name: String, permissions: \[String\]\) async -> Bool" "$f" && grep -qE "func rotate\(" "$f" && grep -qE "func delete\(" "$f" && grep -qE "func formattedCreatedAt" "$f" && grep -qE "func permissionsSummary" "$f" && grep -qE "func dismissSecret\(\)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — aucun dossier `Sources/Features/UserApiKeys`, `grep -rn "UserApiKeys" Sources/` ne renvoie rien)
Post-state attendu: PASS
Note: `create` retourne `Bool` — `false` en échec pour que la feuille reste ouverte ; `pendingSecret` sert la création ET la rotation (un seul affichage du secret, AC-5205).
```

```
### AC-5204 [type: new — la ligne est hors du bloc admin]
Assertion: la ligne « API Keys » vit dans la section Management de ProfileView, porte son identifiant d'accessibilité, reçoit le ViewModel, et sa position dans le fichier est ANTÉRIEURE à la garde `if auth.isAdmin` : elle est donc atteignable sans rôle administrateur.
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfileView.swift; row=$(grep -n "accessibilityIdentifier(\"apiKeysRow\")" "$f" | cut -d: -f1 | head -1); adm=$(grep -n "if auth.isAdmin" "$f" | cut -d: -f1 | head -1); test -n "$row" && test -n "$adm" && test "$row" -lt "$adm" && grep -qE "var apiKeys: UserApiKeysViewModel" "$f" && grep -qE "UserApiKeysView\(vm: apiKeys\)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -n "apiKeysRow" Sources/Features/Profile/ProfileView.swift` ne renvoie rien — la seule occurrence de `apiKeys` du dossier est la propriété `admin` du bloc gardé `:117`)
Post-state attendu: PASS
Note: `row -lt adm` est la mesure de l'écart G20 lui-même — une ligne insérée DANS le bloc `if auth.isAdmin` (donc après `:117`) échoue, même si elle existe.
```

```
### AC-5205 [type: new — le secret est montré une seule fois]
Assertion: le secret n'est présenté que par l'unique alerte de l'écran, reprise du précédent admin (copie dans le presse-papiers + bouton qui remet le secret à `nil`) ; la feuille de création ne connaît pas le secret.
Check post-impl: sh -c 'f=Sources/Features/UserApiKeys/UserApiKeysView.swift; g=Sources/Features/UserApiKeys/APIKeyCreateView.swift; test -f "$f" && test -f "$g" && grep -qE "alert\(" "$f" && n=$(grep -cE "\.alert\(" "$f"); test "${n:-0}" -eq 1 && grep -qE "apiKeyCopySecretButton" "$f" && grep -qF "UIPasteboard.general.string" "$f" && grep -qE "dismissSecret\(\)" "$f" && ! grep -qE "pendingSecret" "$g" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichiers absents ; le seul précédent d'affichage unique est `Sources/Features/Admin/AdminView.swift:59-67`, alerte qui disparaît avec l'étape 10)
Post-state attendu: PASS
Note: `n -eq 1` compte les `.alert(` DÉCLARATIONS : deux alertes dans le même écran (par exemple une pour `errorMessage`) font échouer la carte — la copie se contrôle par un `confirmationDialog` d'erreur ou un bandeau, pas par une seconde alerte de secret.
```

```
### AC-5206 [type: new — la révocation est confirmée]
Assertion: la révocation d'une clé passe par une confirmation destructrice explicite, distincte de celle de la rotation, toutes deux portées par l'état du ViewModel (`deletionTarget` / `rotationTarget`).
Check post-impl: sh -c 'f=Sources/Features/UserApiKeys/UserApiKeysView.swift; test -f "$f" && n=$(grep -cE "confirmationDialog" "$f"); test "${n:-0}" -ge 2 && grep -qE "deletionTarget" "$f" && grep -qE "rotationTarget" "$f" && grep -qF "Apps using this key will stop working." "$f" && grep -qE "role: \.destructive" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent ; `grep -rn "confirmationDialog" Sources/Features/Admin/` ne renvoie rien — la suppression d'une clé y est déclenchée sans confirmation, `AdminView.swift:218-250`)
Post-state attendu: PASS
```

```
### AC-5207 [type: new]
Assertion: la suite `Tests/UserApiKeysViewModelTests.swift` existe avec ≥ 8 cas dont les quatre nommés de la fiche, et le mock expose les coutures neuves (`myAPIKeyResponse`, `apiKeyRotateResponse`, `lastCreateApiKeyPermissions`, `lastRotateApiKeyId`) sans perdre celles dont la suite se sert.
Check post-impl: sh -c 'f=Tests/UserApiKeysViewModelTests.swift; m=Tests/Mocks/MockImmichClient.swift; test -f "$f" && n=$(grep -cE "func test_" "$f"); test "${n:-0}" -ge 8 && grep -qE "test_load_populatesKeysFromTheListEndpoint" "$f" && grep -qE "test_create_sendsNameAndPermissions_andExposesSecretOnce" "$f" && grep -qE "test_rotate_storesTheNewSecretAndInvalidatesNothingLocal" "$f" && grep -qE "test_delete_dropsTheKeyFromTheList" "$f" && grep -qE "myAPIKeyResponse" "$m" && grep -qE "apiKeyRotateResponse" "$m" && grep -qE "lastCreateApiKeyPermissions" "$m" && grep -qE "lastRotateApiKeyId" "$m" && grep -qE "func getMyAPIKey" "$m" && grep -qE "var apiKeysResponse" "$m" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier de test absent ; `Tests/Mocks/MockImmichClient.swift:1100-1102` ne porte que `apiKeysResponse`, `lastCreateApiKeyName`, `lastDeleteApiKeyId`, et `:1176-1196` n'implémente ni `getMyAPIKey()` ni `rotateAPIKey(id:)`)
Post-state attendu: PASS
Note: un `Tests/*.swift` neuf n'est compilé qu'après `xcodegen generate` — sans régénération la suite reste « verte » par omission, et ce check passerait alors sur un fichier jamais exécuté ; d'où AC-5209.
```

```
### AC-5208 [type: new — le secret ne fuit ni dans les journaux ni dans l'état persistant]
Assertion: la feature ne journalise rien (aucun `print(`, `NSLog`, `os_log`, `Logger`) et ne persiste rien (`UserDefaults`, `@AppStorage`, `Keychain`) : le secret vit uniquement dans `pendingSecret` en mémoire, effacé par `dismissSecret()`.
Check post-impl: sh -c 'd=Sources/Features/UserApiKeys; test -d "$d" && ! grep -qE "os_log|NSLog|Logger\(|print\(" "$d"/*.swift && ! grep -qE "UserDefaults|@AppStorage|Keychain|UIPasteboard.general.setItems" "$d"/*.swift && grep -qE "var pendingSecret" "$d/UserApiKeysViewModel.swift" && grep -qE "func dismissSecret" "$d/UserApiKeysViewModel.swift" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (dossier `Sources/Features/UserApiKeys` absent — `test -d` échoue ; aucun fichier à inspecter)
Post-state attendu: PASS
Note: `test -d` est indispensable en tête — sans lui, `! grep` sur un glob vide sort en code 2 et un `!` transformerait l'absence de fichier en PASS par accident. Le périmètre du check est la seule feature neuve : le transport (`Sources/Services/ImmichAPIClient.swift`) ne reçoit que trois corps de méthode à l'étape 3 et ne journalise rien aujourd'hui (`grep -rn "os_log\|Logger(\|print(" Sources/Services/ImmichAPIClient.swift` ne renvoie rien).
```

```
### AC-5209 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED, le fichier de test neuf étant effectivement compilé (régénération XcodeGen faite).
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_userapikeys_test.log 2>/dev/null && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_userapikeys_test.log 2>/dev/null | grep -oE "[0-9]+" | sort -n | tail -1); test "${n:-0}" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent)
Post-state attendu: PASS
Note: c'est le seul check qui atteste que `Tests/UserApiKeysViewModelTests.swift` est bien dans la cible de test — AC-5207 ne lit qu'un fichier.
```
