# Task: change-password

Status: planifié — **aucune AC ouverte** (écart G18 du registre `.omp/backlog/ImmichSwiftUI-backlog.md`).

## Plan (résumé)

**Objectif** : l'utilisateur connecté ouvre « Me » → section Security → « Change Password », saisit son mot
de passe actuel, le nouveau (deux fois), choisit ou non la déconnexion des autres appareils, valide : le
serveur applique le changement (`POST /api/auth/change-password`), l'app confirme et remet le drapeau
`shouldChangePassword` à `false`. Quand le serveur signale `shouldChangePassword` à la connexion (mot de
passe réinitialisé par un administrateur), la même section Security affiche un avertissement qui mène à cet
écran.

**Approche retenue** : A — deux fichiers neufs dans `Sources/Features/Security/` (`ChangePasswordViewModel`
`@MainActor @Observable` + `ChangePasswordView` stateless), deux méthodes ajoutées au protocole
`ImmichClient` et à `ImmichAPIClient` (`changePassword`, `currentUser`), le drapeau `shouldChangePassword`
porté par `AuthViewModel` (rempli au login depuis `LoginResponseDto`, rafraîchi depuis
`UserAdminResponseDto`, remis à `false` après succès), et une ligne `NavigationLink` insérée **dans la
section Security existante** de `ProfileView` (`Sources/Features/Profile/ProfileView.swift:130-141`).

**Alternative B (rejetée)** : présenter la feuille automatiquement au login depuis `AuthenticatedRoot` —
`RestoreSession`/`restoreSession()` ne relit pas le drapeau, l'avertissement deviendrait un événement unique
non rejouable, et l'écran viendrait concurrencer les deux présentations déjà portées par `AuthenticatedRoot`
(feuille `showProfile`, plein écran `AppLockViewModel`).

**Alternative C (rejetée)** : `changePassword(...)` sur `AuthViewModel` et formulaire en ligne dans
`ProfileView`, sans fichier neuf — ferait re-rendre tout l'arbre à chaque frappe (l'état d'auth globale est
observé par `RootView`) et contredit le patron « un ViewModel d'écran par écran » du conteneur.

**Étapes** : (1) EDIT `Sources/Core/Types/DTOs.swift` — `ChangePasswordDto` à trois champs ;
(2) EDIT `Sources/Core/Protocols/ImmichClient.swift` — `changePassword(currentPassword:newPassword:invalidateSessions:)`
retournant `UserAdminResponseDto` (le retour porte le `shouldChangePassword: false` serveur) ;
(3) EDIT `Sources/Services/ImmichAPIClient.swift` — `sendAuthed(.POST, path: ImmichAPI.auth.path('/change-password'))`
+ `currentUser()` sur `ImmichAPI.users.path('/me')` ; (4) NEW `Sources/Features/Security/ChangePasswordViewModel.swift` ;
(5) NEW `Sources/Features/Security/ChangePasswordView.swift` (sans `NavigationStack`) ;
(6) EDIT `Sources/DependencyContainer.swift` — `makeChangePasswordViewModel()` ;
(7) EDIT `Sources/RootView.swift` — `@State changePassword` passé à `ProfileView` ;
(8) EDIT `Sources/Features/Auth/AuthViewModel.swift` — drapeau `shouldChangePassword`, `notePasswordChanged()`,
`refreshShouldChangePassword()` ; (9) EDIT `Sources/Features/Profile/ProfileView.swift` — ligne
`changePasswordRow` + avertissement conditionnel + appel `auth.refreshShouldChangePassword()` dans le `.task` ;
(10) NEW `Tests/ChangePasswordViewModelTests.swift` + EDIT `Tests/Mocks/MockImmichClient.swift` ;
(11) `xcodegen generate` puis suite complète.

**Incertitudes** : libellé exact du message d'erreur d'un mot de passe actuel faux (le serveur jette un 400
`Wrong password`, pas un 401 : le mapping `APIError` → `errorMessage` reste à constater) ; libellé et icône
exacts de la ligne du hub ; défaut du `Toggle` « Sign out on other devices » (l'UI propose `true`, l'API
défaut à `false`) — voir `.omp/change-password/change-password.specs.md` § Incertitudes.

## Critères

```
### AC-5180 [type: new]
Assertion: le corps exact de la spec est déclaré (`ChangePasswordDto` à trois champs, deux requis), la méthode est ajoutée au protocole `ImmichClient` avec le retour `UserAdminResponseDto`, et l'implémentation poste sur la route réelle `/auth/change-password` avec les trois valeurs de la spec (sans nouveau cas dans l'enum `ImmichAPI`).
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs.swift; g=Sources/Core/Protocols/ImmichClient.swift; c=Sources/Services/ImmichAPIClient.swift; grep -qE "struct ChangePasswordDto" "$f" && grep -qE "let newPassword: String" "$f" && grep -qE "let invalidateSessions: Bool" "$f" && perl -0777 -ne "exit 1 unless /struct ChangePasswordDto[\s\S]{0,200}?let password: String/s" "$f" && perl -0777 -ne "exit 1 unless /func changePassword\(\s*currentPassword:\s*String,\s*newPassword:\s*String,\s*invalidateSessions:\s*Bool\s*\)\s*async throws\s*->\s*UserAdminResponseDto/" "$g" && grep -qE "ImmichAPI.auth.path\(.?/change-password" "$c" && grep -qE "ChangePasswordDto\(password: currentPassword, newPassword: newPassword, invalidateSessions: invalidateSessions\)" "$c" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -rn 'change-password' Sources/` ne renvoie rien ; `Sources/Core/Types/DTOs.swift:5` n'a que `LoginCredentialDto` ; `Sources/Core/Protocols/ImmichClient.swift:21-23` n'a que login/logout/validateToken)
Post-state attendu: PASS
Note: le chemin est visé par le préfixe déjà existant `ImmichAPI.auth.path(…)` (cf. `logout`, `ImmichAPIClient.swift:82`) — aucun `case` à ajouter à l'enum, et le retour n'est pas `Void` puisque c'est `UserAdminResponseDto` qui porte le drapeau retombé.
```

```
### AC-5181 [type: new]
Assertion: `currentUser()` (protocole + client) relit l'utilisateur courant sur `GET /api/users/me`, et le conteneur fabrique le ViewModel d'écran en lui prêtant la couture `ImmichClient` partagée.
Check post-impl: sh -c 'c=Sources/Services/ImmichAPIClient.swift; g=Sources/Core/Protocols/ImmichClient.swift; d=Sources/DependencyContainer.swift; grep -qE "func currentUser\(\) async throws -> UserAdminResponseDto" "$c" && grep -qE "ImmichAPI.users.path\(.?/me" "$c" && grep -qE "func currentUser\(\)" "$g" && grep -qE "func makeChangePasswordViewModel" "$d" && grep -qE "ChangePasswordViewModel\(client:" "$d" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -rn 'func currentUser' Sources/ Tests/` ne renvoie rien ; `grep -n 'func makeAuthViewModel' Sources/DependencyContainer.swift` = 81, aucune factory Security)
Post-state attendu: PASS
```

```
### AC-5182 [type: new]
Assertion: `ChangePasswordViewModel` est un `@Observable` d'écran dont la validation est locale et antérieure à tout réseau : `newPasswordTooShort` à la borne `minLength: 8` du contrat, `confirmationMismatch`, `newPasswordUnchanged`, et `canSubmit` qui exige les quatre conditions plus la non-réentrance.
Check post-impl: sh -c 'f=Sources/Features/Security/ChangePasswordViewModel.swift; test -f "$f" && grep -qE "@Observable" "$f" && grep -qE "final class ChangePasswordViewModel" "$f" && grep -qE "var currentPassword = " "$f" && grep -qE "var newPassword = " "$f" && grep -qE "var confirmPassword = " "$f" && grep -qE "var invalidateSessions = true" "$f" && grep -qE "var newPasswordTooShort" "$f" && grep -qE "newPassword.count < 8" "$f" && grep -qE "var confirmationMismatch" "$f" && grep -qE "var newPasswordUnchanged" "$f" && grep -qE "var canSubmit" "$f" && grep -qE "!isSubmitting" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`ls Sources/Features/Security` → No such file or directory ; aucun `ChangePassword*` dans `Sources/`)
Post-state attendu: PASS
Note: la borne `8` est celle de `ChangePasswordDto.newPassword` (`minLength: 8`) — la validation locale existe pour ne pas faire un aller-retour réseau sur une saisie impossible.
```

```
### AC-5183 [type: new]
Assertion: `submit()` est gardé par `canSubmit`, protège son état in-flight par `defer`, appelle le client avec les trois paramètres de la spec, vide les trois champs au succès en gardant les champs en cas d'échec (avec `errorMessage`), et expose `clearError()`/`resetForm()` à l'écran.
Check post-impl: sh -c 'f=Sources/Features/Security/ChangePasswordViewModel.swift; test -f "$f" && grep -qE "func submit\(\) async -> UserAdminResponseDto\?" "$f" && perl -0777 -ne "exit 1 unless /guard canSubmit else[^\n]*\{[^\n]*return nil/s" "$f" && grep -qE "isSubmitting = true" "$f" && grep -qE "defer \{ isSubmitting = false" "$f" && grep -qE "didSucceed = true" "$f" && perl -0777 -ne "exit 1 unless /client\.changePassword\(\s*currentPassword:/s" "$f" && grep -qE "errorMessage = error.localizedDescription" "$f" && grep -qE "func clearError\(\)" "$f" && grep -qE "func resetForm\(\)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: le succès n'est pas rejouable sans re-saisie — c'est le vidage des champs au succès qui le garantit, et c'est ce que vérifie `test_submit_clearsFieldsAndReportsSuccess` (AC-5188).
```

```
### AC-5184 [type: new]
Assertion: `ChangePasswordView` est stateless, ne déclare AUCUN `NavigationStack` (elle est poussée par `ProfileView`, qui en porte déjà un) et ne pose ses identifiants que sur les cinq éléments interactifs — jamais sur un conteneur qui les écrase.
Check post-impl: sh -c 'f=Sources/Features/Security/ChangePasswordView.swift; test -f "$f" && grep -qE "struct ChangePasswordView" "$f" && grep -qE "ChangePasswordViewModel" "$f" && grep -qE "onPasswordChanged" "$f" && ! grep -qE "NavigationStack\s*\{" "$f" && test "$(grep -c "accessibilityIdentifier(" "$f")" -eq 5 && perl -0777 -ne "exit 1 unless /SecureField\(.Current Password.[\s\S]{0,400}?accessibilityIdentifier\(.currentPasswordField.\)/s" "$f" && perl -0777 -ne "exit 1 unless /SecureField\(.New Password.[\s\S]{0,400}?accessibilityIdentifier\(.newPasswordField.\)/s" "$f" && perl -0777 -ne "exit 1 unless /SecureField\(.Confirm New Password.[\s\S]{0,400}?accessibilityIdentifier\(.confirmPasswordField.\)/s" "$f" && perl -0777 -ne "exit 1 unless /Toggle\(.Sign out on other devices.[\s\S]{0,400}?accessibilityIdentifier\(.invalidateSessionsToggle.\)/s" "$f" && perl -0777 -ne "exit 1 unless /Button\(.Change Password.[\s\S]{0,400}?accessibilityIdentifier\(.changePasswordSubmit.\)/s" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: le compte exact de 5 identifiants est la borne : tout identifiant supplémentaire serait un identifiant de conteneur, la faute mesurée dans ce dépôt (un identifiant posé sur un conteneur écrase celui de tous ses descendants, rendant le bouton introuvable par le sien).
```

```
### AC-5185 [type: new]
Assertion: la ligne « Change Password » et l'avertissement de drapeau vivent dans la section **Security** existante du hub « Me », le lien pousse `ChangePasswordView` en appelant `auth.notePasswordChanged()` au succès, et l'avertissement n'apparaît que si `auth.shouldChangePassword` est vrai.
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfileView.swift; grep -qE "var changePassword: ChangePasswordViewModel" "$f" && grep -qE "ChangePasswordView\(vm: changePassword" "$f" && grep -qE "auth.notePasswordChanged\(\)" "$f" && grep -qE "auth.shouldChangePassword" "$f" && test "$(grep -c "changePasswordRow" "$f")" -eq 1 && test "$(grep -c "shouldChangePasswordNotice" "$f")" -eq 1 && perl -0777 -ne "exit 1 unless /NavigationLink[\s\S]{0,600}?accessibilityIdentifier\(.changePasswordRow.\)/s" "$f" && perl -0777 -ne "exit 1 unless /Label\(.This server asks you to change your password.[\s\S]{0,400}?accessibilityIdentifier\(.shouldChangePasswordNotice.\)/s" "$f" && ! grep -qE "Section.*accessibilityIdentifier" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -n 'changePassword' Sources/Features/Profile/ProfileView.swift` ne renvoie rien ; `@State var language` est la dernière propriété stockée, `:22`)
Post-state attendu: PASS
Note: les deux identifiants sont rattachés par distance à un `NavigationLink` / un `Label` — la règle du dépôt étant « identifiants sur les éléments interactifs, jamais sur un conteneur ».
```

```
### AC-5186 [type: new]
Assertion: `AuthViewModel` porte `shouldChangePassword`, le renseigne aux DEUX appels d'`applySession` (login et OAuth, qui renvoient le même `LoginResponseDto`), le remet à `false` par `notePasswordChanged()` — le seul point de retombée après succès — et par `resetSession()`, et sait le relire du serveur via `refreshShouldChangePassword()`, appelé depuis le `.task` de `ProfileView`.
Check post-impl: sh -c 'f=Sources/Features/Auth/AuthViewModel.swift; g=Sources/Features/Profile/ProfileView.swift; grep -qE "var shouldChangePassword: Bool = false" "$f" && grep -qE "func notePasswordChanged\(\)" "$f" && perl -0777 -ne "exit 1 unless /func applySession\(token:[\s\S]{0,200}?shouldChangePassword: Bool/s" "$f" && grep -qE "self.shouldChangePassword = shouldChangePassword" "$f" && test "$(grep -cE shouldChangePassword: "$f")" -ge 3 && perl -0777 -ne "exit 1 unless /func resetSession\(\)[\s\S]{0,900}?shouldChangePassword = false/s" "$f" && grep -qE "func refreshShouldChangePassword\(\) async" "$f" && grep -qE "client.currentUser\(\)" "$f" && grep -qE "shouldChangePassword = user.shouldChangePassword \?\? false" "$f" && grep -qE "await auth.refreshShouldChangePassword\(\)" "$g" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -rn 'shouldChangePassword' Sources/` ne renvoie que des définitions de DTO — `DTOs.swift:17`, `DTOs+Admin.swift:14,32,42` — et le `nil` de `AdminViewModel.swift:58` : aucun `AuthViewModel.shouldChangePassword`)
Post-state attendu: PASS
Note: le compte ≥ 3 de l'étiquette `shouldChangePassword:` (déclaration **et** les deux appels à `applySession` — login et OAuth) est exigé : le chemin OAuth renvoie le même payload que le login, un seul point d'appel renseigné laisserait la moitié des sessions sans drapeau.
```

```
### AC-5187 [type: new — aucun secret journalisé ni persisté]
Assertion: ni le ViewModel, ni la vue, ni le drapeau d'auth n'écrivent un mot de passe : aucun `print`/`os_log`/`Logger` portant un mot de passe dans la feature, aucune persistance (`UserDefaults`/`Keychain`) de la saisie ni du drapeau `shouldChangePassword` (celui-ci est un état de session, pas une préférence comme `isAdmin`).
Check post-impl: sh -c 'd=Sources/Features/Security; f=Sources/Features/Auth/AuthViewModel.swift; test -f "$d/ChangePasswordViewModel.swift" && test -f "$d/ChangePasswordView.swift" && ! grep -qE "print\(|os_log|Logger|UserDefaults|Keychain" "$d"/*.swift && ! grep -qE "print\(.*[Pp]assword|os_log.*[Pp]assword|Logger.*[Pp]assword" "$f" && ! grep -qE "shouldChangePassword.*forKey|forKey.*shouldChangePassword" "$f" && ! grep -qE "defaults.set\(shouldChangePassword" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`ls Sources/Features/Security` → No such file or directory)
Post-state attendu: PASS
Note: le contexte de ce contrôle est la fuite par le journal de l'app ; la clé de persistance `authIsAdmin` (`AuthViewModel.swift:29`) est le précédent de ce qui se persiste — le drapeau du serveur ne doit pas l'imiter.
```

```
### AC-5188 [type: new]
Assertion: `ChangePasswordViewModelTests` expose ≥ 8 cas nommés couvrant les quatre refus de validation, le corps réellement posté (trois champs + drapeau), le vidage au succès, la conservation des champs sur mot de passe actuel faux, et la non-réentrance ; les doublures de test portent les nouveaux membres du protocole (sans quoi la cible de tests ne compile pas).
Check post-impl: sh -c 'f=Tests/ChangePasswordViewModelTests.swift; m=Tests/Mocks/MockImmichClient.swift; test -f "$f" && n=$(grep -cE "func test_" "$f") && test "$n" -ge 8 && grep -qE "test_canSubmit_requiresCurrentPassword" "$f" && grep -qE "test_canSubmit_rejectsShortNewPassword" "$f" && grep -qE "test_canSubmit_rejectsMismatchedConfirmation" "$f" && grep -qE "test_canSubmit_rejectsUnchangedPassword" "$f" && grep -qE "test_submit_sendsThreeDtoFieldsAndInvalidateFlag" "$f" && grep -qE "test_submit_clearsFieldsAndReportsSuccess" "$f" && grep -qE "test_submit_keepsFieldsAndSurfacesErrorOnWrongCurrentPassword" "$f" && grep -qE "test_submit_isNotReentrantWhileInFlight" "$f" && grep -qE "func changePassword\(" "$m" && grep -qE "func currentUser\(" "$m" && grep -qE "lastChangePasswordBody" "$m" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`ls Tests/ChangePasswordViewModelTests.swift` → No such file or directory ; la doublure réelle est `Tests/Mocks/MockImmichClient.swift`, pas `Tests/MockImmichClient.swift`)
Post-state attendu: PASS
Note: un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate` — sans régénération la suite passe « verte » par omission.
```

```
### AC-5189 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED — l'ajout des membres au protocole `ImmichClient` élargit toutes ses conformités, donc la suite est le seul juge de l'absence de régression de compilation.
Check post-impl: sh -c 'grep -qsE "TEST SUCCEEDED" /tmp/immich_change_password_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_change_password_test.log | grep -oE "[0-9]+" | sort -n | tail -1) && test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent — aucune suite de change-password n'a été exécutée)
Post-state attendu: PASS
Note: les 8 tests de la feature ne sont comptés qu'après `xcodegen generate`, d'où la borne ≥ 886 (la baseline ne peut pas descendre : seuls des cas s'ajoutent).
```
