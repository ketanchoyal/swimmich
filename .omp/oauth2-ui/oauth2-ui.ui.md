# Task: oauth2-ui — UI Brief

**Statut** : livré 2026-09-08, réconcilié le 2026-09-10. Ce brief décrivait à l'origine un écran glass avec morphing (`GlassEffectContainer`, `glassEffectID`, sheet `OAuthLoadingView`) : **rien de tout cela n'a été construit** et ce n'était pas le bon pattern — l'écran de login réel suit la refonte `onboarding-premium-redesign` (carte groupée native + barre d'action en bas). Le brief est réécrit sur la surface réelle, pas sur l'intention abandonnée.

## Design Philosophy

Le SSO est une **alternative au mot de passe**, pas un chemin parallèle mis en avant. Il apparaît donc **sous** le formulaire, séparé par un filet discret, et seulement quand le serveur annonce un provider. Le parcours reste celui de l'onboarding : une carte, un CTA ancré en bas.

## Layout (réel)

```
LoginScreen — 4e étape de OnboardingFlowView
└── ScrollView
    ├── header              PVHeaderBadge + titre + sous-titre
    ├── VStack(leading, s8)
    │   ├── PVInputGroup     carte bgSecondary / PVRadius.lg
    │   │   ├── TextField    vous@exemple.com        + .pvFieldSurface()
    │   │   ├── Divider()
    │   │   └── SecureField  ••••••••                + .pvFieldSurface()
    │   ├── orDivider        orRule / « OU » / orRule        ← si canOAuthLogin
    │   ├── Bouton SSO       icône (ou spinner) + libellé serveur ← si canOAuthLogin
    │   └── InlineErrorBadge ← si auth.errorMessage
    └── Spacer(minLength: s48)
.onboardingBottomBar { « Se connecter » — PVPrimaryButtonStyle }
```

Pas de `Form`, pas de sheet, pas de ZStack : le clavier est géré par `@FocusState` (email → mot de passe → `submitLabel(.go)` → `signIn()`), `scrollDismissesKeyboard(.immediately)` garde le CTA atteignable.

## Components

### Bouton SSO

- Conditionné à `auth.canOAuthLogin` (le serveur n'annonce un provider que si `serverConfig.oauthButtonText` est non vide) — sinon rien, pas de bouton mort.
- Libellé = `auth.serverConfig?.oauthButtonText ?? "Sign in with SSO"`, `.lineLimit(1)`.
- Icône `person.badge.key.fill` ; remplacée par un `ProgressView()` pendant le flow (`auth.isLoading`).
- Surface : `Color.gray.opacity(0.12)` en `RoundedRectangle(cornerRadius: PVRadius.md, style: .continuous)` — volontairement **plus discrète** que le CTA primaire (bleu plein), `.buttonStyle(.plain)`, `minHeight: 44`.
- `.disabled(auth.isLoading)`, et le CTA du bas l'est aussi → un seul flow à la fois.

### orDivider

`orRule` / `Text("OU")` `.pvCaption` `Color.textSecondaryPV` / `orRule`, `spacing: PVSpacing.s12`, `.accessibilityHidden(true)` — purement visuel.

`orRule` est un `Rectangle().fill(Color.separatorPV).frame(height: 1)` : **`Divider()` ne convient pas ici**. Dans un `HStack` il adopte l'axe vertical et rend deux barres verticales, pas deux filets horizontaux (constat utilisateur du 2026-09-12). Le label porte `.fixedSize()` pour que les règles absorbent la largeur restante sans tronquer « OU ».

### InlineErrorBadge

Réutilisé tel quel (composant du DesignSystem, AC-013). Rend les erreurs inline sous la carte, jamais en popup. `.transition(.opacity)` + `.animation(PVMotion.gentle, value:)`.

## Interactions

1. Tap sur le bouton SSO → `oauthSignIn()` → `Task { await auth.startOAuthFlow() }`.
2. `auth.isLoading = true` : spinner dans le bouton, bouton et CTA désactivés.
3. `POST /oauth/authorize` (redirect URI + state + code challenge) → `ASWebAuthenticationSession` (service `OAuthSessionPresenter`) — le navigateur système s'ouvre **au-dessus** de l'app ; pas de sheet applicative.
4. Retour du provider sur `app.immich:///oauth-callback` → capturé par la session → `POST /oauth/callback` avec le `codeVerifier` → `applySession` (token Keychain + compte sauvegardé + client reconfiguré).
5. `RootView` bascule sur `isAuthenticated` → TabView principale. L'ouverture de l'app **est** la confirmation : pas d'écran de succès.
6. Annulation du navigateur → état inchangé, aucun message d'erreur, `isLoading` remis à `false`.
7. URL provider malformée / erreur serveur → `InlineErrorBadge`.

## Accessibilité

- Bouton SSO : surface 44 pt de haut, libellé texte fourni par le serveur (donc localisé par le serveur lui-même).
- `orDivider` masqué aux lecteurs d'écran (décoratif).
- Erreurs annoncées via `InlineErrorBadge` + `sensoryFeedback(.error, trigger: auth.errorMessage)`.
- Pas d'animation de forme : rien à réduire sous « Réduire les animations ».

## Fichiers

- `Sources/Features/Auth/Onboarding/LoginScreen.swift` — formulaire + séparateur + bouton SSO + état in-flight.
- `Sources/Features/Auth/AuthViewModel.swift` — `startOAuthFlow()`, `canOAuthLogin`, `oauthSessionHandler`, `applySession`.
- `Sources/Services/OAuthSessionPresenter.swift` — `ASWebAuthenticationSession` + ancre key-window.
- `Sources/Core/Protocols/ImmichClient.swift` — `getOAuthMobileURL` + `exchangeOAuthCode` (déjà wire).
- **Aucun** `OAuthLoadingView.swift`, **aucun** `.onOpenURL` : la session navigateur capture le callback.
