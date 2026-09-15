# Task: locked-folder

> **Audit 2026-09-15 — écart G12** : l'app ne sait ni poser ni lire la visibilité `locked` — `AssetVisibility` porte bien les quatre cas `archive|timeline|hidden|locked` (`Sources/Core/Constants.swift:66-71`) et `AssetBulkUpdateDto.visibility` est déjà typé dessus (`Sources/Core/Types/DTOs.swift:265`), mais un `grep '\.locked' Sources/ Tests/` ne renvoie que la déclaration du cas : aucun appelant n'écrit ni ne lit jamais `locked`.
> Upstream le fait, et le PIN n'y est PAS local : l'OpenAPI `main` expose `POST /api/auth/session/unlock` (« Temporarily grant the session elevated access to locked assets by providing the correct PIN code », `/tmp/immich-openapi-main.json:5974`), `POST /api/auth/session/lock` (« Remove elevated access to locked assets from the current session », `:5932`), `POST /api/auth/pin-code` (`PinCodeSetupDto.pinCode`, pattern `^\d{6}$`, `:25095`) et `GET /api/auth/status` → `AuthStatusResponseDto.isElevated` (`:21180-21209`).
> Le client Flutter s'y adosse également : `mobile/lib/routing/locked_guard.dart`, `mobile/lib/pages/library/locked/pin_auth.page.dart` et le plugin `pinput` (`mobile/pubspec.yaml`) autour de `mobile/lib/presentation/pages/locked_folder.page.dart`.

**Objectif** : l'utilisateur peut, depuis la timeline, déplacer les photos et vidéos sélectionnées dans un dossier verrouillé — elles quittent la timeline et ne sont lisibles nulle part ailleurs — puis rouvrir ce dossier depuis « Me » → Security après avoir saisi son PIN Immich à 6 chiffres (ou validé Face ID s'il l'a autorisé).
Le dossier affiche sa propre grille, permet de resélectionner des éléments et de les remettre dans la timeline, et se reverrouille dès que l'app passe en arrière-plan.

**Hors périmètre** :
- La purge globale de l'élévation de session au passage en arrière-plan quand l'utilisateur est ailleurs dans l'app : le serveur gère lui-même l'expiration (`AuthStatusResponseDto.pinExpiresAt`) et l'App Lock existant protège déjà l'app entière.
- La réinitialisation du PIN depuis un mot de passe oublié (route de reset non vérifiée, voir Incertitudes) : le dossier se contente de remonter l'erreur du serveur.
- L'upload direct dans le dossier verrouillé, le partage ou l'édition d'un asset verrouillé, la recherche à l'intérieur du dossier : la grille ouvre le viewer existant en lecture seule.
- Le contenu du dossier dans les widgets, les Memories et les App Intents : hors de la requête par défaut du serveur, rien à faire.

**Hypothèses** (vérifiées dans le dépôt et contre `immich-app/immich@main`, le 2026-09-15) :

- `AssetVisibility` est un `enum … String, Codable, CaseIterable, Sendable` qui porte déjà les quatre cas — `archive`, `timeline`, `hidden`, `locked` :
  `Sources/Core/Constants.swift:66-71`. Le cas `locked` est donc décodable sans toucher au type.
- Le DTO d'écriture est prêt : `struct AssetBulkUpdateDto: Codable, Equatable { let ids: [String]; var visibility: AssetVisibility? }` —
  `Sources/Core/Types/DTOs.swift:254-267` —, exposé par `func bulkUpdateAssets(dto: AssetBulkUpdateDto) async throws` (`Sources/Core/Protocols/ImmichClient.swift:251-252`), donc `PUT /api/assets`.
- Les deux usages actuels de ce DTO passent `.archive` et retirent les items de la liste locale :
  `Sources/Features/Timeline/TimelineViewModel.swift:134-151`. Le chemin « sortir de la timeline » existe déjà, seule la valeur change pour le dossier verrouillé.
- La lecture est déjà paramétrable : `getTimeBuckets(isFavorite:isTrashed:personId:withPartners:visibility:withStacked:)` et `getTimeBucket(...)` —
  `Sources/Core/Protocols/ImmichClient.swift:30-45` —, et l'OpenAPI documente ce query comme « Filter by asset visibility status (ARCHIVE, TIMELINE, HIDDEN, LOCKED) » (`/tmp/immich-openapi-main.json:15969-15973`, `:16158-16162`).
- `TimelineViewModel.filterVisibility: String?` (`Sources/Features/Timeline/TimelineViewModel.swift:25`) est transmis tel quel aux deux appels (`:161`, `:213`) :
  lire `"locked"` ne demande donc aucune extension de type, seulement un ViewModel qui le fixe.
- Le PIN est serveur, pas client : `POST /api/auth/pin-code` (`PinCodeSetupDto`, 6 chiffres), `PUT /api/auth/pin-code` (`PinCodeChangeDto`),
  `POST /api/auth/session/unlock` (`SessionUnlockDto { pinCode?, password? }`, `/tmp/immich-openapi-main.json:27613-27626`), `POST /api/auth/session/lock`,
  `GET /api/auth/status` (`AuthStatusResponseDto { expiresAt?, isElevated, password, pinCode, pinExpiresAt? }`, `:21180-21209`).
- Aucune de ces cinq routes n'existe côté iOS : `grep -n getAuthStatus Sources/` ne renvoie rien, `ImmichClient` n'a que `login` / `logout` / `validateToken` (`Sources/Core/Protocols/ImmichClient.swift`),
  et `ImmichAPIClient` n'appelle `ImmichAPI.auth.path(...)` que pour `"/logout"` et `"/validateToken"` (`Sources/Services/ImmichAPIClient.swift:81-87`).
- Convention de stockage local pour un PIN rejouable par Face ID : `protocol KeychainStore` expose le trio par compte `saveToken(_:for:)` / `getToken(for:)` / `deleteToken(for:)` —
  `Sources/Core/Protocols/KeychainStore.swift:10-25`.
- `KeychainStoreImpl` (service `app.immich.swiftui`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) supprime l'entrée avant d'écrire et traite `errSecItemNotFound` comme un succès :
  `Sources/Services/KeychainStoreImpl.swift:30-62`. Rotation et purge sont idempotentes, aucun cas d'erreur à gérer.
- Évaluateur biométrique réutilisable : `AppLockViewModel.systemEvaluator`, `static let` de type `@Sendable () async -> Bool`, politique `.deviceOwnerAuthentication` —
  `Sources/Features/Auth/AppLockViewModel.swift`.
- `AppLockService` n'a AUCUNE notion de PIN — seulement `isLocked`, `isEnabled`, `isAuthenticating`, `authenticate()`, `setEnabled(_:)`, `lock()` —
  `Sources/Core/Protocols/AppLockService.swift` — et son état est process-wide : `RootView` superpose un `LockView` dès que `appLock.isEnabled && appLock.isLocked` (`Sources/RootView.swift:27`, `:59-62`, `:273-292`).
- Surface d'entrée : `struct ProfileView: View` (`Sources/Features/Profile/ProfileView.swift:6`) est présenté en `.sheet` par `RootView` (`Sources/RootView.swift:233-234`), reçoit ses ViewModels en `let` (`TrashView(vm: trash)`, l.57) et sa section `Security` (l.131-141) contient le seul toggle d'App Lock (`appLockToggle`).
  Les vues poussées y vivent dans la pile de la sheet, sans `NavigationStack` propre.
- Grille réutilisable : `AssetThumbnailCell` prend `onDelete` / `onArchive` en closures optionnelles (`Sources/Features/Timeline/AssetThumbnailCell.swift:28-29`) et n'impose aucun ViewModel ;
  la toolbar de sélection de la timeline est une suite de boutons `.labelStyle(.iconOnly)` (`Sources/Features/Timeline/TimelineView.swift:564-573`).
- Fabriques : `DependencyContainer` est un singleton `@MainActor` (`Sources/DependencyContainer.swift:11-12`) qui expose des `make*ViewModel()`, certains prenant un contexte d'exécution —
  `makeAlbumDetailViewModel(albumId:)` `:112`, `makeSharedLinkViewerViewModel(baseURL:externalDomain:)` `:123` — et `RootView` détient `auth: AuthViewModel` (`Sources/RootView.swift:11`), donc `auth.activeAccountID` (mentionné l.8) est disponible au point d'injection.
- i18n : le catalogue est `Resources/Localizable.xcstrings`, `sourceLanguage = en`, la clé EST la chaîne anglaise, avec fr/de/es/it pour chaque clé porteuse de mots.
- MVVM strict : `ImmichClient` (protocole) → `ImmichAPIClient` (implémentation) → `DependencyContainer.make*ViewModel()` → ViewModel `@Observable @MainActor` → vue stateless, sans `NavigationStack` quand elle est poussée.

**Approche retenue** : A — gate local adossé à l'élévation SERVEUR.
Un `LockedFolderViewModel` neuf interroge `GET /api/auth/status`, pose le PIN via `POST /api/auth/pin-code` quand `pinCode == false`, appelle `POST /api/auth/session/unlock` avec les 6 chiffres, puis lit `GET /api/timeline/buckets?visibility=locked` ; Face ID ne sert qu'à rejouer un PIN mémorisé dans le Keychain.

- **B (rejetée)** : gate purement local, PIN haché dans le Keychain et aucune route `/auth/session/*` → l'OpenAPI montre que l'accès élevé est un état de SESSION (`AuthStatusResponseDto.isElevated`, `POST /api/auth/session/unlock`) :
  un gate local n'ouvre aucune donnée, `GET /api/timeline/buckets?visibility=locked` répondrait selon l'élévation réelle, donc le dossier serait vide ou contournable au curl — beaucoup de code (stockage, comparaison, écran de saisie) pour zéro effet.
- **C (rejetée)** : réutiliser `AppLockService` / `AppLockViewModel` comme gate du dossier → son état est global (l'overlay de `RootView`, `Sources/RootView.swift:59-62`) et son API n'offre qu'un `authenticate()` sans PIN (`Sources/Core/Protocols/AppLockService.swift`) :
  déverrouiller le dossier déverrouillerait toute l'app, donc aucun sous-ensemble protégé ; y greffer un second état plus un PIN obligerait à modifier un contrat partagé par l'App Lock, les widgets et `MockAppLockService` — couplage plus coûteux qu'un ViewModel dédié.

## Étapes
1. **DTOs d'authentification** — EDIT `Sources/Core/Types/DTOs.swift` : aucun de ces types n'existe (grep `AuthStatusResponseDto` dans `Sources/` : 0 occurrence).
   - `struct AuthStatusResponseDto: Codable, Equatable { let expiresAt: String?; let isElevated: Bool; let password: Bool; let pinCode: Bool; let pinExpiresAt: String? }` — les trois champs requis par l'OpenAPI sont non optionnels.
   - `struct PinCodeSetupDto: Codable { let pinCode: String }`.
   - `struct PinCodeChangeDto: Codable { let newPinCode: String; var pinCode: String?; var password: String? }`.
   - `struct SessionUnlockDto: Codable { var pinCode: String?; var password: String? }` — les optionnels `nil` ne sont pas encodés, donc `SessionUnlockDto(pinCode: pin)` ne poste que le PIN.
2. **Contrat client** — EDIT `Sources/Core/Protocols/ImmichClient.swift` : ajouter une section `// MARK: - Locked folder (G12)` déclarant cinq méthodes.
   - `func getAuthStatus() async throws -> AuthStatusResponseDto`.
   - `func setupPinCode(_ pinCode: String) async throws`.
   - `func changePinCode(dto: PinCodeChangeDto) async throws`.
   - `func unlockAuthSession(pinCode: String) async throws`.
   - `func lockAuthSession() async throws`.
3. **Implémentation transport** — EDIT `Sources/Services/ImmichAPIClient.swift` : les cinq corps, sur le modèle `logout()` (`:81-83`), avec `ImmichAPI.auth.path(...)` (`Sources/Core/Constants.swift:4-7`).
   - `GET "/status"`, `POST "/pin-code"` (corps `AnyEncodable(PinCodeSetupDto(pinCode:))`), `PUT "/pin-code"` (corps `PinCodeChangeDto`), `POST "/session/unlock"` (corps `SessionUnlockDto`), `POST "/session/lock"` sans corps.
   - Les trois appels à 204 sont des `async throws` sans valeur de retour, comme `deleteSharedLink(id:)` (`ImmichAPIClient.swift:262`).
4. **Protocole du PIN mémorisé** — NEW `Sources/Core/Protocols/LockedFolderPINStoring.swift` :
   `protocol LockedFolderPINStoring: AnyObject, Sendable { func storedPIN(for account: String) -> String?; @discardableResult func storePIN(_ pin: String, for account: String) -> Bool; @discardableResult func clearPIN(for account: String) -> Bool }`.
   - Type distinct de `KeychainStore` pour que le ViewModel ne voie jamais de sémantique de token, et pour rester stubbable sans toucher au Keychain.
5. **Implémentation Keychain** — NEW `Sources/Services/KeychainLockedFolderPINStore.swift` :
   `final class KeychainLockedFolderPINStore: LockedFolderPINStoring`, `init(keychain: KeychainStore)`, account construit en `"lockedFolderPIN." + accountID`.
   - Délègue à `saveToken(_:for:)` / `getToken(for:)` / `deleteToken(for:)` (`Sources/Core/Protocols/KeychainStore.swift:19-25`) : hérite de `.whenUnlockedThisDeviceOnly` et de la purge idempotente de `KeychainStoreImpl`.
6. **ViewModel du dossier** — NEW `Sources/Features/LockedFolder/LockedFolderViewModel.swift` : `@Observable @MainActor final class LockedFolderViewModel`.
   - `init(client: ImmichClient, pins: LockedFolderPINStoring, accountID: String, evaluator: @Sendable () async -> Bool = AppLockViewModel.systemEvaluator, biometricsAvailable: @Sendable () -> Bool = { var e: NSError?; let c = LAContext(); return c.canEvaluatePolicy(.deviceOwnerAuthentication, error: &e) })`.
   - État : `enum Gate { case needsSetup, locked, unlocked }` + `var gate: Gate`, `pinEntry`, `confirmationEntry`, `rememberPIN: Bool`, `isBusy`, `failedAttempts`, `errorMessage`, `buckets: [TimeBucketsResponseDto]`, `items: [AssetReactItem]`, `selectedIds: Set<String>`, `bucketIndex`, `isLoadingMore`.
   - `refreshGate()` : `try await client.getAuthStatus()` → `.unlocked` si `isElevated`, sinon `pinCode ? .locked : .needsSetup` ; appelée à l'apparition de la vue.
   - `setupPIN()` : garde `pinEntry.count == 6 && pinEntry == confirmationEntry`, puis `client.setupPinCode(pinEntry)` + `client.unlockAuthSession(pinCode: pinEntry)`, puis `pins.storePIN(pinEntry, for: accountID)` si `rememberPIN`.
   - `submitPIN()` : `client.unlockAuthSession(pinCode: pinEntry)` → `gate = .unlocked`, `failedAttempts = 0`, `pinEntry = ""` ; en échec `failedAttempts += 1`, `pinEntry = ""`, message d'erreur, saisie refusée au-delà de 5 échecs.
   - `unlockWithBiometrics()` : `guard let pin = pins.storedPIN(for: accountID), await evaluator()` puis `client.unlockAuthSession(pinCode: pin)` — le PIN mémorisé est rejoué, jamais un accès direct.
   - `relock()` : `gate = .locked`, `items = []`, `buckets = []`, `selectedIds = []`, `try? await client.lockAuthSession()`.
   - `loadFirstPage()` / `loadMore()` : même mécanique que `TimelineViewModel` (`Sources/Features/Timeline/TimelineViewModel.swift:161-165` puis `:213-216`) avec `visibility: "locked"` et `AssetReactItem.zip(columnar)`.
   - `restoreSelectionToTimeline()` : `client.bulkUpdateAssets(dto: AssetBulkUpdateDto(ids: Array(selectedIds), visibility: .timeline))`, puis retrait local des items, sur le modèle de `archiveSelected()` (`:134-141`).
7. **Vue du dossier** — NEW `Sources/Features/LockedFolder/LockedFolderView.swift` : `struct LockedFolderView: View { let vm: LockedFolderViewModel }` — **aucun `NavigationStack`** (poussée dans la pile de la sheet « Me », comme `TrashView`).
   - `gate == .needsSetup` → `private struct LockedFolderSetupView` : `SecureField` en `.keyboardType(.numberPad)`, champs saisie + confirmation, `Toggle("Unlock with Face ID")` affiché seulement si disponible, bouton `lockedFolderCreatePINButton`.
   - `gate == .locked` → `private struct LockedFolderPINView` : `SecureField`, bouton `lockedFolderUnlockButton`, bouton biométrique `lockedFolderBiometricButton` (masqué dès que `failedAttempts` atteint le plafond), `Text` d'erreur.
   - `gate == .unlocked` → `ScrollView` + `LazyVGrid` de `AssetThumbnailCell` réutilisé avec ses callbacks par défaut (`Sources/Features/Timeline/AssetThumbnailCell.swift:28-29`), compteur d'éléments, bouton toolbar « Move back to timeline » (`restoreFromLockedFolderButton`, désactivé si `selectedIds.isEmpty`), état vide, `.refreshable`, bouton explicite « Lock now » (`lockNowButton`).
   - Les `accessibilityIdentifier` sont posés sur chaque élément interactif, jamais sur un conteneur (un identifiant de conteneur écrase celui de ses descendants).
8. **Reverrouillage à l'arrière-plan** — EDIT `Sources/Features/LockedFolder/LockedFolderView.swift` : `@Environment(\.scenePhase)` + `.onChange(of: scenePhase) { _, phase in if phase != .active { Task { await vm.relock() } } }`.
   - Pas de `relock()` sur `onDisappear` : pousser le viewer d'un asset depuis la grille fait disparaître la vue source dans la pile, ce qui redemanderait le PIN après chaque photo — le bouton « Lock now » couvre l'intention explicite.
9. **Sortie de la timeline** — EDIT `Sources/Features/Timeline/TimelineViewModel.swift` :
   ajouter `moveSelectedToLockedFolder()` et `moveToLockedFolder(id:)`, copiées sur `archiveSelected()` / `archive(id:)` (`:134-151`) avec `visibility: .locked`, mêmes `items.removeAll`, `loadedIds.subtract` et `exitSelectionMode()`.
10. **Points d'entrée timeline** — EDIT `Sources/Features/Timeline/TimelineView.swift` :
    dans la toolbar de sélection (l.564-573), ajouter après « Archive » un bouton `Label("Move to Locked Folder", systemImage: "lock")`, `.accessibilityIdentifier("moveToLockedFolderButton")`, `.disabled(vm.selectedIds.isEmpty)`.
    - EDIT `Sources/Features/Timeline/AssetThumbnailCell.swift` : ajouter `var onMoveToLockedFolder: (() -> Void)? = nil` à côté de `onArchive` (l.29) et un item de menu contextuel après celui d'Archive (l.114-120), rendu uniquement si la closure est fournie.
    - Ne PAS ajouter d'option `locked` au menu de filtre de la timeline (`TimelineView.swift:588-621` : All / Favorites / Archived / Shared with you) : le dossier verrouillé n'est pas un filtre de la timeline.
11. **Entrée depuis le hub « Me »** — EDIT `Sources/Features/Profile/ProfileView.swift` :
    ajouter `let lockedFolder: LockedFolderViewModel` à la liste des propriétés, puis, dans la section `Security` (l.131-141), un `NavigationLink { LockedFolderView(vm: lockedFolder) } label: { Label("Locked Folder", systemImage: "lock") }` avec `.accessibilityIdentifier("lockedFolderRow")`, placé avant le `Toggle("Require Face ID", …)`.
    - Enrichir le footer de la section : l'App Lock protège l'app entière, le dossier verrouillé a son propre PIN.
12. **Câblage conteneur** — EDIT `Sources/DependencyContainer.swift` :
    `let lockedFolderPINs: LockedFolderPINStoring`, initialisé par `KeychainLockedFolderPINStore(keychain: keychain)` près de `self.appLock = AppLockViewModel()` (l.62), puis `func makeLockedFolderViewModel(accountID: String) -> LockedFolderViewModel` à côté de `makeStorageStatsViewModel()` (l.131).
13. **Injection dans la sheet** — EDIT `Sources/RootView.swift` :
    compléter l'appel `ProfileView(...)` (l.234) avec `lockedFolder: container.makeLockedFolderViewModel(accountID: auth.activeAccountID)`.
14. **i18n** — EDIT `Resources/Localizable.xcstrings` :
    ajouter les clés anglaises neuves avec fr/de/es/it — `Locked Folder`, `Move to Locked Folder`, `Move back to timeline`, `Lock now`, `Unlock`, `Create a PIN`, `Confirm PIN`, `Unlock with Face ID`, `6 digits`, `Wrong PIN`, `Too many attempts`, `Nothing in your locked folder` (la clé EST la chaîne anglaise, `sourceLanguage = en`).
15. **Doubles et tests** — EDIT `Tests/Mocks/MockImmichClient.swift` :
    implémenter les cinq méthodes neuves avec réponses cannelées et état capturé (`authStatus`, `unlockedPINs: [String]`, `lockSessionCallCount`, `bulkUpdateCalls`).
    - NEW `Tests/LockedFolderViewModelTests.swift` avec `private final class StubPINStore: LockedFolderPINStoring` (dictionnaire en mémoire).
    - Cas couverts : `refreshGate()` sur les trois états (`isElevated` vrai, `pinCode == false`, sinon), refus d'un PIN de 5 chiffres et d'une confirmation divergente, succès d'`unlockAuthSession` qui bascule en `.unlocked` et charge les items, échec qui incrémente `failedAttempts` sans changer de gate, `unlockWithBiometrics()` (évaluateur appelé une fois, PIN rejoué depuis le stub), `restoreSelectionToTimeline()` qui émet bien `AssetBulkUpdateDto(visibility: .timeline)`.
16. `xcodegen generate` (fichiers ajoutés aux étapes 4, 5, 6, 7 et 15) puis suite complète `-only-testing:ImmichSwiftUITests`.

## Incertitudes à lever à l'implémentation
- Route du reset du PIN : le schéma `PinCodeResetDto` existe (`/tmp/immich-openapi-main.json:25083`) mais sa route n'a pas été vérifiée → `jq -r '.paths | to_entries[] | select(.key|test("pin-code")) | .key + " " + (.value|keys|join(","))' /tmp/immich-openapi-main.json`.
- Réponse du serveur à `GET /api/timeline/buckets?visibility=locked` quand la session n'est PAS élevée (403, ou liste vide) : si c'est une liste vide, le gate doit rester piloté par `AuthStatusResponseDto.isElevated` et jamais par le contenu de la réponse → `curl -H "x-api-key: …" "$IMMICH/api/timeline/buckets?visibility=locked"` avant et après `POST /api/auth/session/unlock` sur un serveur réel.
- `AssetBulkUpdateDto.visibility` est-il encore non déprécié ? Plusieurs schémas portent `"deprecated": true` sur `visibility` (`:24047`, `:26330`, `:28560`) mais pas ceux des lignes `:19931` / `:20545` → `jq '.components.schemas.AssetBulkUpdateDto.properties.visibility' /tmp/immich-openapi-main.json`.
- `sendAuthed` tolère-t-il un `204` sans corps pour un `async throws` sans valeur (seul précédent vérifié : `deleteSharedLink`, `ImmichAPIClient.swift:262`) → rejouer `ImmichAPIClientTests` après l'étape 3.
- Un `SecureField` porte-t-il bien son `accessibilityIdentifier` jusqu'aux XCUITest sur ce projet, ou faut-il viser `secureTextFields[...]` → `grep -rn "secureTextFields" UITests/`.
- Le `localizedReason` de `AppLockViewModel.systemEvaluator` utilise `String(localized: "Unlock PhotoVault")` : la clé existe-t-elle dans le catalogue, et faut-il un libellé distinct pour le dossier ? → `grep -n "Unlock PhotoVault" Resources/Localizable.xcstrings`.
- `Tests/ImmichAPIClientTests.swift` énumère-t-il les méthodes du protocole (il casserait à l'étape 2) → `grep -n "ImmichClient" Tests/ImmichAPIClientTests.swift`.
