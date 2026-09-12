# Task: oauth2-ui

**Statut** : livré (2026-09-08), réconcilié le 2026-09-10 — 8/8 AC PASS, suite 692 tests TEST SUCCEEDED.
**Card AC** : `.opencode/scratch/oauth2-ui.acceptance.md`
**UI brief** : `.omp/oauth2-ui/oauth2-ui.ui.md`
**Prérequis couvert ailleurs** : `oauth.acceptance.md` (AC-1130..AC-1135, shipped) — transport (`getOAuthMobileURL`, `exchangeOAuthCode`, DTOs, constantes de chemin). Cette spec ne couvre que la surface.

**Objectif** : connexion OIDC/SSO depuis l'écran de login, sur les serveurs Immich qui exposent un provider (`serverConfig.oauthButtonText` non vide).

## Ground truth (vérifié 2026-09-10)

| Ancre | Fichier:ligne |
|---|---|
| `static let oauthRedirectURI = "app.immich:///oauth-callback"` | `Sources/Features/Auth/AuthViewModel.swift:32` |
| `var oauthSessionHandler: (URL) async -> URL?` (défaut `OAuthSessionPresenter.present`) | `AuthViewModel.swift:35-37` |
| `var canOAuthLogin` (gate `serverConfig.oauthButtonText` non vide) | `AuthViewModel.swift:239-242` |
| `func startOAuthFlow()` — mobile URL → session → `exchangeOAuthCode` → `applySession` | `AuthViewModel.swift:248-281` |
| `defer { isLoading = false }` (toutes les sorties du flow) | `AuthViewModel.swift:256` |
| `private func applySession(token:email:name:userId:isAdmin:)` partagé login/OAuth | `AuthViewModel.swift:285` |
| `enum OAuthSessionPresenter` (`@MainActor`), `callbackScheme = "app.immich"`, `ASWebAuthenticationSession` | `Sources/Services/OAuthSessionPresenter.swift:10-28` |
| Bouton SSO conditionnel + `orDivider` + spinner in-flight | `Sources/Features/Auth/Onboarding/LoginScreen.swift:53-74, 110-133` |
| `CFBundleURLTypes` → `app.immich` | `Resources/Info.plist:25-33`, `project.yml:56-58` |
| `OAuthPKCE` — state + verifier + challenge S256 | `Sources/Core/Utilities/OAuthPKCE.swift` |
| `oauthAuthorizeResponse` / `oauthCallbackResponse` / `oauthError` / `lastOAuth*` | `Tests/Mocks/MockImmichClient.swift:24-64` |
| 6 tests `test_oauth_*` | `Tests/AuthViewModelTests.swift:326-446` |

**Endpoints** : `POST /api/oauth/authorize` (body `{redirectUri, state, codeChallenge}`) et `POST /api/oauth/callback` (body `{url, state, codeVerifier}`) — déjà wire, aucun ajout. ⚠️ Les routes `/api/auth/oauth/*` initialement câblées **n'existent pas** dans le contrôleur `oauth` d'Immich et rendaient un 404 (corrigé le 2026-09-12).

## Approche retenue

**A — `ASWebAuthenticationSession` (service injectable) + bouton contextuel dans `LoginScreen`.**

Le callback est capturé **par la session navigateur** (`callbackURLScheme`), rendu à la closure de complétion. Conséquence de conception : **aucun `.onOpenURL` n'est nécessaire** dans `ImmichSwiftUIApp`, et en ajouter un serait du code mort. Le résultat du flow n'a pas de type intermédiaire (`OAuthResult`) : `startOAuthFlow()` appelle directement `applySession(...)`, le même chemin que le login mot de passe — une seule application de session à maintenir.

- **B (rejetée)** : écran OAuth dédié. `LoginScreen` porte déjà l'URL serveur et la config ; un écran de plus ne gagne rien.
- **C (rejetée)** : Safari externe + Universal Links. Moins fluide, retour non maîtrisé, et `prefersEphemeralWebBrowserSession = false` (cookies du provider conservés) serait à réimplémenter.

## Étapes (as-built)

1. **EDIT** `AuthViewModel.swift` — `oauthRedirectURI`, `canOAuthLogin`, `oauthSessionHandler` injectable, `startOAuthFlow()`, `applySession` partagé.
2. **NEW** `Sources/Services/OAuthSessionPresenter.swift` — `ASWebAuthenticationSession` + `AnchorProvider` (première `UIWindowScene` key-window ; une référence de scène fixe périmerait).
3. **EDIT** `LoginScreen.swift` — bouton SSO conditionnel, libellé = texte du serveur (fallback « Sign in with SSO »), séparateur `orDivider`, `oauthSignIn()`.
4. **EDIT** `AuthViewModel.swift` + `LoginScreen.swift` (2026-09-10) — `defer { isLoading = false }` (l'annulation et l'URL provider malformée sortaient avant la remise à zéro : le CTA de login restait désactivé et le bouton SSO grisé pour de bon), spinner sur le bouton SSO, séparateur « OU ».
5. **EDIT** `Tests/AuthViewModelTests.swift` — 6 tests `test_oauth_*` : gate `canOAuthLogin`, succès complet (token + admin + nom + redirect URI transmis), annulation (état intact + `isLoading == false`), URL provider malformée, erreur serveur, serveur sans OAuth.
6. **Régression** — 691 → 692 tests, TEST SUCCEEDED (iPhone 17).

## Tests attendus

- `Tests/AuthViewModelTests.swift` → 6 tests `test_oauth_*` (voir ci-dessus).
- Régression : suite ≥ 691 tests, `TEST SUCCEEDED`.

## Risques / limites

- **Non vérifié bout-en-bout** : la session navigateur est injectée, donc les tests couvrent le contrat du ViewModel, pas `ASWebAuthenticationSession` ni le retour réel du provider. Exige un serveur Immich avec provider OIDC configuré — vérification manuelle.
- `oauthButtonText` est un signal serveur : serveur sans OAuth ⇒ pas de bouton (jamais de bouton mort).
