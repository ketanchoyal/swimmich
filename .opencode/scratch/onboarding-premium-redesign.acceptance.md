# Task: onboarding-premium-redesign

## Plan

**Objectif** : Redesign l'onboarding Immich SwiftUI vers "state of the art" SwiftUI iOS 17+ (premium hero redesign, Apple Photos/iCloud feel).

**Hypothèses** (grounded par specialist + challenger, fichier:ligne) :
- `Sources/Features/Auth/OnboardingFlowView.swift:221` — fichier unique actuel, 5 sous-vues, `NavigationStack(path: $path)` avec `Step` enum.
- `Sources/Features/Auth/AuthViewModel.swift` — `@Observable`, API publique (lignes 18-33 props, 70/96 methods). INTACT.
- `Sources/Features/Auth/LoginView.swift:41` + `ServerConnectView.swift:61` — **dead code** (legacy pre-onboarding auth screens, jamais instanciés depuis RootView, `Form` + `Color.statusError` deprecated alias). À SUPPRIMER dans cette tâche.
- `Sources/RootView.swift:29` — gate `auth.isAuthenticated`, ligne 44 `OnboardingFlowView()` instancié. INTACT.
- `Sources/DesignSystem/Tokens/*` — PV* tokens disponibles (Spacing/Radius/Font/Duration/Motion + Color+PV).
- `project.yml:21` — `- path: Sources` (glob récursif). NOUVEAUX fichiers sous `Sources/Features/Auth/Onboarding/*.swift` auto-inclus. Aucun xcodegen requis.
- `Tests/AuthViewModelTests.swift` — 5 tests, aucun test UI onboarding pré-existant.
- iPhone 17 simulator dispo (memory doc env). Nom exact fragile — dépend des simulators installés localement.

**Approche retenue** : B — Extract `Sources/Features/Auth/Onboarding/` module (6 fichiers : orchestrateur + 5 écrans).

**Étapes** :
1. Supprimer `Sources/Features/Auth/OnboardingFlowView.swift` (221 lignes).
2. Supprimer `Sources/Features/Auth/LoginView.swift` + `Sources/Features/Auth/ServerConnectView.swift` (dead code legacy, jamais instanciés depuis RootView — nettoyage cohérent avec redesign).
3. Créer `Sources/Features/Auth/Onboarding/OnboardingFlowView.swift` — orchestrateur `NavigationStack(path:)` + `Step` enum + `destination(for:)`.
4. Créer `WelcomeScreen.swift` — TabView `.tabViewStyle(.page)` multi-slide (brand intro), `.symbolEffect(.bounce)` + `.phaseAnimator`, gradient hero full-screen immichPrimary, bouton "Commencer" push `.serverURL`.
5. Créer `ServerURLScreen.swift` — custom input (pas Form), `@FocusState`, `submitLabel(.continue)`, `scrollDismissesKeyboard(.interactively)`, bouton verify `auth.connectServer()`, preserve `$PHASE_QR` TODO.
6. Créer `ServerVerifyScreen.swift` — display card custom (pas Form), info version/domain/initialized, error state immichError, preserve `$PHASE_CERT` TODO.
7. Créer `LoginScreen.swift` — custom inputs email/password, `@FocusState` managed, `submitLabel(.done)`, keyboard avoidance, bouton login `auth.login()`, preserve `$PHASE_OAUTH` TODO.
8. Créer `SuccessScreen.swift` — hero confirmation avec `.symbolEffect(.bounce)` checkmark.circle.fill immichSuccess, auto-dismiss ou manual.
9. Build + test pipeline.

## Acceptance Contract

### Approches candidates

- **A — Single-file rewrite** : tout dans 1 fichier ~600 lignes. Pro: diff unique, git blame propre. Con: charge cognitive review, pas réutilisable.
- **B — Extract Onboarding/ module** (retenu) : 6 fichiers, un par écran + orchestrateur. Pro: project.yml glob couvre (vérifié `project.yml:21`), clean boundary, future-proof pour $PHASE_*. Apple convention.
- **C — Hybrid** : orchestre inline + welcome extrait. Con: mixte inconsistent.

### Approche retenue + rationale

**B**. project.yml glob `Sources/` couvre auto, aucun xcodegen. Module auto-documenté, un diff par écran pour review. $PHASE_OAUTH/QR/CERT futurs pourront étendre leur écran sans toucher le flow. Aucun fichier > 150 lignes.

### Critères

```
### AC-001 [type: regression]
Assertion: Le projet compile sans erreur après le redesign.
Check post-impl: xcodebuild build -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
Pre-state attendu: BUILD SUCCEEDED
Post-state attendu: BUILD SUCCEEDED

### AC-002 [type: regression]
Assertion: Tous les tests existants passent sans régression.
Check post-impl: xcodebuild test -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | rg -c 'Test Suite.*passed'
Pre-state attendu: suite de tests passent (Tests/AuthViewModelTests.swift — 5 méthodes)
Post-state attendu: mêmes tests passent, 0 failures

### AC-003 [type: regression]
Assertion: Aucune signature publique dans AuthViewModel.swift n'est modifiée.
Check post-impl: git diff HEAD -- Sources/Features/Auth/AuthViewModel.swift
Pre-state attendu: sortie vide
Post-state attendu: sortie vide

### AC-004 [type: regression]
Assertion: Les APIs connectServer, login(email:password:), serverURLString, serverStatus, serverConfig, isLoading, errorMessage, isAuthenticated restent référencées dans le code onboarding.
Check post-impl: rg 'connectServer|login\(email|serverURLString|serverStatus|serverConfig|\.isLoading|\.errorMessage|\.isAuthenticated' Sources/Features/Auth/Onboarding/ | wc -l
Pre-state attendu: ≥ 8 occurrences dans OnboardingFlowView.swift actuel
Post-state attendu: ≥ 8 occurrences dans Onboarding/

### AC-005 [type: new]
Assertion: Les patterns iOS 17+ .symbolEffect, .phaseAnimator, @FocusState, .submitLabel, .contentTransition sont tous présents dans Onboarding/.
Check post-impl: rg -c 'symbolEffect|phaseAnimator|@FocusState|submitLabel|contentTransition' Sources/Features/Auth/Onboarding/
Pre-state attendu: 0 (aucun pattern actuellement dans OnboardingFlowView.swift)
Post-state attendu: ≥ 5

### AC-006 [type: regression]
Assertion: Flow 5 étapes préservé (welcome/serverURL/verify/login/success) + gate RootView auth.isAuthenticated inchangé.
Check post-impl: rg 'case \.welcome|case \.serverURL|case \.verify|case \.login|case \.success' Sources/Features/Auth/Onboarding/OnboardingFlowView.swift && rg 'auth\.isAuthenticated' Sources/RootView.swift
Pre-state attendu: 5 cases dans OnboardingFlowView.swift + 1 ref RootView.swift:29
Post-state attendu: 5 cases + 1 ref invariante

### AC-007 [type: regression]
Assertion: Les 3 phase markers TODO sont préservés (regex restreinte aux commentaires TODO pour exclure le header doc-comment).
Check post-impl: rg 'TODO: \$PHASE_' Sources/Features/Auth/Onboarding/ | wc -l
Pre-state attendu: 3 occurrences (TODOs seulement — header doc comment ligne 8 exclu par la regex restrictive)
Post-state attendu: 3 occurrences

### AC-008 [type: new]
Assertion: Aucune vue d'onboarding n'utilise Form { }.
Check post-impl: rg 'Form\s*\{' Sources/Features/Auth/Onboarding/
Pre-state attendu: 2 occurrences
Post-state attendu: 0 occurrence

### AC-009 [type: new]
Assertion: WelcomeScreen a un indicateur de page (TabView .tabViewStyle(.page) OU PageTabViewStyle OU indicateur custom).
Check post-impl: rg 'tabViewStyle.*page|PageTabViewStyle' Sources/Features/Auth/Onboarding/WelcomeScreen.swift
Pre-state attendu: 0 résultat (pas de WelcomeScreen.swift avant)
Post-state attendu: ≥ 1 résultat

### AC-010 [type: regression]
Assertion: project.yml inchangé — le glob Sources/ couvre les nouveaux fichiers.
Check post-impl: git diff HEAD -- project.yml
Pre-state attendu: sortie vide
Post-state attendu: sortie vide

### AC-011 [type: new]
Assertion: Legacy LoginView.swift + ServerConnectView.swift supprimés (dead code, plus de doublon avec les nouveaux Onboarding/LoginScreen).
Check post-impl: ls Sources/Features/Auth/LoginView.swift Sources/Features/Auth/ServerConnectView.swift 2>&1
Pre-state attendu: les 2 fichiers existent (41 + 61 lignes)
Post-state attendu: "No such file" pour les 2 (suppression confirmée)
```

### Failure modes (top 3 + quel AC les détecte)

| # | Failure mode | AC détecteur | Gravité |
|---|---|---|---|
| FM-1 | NavigationStack(path:) vs TabView multi-slide swipe conflict (runtime gesture, ne casse pas la compilation) | AC-006 (préservation flow) partiel + V-01/V-02 manuelle. AC-001 build ne détecte PAS ce cas runtime. | HIGH |
| FM-2 | @FocusState + clavier sur petit device (iPhone 17e), bouton caché | AC-001 ne détecte pas. Vérif manuelle V-05 + scrollDismissesKeyboard. | MEDIUM |
| FM-3 | Suppression accidentelle appel connectServer()/login() pendant refactor | AC-004 (rg sur méthodes) | HIGH |

## Vérifications manuelles (hors auto-feedback loop)

- V-01 : gradient hero full-screen welcome évoque Apple Photos/iCloud.
- V-02 : animations symbolEffect + phaseAnimator fluides (mode Slow Animations sim).
- V-03 : contentTransition(.push) sentiment progression horizontale cohérent.
- V-04 : VoiceOver fonctionnel (boutons labellisés, TextFields accessibles).
- V-05 : keyboard avoidance iPhone 17e, champs email/password restent visibles.
- V-06 : flux complet end-to-end (URL → Verify → Login → Success → TabView).
- V-07 : PVPrimaryButtonStyle réutilisé partout (cohérence DS).
- V-08 : Reduce Motion respecté (animations → linear 0.3s quand activé).
