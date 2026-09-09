# Task: oauth2-ui

Status: plan

## Plan

**Objectif**: Ajouter le bouton OAuth2 dans LoginScreen pour la connexion OIDC. Les DTOs et client sont wire (`getOAuthMobileURL`, `exchangeOAuthCode`) mais pas d'interface.

**Hypothèses** (ground truth vérifié):
- `AuthViewModel` (Sources/Features/Auth/AuthViewModel.swift) gère login email/password.
- ImmichClient expose `getOAuthMobileURL(redirectURI:)` → `OAuthMobileResponseDto` et `exchangeOAuthCode(url:redirectURI:)` → `OAuthCallbackResponseDto`.
- DTOs dans DTOs+Auth.swift: `OAuthMobileResponseDto{authorizationUrl,redirectURI}`, `OAuthCallbackResponseDto{accessToken,refreshToken,tokenType,expiresIn}`.
- `LoginScreen.swift` existe avec email/password form.
- `KeychainStore` persiste tokens (déjà utilisé par AuthViewModel).
- `ASWebAuthenticationSession` disponible pour le flow OIDC.

**Approche retenue**: A — `ASWebAuthenticationSession` pour OIDC, bouton "Sign in with Provider" dans LoginScreen, `onOpenURL` handler dans ImmichSwiftUIApp.
**B (rejetée)**: Écran dédié → inutile, LoginScreen suffit.
**C (rejetée)**: Safari externe + Universal Links → moins fluide que ASWebAuthenticationSession.

**Étapes**:
1. EDIT `AuthViewModel.swift` — Ajouter `oauthResult: OAuthResult?`, `func startOAuthFlow()`, `func handleOAuthCallback(url:)`.
2. `AuthViewModel.startOAuthFlow()` — `getOAuthMobileURL(redirectURI: "app.immich://oauth-callback")` → `ASWebAuthenticationSession(url:redirectURI:)` → `onDidFinish` parse URL → `handleOAuthCallback` → `exchangeOAuthCode` → set `activeAccountID`.
3. EDIT `LoginScreen.swift` — Ajouter bouton OAuth avec `ASWebAuthenticationSession`, `OR` divider, `showOAuthSession` state.
4. EDIT `ImmichSwiftUIApp.swift` — Ajouter `.onOpenURL` handler pour `app.immich://oauth-callback` → `auth.handleOAuthCallback(url:)`.
5. NEW `OAuthLoadingView.swift` — Sheet showing loading state during ASWebAuthenticationSession.
6. Tests — `AuthViewModelTests` +4 (startOAuth, handleCallback, exchangeCode, ASWeb params).
7. Build + suite complète → /tmp/immich_oauth_test_summary.txt.

## Acceptance Contract

### Approches candidates
**A (retenue)**: ASWebAuthenticationSession + bouton dans LoginScreen + onOpenURL handler.
**B**: Écran dédié → inutile.
**C**: Safari externe → moins fluide.

### Approche retenue + rationale
**A**. Flow natif iOS, pas d'écran supplémentaire, réutilise DTOs + client déjà wire.

### Critères

```
### AC-3000 [type: new]
Assertion: AuthViewModel expose startOAuthFlow(), handleOAuthCallback(url:), oauthResult: OAuthResult?, oauthAuthorizationURL: URL?.
Check post-impl: sh -c 'f=Sources/Features/Auth/AuthViewModel.swift; grep -qE "func startOAuthFlow\(\)" "$f" && grep -qE "func handleOAuthCallback\(url: URL\)" "$f" && grep -qE "oauthResult: OAuthResult\?" "$f" && grep -qE "oauthAuthorizationURL: URL\?" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3001 [type: new]
Assertion: AuthViewModel.startOAuthFlow() appelle getOAuthMobileURL(redirectURI: "app.immich://oauth-callback"), ouvre ASWebAuthenticationSession, configure onDidFinish pour appeler handleOAuthCallback(url:).
Check post-impl: sh -c 'f=Sources/Features/Auth/AuthViewModel.swift; grep -qE "getOAuthMobileURL" "$f" && grep -qE "app.immich://oauth-callback" "$f" && grep -qE "ASWebAuthenticationSession" "$f" && grep -qE "handleOAuthCallback" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3002 [type: new]
Assertion: AuthViewModel.handleOAuthCallback(url:) parse app.immich://oauth-callback avec query params code + state, appelle exchangeOAuthCode(code:redirectURI:), set activeAccountID, dismiss sheet, haptic success.
Check post-impl: sh -c 'f=Sources/Features/Auth/AuthViewModel.swift; grep -qE "URLQueryItem" "$f" && grep -qE "exchangeOAuthCode" "$f" && grep -qE "activeAccountID" "$f" && grep -qE "dismiss\(\)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3003 [type: new]
Assertion: LoginScreen expose bouton OAuth (globe SF Symbol + "Sign in with Provider") + OR divider + sheet OAuthLoadingView.
Check post-impl: sh -c 'f=Sources/Features/Auth/LoginScreen.swift; grep -qE "globe" "$f" && grep -qE "Sign in with Provider" "$f" && grep -qE "OR" "$f" && grep -qE "showOAuthSession" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3004 [type: new]
Assertion: ImmichSwiftUIApp expose .onOpenURL handler vérifiant scheme == "immich" et host == "oauth-callback", appelle auth.handleOAuthCallback(url:).
Check post-impl: sh -c 'grep -qE "onOpenURL" Sources/ImmichSwiftUIApp.swift && grep -qE "immich" Sources/ImmichSwiftUIApp.swift && grep -qE "oauth-callback" Sources/ImmichSwiftUIApp.swift && grep -qE "handleOAuthCallback" Sources/ImmichSwiftUIApp.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3005 [type: new]
Assertion: OAuthLoadingView existe (NEW file) avec ProgressView, message "Connecting to provider...", onAppear lance ASWebAuthenticationSession.
Check post-impl: sh -c 'f=Sources/Features/Auth/OAuthLoadingView.swift; test -f "$f" && grep -qE "ProgressView" "$f" && grep -qE "Connecting to provider" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3006 [type: new]
Assertion: AuthViewModelTests expose ≥4 tests OAuth (startOAuth, handleCallback, exchangeCode, error).
Check post-impl: sh -c 'f=Tests/AuthViewModelTests.swift; grep -qE "func test_oauth\|func test_oauth2\|func test_startOAuth\|func test_handleCallback\|func test_exchangeCode" "$f" && n=$(grep -cE "func test_oauth\|func test_oauth2\|func test_startOAuth\|func test_handleCallback\|func test_exchangeCode" "$f"); test "$n" -ge 4 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3007 [type: regression]
Assertion: Suite complète ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_oauth_test_summary.txt && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_oauth_test_summary.txt | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (pas de summary)
Post-state attendu: PASS
```
