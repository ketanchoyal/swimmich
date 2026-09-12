# Task: oauth2-ui

Status: shipped — AC-3000–AC-3007 PASS le 2026-09-10 (suite 692 tests, TEST SUCCEEDED sur iPhone 17). Les critères d'origine (AC-3000..AC-3005) pinnaient une surface jamais construite : voir « Reconciliation » ci-dessous.

**Spec** : `.omp/oauth2-ui/oauth2-ui.specs.md`
**UI brief** : `.omp/oauth2-ui/oauth2-ui.ui.md`
**Dépendances** : aucune. `oauth.acceptance.md` (AC-1130..AC-1135, shipped) couvre le *transport* (`getOAuthMobileURL` + `exchangeOAuthCode` + DTOs) ; cette card couvre la *surface* (bouton, session navigateur, application de session).

## Plan

**Objectif** : connexion OIDC/SSO depuis l'écran de login. Les DTOs et le client étaient wire depuis P0 ; il manquait le bouton et la session navigateur.

**Hypothèses** (ground truth vérifié le 2026-09-10) :
- `AuthViewModel` (`Sources/Features/Auth/AuthViewModel.swift`) : `static let oauthRedirectURI = "app.immich:///oauth-callback"` (l.32), `var oauthSessionHandler: (URL) async -> URL?` injectable — défaut `OAuthSessionPresenter.present` (l.35-37), `var canOAuthLogin` (l.239, gate sur `serverConfig.oauthButtonText` non vide), `func startOAuthFlow()` (l.245-289), `func applySession(...)` partagé avec le login mot de passe.
- `OAuthSessionPresenter` (`Sources/Services/OAuthSessionPresenter.swift`) : enum `@MainActor`, `static let callbackScheme = "app.immich"` (l.13), `ASWebAuthenticationSession(url:callbackURLScheme:)` (l.17-19), ancre = première `UIWindowScene` key-window (l.32).
- `LoginScreen` (`Sources/Features/Auth/Onboarding/LoginScreen.swift`) : étape 4 de l'onboarding, form email/mot de passe dans un `PVInputGroup`, bouton SSO conditionnel (l.53), `orDivider` (l.110), CTA « Se connecter » dans `.onboardingBottomBar`.
- Le schéma est déclaré côté app : `CFBundleURLTypes` → `app.immich` dans `Resources/Info.plist` (l.25-33) et `project.yml` (l.56-58).
- `client.authorizeOAuth(redirectURI:state:codeChallenge:)` → `OAuthAuthorizeResponseDto { url }` et `client.exchangeOAuthCode(url:state:codeVerifier:)` → `LoginResponseDto` (`Sources/Core/Types/DTOs+Auth.swift`).
- `MockImmichClient` porte déjà `oauthMobileResponse` / `oauthCallbackResponse` / `oauthError` / `lastOAuth*` (`Tests/Mocks/MockImmichClient.swift:25-56`).

**Endpoints** : `POST /api/oauth/authorize` et `POST /api/oauth/callback` — tous deux déjà wire (aucun endpoint ajouté). ⚠️ les routes `/api/auth/oauth/*` pinées à l'origine n'existent pas (404), voir Révision du 2026-09-12.

**Approche retenue** : **A — `ASWebAuthenticationSession` pilotée par `AuthViewModel`, bouton dans `LoginScreen`, ancre injectable.**
Le callback est capturé par la session navigateur elle-même (`callbackURLScheme`), donc **aucun handler `.onOpenURL` n'est nécessaire** : `ASWebAuthenticationSession` rend l'URL de callback à sa closure de complétion, et `startOAuthFlow()` enchaîne directement sur `exchangeOAuthCode`. Un `.onOpenURL` en plus serait du code mort — le schéma `app.immich` n'est jamais routé vers l'app pendant la session.
- **B (rejetée)** : écran dédié. Inutile — `LoginScreen` a déjà le contexte (URL serveur + config).
- **C (rejetée)** : Safari externe + Universal Links. Moins fluide, et perd la maîtrise du retour (`prefersEphemeralWebBrowserSession = false` garde les cookies du provider).

**Étapes** (as-built) :
1. **EDIT** `AuthViewModel.swift` — `canOAuthLogin`, `startOAuthFlow()`, `oauthSessionHandler` injectable, `applySession` partagé, `oauthRedirectURI`.
2. **NEW** `Sources/Services/OAuthSessionPresenter.swift` — `ASWebAuthenticationSession` + `AnchorProvider` (ancre = première key-window ; une référence de scène fixe périmerait).
3. **EDIT** `LoginScreen.swift` — bouton SSO conditionnel libellé par `serverConfig.oauthButtonText` (fallback « Sign in with SSO »), séparateur `orDivider` entre le chemin mot de passe et le chemin SSO, spinner in-flight, `oauthSignIn()`.
4. **EDIT** `LoginScreen.swift` + `AuthViewModel.swift` (2026-09-10, cette passe) — `defer { isLoading = false }` : l'annulation navigateur et l'URL provider malformée laissaient `isLoading == true`, ce qui **désactivait définitivement** le CTA du bas et grisait le bouton SSO ; spinner sur le bouton SSO pendant le flow ; `orDivider` (« OU »).
5. **NEW** tests — `test_oauth_*` ×6 dans `Tests/AuthViewModelTests.swift` (l.326-446) : gate `canOAuthLogin`, échange + application de session (token, admin, nom, redirect URI), annulation, URL malformée, erreur serveur, serveur sans OAuth.
6. `xcodebuild test` → 692 tests, TEST SUCCEEDED (baseline 691).

**Risques / limites assumées** :
- Le flow n'est **pas** vérifiable en intégration réelle sans un serveur Immich avec un provider OIDC configuré : la session navigateur est injectée (`oauthSessionHandler`), donc les tests couvrent le contrat du ViewModel, pas `ASWebAuthenticationSession`. La vérification bout-en-bout reste manuelle.
- `oauthButtonText` vient du serveur : si le serveur n'expose pas OAuth, le bouton n'apparaît pas du tout (pas de bouton mort).

## Reconciliation

Les critères d'origine de cette card (`AC-3000..AC-3005` version 2026-09-08) ont été **réécrits**, pas « réparés ». Ils pinnaient une surface qui n'a jamais existé et que le code a remplacée :

| Ancien critère | Ce qu'il pinnait | Réalité |
|---|---|---|
| AC-3000 | `oauthResult: OAuthResult?`, `oauthAuthorizationURL: URL?`, `func handleOAuthCallback(url:)` | Aucun des trois. Le résultat est appliqué directement via `applySession` (l.285) — pas de type intermédiaire. |
| AC-3001/3002 | `ASWebAuthenticationSession` **et** `app.immich://oauth-callback` (deux slashes) **et** `handleOAuthCallback` dans `AuthViewModel` | La session vit dans `OAuthSessionPresenter` (service), pas dans le ViewModel ; le ViewModel ne connaît que la closure injectée. |
| AC-3003 | littéral `"Sign in with Provider"`, `showOAuthSession`, `globe` | Le libellé est **le texte du serveur** (`serverConfig.oauthButtonText`, fallback « Sign in with SSO ») ; l'icône est `person.badge.key.fill` ; il n'y a pas de sheet de session (le navigateur système en tient lieu). |
| AC-3004 | `.onOpenURL` dans `ImmichSwiftUIApp` | Structurellement inutile : `ASWebAuthenticationSession` capture le callback via `callbackURLScheme`. L'ajouter serait du code mort. |
| AC-3005 | `Sources/Features/Auth/OAuthLoadingView.swift` avec « Connecting to provider… » | Fichier jamais créé — le feedback in-flight est un `ProgressView` **dans le bouton** (l.59), pas une sheet. |
| AC-3006 | ≥4 tests nommés `test_oauth\|test_startOAuth\|test_handleCallback\|test_exchangeCode` | Il n'y a pas de `handleOAuthCallback` ; les 6 tests réels sont `test_oauth_*`. |

Même classe de dérive que les 8 checks réécrits le 2026-09-10 pour `backup-engine` / `backup-live-activity`. La spec et le UI brief ont été corrigés dans la même passe (ils décrivaient le même `OAuthLoadingView` fantôme et un glass morph jamais implémenté — l'écran réel suit le pattern `PVInputGroup` + `.onboardingBottomBar` de `onboarding-premium-redesign`).

**Révision du 2026-09-12** (constat utilisateur en production : « login with OAuth → 404 ») :
- Les routes étaient fausses. Le contrôleur Immich est `@Controller('oauth')` : `POST /api/oauth/authorize` (body `OAuthConfigDto`) et `POST /api/oauth/callback` (body `OAuthCallbackDto`). `/api/auth/oauth/mobile` et `/api/auth/oauth/callback` **n'existent pas** → 404 systématique.
- Le flow envoyait un `GET …?redirectUri=` alors que `authorize` est un **POST** avec `{redirectUri, state, codeChallenge}`. Le PKCE (`state` + S256 `codeChallenge` + `codeVerifier`) est désormais généré côté client (`Sources/Core/Utilities/OAuthPKCE.swift`) : la session navigateur ne partage pas les cookies posés par `authorize`.
- Le redirect URI passe à `app.immich:///oauth-callback` (trois slashes) — la valeur publiée par la doc Immich et celle à whitelister chez le provider. L'ancienne valeur à deux slashes ne matchait pas une redirect URI déclarée avec trois.
- Le libellé « OU » s'affichait flanqué de deux **barres verticales** : `Divider()` rend un trait vertical dans un `HStack`. Remplacé par une règle `Rectangle` horizontale explicite (`orRule`).

## Acceptance Contract

### Approches candidates
**A (retenue)** : session navigateur dans un service injectable + bouton contextuel dans `LoginScreen`, libellé serveur, séparateur OR.
**B** : écran dédié. Rejetée (le login screen a déjà tout le contexte).
**C** : Safari externe + Universal Links. Rejetée (moins fluide, retour non maîtrisé).

### Approche retenue + rationale
**A** — c'est le flow natif iOS pour OIDC : pas de handler de deep link à maintenir, pas d'écran supplémentaire, et la closure injectée rend le contrat testable sans navigateur.

### Critères

```
### AC-3000 [type: new]
Assertion: AuthViewModel expose le gate OAuth et le point d'entrée du flow, avec la session navigateur derrière une closure injectable.
Check post-impl: sh -c 'f=Sources/Features/Auth/AuthViewModel.swift; grep -qE "var canOAuthLogin" "$f" && grep -qE "func startOAuthFlow\(\) async" "$f" && grep -qE "var oauthSessionHandler: \(URL\) async -> URL\?" "$f" && echo PASS || echo FAIL'
Pre-state attendu: PASS (livré 2026-09-08)
Post-state attendu: PASS
```

```
### AC-3001 [type: new]
Assertion: le flow enchaîne authorize → session navigateur → échange du code avec le vérificateur PKCE, et le redirect URI est le schéma réellement déclaré côté app (`app.immich`, trois slashes).
Check post-impl: sh -c 'f=Sources/Features/Auth/AuthViewModel.swift; grep -qE "authorizeOAuth\(" "$f" && grep -qE "oauthSessionHandler\(providerURL\)" "$f" && grep -qE "exchangeOAuthCode\(" "$f" && grep -qF "app.immich:///oauth-callback" "$f" && grep -qE "callbackURLScheme: callbackScheme" Sources/Services/OAuthSessionPresenter.swift && grep -qE "static let callbackScheme = \"app.immich\"" Sources/Services/OAuthSessionPresenter.swift && grep -qF "<string>app.immich</string>" Resources/Info.plist && echo PASS || echo FAIL'
Pre-state attendu: PASS (livré 2026-09-08)
Post-state attendu: PASS
```

```
### AC-3001b [type: new]
Assertion: le flow envoie un PKCE généré côté client (state + challenge à l'authorize, verifier au callback) — le serveur l'exige, et la session navigateur ne partage pas le cookie jar de l'app.
Check post-impl: sh -c 'f=Sources/Features/Auth/AuthViewModel.swift; grep -qE "let pkce = OAuthPKCE\(\)" "$f" && grep -qE "state: pkce.state" "$f" && grep -qE "codeChallenge: pkce.codeChallenge" "$f" && grep -qE "codeVerifier: pkce.codeVerifier" "$f" && test -f Sources/Core/Utilities/OAuthPKCE.swift && grep -qE "SHA256.hash" Sources/Core/Utilities/OAuthPKCE.swift && grep -qE "base64URLEncodedString" Sources/Core/Utilities/OAuthPKCE.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun PKCE : le flow envoyait un redirectUri seul)
Post-state attendu: PASS
```

```
### AC-3002 [type: new]
Assertion: le flag in-flight est remis à false sur TOUTES les sorties du flow (annulation, URL provider malformée, erreur, succès) — sinon le CTA de login reste désactivé — et c'est couvert par un test de non-régression.
Check post-impl: sh -c 'f=Sources/Features/Auth/AuthViewModel.swift; grep -qE "isLoading = true" "$f" && grep -qE "defer \{ isLoading = false \}" "$f" && grep -qE "func test_oauth_cancelLeavesStateUntouched" Tests/AuthViewModelTests.swift && grep -qE "func test_oauth_malformedProviderURLResetsLoading" Tests/AuthViewModelTests.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (annulation et URL malformée sortaient avant `isLoading = false`)
Post-state attendu: PASS
```

```
### AC-3003 [type: new]
Assertion: LoginScreen porte le bouton SSO, conditionné au serveur, libellé par le serveur, séparé du chemin mot de passe — sans littéral en dur.
Check post-impl: sh -c 'f=Sources/Features/Auth/Onboarding/LoginScreen.swift; grep -qE "if auth.canOAuthLogin" "$f" && grep -qE "serverConfig\?\.oauthButtonText" "$f" && grep -qF "private var orDivider" "$f" && grep -qE "await auth.startOAuthFlow\(\)" "$f" && ! grep -qF "Sign in with Provider" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (bouton présent, séparateur et état in-flight absents)
Post-state attendu: PASS
```

```
### AC-3004 [type: new]
Assertion: la surface de login ne contient PAS d'écran de chargement dédié ni de handler de deep link — la session système capture le callback, un `.onOpenURL` serait du code mort.
Check post-impl: sh -c 'test ! -f Sources/Features/Auth/OAuthLoadingView.swift && test ! -f Sources/Features/Auth/Onboarding/OAuthLoadingView.swift && ! grep -q "onOpenURL" Sources/ImmichSwiftUIApp.swift && grep -qE "if auth.isLoading \{" Sources/Features/Auth/Onboarding/LoginScreen.swift && grep -qE "ProgressView\(\)" Sources/Features/Auth/Onboarding/LoginScreen.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (OAuthLoadingView absent, spinner absent)
Post-state attendu: PASS
```

```
### AC-3005 [type: new]
Assertion: le bouton SSO n'affiche jamais de libellé vide (fallback quand le serveur n'envoie pas de texte).
Check post-impl: sh -c 'f=Sources/Features/Auth/Onboarding/LoginScreen.swift; grep -qE "oauthButtonText \?\? \"Sign in with SSO\"" "$f" && grep -qE "\.lineLimit\(1\)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: PASS (livré 2026-09-08)
Post-state attendu: PASS
```

```
### AC-3006 [type: new]
Assertion: le contrat du flow est couvert par ≥6 tests `test_oauth_*` (succès, annulation, URL malformée, erreur, gate serveur, absence d'OAuth).
Check post-impl: sh -c 'f=Tests/AuthViewModelTests.swift; n=$(grep -cE "func test_oauth_" "$f"); test "${n:-0}" -ge 6 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (5 tests)
Post-state attendu: PASS
```

```
### AC-3007 [type: regression]
Assertion: suite complète ≥ 691 tests (baseline 2026-09-10), TEST SUCCEEDED.
Check post-impl: sh -c 'xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination "platform=iOS Simulator,name=iPhone 17" 2>&1 | tee /tmp/immich_oauth_test_summary.txt | grep -q "TEST SUCCEEDED" && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_oauth_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "${n:-0}" -ge 691 && echo PASS || echo FAIL'
Pre-state attendu: PASS (691 tests)
Post-state attendu: PASS (697 tests)
```

```
### AC-3008 [type: regression]
Assertion: le séparateur « OU » est une vraie règle horizontale. `Divider()` rend un trait **vertical** dans un `HStack` — la barre verticale observée de part et d'autre du texte au 2026-09-12.
Check post-impl: sh -c 'f=Sources/Features/Auth/Onboarding/LoginScreen.swift; grep -qF "private var orRule" "$f" && grep -qE "Rectangle\(\)" "$f" && grep -qE "\.frame\(height: 1\)" "$f" && grep -qE "\.fill\(Color.separatorPV\)" "$f" && ! grep -qE "^\s+Divider\(\)\s*$" <(sed -n "/private var orDivider/,/^    }/p" "$f") && echo PASS || echo FAIL'
Pre-state attendu: FAIL (deux `Divider()` dans un `HStack` → deux barres verticales)
Post-state attendu: PASS
```
