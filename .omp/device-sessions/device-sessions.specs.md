# Task: device-sessions

> **Audit 2026-09-15 — écart G19** (`.omp/backlog/ImmichSwiftUI-backlog.md:794`, bande AC-5190–5199 ligne 869) : la gestion
>   des sessions/appareils connectés n'existe que côté web — `web/src/lib/components/user-settings-page/DeviceCard.svelte`
>   (vérifié sur `immich-app/immich@main` : HTTP 200, rend `{deviceOS} • {deviceType} (v{appVersion})`, `last_seen` en
>   relatif + absolu, icône par OS, bouton poubelle `aria-label={$t('log_out')}` masqué par `{#if !session.current}`) — et
>   le client Flutter n'a **aucun** écran équivalent (`mobile/lib/routing/router.dart` sur `main` : 0 occurrence de «
>   session » ou « device » en 200 OK). Côté iOS l'API n'est même pas déclarée :
>   `grep -rn "SessionResponseDto\|deviceType\|deviceOS" Sources/` ne renvoie rien, et `Sources/Features/Security/` n'existe
>   pas.

**Objectif** : depuis le hub « Me », section Security, l'utilisateur ouvre « Connected Devices » et voit chaque session du
compte (OS • type • version de l'app, dernière activité en relatif et en absolu, badge « This device » pour la session
courante, icône par OS). Il peut révoquer n'importe quelle autre session (swipe ou bouton poubelle, jamais la courante),
déconnecter d'un coup tous les autres appareils, et contrôler l'accès élevé de la session courante : verrouiller maintenant
(l'app retombe en lecture normale) ou déverrouiller avec le PIN à 6 chiffres du compte.

**Hors périmètre** :
- `POST /api/sessions` (`createSession`, « used for casting » — `server/src/controllers/session.controller.ts:23-38`) :
  c'est la fiche `chromecast` qui crée une session enfant pour le cast.
- `PUT /api/sessions/{id}` avec `SessionUpdateDto.isPendingSyncReset` : le drapeau de reset de synchronisation appartient
  aux fiches backup/sync (« Reset pending sync state », `SessionService.update`). Le champ est décodé (contrat) mais
  **aucun** contrôle ne l'écrit ici.
- La protection des assets verrouillés elle-même (parcourir le dossier verrouillé, PIN du compte) : fiche `locked-folder`.
  Cette fiche n'expose que les deux leviers de session (`lock` / `unlock`) et l'état d'élévation local.
- `AppLockViewModel` (Face ID/passcode du dépôt, `appLockToggle`, `ProfileView.swift:132-137`) : verrou **local à
  l'appareil**, sans identifiant de session ni PIN serveur ; il n'est ni remplacé ni modifié.
- Aucun nouveau composant DesignSystem : les lignes réutilisent `LabeledContent` / `Label` / `swipeActions` et les tokens
  existants.

**Hypothèses** (vérifiées dans le dépôt et contre `immich-app/immich@main`, le 2026-09-15) :
- **Upstream — le contrat des routes** (tout lu dans `/tmp/immich-openapi-main.json`) :
  - `GET /sessions` → 200 `SessionResponseDto[]` (propriétés
    `id, createdAt, updatedAt, expiresAt, current, deviceType, deviceOS, appVersion, isPendingSyncReset` ; `required` = tout
    **sauf** `expiresAt` ; `appVersion` est `nullable` ⇒ optionnel en Swift) ; `SessionService.getAll` mappe
    `auth.session?.id` sur `current`.
  - `DELETE /sessions/{id}` → 204 (permission `AuthDeviceDelete`) ; `DELETE /sessions` → 204 et le contrôleur précise « This
    will not delete the current session » (`SessionService.deleteAll` →
    `invalidateAll({ userId, excludeId: currentSessionId })`).
  - `POST /auth/session/lock` → 204, **sans corps** (`requestBody: null` dans l'OpenAPI) ; `AuthService.lockSession` pose
    `pinExpiresAt = null`.
  - `POST /auth/session/unlock` → 204, corps `SessionUnlockDto { password?, pinCode? }` (description du `pinCode` : « New
    PIN code (4-6 digits) », `pattern` `^\d{6}$`) ; `AuthService.unlockSession` valide **uniquement** `pinCode` et pose
    `pinExpiresAt = now + 15 min`.
  - Les deux routes `/auth/session/*` exigent un **token de session** : `AuthService` lève
    `BadRequestException('This endpoint can only be used with a session token')` sinon (comptes connectés par clé API).
- **iOS — ce qui existe déjà** :
  - Décodage des dates : `JSONDecoder.immich` (`Sources/Services/JSONCoding.swift:16-21`) applique `.immichISO8601` ⇒
    `createdAt` / `updatedAt` / `expiresAt` se déclarent en `Date`.
  - Style client : `ImmichClient` est un protocole `AnyObject, Sendable` (`Sources/Core/Protocols/ImmichClient.swift:12`)
    dont la section Admin API keys (`:244-246`) est le précédent exact (liste + suppression) ; `ImmichAPIClient` implémente
    les DELETE en `sendAuthedRaw(.DELETE, path:body:)` (`:584-586`, `deleteAPIKey`) et les GET en `sendAuthed` (`:576`). Les
    chemins sont déclarés dans `enum ImmichAPI` (`Sources/Core/Constants.swift:4-31`, dernier ajout `apiKeys` ligne 31).
  - MVVM strict : `DependencyContainer.make*ViewModel()` construit les VMs avec `client as any ImmichClient`
    (`makeDuplicatesViewModel`, `Sources/DependencyContainer.swift:205-207`) ; les VMs sont injectés depuis `RootView`
    (`@State private var offline: OfflineDownloadViewModel` `Sources/RootView.swift:105`,
    `_offline = State(initialValue: container.makeOfflineDownloadViewModel())` `:133`, passage à `ProfileView(...)` `:234`).
  - `ProfileView` porte le `NavigationStack` (`Sources/Features/Profile/ProfileView.swift:25-26`) et **aucune** vue poussée
    n'en déclare (règle du dépôt, cf. `LanguageSettingsView`) ; ses VMs stockés vont de `:12` à `:23` ; sa section
    `Security` est `:131-141` (`Section {` `:131`, `Toggle("Require Face ID")` `:132`,
    `.accessibilityIdentifier("appLockToggle")` `:136`, `Text("Security")` `:138`) et son pied de formulaire `Log Out`
    `:143-149`.
- **Ce qui rend la fiche nécessaire** : aucune route `/sessions` n'est déclarée (grep ci-dessus), aucune vue ne liste les
  sessions, et l'app n'a aucun moyen de révoquer un appareil distant — `AuthViewModel.logout()` ne déconnecte que l'appareil
  courant.

**Approche retenue** : A — une feature dédiée `Sources/Features/Security/` : un `DeviceSessionsViewModel` (`@MainActor
@Observable`, `any ImmichClient`) qui possède la liste, l'état d'élévation et les cinq actions, plus une
`DeviceSessionsView` stateless (sans `NavigationStack`) poussée depuis la section Security de `ProfileView`, et une ligne
`NavigationLink` dans cette section.
- **B (rejetée)** : poser la liste directement dans le `Form` de `ProfileView` (section Security dépliée) → deux raisons
  mesurables. (1) Le `Form` charge déjà le stockage à chaque apparition (`.task { await storage.load() }` `:154`) ; y
  ajouter `GET /sessions` ferait payer un aller-retour réseau à l'ouverture de l'onglet « Me », alors que l'upstream garde
  les sessions sur leur propre écran. (2) Les actions destructives ont besoin d'un état de confirmation et d'un champ PIN,
  que `ProfileView` (240 lignes, 13 VMs stockés `:12-23`) ne peut pas héberger sans devenir un écran multi-rôles.
- **C (rejetée)** : réutiliser `AppLockViewModel` comme « lock de session » → mesurablement faux : il est câblé sur
  `@AppStorage(AppLockViewModel.enabledKey)` et sur Face ID, sans identifiant de session ni corps `SessionUnlockDto`, donc
  il ne peut appeler ni `/auth/session/lock` ni `/auth/session/unlock` ; le verrou serveur et le verrou local sont deux
  contrats distincts (le premier a un TTL de 15 min côté serveur, le second garde l'app à chaque retour au premier plan).

## Étapes

1. **Les DTOs** — NEW `Sources/Core/Types/DTOs+Session.swift` :
   `struct SessionResponseDto: Codable, Equatable, Identifiable, Sendable` avec `let id: String`, `let createdAt: Date`,
   `let updatedAt: Date`, `let expiresAt: Date?`, `let current: Bool`, `let deviceType: String`, `let deviceOS: String`,
   `let appVersion: String?`, `let isPendingSyncReset: Bool` (ordre et optionalité alignés sur le `required` de l'OpenAPI).
   Puis `struct SessionUnlockDto: Codable, Equatable, Sendable { let pinCode: String }` — le champ `password` de l'upstream
   n'est pas modélisé, `AuthService.unlockSession` ne le lit pas.
2. **Le ViewModel** — NEW `Sources/Features/Security/DeviceSessionsViewModel.swift` : `import Foundation`,
   `import Observation`, `@MainActor @Observable final class DeviceSessionsViewModel` avec
   `private let client: any ImmichClient` et `init(client: any ImmichClient)`.
   - État : `var sessions: [SessionResponseDto] = []`, `var isLoading = false`, `var errorMessage: String?`,
     `var isElevated = false` (« accès élevé » local, voir Incertitudes) ; projections
     `var currentSession: SessionResponseDto? { sessions.first(where: \.current) }` et
     `var otherSessions: [SessionResponseDto] { sessions.filter { !$0.current } }`.
   - Actions : `func load() async` (`isLoading`, `client.getSessions()`, `current` en tête puis `updatedAt` décroissant,
     `errorMessage = error.localizedDescription` en `catch`), `func revoke(_ session: SessionResponseDto) async` (garde
     `guard !session.current else { return }`, puis `client.deleteSession(id:)` + `await load()`),
     `func revokeAllOthers() async` (`client.deleteAllSessions()` + `await load()`), `func lockCurrentSession() async`
     (`client.lockAuthSession()` puis `isElevated = false`), `func unlock(pinCode: String) async` (`guard pinCode.count ==
     6`, `client.unlockAuthSession(pinCode:)` puis `isElevated = true`), `func clearError()`.
   - Présentation, sans dupliquer un formateur existant : `func lastSeenText(for session: SessionResponseDto) -> String`
     (relatif via `RelativeDateTimeFormatter` — `LongDateFormatter` du dépôt ne fait que du parsing ISO,
     `Sources/Core/Utilities/LongDateFormatter.swift:11-35`),
     `func lastSeenAbsoluteText(for session: SessionResponseDto) -> String` (via
     `updatedAt.formatted(date: .abbreviated, time: .shortened)`), et
     `func deviceSymbol(for session: SessionResponseDto) -> String` qui reprend la table de `DeviceCard.svelte`
     (`macOS`/`iOS` → `apple.logo`, `Android` → `smartphone`, `Windows` → `pc`, `Linux`/`Ubuntu` → `desktopcomputer`,
     `deviceType` Chrome/Chromium/`Chrome OS` → `globe`, `Google Cast` → `airplayvideo`, sinon `questionmark.circle`).
3. **L'écran** — NEW `Sources/Features/Security/DeviceSessionsView.swift` : `import SwiftUI`,
   `struct DeviceSessionsView: View` prenant `@Bindable var vm: DeviceSessionsViewModel`, avec
   `@State private var showRevokeAllConfirm = false`, `@State private var showUnlock = false`, `@State private var pin = ""`.
   - Corps : `List` en deux sections — « This device » (`vm.currentSession`) et « Other devices » (`vm.otherSessions` en
     `ForEach`, chaque ligne portant
     `.swipeActions(edge: .trailing, allowsFullSwipe: false) { Button("Log Out", role: .destructive) { Task { await vm.revoke(session) } } }`),
     ligne = `Label(session.deviceOS, systemImage: vm.deviceSymbol(for: session))` + `VStack` type/version +
     `vm.lastSeenText(for: session)` / `vm.lastSeenAbsoluteText(for: session)`, et
     `if session.current { Text("This device") }` (miroir de `DeviceCard.svelte`).
   - Toolbar : bouton cadenas (`systemImage: vm.isElevated ? "lock.open" : "lock"`) appelant `lockCurrentSession()` en tâche
     ou armant `showUnlock = true`, et bouton « Log out other devices » (`role: .destructive`,
     `.disabled(vm.otherSessions.isEmpty)`) armé par `showRevokeAllConfirm`.
   - Modificateurs : `.navigationTitle("Connected Devices")`, `.navigationBarTitleDisplayMode(.inline)`,
     `.task { await vm.load() }`, `.refreshable { await vm.load() }`, `.alert("Unlock", isPresented: $showUnlock)` contenant
     `TextField("PIN", text: $pin).keyboardType(.numberPad)` et appelant `await vm.unlock(pinCode: pin)`,
     `.confirmationDialog` pour la révocation massive, et une ligne d'erreur sur `vm.errorMessage` qui appelle
     `vm.clearError()`. **Aucun `NavigationStack`** (poussée depuis `ProfileView`, qui en porte un).
   - Identifiants, posés sur les éléments interactifs et jamais sur un conteneur : `deviceSessionsList`,
     `deviceSessionRow_<id>`, `deviceSessionsLockButton`, `deviceSessionsRevokeAllButton`, `deviceSessionsUnlockField`,
     `deviceSessionsUnlockConfirm`.
4. **Le protocole client** — EDIT `Sources/Core/Protocols/ImmichClient.swift` : après la section Admin API keys (`:246`),
   ajouter `// MARK: - Sessions (gap G19)` puis `func getSessions() async throws -> [SessionResponseDto]`,
   `func deleteSession(id: String) async throws`, `func deleteAllSessions() async throws`,
   `func lockAuthSession() async throws`, `func unlockAuthSession(pinCode: String) async throws`.
5. **Les chemins** — EDIT `Sources/Core/Constants.swift` : dans `enum ImmichAPI`, après `apiKeys` (`:31`), ajouter
   `static let sessions = SubPath(root: "/sessions") // G19 (device sessions)`,
   `static let sessionLock = SubPath(root: "/auth/session/lock") // G19` et
   `static let sessionUnlock = SubPath(root: "/auth/session/unlock") // G19`.
6. **L'implémentation HTTP** — EDIT `Sources/Services/ImmichAPIClient.swift` : après `deleteAPIKey` (`:584-586`), ajouter
   les cinq méthodes — `getSessions()` → `try await sendAuthed(.GET, path: ImmichAPI.sessions.path(""))` ;
   `deleteSession(id:)` → `_ = try await sendAuthedRaw(.DELETE, path: ImmichAPI.sessions.path("/\(id)"), body: nil)` ;
   `deleteAllSessions()` → `_ = try await sendAuthedRaw(.DELETE, path: ImmichAPI.sessions.path(""), body: nil)` ;
   `lockAuthSession()` → `_ = try await sendAuthedRaw(.POST, path: ImmichAPI.sessionLock.path(""), body: nil)` ;
   `unlockAuthSession(pinCode:)` →
   `_ = try await sendAuthedRaw(.POST, path: ImmichAPI.sessionUnlock.path(""), body: AnyEncodable(SessionUnlockDto(pinCode: pinCode)))`.
   Aucune n'utilise `sendNoAuth` : elles partagent la gestion 401 déjà en place.
7. **L'injection** — EDIT `Sources/DependencyContainer.swift` : après `makeLanguageSettingsViewModel()` (`:223-228`),
   ajouter
   `func makeDeviceSessionsViewModel() -> DeviceSessionsViewModel { DeviceSessionsViewModel(client: client as any ImmichClient) }`
   — même patron que `makeDuplicatesViewModel` (`:205-207`).
8. **Le câblage racine** — EDIT `Sources/RootView.swift` : déclarer
   `@State private var deviceSessions: DeviceSessionsViewModel` après `language` (`:107`), l'initialiser après
   `_notifications = State(initialValue: container.makeNotificationsViewModel())` (`:134`) par
   `_deviceSessions = State(initialValue: container.makeDeviceSessionsViewModel())`, et passer
   `deviceSessions: deviceSessions` à l'appel `ProfileView(...)` du `.sheet(isPresented: $showProfile)` (`:234`).
9. **Le point d'entrée** — EDIT `Sources/Features/Profile/ProfileView.swift` : ajouter
   `@State var deviceSessions: DeviceSessionsViewModel` après `language` (`:22`), puis dans la section Security,
   **immédiatement après** le `Toggle("Require Face ID")` (`:132-137`) et avant le `footer`, la ligne
   `NavigationLink { DeviceSessionsView(vm: deviceSessions) } label: { Label("Connected Devices", systemImage: "laptopcomputer.and.iphone") }`
   portant `.accessibilityIdentifier("deviceSessionsRow")`. Ancrage délibéré : la session est un objet de sécurité, pas un
   écran de bibliothèque, et le web range `DeviceCard` sous les réglages de sécurité du compte.
10. **Les tests du ViewModel** — NEW `Tests/DeviceSessionsViewModelTests.swift` : `import XCTest`,
    `@testable import ImmichSwiftUI`, `final class DeviceSessionsViewModelTests: XCTestCase` `@MainActor`, en réutilisant
    `MockImmichClient` (`Tests/Mocks/`). Huit cas : `test_load_populatesSessionsAndFlagsCurrent`,
    `test_load_failure_surfacesErrorMessageAndKeepsListEmpty`, `test_revoke_sendsDeleteForTheGivenIdAndReloads`,
    `test_revoke_ignoresTheCurrentSession`, `test_revokeAllOthers_deletesWithoutIdAndReloads`, `test_lock_clearsElevation`,
    `test_unlock_rejectsPinShorterThanSixDigitsWithoutCallingTheClient`, `test_unlock_withSixDigitPin_raisesElevation`.
11. `xcodegen generate` (trois fichiers source et un fichier de test sont ajoutés : sans régénération ils ne sont pas
    compilés), puis suite complète `-only-testing:ImmichSwiftUITests`.

## Incertitudes à lever à l'implémentation

- **L'état d'élévation n'est exposé par aucun champ.** `SessionResponseDto` ne porte ni `pinExpiresAt` ni booléen équivalent
  (vérifié dans `/tmp/immich-openapi-main.json`), alors qu'`AuthService.unlockSession` pose un TTL serveur de 15 min :
  `isElevated` est donc un état **local optimiste**, faux au lancement. Vérifier qu'aucun champ n'a été ajouté entre-temps
  par :
  `python3 -c "import json;d=json.load(open('/tmp/immich-openapi-main.json'));print(list(d['components']['schemas']['SessionResponseDto']['properties']))"`.
- **Le PIN exact attendu.** La description du DTO dit « 4-6 digits » mais son `pattern` est `^\d{6}$`, et l'app ne peut pas
  savoir combien de chiffres le compte a choisi : le champ n'accepte que 6 chiffres et l'erreur serveur est affichée telle
  quelle. Vérifier par :
  `curl -s https://raw.githubusercontent.com/immich-app/immich/main/server/src/services/auth.service.ts | grep -n -A 12 "async unlockSession"`.
- **Le comportement en compte par clé API.** `lockSession` / `unlockSession` lèvent `BadRequestException` sans token de
  session ; l'app a un mode multi-comptes (`Sources/Core/Types/SavedAccount.swift`) dont certains comptes peuvent être
  configurés par clé. Le VM affiche le message serveur sans traitement spécial ; si le 400 s'avère fréquent, masquer les
  deux contrôles. Vérifier par :
  `curl -s https://raw.githubusercontent.com/immich-app/immich/main/server/src/services/auth.service.ts | grep -n "can only be used with a session token"`.
- **Le champ `expiresAt`.** Absent de `required` ⇒ optionnel ; si le serveur renvoie `null` (session créée sans `duration`,
  cf. `SessionService.create`), la ligne de détail ne doit pas afficher de section expiration vide. Vérifier par :
  `grep -n "expiresAt" Sources/Features/Security/DeviceSessionsView.swift`.
- **Le libellé des chaînes.** La clé du catalogue est la chaîne anglaise (`Resources/Localizable.xcstrings`,
  `sourceLanguage = en`) : « Connected Devices », « This device », « Other devices », « Log out other devices », « Last seen »,
  « Log Out », « Unlock », « PIN », « Unknown ». Si une clé proche existe déjà, la réutiliser. Vérifier par :
  `python3 -c "import json;d=json.load(open('Resources/Localizable.xcstrings'));print([k for k in d['strings'] if 'Device' in k or 'session' in k.lower()])"`.
- **L'icône de la ligne du hub.** `laptopcomputer.and.iphone` (iOS 16+) doit être confirmée pour la cible de déploiement du
  projet ; `ipad.and.iphone` ou `rectangle.stack.badge.person.crop` sont les replis. Aucune commande ne tranche un choix
  d'icône : contrôle visuel au build, puis décision de revue.
- **Le tri des lignes.** L'upstream affiche la liste dans l'ordre du serveur (`sessionRepository.getByUserId`) ; ici la
  session courante est isolée dans sa propre section et les autres sont triées par `updatedAt` décroissant. Si l'ordre
  serveur s'avère stable et plus lisible, s'y aligner. Vérifier par :
  `grep -n "sorted" Sources/Features/Security/DeviceSessionsViewModel.swift`.

