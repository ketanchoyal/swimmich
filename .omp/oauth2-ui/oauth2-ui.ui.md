# Task: oauth2-ui — UI Brief (Liquid Glass Primary)

## Design Philosophy

Le login OAuth2 est une **fenêtre vitrée** sur l'identité provider. Le bouton OAuth est une capsule vitrée qui morph en sheet de connexion. C'est comme le "Sign in with Apple" mais pour tout provider OIDC — fluide, contextuel, et profondément vitré.

## Layout

```
LoginScreen
└── ZStack {
    ├── Background: subtle blurred photo (brand gradient)
    └── GlassEffectContainer {
        ├── ImmichLogo (brand identity)
        ├── Email input — glass field
        ├── Divider (glass line)
        ├── Password input — glass field
        ├── InlineErrorBadge (glass banner)
        ├── Sign In button — prominent glass CTA
        ├── OR divider (glass pill)
        └── OAuth button — glass capsule, morphs into auth sheet
    }
    .toolbar { ... }
```

### OAuthLoadingView — Glass auth flow
```
NavigationStack
└── ZStack {
    ├── Background: subtle blurred photo
    └── GlassEffectContainer {
        ├── Loading spinner — glass circle
        ├── "Connecting to provider..." — glass text
        ├── "A browser window will open..." — glass text
        └── Browser preview — glass frame
    }
```

## Components

### LoginScreen — Glass login form

```swift
struct LoginScreen: View {
    @State var vm: AuthViewModel
    @Namespace private var glassNamespace
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Brand gradient background
                LinearGradient(
                    colors: [Color.immichPrimary.opacity(0.3), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                GlassEffectContainer {
                    VStack(spacing: PVSpacing.s32) {
                        // Branding
                        ImmichLogo(title: "Immich")
                            .font(.pvTitleXL)
                            .foregroundStyle(Color.immichPrimary)
                            .glassEffect(.regular)
                            .padding(.top, PVSpacing.s48)
                        
                        // Email input — glass field
                        Section {
                            TextField("Email", text: $vm.email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .pvFieldSurface(focused: $vm.emailFocused)
                        }
                        
                        // Password input — glass field
                        Section {
                            SecureField("Password", text: $vm.password)
                                .textContentType(.password)
                                .pvFieldSurface(focused: $vm.passwordFocused)
                        }
                        
                        // Error banner — glass
                        if let error = vm.loginError {
                            InlineErrorBadge(message: error)
                                .glassEffect(.regular)
                        }
                        
                        // Sign In — prominent glass CTA
                        Button { vm.login() } label: {
                            HStack {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.pvBody)
                                Text("Sign In")
                                    .font(.pvHeadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(PVSpacing.s16)
                            .glassEffect(.interactive())
                        }
                        
                        // OR divider — glass pill
                        HStack(spacing: PVSpacing.s12) {
                            Divider()
                            Text("OR")
                                .font(.pvCaption)
                                .foregroundStyle(.tertiary)
                                .glassEffect(.regular)
                            Divider()
                        }
                        
                        // OAuth button — glass capsule, morphs into sheet
                        Button { vm.startOAuthFlow() } label: {
                            HStack(spacing: PVSpacing.s12) {
                                Image(systemName: "globe")
                                    .font(.pvBody)
                                    .foregroundStyle(Color.immichPrimary)
                                Text("Sign in with Provider")
                                    .font(.pvBody.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(PVSpacing.s16)
                            .glassEffect(.regular)
                            .glassEffectID("oauth_button", in: glassNamespace)
                        }
                    }
                    .padding(PVSpacing.s32)
                }
                .padding(.horizontal, PVSpacing.s16)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { vm.showServerSettings = true } label: {
                        Image(systemName: "gear")
                            .foregroundStyle(.secondary)
                            .glassEffect(.interactive())
                            .frame(width: 32, height: 32)
                    }
                }
            }
            .sheet(isPresented: $vm.showOAuthSession) {
                OAuthLoadingView(authURL: $vm.oauthAuthorizationURL)
            }
        }
    }
}
```

### OAuthLoadingView — Glass auth flow

```swift
struct OAuthLoadingView: View {
    @Binding var authURL: URL?
    @Environment(\.dismiss) private var dismiss
    @Namespace private var glassNamespace
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.immichBackground.ignoresSafeArea()
                
                GlassEffectContainer {
                    VStack(spacing: PVSpacing.s24) {
                        // Spinner — glass circle
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.immichPrimary)
                            .frame(width: 48, height: 48)
                            .glassEffect(.regular)
                            .scaleEffect(1.5)
                        
                        Text("Connecting to provider...")
                            .font(.pvBody)
                            .foregroundStyle(.primary)
                        
                        Text("A browser window will open to complete sign in.")
                            .font(.pvCaption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(PVSpacing.s24)
                }
                .padding(.horizontal, PVSpacing.s16)
            }
            .toolbar { ImmichAppBar(title: "Sign In") }
        }
        .onAppear { openAuthorizationSession() }
    }
}
```

## Interactions

### "Sign in with Provider" button
1. Tap → glass shimmer on button + haptic `.selection`
2. Shows OAuthLoadingView (glass morph from button via `glassEffectID`)
3. Calls `getOAuthMobileURL(redirectURI: "app.immich://oauth-callback")`
4. Opens ASWebAuthenticationSession
5. User signs in on provider's page
6. Provider redirects to `app.immich://oauth-callback`
7. ImmichSwiftUIApp catches URL → calls `exchangeOAuthCode`
8. Token received → AuthViewModel sets activeAccountID
9. OAuthLoadingView dismisses → user sees Timeline

### Error handling
- Authorization URL fetch fails → InlineErrorBadge (glass banner)
- User cancels → sheet dismisses (glass morph back to login)
- Exchange code fails → InlineErrorBadge with "Réessayer" button (glass interactive)
- Network error → InlineErrorBadge + retry button (glass interactive)

## Liquid Glass (iOS 26 — PRIMARY)

### Philosophy
- **Toutes** les surfaces du login sont des glass cards
- **Groupes** de inputs dans `GlassEffectContainer`
- **Morphing** du bouton OAuth en sheet via `glassEffectID`
- **Shimmer tactile** sur tous les éléments interactifs
- **Glass inputs** avec field surfaces

### Specific applications
1. **Login form** : All inputs in glass field surfaces
2. **Sign In button** : `.glassEffect(.interactive())` — prominent glass CTA
3. **OAuth button** : Glass capsule → morph into auth sheet via `glassEffectID`
4. **OR divider** : Glass pill
5. **OAuth loading** : Glass card with glass spinner
6. **Error badge** : Glass banner
7. **Gear button** : `.glassEffect(.interactive())` in toolbar

### Background
- Subtle Immich brand gradient behind the glass login — depth and brand identity

## Accessibility

- Glass cards maintain contrast via `.regular` glass (auto adjusts for Reduce Transparency)
- Email field: `.accessibilityLabel("Email address")`
- Password field: `.accessibilityLabel("Password")`
- Sign In button: `.accessibilityLabel("Sign in with email and password")`
- OAuth button: `.accessibilityLabel("Sign in with identity provider")`
- Loading view: `.accessibilityLabel("Loading, please wait")`
- InlineErrorBadge: `.accessibilityLabel("Error: \(message)")` + "Réessayer" button
- All elements ≥ 44×44pt
- Reduce Motion: glass morphs → opacity crossfade, no shape change

## Animations

- OAuth button → sheet: `.glassEffectTransition(.matchedGeometry)` — shape morph
- Button press: `PVMotion.snappy` (0.25s, damping 0.75)
- Sheet presentation: `detent(.medium)` — medium size
- Loading spinner: system ProgressView (always animating)
- Error badge appearance: `.contentTransition(.opacity)` — fade in
- Reduce Motion: spinner → pulsing dot (`.contentTransition(.opacity)`), no scale animation

## Key Files Modified

- `Sources/Features/Auth/LoginScreen.swift` — Glass form + OAuth button + glass morph
- `Sources/Features/Auth/AuthViewModel.swift` — startOAuthFlow(), handleOAuthCallback(url:)
- `Sources/ImmichSwiftUIApp.swift` — onOpenURL handler for app.immich://oauth-callback
- `Sources/Features/Auth/OAuthLoadingView.swift` — NEW: glass loading sheet
- `Sources/Core/Protocols/ImmichClient.swift` — already has getOAuthMobileURL + exchangeOAuthCode
