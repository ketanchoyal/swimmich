# Task: oauth

Status: shipped — AC-1130..AC-1135 PASS 2026-08-12 (459 tests, +5). **Révisé le 2026-09-12** : AC-1130/1131/1132 pinnaient la mauvaise route OAuth (`/api/auth/oauth/*`, qui n'existe pas côté serveur → 404 en production) et un redirect URI à deux slashes. Checks réécrits sur la surface réelle + AC-1131b ajouté (routes du contrôleur `oauth` + assertion de chemin au niveau transport).

## Plan
**Objectif**: OAuth2/SSO sign-in (parity Flutter) — mobile flow: `POST /api/oauth/authorize` (OAuthConfigDto : redirectUri + state + codeChallenge PKCE) → ASWebAuthenticationSession → `POST /api/oauth/callback` (OAuthCallbackDto : url + state + codeVerifier) → session appliquée comme login. Nettoie TODO `$PHASE_OAUTH` (LoginScreen.swift:50).

**Hypothèses**:
- ServerConfigDto.oauthButtonText (DTOs.swift:43-44) — bouton visible quand non-vide.
- ImmichAPI.auth groupe existant (auth/mobile, auth/callback à ajouter).
- AuthViewModel (Sources/Features/Auth/AuthViewModel.swift, 208L): login()/persistSession pattern :149-175, keychain/defaults keys, `client` private.
- URL scheme app: CFBundleURLTypes dans project.yml info.properties.
- ASWebAuthenticationSession requiert presentation anchor — wrapper injectable `oauthSessionHandler: (URL) async -> URL?` (tests: mock; prod: presenter).

**Approche retenue**: A — DTOs+Auth.swift (`OAuthAuthorizeRequestDto{redirectUri,state,codeChallenge}`, `OAuthAuthorizeResponseDto{url}`, `OAuthCallbackRequestDto{url,state,codeVerifier}` ; la réponse du callback est `LoginResponseDto`) + `OAuthPKCE` (state/verifier/challenge S256) + client authorizeOAuth/exchangeOAuthCode + AuthViewModel.startOAuthFlow() avec `oauthSessionHandler` injectable + OAuthSessionPresenter (ASWebAuthenticationSession, presentationContextProvider key-window) + LoginScreen bouton `serverConfig.oauthButtonText` + CFBundleURLTypes app.immich. **B** (rejetée): OAuth inline sans seam → non testable. **C** (rejetée): deep-link manuel.

**Étapes**:
1. Card écrite.
2. NEW `Sources/Core/Types/DTOs+Auth.swift`.
3. Constants: oauth.authorize + oauth.callback SubPaths (`/api/oauth/*`, contrôleur `oauth` d'Immich).
4. Protocole + ImmichAPIClient: getOAuthMobileURL(redirectURI:), exchangeOAuthCode(url:redirectURI:).
5. AuthViewModel: redirectURI, oauthSessionHandler injectable, canOAuthLogin, startOAuthFlow() (applySession partagé).
6. NEW `Sources/Services/OAuthSessionPresenter.swift`.
7. LoginScreen: bouton OAuth quand canOAuthLogin.
8. project.yml CFBundleURLTypes app.immich + xcodegen.
9. MockImmichClient + Tests/AuthViewModelTests oauth tests.
10. Suite → /tmp/immich_oauth_test_summary.txt + checks AC + memory.md.

## Acceptance Contract

### Approches candidates
**A (retenue)**: seam injectable + presenter ASWebAuthenticationSession. Testable.
**B**: Inline. Non testable.
**C**: Deep link manuel. UX cassée.

### Approche retenue + rationale
**A**. Pattern DI codebase; mock session en tests; serveur client P0-style.

### Critères

```
### AC-1130 [type: new]
Assertion: DTOs OAuth : requête `OAuthAuthorizeRequestDto{redirectUri,state,codeChallenge}` + réponse `OAuthAuthorizeResponseDto{url}` + `OAuthCallbackRequestDto{url,state,codeVerifier}`. Pas de DTO de réponse dédié au callback : le serveur renvoie `LoginResponseDto`.
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs+Auth.swift; test -f "$f" && grep -q "struct OAuthAuthorizeRequestDto" "$f" && grep -q "struct OAuthAuthorizeResponseDto" "$f" && grep -q "struct OAuthCallbackRequestDto" "$f" && grep -q "codeChallenge" "$f" && grep -q "codeVerifier" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1131 [type: new]
Assertion: Client expose authorizeOAuth(redirectURI:state:codeChallenge:) + exchangeOAuthCode(url:state:codeVerifier:), routés vers les constantes `oauthAuthorize` / `oauthCallback`.
Check post-impl: sh -c 'grep -q "func authorizeOAuth" Sources/Core/Protocols/ImmichClient.swift && grep -q "func exchangeOAuthCode" Sources/Core/Protocols/ImmichClient.swift && grep -q "oauthAuthorize" Sources/Services/ImmichAPIClient.swift && grep -q "oauthCallback" Sources/Services/ImmichAPIClient.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1131b [type: regression]
Assertion: les routes OAuth sont celles du contrôleur `oauth` d'Immich — `POST /api/oauth/authorize` et `POST /api/oauth/callback`. `/api/auth/oauth/*` n'existe pas et rend un 404.
Check post-impl: sh -c 'f=Sources/Core/Constants.swift; grep -qF "root: \"/oauth/authorize\"" "$f" && grep -qF "root: \"/oauth/callback\"" "$f" && ! grep -qF "/auth/oauth" "$f" && grep -qE "captured.url\?\.path, \"/api/oauth/authorize\"" Tests/ImmichAPIClientTests.swift && grep -qE "captured.url\?\.path, \"/api/oauth/callback\"" Tests/ImmichAPIClientTests.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (constantes `auth/oauth/mobile` + `auth/oauth/callback` → 404)
Post-state attendu: PASS
```

```
### AC-1132 [type: new]
Assertion: AuthViewModel.startOAuthFlow() + oauthSessionHandler injectable + canOAuthLogin + redirectURI `app.immich:///oauth-callback` (trois slashes — la valeur publiée par Immich) + PKCE généré côté client.
Check post-impl: sh -c 'f=Sources/Features/Auth/AuthViewModel.swift; grep -q "func startOAuthFlow" "$f" && grep -q "oauthSessionHandler" "$f" && grep -qF "app.immich:///oauth-callback" "$f" && grep -q "OAuthPKCE()" "$f" && grep -q "codeChallenge: pkce.codeChallenge" "$f" && grep -q "codeVerifier: pkce.codeVerifier" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1133 [type: new]
Assertion: OAuthSessionPresenter (ASWebAuthenticationSession) existe + LoginScreen bouton quand canOAuthLogin.
Check post-impl: sh -c 'grep -q "ASWebAuthenticationSession" Sources/Services/OAuthSessionPresenter.swift && grep -q "canOAuthLogin" Sources/Features/Auth/Onboarding/LoginScreen.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1134 [type: new]
Assertion: project.yml CFBundleURLTypes app.immich + tests oauth ≥ 3 (success/cancel/failure).
Check post-impl: sh -c 'grep -q "app.immich" project.yml && f=Tests/AuthViewModelTests.swift; n=$(grep -c "func test_.*[Oo][Aa][Uu][Tt][Hh]" "$f"); test "$n" -ge 3 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1135 [type: regression]
Assertion: Suite ≥ 454, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_oauth_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_oauth_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 454 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
