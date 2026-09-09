# Task: oauth2-ui

**Objectif** : Ajouter le bouton OAuth2 dans l'écran de login pour la connexion via OIDC provider (Google, Microsoft, Keycloak, etc.). Les DTOs et le client sont wire (`getOAuthMobileURL`, `exchangeOAuthCode`) mais il n'y a pas de bouton UI.

**Hypothèses** :
- `getOAuthMobileURL(redirectURI: String)` → `OAuthMobileResponseDto` (ImmichClient, wire).
- `exchangeOAuthCode(url: String, redirectURI: String)` → `OAuthCallbackResponseDto` (ImmichClient, wire).
- `OAuthMobileResponseDto` expose `authorizationUrl`, `verificationUri`, `userCode`, `deviceCode`, `interval` (RFC 8628 ou RFC 9614).
- `OAuthCallbackResponseDto` expose `accessToken`, `refreshToken` — same shape que le login.
- `AuthViewModel` gère le login email/password — on ajoute OAuth comme alternative.
- `OnboardingFlowView` — le onboarding 3-step (welcome → serverURL → login) — on ajoute OAuth au login step.
- iOS Safari pour l'OIDC flow (ASWebAuthenticationSession).
- `redirectURI` format : `app.immich://oauth-callback` (custom URL scheme).
- `LoginScreen.swift` existe — on ajoute un bouton "Sign in with provider" en dessous du login form.

**Approche retenue** : A — `ASWebAuthenticationSession` pour le OAuth flow, bouton dans LoginScreen, result injecté dans AuthViewModel.
- **B (rejetée)** : nouveau écran dédié. Inutile, le login screen suffit.
- **C (rejetée)** : navigateur externe (Safari) + Universal Links. Moins fluide que ASWebAuthenticationSession.

## Étapes

1. **AuthViewModel** — Étendre avec :
   - `func startOAuthFlow()` — lance le flow OAuth.
   - `oauthResult: OAuthResult?` — résultat du flow (accessToken + success).
   - `OAuthResult` struct : `{ accessToken: String, refreshToken: String }`.
   - `func handleOAuthCallback(url: URL)` — parse le callback URL + exchange code.
2. **OAuth flow integration** :
   - `ASWebAuthenticationSession` pour ouvrir l'OIDC provider.
   - `redirectURI` = `app.immich://oauth-callback` (custom URL scheme).
   - `onDidFinish` → parse URL → `handleOAuthCallback(url:)` → call `exchangeOAuthCode` → set result.
   - `getOAuthMobileURL` → obtenir `authorizationUrl` + `redirectURI` → passer à ASWebAuthenticationSession.
3. **LoginScreen** — Ajouter :
   - Bouton "Sign in with Google" / "Sign in with provider" (large button, system image: `globe`).
   - Ou un bouton "OAuth" générique + picker de provider (si l'endpont supporte des providers distincts).
   - Alternative : bouton "Sign in with provider" → présente un sheet de recherche de provider.
   - Disposition : login form en haut, "OR" separator, OAuth button en bas.
4. **AuthViewModel** — `startOAuthFlow` → call `getOAuthMobileURL(redirectURI:)` → `ASWebAuthenticationSession` → redirect URI → `handleOAuthCallback(url:)` → `exchangeOAuthCode` → set `activeAccountID` (same comme le login).
5. **ImmichSwiftUIApp** — `.onOpenURL { url in if url.scheme == "immich" { auth.handleOAuthCallback(url: url) } }`.
6. **Tests** — `AuthViewModelTests` + tests (startOAuth, handleCallback, exchangeCode, ASWeb params).
7. **xcodegen + suite**.

## Acceptance Contract

### Approches candidates
**A (retenue)** : ASWebAuthenticationSession + bouton dans LoginScreen + onOpenURL handler.
**B** : Écran dédié. Inutile.
**C** : Safari externe + Universal Links. Moins fluide.

### Approche retenue + rationale
**A**. Flow natif iOS, pas d'écran supplémentaire, réutilise les DTOs + client déjà wire.

### Critères

```
### AC-OA01 [type: new]
Assertion: AuthViewModel expose startOAuthFlow(), handleOAuthCallback(url:), oauthResult.
Check post-impl: sh -c 'f=Sources/Features/Auth/AuthViewModel.swift; grep -q "func startOAuthFlow" "$f" && grep -q "func handleOAuthCallback" "$f" && grep -q "oauthResult" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-OA02 [type: new]
Assertion: LoginScreen intègre un bouton OAuth (ASWebAuthenticationSession, app.immich://oauth-callback).
Check post-impl: sh -c 'f=Sources/Features/Auth/LoginScreen.swift; grep -q "ASWebAuthenticationSession\|oauth\|OAuth" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-OA03 [type: new]
Assertion: ImmichSwiftUIApp intègre .onOpenURL handler pour app.immich://oauth-callback.
Check post-impl: sh -c 'grep -q "onOpenURL" Sources/ImmichSwiftUIApp.swift && grep -q "oauth" Sources/ImmichSwiftUIApp.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-OA04 [type: new]
Assertion: AuthViewModelTests expose tests OAuth (startOAuth, handleCallback, exchangeCode, error).
Check post-impl: sh -c 'f=Tests/AuthViewModelTests.swift; n=$(grep -c "oauth\|OAuth" "$f"); test "$n" -ge 8 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-OA05 [type: regression]
Assertion: Suite ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_oauth_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_oauth_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
