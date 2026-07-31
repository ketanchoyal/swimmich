# Task: onboarding-input-screens-polish

## Plan

**Objectif** : Redesign esthétique des 2 écrans d'input de l'onboarding (ServerURLScreen + LoginScreen) — champs groupés en carte, focus ring, headers en badge "bg-accent", erreur repositionnée sous le champ avec bouton Réessayer (PRD:237/252), InlineErrorBadge extrait en composant DS. Flow 5 étapes PRD §5.10 INTACT (pas de fusion d'écrans — PRD:220 l'interdit explicitement).

**Hypothèses** (groundées, pré-states vérifiés le 2026-07-31) :
- `Sources/Features/Auth/Onboarding/ServerURLScreen.swift` — champ URL `.background(Color.bgTertiary)` (l.38), PAS de carte/focus ring, header icône nue 36pt (l.72), erreur `.unreachable` → `InlineErrorBadge` ligne 56 APRÈS le bouton ligne 44 (PRD:237 violé : erreur doit être sous le champ), `InlineErrorBadge` défini ici l.96-114, TODO $PHASE_QR l.42.
- `Sources/Features/Auth/Onboarding/LoginScreen.swift` — 2 chips `bgTertiary` séparées (l.39, l.54) non groupées, focus enum Field{email,password}, badge erreur l.61-64 avant bouton l.66 (OK PRD), animation PVMotion.gentle l.80, TODO $PHASE_OAUTH l.59.
- `Sources/Features/Auth/Onboarding/ServerVerifyScreen.swift` — pattern carte bgSecondary+Radius.lg (l.116-117) à réutiliser. TODO $PHASE_CERT l.67.
- `OnboardingFlowView.swift` — path vide `= []` l.21 (pitfall mémoire : jamais .welcome dans path), 5 cases l.35-39.
- `Sources/DesignSystem/Components/` — 6 composants existants (PVStatusBadge, PVButtonStyle, ImmichAppBar, PVEmptyState, PVGridCell, PVAlbumCard). Nouveaux fichiers auto-inclus (project.yml:21 glob Sources/). project.yml l.45-46 contient PRODUCT_BUNDLE_IDENTIFIER + DEVELOPMENT_TEAM → xcodegen generate sûr (mémoire pitfall [2026-07-29]).
- Couleurs dispo : Color.immichPrimary, bgPrimary/bgSecondary/bgTertiary, textPrimaryPV/textSecondaryPV, immichError, brandIndigo (Color+PhotoVault.swift:37-42, ImmichColors.swift:13/49). Aucune couleur brute dans Features (gouvernance).
- `AuthViewModel.swift` — `normalizedBaseURL` public (l.50-58, auto-https existe), connectServer/login/session INTACT, ne pas toucher.
- Tests : 153 verts (somme `func test` = 153 vérifiée). Aucun test UI onboarding. `rg` ABSENT du PATH (checks en grep portable).
- Build : `xcodegen generate && xcodebuild build -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17'` (iPhone 17/17Pro/17e dispo, PAS iPhone 16).

**Étapes** :
1. Créer `Sources/DesignSystem/Components/PVInputGroup.swift` — `struct PVInputGroup<Content: View>` : conteneur carte `.background(Color.bgSecondary)` + `.clipShape(RoundedRectangle(cornerRadius: PVRadius.lg, style: .continuous))`. C'est la carte groupée (pattern ServerVerifyScreen l.116-117).
2. Créer `Sources/DesignSystem/Components/PVFieldSurface.swift` — ViewModifier `pvFieldSurface(focused: Bool)` : `.padding(PVSpacing.s16)` + overlay ring `.stroke(Color.immichPrimary, lineWidth: 1.5)` avec `.opacity(focused ? 1 : 0)` + `.animation(PVMotion.snappy, value: focused)`. PAS de background (la carte PVInputGroup la fournit). Focus lu au call-site (Bool), aucun binding générique.
3. Créer `Sources/DesignSystem/Components/PVHeaderBadge.swift` — badge 72pt, icône 32pt, wash `Color.immichPrimary.opacity(0.12)`, clipShape Radius.lg (pattern "badge bg-accent" PRD:223) + `.accessibilityAddTraits(.isHeader)` (PRD:256).
4. Créer `Sources/DesignSystem/Components/InlineErrorBadge.swift` — DEPLACE depuis ServerURLScreen.swift:96-114 + param `retry: (() -> Void)?` → bouton "Réessayer" (PRD:252).
5. Refactor ServerURLScreen : header → `PVHeaderBadge(icon: "link.badge.plus")`, champ dans `PVInputGroup` + `.pvFieldSurface(focused: isFocused)`, `.focused($isFocused)` conservé, erreur déplacée SOUS le champ AVANT le bouton, câblage retry → connect(), gardes disabled/clavier/onAppear/scrollDismissesKeyboard conservés, TODO $PHASE_QR préservé.
6. Refactor LoginScreen : header → `PVHeaderBadge(icon: "person.crop.circle.badge.checkmark")`, email+password groupés dans UN `PVInputGroup` avec `Divider()` entre les 2, `.pvFieldSurface(focused:)` sur chaque champ (focus == .email / == .password), focus chaîné conservé (.next/.go/focused equals/onSubmit focus=.password), erreur sous la carte avant CTA (déjà le cas), gardes conservés, TODO $PHASE_OAUTH préservé.
7. `xcodegen generate` (nouveaux fichiers) — identité préservée (project.yml source de vérité).
8. Build + tester (baseline A regression) + vérifier AC new/regression.

## Acceptance Contract

### Approches candidates

- **A — Restyle inline, zéro composant partagé** : carte + ring + badge dupliqués localement dans chaque écran. Pro : diff minimal. Con : duplication (2 écrans + futurs $PHASE_QR/OAUTH), InlineErrorBadge reste dans fichier écran, PRD:252/256 servis en doublon.
- **B — Extraction composants DS (retenue)** : `PVInputGroup` (carte), `PVFieldSurface` (modifier ring), `PVHeaderBadge` (badge + trait header), `InlineErrorBadge` déplacé + retry. Focus attaché au call-site (Bool / FocusState<Field>) — PAS de binding générique. Pro : DRY, pattern DS existant, évolutif. Con : 4 fichiers nouveaux.
- **C — Composant champ générique `PVFormField<F>` paramétré par `FocusState<F>.Binding`** : rejeté — domaines FocusState hétérogènes (URL: Bool vs Login: Field?), binding générique fragile au compile, chaînage .next/.go + SecureField diffèrent par champ ⇒ composant enflé, sur-ingénierie pour 2 écrans.

### Approche retenue + rationale

**B**. Cible exactement les défauts visuels identifiés (chips isolées → carte groupée ; pas de ring → ring focus ; icône nue → badge ; erreur déconnectée → sous le champ + Réessayer) dans le pattern DS existant (PVStatusBadge wash, ServerInfoCard carte bgSecondary+lg). `AuthViewModel` et `project.yml` intacts. `@FocusState` reste local aux écrans (Bool pour URL, Field? pour Login) — le modifier lit seulement `focused: Bool`, zéro risque compile. Les AC vérifient l'ADOPTION des composants par les écrans (pas seulement leur existence).

### Critères

```
### AC-001 [type: regression]
Assertion: Le projet compile après redesign (xcodegen régénère le pbxproj — nouveaux fichiers Components inclus).
Check post-impl: xcodegen generate && xcodebuild build -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
Pre-state attendu: BUILD SUCCEEDED
Post-state attendu: BUILD SUCCEEDED

### AC-002 [type: regression]
Assertion: Les 153 tests passent, 0 failure.
Check post-impl: xcodebuild test -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E 'Executed [0-9]+ tests' | tail -1
Pre-state attendu: "Executed 153 tests, with 0 failures"
Post-state attendu: "Executed ≥153 tests, with 0 failures"

### AC-003 [type: regression]
Assertion: AuthViewModel.swift n'est pas modifié.
Check post-impl: git diff HEAD -- Sources/Features/Auth/AuthViewModel.swift | wc -l
Pre-state attendu: 0
Post-state attendu: 0

### AC-004 [type: regression]
Assertion: project.yml inchangé (identité bundle/team préservée — le glob Sources/ couvre les nouveaux fichiers).
Check post-impl: git diff HEAD -- project.yml | wc -l
Pre-state attendu: 0
Post-state attendu: 0

### AC-005 [type: regression]
Assertion: Les 3 markers $PHASE_ survivent (QR/URL, OAUTH/Login, CERT/Verify).
Check post-impl: grep -rn 'TODO: \$PHASE_' Sources/ | wc -l
Pre-state attendu: 3
Post-state attendu: 3

### AC-006 [type: regression]
Assertion: Flow 5 étapes + pitfall path vide préservés (jamais .welcome dans path).
Check post-impl: grep -cE 'case \.(welcome|serverURL|verify|login|success)' Sources/Features/Auth/Onboarding/OnboardingFlowView.swift; grep -c 'path: \[Step\] = \[\]' Sources/Features/Auth/Onboarding/OnboardingFlowView.swift
Pre-state attendu: 5 puis 1 (l.35-39, l.21)
Post-state attendu: 5 puis 1

### AC-007 [type: regression]
Assertion: Aucun Form/List/Alert introduit (pas de formulaire unique PRD:220).
Check post-impl: grep -rnE 'Form\s*\{|List\s*\{|\.alert\(' Sources/Features/Auth/Onboarding/ | wc -l
Pre-state attendu: 0
Post-state attendu: 0

### AC-008 [type: regression]
Assertion: Chaîne de focus Login intacte (email→password, .next/.go, onSubmit focus=.password).
Check post-impl: grep -cE '^\s+\.submitLabel\(\.next\)' Sources/Features/Auth/Onboarding/LoginScreen.swift; grep -cE '^\s+\.submitLabel\(\.go\)' Sources/Features/Auth/Onboarding/LoginScreen.swift; grep -cE '^\s+\.focused\(\$focus, equals: \.email\)' Sources/Features/Auth/Onboarding/LoginScreen.swift; grep -cE '^\s+\.focused\(\$focus, equals: \.password\)' Sources/Features/Auth/Onboarding/LoginScreen.swift; grep -c 'onSubmit { focus = .password }' Sources/Features/Auth/Onboarding/LoginScreen.swift
Pre-state attendu: 1 ×5
Post-state attendu: 1 ×5

### AC-009 [type: regression]
Assertion: Guards disabled CTA conservés (URL: vide/loading ; Login: email/password/loading).
Check post-impl: grep -c 'disabled(auth.serverURLString.isEmpty || auth.isLoading)' Sources/Features/Auth/Onboarding/ServerURLScreen.swift; grep -c 'disabled(email.isEmpty || password.isEmpty || auth.isLoading)' Sources/Features/Auth/Onboarding/LoginScreen.swift
Pre-state attendu: 1 ; 1
Post-state attendu: 1 ; 1

### AC-010 [type: regression]
Assertion: Config clavier conservée (URL/email, autocap never, autocorrection off).
Check post-impl: grep -c 'keyboardType(.URL)' Sources/Features/Auth/Onboarding/ServerURLScreen.swift; grep -c 'keyboardType(.emailAddress)' Sources/Features/Auth/Onboarding/LoginScreen.swift; grep -rc 'textInputAutocapitalization(.never)' Sources/Features/Auth/Onboarding/; grep -rc 'autocorrectionDisabled' Sources/Features/Auth/Onboarding/
Pre-state attendu: 1 ; 1 ; 2 ; 2
Post-state attendu: 1 ; 1 ; 2 ; 2

### AC-011 [type: regression]
Assertion: Auto-focus onAppear conservé (URL champ, Login email).
Check post-impl: grep -c 'onAppear { isFocused = true }' Sources/Features/Auth/Onboarding/ServerURLScreen.swift; grep -c 'onAppear { focus = .email }' Sources/Features/Auth/Onboarding/LoginScreen.swift
Pre-state attendu: 1 ; 1
Post-state attendu: 1 ; 1

### AC-012 [type: regression]
Assertion: Scaffolding écran conservé (scrollDismissesKeyboard immédiat, fond bgPrimary, navigationTitle inline).
Check post-impl: grep -cE '^\s+\.scrollDismissesKeyboard\(\.immediately\)' Sources/Features/Auth/Onboarding/ServerURLScreen.swift Sources/Features/Auth/Onboarding/LoginScreen.swift; grep -cE '^\s+\.background\(Color\.bgPrimary\.ignoresSafeArea' Sources/Features/Auth/Onboarding/ServerURLScreen.swift Sources/Features/Auth/Onboarding/LoginScreen.swift; grep -c 'navigationBarTitleDisplayMode(.inline)' Sources/Features/Auth/Onboarding/ServerURLScreen.swift Sources/Features/Auth/Onboarding/LoginScreen.swift
Pre-state attendu: 1+1 ; 1+1 ; 1+1
Post-state attendu: 1+1 ; 1+1 ; 1+1

### AC-013 [type: regression]
Assertion: Zéro alias déprécié / couleur brute dans Onboarding (gouvernance).
Check post-impl: grep -rnE 'brandIndigo|statusSuccess|statusError|statusPending|accentInfo|#[0-9A-Fa-f]{6}|UIColor|Color\(red' Sources/Features/Auth/Onboarding/ | wc -l
Pre-state attendu: 0
Post-state attendu: 0

### AC-014 [type: regression]
Assertion: Badge erreur Login reste positionné AVANT le CTA (inline sous la carte champs).
Check post-impl: [ $(grep -n 'InlineErrorBadge' Sources/Features/Auth/Onboarding/LoginScreen.swift | head -1 | cut -d: -f1) -lt $(grep -n 'Button(action: signIn)' Sources/Features/Auth/Onboarding/LoginScreen.swift | head -1 | cut -d: -f1) ] && echo OK || echo FAIL
Pre-state attendu: OK
Post-state attendu: OK

### AC-015 [type: regression]
Assertion: Écrans hors-scope byte-identiques (Flow/Verify/Welcome/Success — fichiers untracked, shasum requis car git diff inopérant).
Check post-impl: shasum Sources/Features/Auth/Onboarding/OnboardingFlowView.swift Sources/Features/Auth/Onboarding/ServerVerifyScreen.swift Sources/Features/Auth/Onboarding/WelcomeScreen.swift Sources/Features/Auth/Onboarding/SuccessScreen.swift
Pre-state attendu: 777f481671b8b72375ffeacfd714c3d34c812bec 83a2a069589ee3b3d8e25bf19414579833514415 8666a9630605ba44f658b0a5068f923dd62ede08 55d52ffd3b3d5aa409570fb9521f3c07f403ea57
Post-state attendu: identiques (4/4)

### AC-016 [type: regression]
Assertion: Animation d'erreur Login conservée (PVMotion.gentle sur errorMessage).
Check post-impl: grep -cE '^\s+\.animation\(PVMotion\.gentle, value: auth\.errorMessage\)' Sources/Features/Auth/Onboarding/LoginScreen.swift
Pre-state attendu: 1 (l.80)
Post-state attendu: 1

### AC-017 [type: regression]
Assertion: Focus reste local aux écrans — aucune déclaration @FocusState dans les composants DS (pattern declaration-only, doc-comment exclu).
Check post-impl: grep -cE '^\s+@FocusState' Sources/Features/Auth/Onboarding/ServerURLScreen.swift Sources/Features/Auth/Onboarding/LoginScreen.swift; grep -rn '@FocusState' Sources/DesignSystem/Components/ | wc -l
Pre-state attendu: 1+1 ; 0
Post-state attendu: 1+1 ; 0

### AC-101 [type: new]
Assertion: Champs groupés en carte via PVInputGroup sur les 2 écrans ; Divider entre email/password sur Login ; chips bgTertiary isolées supprimées des 2 écrans.
Check post-impl: grep -c 'PVInputGroup' Sources/Features/Auth/Onboarding/ServerURLScreen.swift; grep -c 'PVInputGroup' Sources/Features/Auth/Onboarding/LoginScreen.swift; grep -c 'Divider()' Sources/Features/Auth/Onboarding/LoginScreen.swift; grep -c 'background(Color.bgTertiary)' Sources/Features/Auth/Onboarding/ServerURLScreen.swift; grep -c 'background(Color.bgTertiary)' Sources/Features/Auth/Onboarding/LoginScreen.swift
Pre-state attendu: 0 ; 0 ; 0 ; 1 ; 2
Post-state attendu: ≥1 ; ≥1 ; ≥1 ; 0 ; 0

### AC-102 [type: new]
Assertion: Ring de focus DS existe (stroke immichPrimary conditionné par focused) ET est adopté par les 2 écrans via pvFieldSurface.
Check post-impl: grep -rn 'stroke(Color.immichPrimary' Sources/DesignSystem/Components/ | wc -l; grep -c 'pvFieldSurface' Sources/Features/Auth/Onboarding/ServerURLScreen.swift; grep -c 'pvFieldSurface' Sources/Features/Auth/Onboarding/LoginScreen.swift
Pre-state attendu: 0 ; 0 ; 0
Post-state attendu: ≥1 ; ≥1 ; ≥1

### AC-103 [type: new]
Assertion: Header badge DS (PVHeaderBadge avec wash immichPrimary.opacity(0.12)) adopté par les 2 écrans ; icône nue 36pt supprimée.
Check post-impl: grep -c 'PVHeaderBadge' Sources/Features/Auth/Onboarding/ServerURLScreen.swift; grep -c 'PVHeaderBadge' Sources/Features/Auth/Onboarding/LoginScreen.swift; grep -c 'immichPrimary.opacity(0.12)' Sources/DesignSystem/Components/PVHeaderBadge.swift; grep -c 'system(size: 36' Sources/Features/Auth/Onboarding/ServerURLScreen.swift; grep -c 'system(size: 36' Sources/Features/Auth/Onboarding/LoginScreen.swift
Pre-state attendu: 0 ; 0 ; 0 ; 1 ; 1
Post-state attendu: ≥1 ; ≥1 ; ≥1 ; 0 ; 0

### AC-104 [type: new]
Assertion: Erreur URL repositionnée SOUS le champ, AVANT le bouton (actuellement après le bouton → PRD:237 violé).
Check post-impl: [ $(grep -n 'InlineErrorBadge' Sources/Features/Auth/Onboarding/ServerURLScreen.swift | head -1 | cut -d: -f1) -lt $(grep -n 'Button(action: connect)' Sources/Features/Auth/Onboarding/ServerURLScreen.swift | head -1 | cut -d: -f1) ] && echo OK || echo FAIL
Pre-state attendu: FAIL (badge l.56 > bouton l.44)
Post-state attendu: OK

### AC-105 [type: new]
Assertion: InlineErrorBadge déplacé dans DesignSystem/Components/ avec action retry optionnelle ; écran URL câble "Réessayer" → connect() sur .unreachable (PRD:252).
Check post-impl: grep -c 'struct InlineErrorBadge' Sources/DesignSystem/Components/InlineErrorBadge.swift; grep -c 'struct InlineErrorBadge' Sources/Features/Auth/Onboarding/ServerURLScreen.swift; grep -rn 'Réessayer' Sources/ | wc -l; grep -c 'retry' Sources/Features/Auth/Onboarding/ServerURLScreen.swift
Pre-state attendu: 0 ; 1 ; 0 ; 0
Post-state attendu: 1 ; 0 ; ≥1 ; ≥1

### AC-106 [type: new]
Assertion: Titre exposé en header VoiceOver via accessibilityAddTraits(.isHeader) dans PVHeaderBadge (PRD:256), adopté par les 2 écrans.
Check post-impl: grep -rn 'accessibilityAddTraits' Sources/DesignSystem/Components/PVHeaderBadge.swift | wc -l; grep -c 'PVHeaderBadge' Sources/Features/Auth/Onboarding/ServerURLScreen.swift; grep -c 'PVHeaderBadge' Sources/Features/Auth/Onboarding/LoginScreen.swift
Pre-state attendu: 0 ; 0 ; 0
Post-state attendu: ≥1 ; ≥1 ; ≥1
```

### Failure modes (top 3 + quel AC les détecte)

| # | Failure mode | AC détecteur | Gravité |
|---|---|---|---|
| FM-1 | Chaîne de focus Login cassée pendant le regroupement en carte (.submitLabel/.focused/.onSubmit perdus) → silent UX regression, aucun test UI ne la rattrape | AC-008 (+ AC-001 compile) | HIGH |
| FM-2 | Réordonnancement badge erreur URL oublié (reste après bouton) OU Réessayer non câblé → PRD:237/252 non servis | AC-104 + AC-105 | MEDIUM |
| FM-3 | Débordement scope : Welcome/Success/Verify/Flow ou AuthViewModel ou project.yml touchés (fichiers untracked → git diff aveugle) | AC-015 (shasum) + AC-003/AC-004 | HIGH |

## Vérifications manuelles (hors auto-feedback loop)

- V-01 : ring de focus immichPrimary visible sur champ actif, disparaît au blur, animation snappy non saccadée.
- V-02 : carte groupée lisible light/dark, Divider subtile, pas d'effet "double fond" (chip bgTertiary résiduelle dans carte).
- V-03 : badge header proportionnel (72pt, icône centrée), cohérent entre les 2 écrans.
- V-04 : erreur URL s'affiche sous le champ (pas en bas d'écran), bouton Réessayer relance le ping, clavier RESTE OUVERT après erreur (PRD:253).
- V-05 : keyboard avoidance iPhone 17e — CTA "Vérifier/Se connecter" atteignable sans masquage.
- V-06 : Dynamic Type XXL — CTA pleine largeur, texte enroulé non tronqué.
- V-07 : VoiceOver — titre lu comme header, champs labellisés, erreur annoncée.
- V-08 : E2E complet URL→Verify→Login→Success→TabView.
