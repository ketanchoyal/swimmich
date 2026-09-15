# Task: user-api-keys

> **Audit 2026-09-15 — écart G20** (`.omp/backlog/ImmichSwiftUI-backlog.md:795`) : l'utilisateur ne peut pas gérer ses propres clés API. Côté iOS la seule surface est
> `apiKeysSection` de `AdminView` (`Sources/Features/Admin/AdminView.swift:31,218-250`), inatteignable pour un compte non administrateur (`Sources/Features/Profile/ProfileView.swift:117`
> la garde par `if auth.isAdmin`) — alors que l'endpoint de liste n'est PAS réservé aux admins (`GET /api/api-keys`, `operationId: getApiKeys`, description OpenAPI « Retrieve all
> API keys of the current user »). Côté upstream, le sélecteur de permissions `web/src/lib/components/user-settings-page/UserApiKeyGrid.svelte` (`immich-app/immich@e55ac299`) et la
> rotation `POST /api/api-keys/{id}/rotate` n'ont aucun équivalent Swift.

**Objectif** : après cette fiche, n'importe quel compte — administrateur ou non — ouvre « API Keys » depuis le hub « Me » et gère lui-même ses clés : il les liste avec leur nom,
leur date de création et l'étendue de leurs permissions ; il en crée une en choisissant ses permissions (accès complet ou sélection par catégorie) et lit le secret **une seule
fois**, dans l'unique alerte que l'app consacre à un secret ; il fait tourner une clé dont le secret a fuité, ce qui invalide l'ancien immédiatement, et il révoque une clé devenue
inutile.

**Hors périmètre** :
- L'**édition** d'une clé (renommage, changement de permissions) : la route existe (`PUT /api/api-keys/{id}`, `operationId: updateApiKey`, `history: deprecated('v3')`) mais l'objectif
  est lister/créer/faire tourner/révoquer. L'inclure imposerait un second formulaire pour un résultat atteignable en révoquant puis recréant.
- Toute vue sur les clés d'**autrui** : `GET /api/api-keys` renvoie celles du porteur du jeton, et `GET /api/api-keys/{id}` répond 403 si la clé n'appartient pas à l'appelant.
- La **gestion des sessions/appareils** (`/api/sessions`) : c'est l'écart G19, fiche `device-sessions`. Une clé API et une session sont deux objets distincts côté serveur ; les
  réunir ferait croire que révoquer une clé ferme une session.
- La **documentation d'usage** d'une clé (curl, variables d'environnement, clients tiers) : ni le sélecteur de permissions upstream ni cette fiche n'introduisent d'écran d'aide.

**Hypothèses** (vérifiées dans le dépôt et contre `immich-app/immich@e55ac299`, le 2026-09-15) :

- **Contrat OpenAPI** (`/tmp/immich-openapi-main.json`, OpenAPI publié `main`) :
  - `GET /api-keys` → `200` → `ApiKeyResponseDto[]`, `operationId: getApiKeys`, permission `apiKey.read` — **non admin** : c'est la liste des clés du porteur du jeton.
  - `GET /api-keys/me` → `200` → **`ApiKeyResponseDto` au singulier** (jamais un tableau), `operationId: getMyApiKey`, `@Authenticated({ permission: false })`, description « Retrieve
    the API key that is used to access this endpoint » ; le contrôleur `server/src/controllers/api-key.controller.ts` appelle `service.getMine(auth)`. Ce n'est donc pas la liste :
    c'est la clé qui porte la requête courante.
  - `POST /api-keys` → `201` → `ApiKeyCreateResponseDto`, corps `ApiKeyCreateDto` = `{name, permissions?}` où `permissions` est un tableau de `Permission`.
  - `POST /api-keys/{id}/rotate` → `201` → `ApiKeyCreateResponseDto`, permission `apiKey.rotate`, `added('v3')`. **La méthode est POST, pas PUT** — le backlog
    (`.omp/backlog/ImmichSwiftUI-backlog.md:795`) annonce `PUT` : coquille de l'audit, corrigée ici sur la foi de l'OpenAPI et du contrôleur.
  - `DELETE /api-keys/{id}` → `204`, permission `apiKey.delete`.
  - `ApiKeyResponseDto` = `{id, name, createdAt, updatedAt, permissions}` ; `permissions` est **required** côté OpenAPI mais optionnel dans le DTO Swift (décodage plus permissif).
  - `ApiKeyCreateResponseDto` exige `secret` **et** `apiKey` (marqué `Deprecated` en v3.2.0) plus les champs aplatis `id/name/createdAt/updatedAt/permissions` — le DTO Swift
    `{secret, apiKey}` en décode un sous-ensemble valide.
  - L'enum `Permission` compte 146 valeurs et commence par `all`, qui dispense de toute autre.
- **Ce que le dépôt sait déjà faire** :
  - `Sources/Core/Types/DTOs+Admin.swift:92-105` : `ApiKeyResponseDto` (Identifiable, `permissions: [String]?`) et `ApiKeyCreateResponseDto` (`secret` + `apiKey`) décodent liste,
    création et rotation sans modification.
  - `Sources/Core/Protocols/ImmichClient.swift:244-246` : `getAPIKeys()`, `createAPIKey(name:)`, `deleteAPIKey(id:)`. Seuls manquent `getMyAPIKey()` et `rotateAPIKey(id:)`, et
    `createAPIKey` ne transmet pas `permissions` (corps `AnyEncodable(["name": name])`, `Sources/Services/ImmichAPIClient.swift:580-582`).
  - `Sources/Core/Constants.swift:31` : `static let apiKeys = SubPath(root: "/api-keys")` — les nouvelles routes se composent par `ImmichAPI.apiKeys.path("/me")` et
    `path("/\(id)/rotate")`, sans nouvelle constante.
  - `Sources/Services/ImmichAPIClient.swift:684-692` : `sendAuthed` / `sendAuthedRaw` ; `:827-837` accepte `200..<300` et retourne sans décoder sur `204` — le `201` de la rotation
    et le `204` de la suppression passent donc tels quels, sans branche nouvelle dans le client.
  - `Sources/Features/Admin/AdminViewModel.swift:14,20,36-42,125-134,136-142` : l'écran admin porte déjà `apiKeys`, `lastAPIKeySecret`, la création et la suppression. Son `load()`
    charge users + jobs + libraries + clés en un `async let` — trois requêtes dont cette fiche n'a aucun besoin.
  - `Sources/Features/Admin/AdminView.swift:59-67` : précédent de présentation du secret une seule fois — un `.alert("API Key Secret", …)` avec un bouton `Copy`
    (`UIPasteboard.general.string`) et un `OK` qui remet le secret à `nil`. C'est la convention à réutiliser, pas à réinventer.
  - `Sources/DependencyContainer.swift:179-181` (`makeAdminViewModel`) et `:212` (`makeOfflineDownloadViewModel`) : le patron des fabriques est `make*ViewModel()` retournant un VM
    construit avec `client as any ImmichClient`.
  - `Sources/Features/Profile/ProfileView.swift:25` : le hub « Me » porte le `NavigationStack` ; les vues poussées n'en déclarent pas (précédent `OfflineAssetsView`, `:107-112`). La
    section d'accueil est `Section { … } header: { Text("Management") }`, `:55-115`.
  - `Tests/Mocks/MockImmichClient.swift:1100-1103,1176-1196` : le mock implémente déjà les trois méthodes avec `apiKeysResponse`, `lastCreateApiKeyName`, `lastDeleteApiKeyId`,
    `adminError`. Aucun test ne couvre les clés API (aucune occurrence de `apiKeys`/`createAPIKey` ailleurs dans `Tests/`).
  - `Sources/RootView.swift` construit tous les VM du hub « Me » dans `AuthenticatedRoot` (précédents `@State private var offline: OfflineDownloadViewModel` et
    `admin: AdminViewModel`) puis les passe à `ProfileView`.
- **Ce qui rend la fiche nécessaire** : `grep -rn "apiKeys" Sources/Features/` ne renvoie que le dossier `Admin/` — aucune vue de clés API n'existe pour un
  non-administrateur, et `Sources/Features/UserApiKeys/` n'existe pas.

**Approche retenue** : A — un `UserApiKeysViewModel` + `UserApiKeysView` neufs dans `Sources/Features/UserApiKeys/`, exposés à tous les comptes depuis la section Management du hub
« Me », plus les deux méthodes manquantes du protocole `ImmichClient` ; la section clés d'`AdminView` est **supprimée** (et non dupliquée) car elle montrait en réalité les clés de
l'admin lui-même.
- **B (rejetée)** : garder la section d'`AdminView` et n'y ajouter que la rotation → la surface reste gardée par `if auth.isAdmin` (`ProfileView.swift:117`), donc l'objectif
  (« gérer SES clés ») reste hors d'atteinte de tout compte non administrateur ; et le formulaire de création/suppression devrait de toute façon en sortir, ce qui laisserait deux
  propriétaires du même état dans deux écrans.
- **C (rejetée)** : pousser une nouvelle vue qui réutilise `AdminViewModel` tel quel → `AdminViewModel.load()` émet trois requêtes inutiles ici (users, jobs, libraries, `:36-42`) et
  expose à une surface non-admin des mutations d'administration (`createUser`, `deleteUser`, `updateUser`, `deleteLibrary`) qu'il faudrait masquer une à une ; le VM est moulé pour
  la console d'admin, pas pour un écran utilisateur. Un VM dédié ne partage que la couture `ImmichClient`.

## Étapes

1. **Les permissions** — NEW `Sources/Core/Types/APIKeyPermission.swift` : `enum APIKeyPermission` sans cas, portant `static let all: [String]` (les 146 valeurs de l'enum
   `Permission`, **régénérées** par la commande des Incertitudes), `static var grouped: [(category: String, items: [String])]` qui groupe sur le préfixe avant le premier `.` (les
   valeurs sans point, `all` et `maintenance`, formant le groupe `general`) et `static func summary(for:) -> String` qui retourne `"Full access"` si la liste contient `all`, sinon
   un décompte. Ce fichier ne porte que des données et deux projections : aucune logique d'affichage.
2. **La couture réseau** — EDIT `Sources/Core/Protocols/ImmichClient.swift:244-246` : ajouter `func getMyAPIKey() async throws -> ApiKeyResponseDto` et
   `func rotateAPIKey(id: String) async throws -> ApiKeyCreateResponseDto`, et changer `createAPIKey` en `func createAPIKey(name: String, permissions: [String]) async throws ->
   ApiKeyCreateResponseDto`. Les trois signatures vivent dans le même bloc `// MARK:` clés API, à côté de `deleteAPIKey(id:)`, réutilisée telle quelle.
3. **Les chemins** — EDIT `Sources/Services/ImmichAPIClient.swift:576-586` : `getMyAPIKey()` par `try await sendAuthed(.GET, path: ImmichAPI.apiKeys.path("/me"))`,
   `rotateAPIKey(id:)` par `try await sendAuthed(.POST, path: ImmichAPI.apiKeys.path("/\(id)/rotate"))`, et corps de `createAPIKey(name:permissions:)` élargi à
   `AnyEncodable(["name": name, "permissions": permissions])`. Le `201` et le `204` sont déjà acceptés (`:827-837`) : aucune autre méthode du fichier ne bouge.
4. **Le ViewModel — état** — NEW `Sources/Features/UserApiKeys/UserApiKeysViewModel.swift` : `import Foundation`, `import Observation`, `@MainActor @Observable final class
   UserApiKeysViewModel` avec `private let client: any ImmichClient`, `init(client: any ImmichClient)`, `var keys: [ApiKeyResponseDto] = []`, `var myKey: ApiKeyResponseDto?`,
   `var isLoading = false`, `var errorMessage: String?`, `var pendingSecret: String?` (le secret à afficher une seule fois, création **et** rotation confondues),
   `var rotationTarget: ApiKeyResponseDto?`, `var deletionTarget: ApiKeyResponseDto?`.
5. **Le ViewModel — actions** — NEW `Sources/Features/UserApiKeys/UserApiKeysViewModel.swift` (suite de l'étape 4) : `load()` (`getAPIKeys()` → `keys`), `loadMyKey()` (`myKey = try? await client.getMyAPIKey()`),
   `create(name:permissions:) async -> Bool` (trim du nom, refus d'un nom vide sans appel réseau, `pendingSecret = resp.secret`, `await load()`, retourne `false` en échec pour que la
   feuille reste ouverte), `rotate(_ key:) async` et `delete(_ key:) async` (chacune remet sa cible à `nil`, appelle `load()`, et `delete` réutilise `deleteAPIKey(id:)`). Le `try?`
   de `loadMyKey()` est délibéré et borné à cette ligne : la ligne « clé courante » est informative, l'app s'authentifie par jeton de session, et un refus du serveur ne doit pas
   empêcher la liste de s'afficher (voir Incertitudes).
6. **Le ViewModel — projections** — NEW `Sources/Features/UserApiKeys/UserApiKeysViewModel.swift` (suite de l'étape 5) : `formattedCreatedAt(_ key:) -> String` sur `key.createdAt` en réutilisant le formateur ISO-8601 du dépôt
   (`Sources/Core/Utilities/LongDateFormatter.swift`), avec repli sur `String(localized: "Unknown")` si la chaîne ne se décode pas ;
   `permissionsSummary(_ key:) -> String { APIKeyPermission.summary(for: key.permissions ?? []) }` ; `dismissSecret()`. Toute erreur passe par `error.localizedDescription` dans
   `errorMessage`, comme `AdminViewModel.swift:45`.
7. **L'écran — corps** — NEW `Sources/Features/UserApiKeys/UserApiKeysView.swift` : `import SwiftUI`, `struct UserApiKeysView: View` prenant `@Bindable var vm:
   UserApiKeysViewModel` et `@State private var showCreate = false`. **Aucun `NavigationStack`** : la vue est poussée depuis `ProfileView`, qui en porte déjà un. Une `List` porte une
   section `header: { Text("Current session") }` rendue uniquement si `vm.myKey != nil` (nom de la clé, permissions en sous-titre, identifiant `apiKeysCurrentRow`), puis une section
   `header: { Text("Your keys") }` où `ForEach(vm.keys)` produit une ligne par clé (nom, `vm.formattedCreatedAt(key)`, `vm.permissionsSummary(key)`) avec `.swipeActions` :
   `Button(role: .destructive) { vm.deletionTarget = key } label: { Label("Delete", systemImage: "trash") }` et `Button { vm.rotationTarget = key } label: { Label("Rotate",
   systemImage: "arrow.triangle.2.circlepath") }`, plus un état vide (« No API keys yet ») quand `vm.keys.isEmpty && !vm.isLoading`.
8. **L'écran — chrome** — NEW `Sources/Features/UserApiKeys/UserApiKeysView.swift` (suite de l'étape 7) : `.navigationTitle("API Keys")`, `.navigationBarTitleDisplayMode(.inline)`, `.task { await vm.load(); await vm.loadMyKey() }`,
   `.refreshable { await vm.load() }`, un `ToolbarItem(placement: .topBarTrailing)` avec `Button { showCreate = true } label: { Label("Create", systemImage: "plus") }`
   (identifiant `apiKeysCreateButton`), `.sheet(isPresented: $showCreate)`, l'alerte du secret reprise **textuellement** du précédent admin (`AdminView.swift:59-67` :
   `Button("Copy")` → `UIPasteboard.general.string`, `Button("OK", role: .cancel) { vm.dismissSecret() }`, identifiant `apiKeyCopySecretButton`), les deux `confirmationDialog` de
   `rotationTarget` (« Rotate key? » / « The current secret stops working immediately. The new secret is shown once. ») et de `deletionTarget` (« Delete key? » / « Apps using this
   key will stop working. »), et l'affichage de `vm.errorMessage` quand il est non nil.
9. **La création** — NEW `Sources/Features/UserApiKeys/APIKeyCreateView.swift` : `import SwiftUI`, `struct APIKeyCreateView: View` avec `let onCreate: (String, [String]) async ->
   Bool`, `@Environment(\.dismiss)`, `@State private var name = ""`, `@State private var fullAccess = true`, `@State private var selected: Set<String> = []`. Un `NavigationStack`
   **interne** est obligatoire ici : c'est une feuille, elle n'hérite d'aucune barre.
10. **Le sélecteur de permissions** — NEW `Sources/Features/UserApiKeys/APIKeyCreateView.swift` (suite de l'étape 9) : un `Form` portant un `TextField("Name", text: $name)` (identifiant `apiKeyNameField`), un
    `Toggle("Full access", isOn: $fullAccess)` puis, quand `fullAccess` est faux, une section dépliable par catégorie de `APIKeyPermission.grouped` avec une ligne de sélection par
    catégorie (tout cocher / tout décocher) et un `Toggle` par permission — transposition directe de `UserApiKeyGrid.svelte` (puce « select all » de catégorie + une puce par item).
    `Button("Create")` / `Button("Cancel")` en barre, le bouton créateur appelant `onCreate(name, fullAccess ? ["all"] : Array(selected))` et ne fermant la feuille que si le retour
    est `true`.
11. **L'injection** — EDIT `Sources/DependencyContainer.swift:179-181` : ajouter, à côté de `makeAdminViewModel()`, `func makeUserApiKeysViewModel() -> UserApiKeysViewModel
    { UserApiKeysViewModel(client: client as any ImmichClient) }`.
12. **Le câblage racine** — EDIT `Sources/RootView.swift` : déclarer `@State private var apiKeys: UserApiKeysViewModel` dans `AuthenticatedRoot` à côté de la déclaration de
    `admin`, l'initialiser dans `init(container:)` par `_apiKeys = State(initialValue: container.makeUserApiKeysViewModel())`, puis le passer à l'appel `ProfileView(...)` du
    `.sheet(isPresented: $showProfile)` sous la forme `apiKeys: apiKeys`.
13. **Le point d'entrée** — EDIT `Sources/Features/Profile/ProfileView.swift` : ajouter `@State var apiKeys: UserApiKeysViewModel` aux propriétés stockées (après `admin`, `:30`),
    puis insérer dans la section Management, **après** la ligne Offline Storage (`:107-112`) et donc juste avant le `} header: { Text("Management") }` de `:113`, une ligne
    `NavigationLink { UserApiKeysView(vm: apiKeys) } label: { Label("API Keys", systemImage: "key.horizontal") }` portant `.accessibilityIdentifier("apiKeysRow")`. La ligne est
    délibérément **hors** du bloc `if auth.isAdmin` (`:117-125`) : c'est tout l'objet de l'écart G20.
14. **La coupe dans la vue admin** — EDIT `Sources/Features/Admin/AdminView.swift` : retirer `apiKeysSection` de `body` (`:31`), l'alerte « API Key Secret » (`:59-67`) et le
    `@ViewBuilder private var apiKeysSection` (`:218-250`), devenus la propriété de `UserApiKeysView`. La chaîne `"API Keys (\(vm.apiKeys.count))"` de `:248` disparaît avec eux.
15. **La coupe dans le ViewModel admin** — EDIT `Sources/Features/Admin/AdminViewModel.swift` : retirer `apiKeys` (`:14`), `lastAPIKeySecret` (`:20`), le
    `async let k = client.getAPIKeys()` (`:37`) et son affectation (`:42`), puis `createAPIKey(name:)` (`:125-134`) et `deleteAPIKey(_:)` (`:136-142`). `load()` ne garde que users,
    jobs et libraries : il ne reste aucune duplication de la surface clés.
16. **Le mock** — EDIT `Tests/Mocks/MockImmichClient.swift:1100-1103,1176-1196` : ajouter `var myAPIKeyResponse: ApiKeyResponseDto?`, `var apiKeyCreateResponse:
    ApiKeyCreateResponseDto?`, `var apiKeyRotateResponse: ApiKeyCreateResponseDto?`, `var lastCreateApiKeyPermissions: [String]?`, `var lastRotateApiKeyId: String?` ; implémenter
    `getMyAPIKey()` (retourne `myAPIKeyResponse`, ou jette `globalError ?? adminError`), `rotateAPIKey(id:)` (mémorise l'id, retourne `apiKeyRotateResponse` ou un
    `ApiKeyCreateResponseDto(secret: "rotated", apiKey: ApiKeyResponseDto(id: id, name: "rotated"))`) et la nouvelle signature de `createAPIKey(name:permissions:)`.
    `apiKeysResponse`, `lastCreateApiKeyName` et `lastDeleteApiKeyId` sont conservés : la nouvelle suite s'en sert.
17. **Les tests du ViewModel** — NEW `Tests/UserApiKeysViewModelTests.swift` : `import XCTest`, `@testable import ImmichSwiftUI`, suite `final class UserApiKeysViewModelTests:
    XCTestCase`, `@MainActor`, construite sur `MockImmichClient` comme les suites existantes. Cas : `test_load_populatesKeysFromTheListEndpoint`,
    `test_create_sendsNameAndPermissions_andExposesSecretOnce`, `test_create_rejectsEmptyName_withoutCallingTheClient`, `test_rotate_storesTheNewSecret`,
    `test_delete_dropsTheKeyFromTheList`, `test_loadMyKey_failure_leavesTheRowAbsent`, `test_permissionsSummary_saysFullAccessForTheAllPermission`,
    `test_createdAt_undecodable_returnsUnknownLabel`.
18. **Les chaînes** — aucune écriture manuelle dans `Resources/Localizable.xcstrings` : la clé est la chaîne anglaise et l'extraction est faite par Xcode au build, les 4 langues
    étant ajoutées par le flux i18n existant. Chaînes neuves des étapes 7 à 10 : `API Keys`, `Current session`, `Your keys`, `No API keys yet`, `Create`, `Cancel`, `Delete`,
    `Rotate`, `Full access`, `Name`, `Rotate key?`, `Delete key?`, `The current secret stops working immediately. The new secret is shown once.`, `Apps using this key will stop
    working.`, `Unknown`.
19. `xcodegen generate` (quatre fichiers source et un fichier de test ont été ajoutés : sans régénération ils ne sont pas compilés), puis la suite complète
    `-only-testing:ImmichSwiftUITests`.

## Incertitudes à lever à l'implémentation

- **Ce que `GET /api/api-keys/me` répond quand la requête est portée par un jeton de session et non par une clé.** Le contrôleur upstream
  (`server/src/controllers/api-key.controller.ts`, `getMyApiKey` → `service.getMine(auth)`) documente la route comme « Retrieve the API key that is used to access this endpoint » :
  pour un appelant authentifié par clé, la réponse est cette clé ; pour un appelant authentifié par session, elle dépend de `getMine`, que cette fiche n'a pas lu. Si la réponse est
  une erreur, la section « Current session » doit être **supprimée** (un seul point d'appel : `UserApiKeysView` lit `vm.myKey`, et `loadMyKey()` est la seule méthode à retirer).
  Trancher par : `grep -n "getMine" -A 12 server/src/services/api-key.service.ts` sur un checkout upstream, ou à défaut
  `curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOKEN" "$IMMICH/api/api-keys/me"` avec un jeton de session réel.
- **La liste exacte des permissions.** Elle doit être régénérée, pas recopiée : `jq -r '.components.schemas.Permission.enum[]' /tmp/immich-openapi-main.json` (146 valeurs). Ne pas
  élaguer : une permission absente de la liste rend une clé impossible à créer dans une portée que le serveur accepte.
- **Le formateur de date ISO-8601.** Réutiliser celui du dépôt plutôt qu'en écrire un second (règle du projet : une seule convention). Confirmer son nom et sa signature par
  `grep -n "func \|enum \|struct " Sources/Core/Utilities/LongDateFormatter.swift` ; s'il ne fait que du `parse`, la projection de l'étape 6 utilise `Date.ISO8601FormatStyle` avec
  repli sur `String(localized: "Unknown")`.
- **Le nom du composant web qui porte la liste et le formulaire.** Seul `UserApiKeyGrid.svelte` a été lu, et c'est un sélecteur de permissions, pas une liste ; la liste vit ailleurs
  dans `web/src/lib/components/user-settings-page/`. Aucun impact sur cette fiche, qui s'ancre sur le contrat OpenAPI — vérifier seulement le libellé retenu si un doute apparaît :
  `ls web/src/lib/components/user-settings-page/`.
- **Les captures XCUITest qui attendraient l'ancien libellé.** La chaîne `API Keys` est aussi le titre de la section admin supprimée à l'étape 14 (`AdminView.swift:248`). Vérifier
  qu'aucun test existant ne l'attend : `grep -rn "API Keys" UITests/ Tests/`.
- **Le comportement de rotation sur une clé qui porte la requête courante.** L'app s'authentifie par jeton de session (`ImmichClient` passe `token` à `sendAuthedRaw`) et aucune autre
  surface du dépôt ne consomme `ImmichClient.getAPIKeys()` : faire tourner une clé ne peut donc pas déconnecter l'app. Le confirmer avant de retirer le garde-fou d'UI :
  `grep -rn "apiKey\|api-key" Sources/Features/Settings/ Sources/Services/Keychain*` — si un second consommateur apparaît, la rotation de la clé courante demande une confirmation
  supplémentaire.
- **L'icône `key.horizontal`.** Choisie pour ne pas ressembler à `gearshape.2` (Administration, `ProfileView.swift:122`) ni à `arrow.down.circle` (Offline Storage, `:110`). Aucune
  commande ne tranche un choix d'icône : contrôle visuel dans la maquette Xcode, remplacement par `key` si le glyphe se lit mal à 17 pt.
