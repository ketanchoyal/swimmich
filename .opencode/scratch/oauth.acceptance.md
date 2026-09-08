# Task: oauth

Status: shipped — AC-1130..AC-1135 PASS 2026-08-12 (459 tests, +5). Note: AC-1131 check edité (chemins via constantes oauthMobile/oauthCallback, pas de littéraux).

## Plan
**Objectif**: OAuth2/SSO sign-in (parity Flutter) — mobile flow: `GET /api/auth/oauth/mobile?redirectUri=` → ASWebAuthenticationSession → callback → `POST /api/auth/oauth/callback` → session appliquée comme login. Nettoie TODO `$PHASE_OAUTH` (LoginScreen.swift:50).

**Hypothèses**:
- ServerConfigDto.oauthButtonText (DTOs.swift:43-44) — bouton visible quand non-vide.
- ImmichAPI.auth groupe existant (auth/mobile, auth/callback à ajouter).
- AuthViewModel (Sources/Features/Auth/AuthViewModel.swift, 208L): login()/persistSession pattern :149-175, keychain/defaults keys, `client` private.
- URL scheme app: CFBundleURLTypes dans project.yml info.properties.
- ASWebAuthenticationSession requiert presentation anchor — wrapper injectable `oauthSessionHandler: (URL) async -> URL?` (tests: mock; prod: presenter).

**Approche retenue**: A — DTOs+Auth.swift (OAuthMobileResponseDto{url}, OAuthCallbackResponseDto{accessToken,isAdmin,name,email,profileImagePath,shouldChangePassword?}) + client getOAuthMobileURL/exchangeOAuthCode + AuthViewModel.startOAuthFlow() avec `oauthSessionHandler` injectable + OAuthSessionPresenter (ASWebAuthenticationSession, presentationContextProvider key-window) + LoginScreen bouton `serverConfig.oauthButtonText` + CFBundleURLTypes app.immich. **B** (rejetée): OAuth inline sans seam → non testable. **C** (rejetée): deep-link manuel.

**Étapes**:
1. Card écrite.
2. NEW `Sources/Core/Types/DTOs+Auth.swift`.
3. Constants: auth.oauth/mobile + auth.oauth/callback SubPaths.
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
Assertion: DTOs OAuthMobileResponseDto{url} + OAuthCallbackResponseDto{accessToken,isAdmin,name,email,profileImagePath,shouldChangePassword?} existent.
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs+Auth.swift; test -f "$f" && grep -q "struct OAuthMobileResponseDto" "$f" && grep -q "struct OAuthCallbackResponseDto" "$f" && grep -q "shouldChangePassword" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1131 [type: new]
Assertion: Client expose getOAuthMobileURL(redirectURI:) + exchangeOAuthCode(url:redirectURI:).
Check post-impl: sh -c 'grep -q "func getOAuthMobileURL" Sources/Core/Protocols/ImmichClient.swift && grep -q "func exchangeOAuthCode" Sources/Core/Protocols/ImmichClient.swift && grep -q "oauthMobile" Sources/Services/ImmichAPIClient.swift && grep -q "oauthCallback" Sources/Services/ImmichAPIClient.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1132 [type: new]
Assertion: AuthViewModel.startOAuthFlow() + oauthSessionHandler injectable + canOAuthLogin + redirectURI app.immich://oauth-callback.
Check post-impl: sh -c 'f=Sources/Features/Auth/AuthViewModel.swift; grep -q "func startOAuthFlow" "$f" && grep -q "oauthSessionHandler" "$f" && grep -q "oauth-callback" "$f" && echo PASS || echo FAIL'
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
