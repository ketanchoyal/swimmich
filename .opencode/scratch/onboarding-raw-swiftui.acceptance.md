# Task: onboarding-raw-swiftui

## Plan

**Objectif** : Revamp onboarding "trop custom" → "raw SwiftUI comme Apple". Restyle natif des 5 écrans (Welcome/ServerURL/Verify/Login/Success) avec primitives système (Form+Section insetGrouped, `.buttonStyle(.borderedProminent)` + `.controlSize(.large)`, polices sémantiques, couleurs système + tint, navigationTitle natifs), suppression des 4 composants DS devenus dead code (PVInputGroup/PVFieldSurface/PVHeaderBadge/InlineErrorBadge, utilisés UNIQUEMENT par onboarding — vérifié grep), disparition des artefacts custom (gradient hero, phaseAnimator, symbolEffect, carousel 3 slides, .toolbar(.hidden), .tracking(1) labels uppercase, fonds bgPrimary custom, PVPrimaryButtonStyle onboarding). Comportements PRD §5.10 préservés : 5 écrans UN focus, erreurs inline sous champ (jamais Alert), retry sur erreur réseau, clavier jamais fermé auto après erreur, chaînes submitLabel/onSubmit, autofocus, keyboardTypes, disabled states, TODO stubs $PHASE_*. Gate RootView + AuthViewModel + PVButtonStyle hors scope.

**Hypothèses** (groundées code avant impl) :
- H1 : Les 4 composants DS ne sont utilisés que par onboarding (grep Sources : les 4 noms n'apparaissent que dans leurs fichiers de définition + usages Onboarding/). Suppression safe.
- H2 : `PVPrimaryButtonStyle` reste utilisé hors onboarding (RootView.swift:81, TrashView.swift:106, TimelineView.swift:153) → PVButtonStyle.swift INTACT.
- H3 : Aucun test ne référence les composants/écrans onboarding (grep Tests = 0). Baseline = 153 tests verts.
- H4 : project.yml:45-46 contient PRODUCT_BUNDLE_IDENTIFIER fr.millianlmx.immich-ios + DEVELOPMENT_TEAM 2MJF39L8VY → `xcodegen generate` safe (pitfall mémoire : pbxproj jamais source de vérité, régénéré).
- H5 : Pitfall mémoire : `path: [Step] = []` (jamais `.welcome` dans path) — OnboardingFlowView.swift:21-26 conservé tel quel.
- H6 : PRD:220 interdit fusion d'écrans (pas de formulaire unique URL+email+password).

**Étapes** :
1. Réécrire les 5 écrans Onboarding/ en SwiftUI natif (Form insetGrouped pour input/verify, VStack native pour welcome/success, CTA borderedProminent+controlSize(.large), polices sémantiques, fonds système, erreurs inline, isHeader sur titres).
2. OnboardingFlowView.swift : INTACT (AC-07).
3. Supprimer Sources/DesignSystem/Components/{PVInputGroup,PVFieldSurface,PVHeaderBadge,InlineErrorBadge}.swift.
4. `xcodegen generate` (régénère pbxproj sans les fichiers supprimés).
5. Build + suite complète de tests (baseline B : contract).

## Acceptance Contract

### Approches candidates

- **A — Strip minimal in-place** : remplacer les composants custom par des primitives natives dans les 5 fichiers existants, sans supprimer les 4 composants DS. Pro : diff minimal, zéro regen. Con : 4 composants dead code restent (pattern session précédente : dead code supprimé), l'invitation "raw Apple" reste polluée par le legacy DS.
- **B — Raw SwiftUI rewrite + purge dead code (retenue)** : réécrire les 5 écrans avec les patterns natifs Apple (Form insetGrouped façon réglages, CTA borderedProminent, polices sémantiques), SUPPRIMER les 4 composants devenus morts + `xcodegen generate`. Pro : résultat 100% natif, codebase purgée, aligné décision mémoire (LoginView/ServerConnectView dead code supprimés). Con : nécessite regen pbxproj (mitigé : identity dans project.yml, H4 vérifiée).
- **C — Fusion en 1 formulaire unique** : on abandonne le flow 5 écrans. Pro : le plus "simple". Con : VIOLATION PRD:220 explicite ("Pas de formulaire unique avec URL + email + mot de passe d'un coup"), perd le focus-par-écran.

### Approche retenue + rationale

**B**. Le reproche user = "trop custom" : les composants DS (cartes, focus rings, badges wash, boutons capsule) SONT le problème. Les remplacer par du natif tout en laissant 4 composants morts dans le DesignSystem contredirait le raw-Apple et salirait la gouvernance (même rationale que la suppression LoginView/ServerConnectView). PRD §5.10 reste la spec fonctionnelle : 5 écrans, un focus par écran, erreurs inline, retry réseau — le restyle est cosmétique au-dessus d'un comportement verrouillé par les AC regression. Le carousel 3 slides de Welcome dévie du PRD Écran 1 (icône+titre+sous-titre+UN CTA) ET du raw Apple → remplacé par écran d'accueil simple.

### Critères

### AC-01 [type: new]
Assertion: Chaque CTA onboarding utilise `.buttonStyle(.borderedProminent)` + `.controlSize(.large)` (Welcome, ServerURL, Verify, Login — 4 CTA).
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
B=$(grep -rn 'borderedProminent' Sources/Features/Auth/Onboarding | wc -l | tr -d ' ')
C=$(grep -rn 'controlSize(.large)' Sources/Features/Auth/Onboarding | wc -l | tr -d ' ')
[ "$B" -ge 4 ] && [ "$C" -ge 4 ] && echo "PASS (borderedProminent=$B, controlSize.large=$C)" || echo "FAIL (borderedProminent=$B, controlSize.large=$C)"
```
Pre-state attendu: NON satisfaite (4 CTA en PVPrimaryButtonStyle → B=0 ; C=1 seul ProgressView Verify).
Post-state attendu: satisfaite (B≥4, C≥4).

### AC-02 [type: new]
Assertion: Les écrans portent un `navigationTitle` natif (≥3 écrans) et CHAQUE écran expose son titre de contenu via `.accessibilityAddTraits(.isHeader)` (5/5, PRD:256 — le trait quittait PVHeaderBadge.swift supprimé).
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
T=$(grep -rn 'navigationTitle' Sources/Features/Auth/Onboarding | wc -l | tr -d ' ')
H=$(grep -rn 'accessibilityAddTraits(.isHeader)' Sources/Features/Auth/Onboarding | wc -l | tr -d ' ')
[ "$T" -ge 3 ] && [ "$H" -ge 5 ] && echo "PASS (navTitle=$T, isHeader=$H)" || echo "FAIL (navTitle=$T, isHeader=$H)"
```
Pre-state attendu: NON satisfaite (T=3 mais H=0 dans Onboarding/, trait dans PVHeaderBadge.swift).
Post-state attendu: satisfaite (T≥3, H≥5).

### AC-03 [type: new]
Assertion: Zéro token PV, zéro couleur custom, zéro surface custom (cartes/focus ring/gradient/fond custom) dans Onboarding — polices sémantiques système uniquement.
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
N=$(grep -rnE '\.font\(\.pv|PVSpacing\.|PVMotion\.|PVRadius\.|Color\.(bg|text|immich)|ignoresSafeArea|RoundedRectangle|clipShape|tracking\(' Sources/Features/Auth/Onboarding | wc -l | tr -d ' ')
[ "$N" -eq 0 ] && echo "PASS (0)" || echo "FAIL ($N)"
```
Pre-state attendu: NON satisfaite (.pvH1/.pvBody/.pvCaption, PVSpacing.s24 etc., Color.bgPrimary:67, Color.textSecondaryPV, Color.immichError, tracking:27/31/49).
Post-state attendu: satisfaite (N=0).

### AC-04 [type: new]
Assertion: Les artefacts custom disparaissent : LinearGradient, phaseAnimator, symbolEffect, carousel (tabViewStyle/indexViewStyle/WelcomeSlide), bouton "Passer", `.toolbar(.hidden)`.
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
N=$(grep -rnE 'LinearGradient|phaseAnimator|symbolEffect|tabViewStyle|indexViewStyle|WelcomeSlide|toolbar\(\.hidden|Passer' Sources/Features/Auth/Onboarding | wc -l | tr -d ' ')
[ "$N" -eq 0 ] && echo "PASS (0)" || echo "FAIL ($N)"
```
Pre-state attendu: NON satisfaite (LinearGradient 2, phaseAnimator 2, symbolEffect 2, tabViewStyle 1, indexViewStyle 1, WelcomeSlide 3, toolbar(.hidden 2, Passer 1).
Post-state attendu: satisfaite (N=0).

### AC-05 [type: new]
Assertion: WelcomeScreen = écran 1 PRD : UN seul bouton CTA, titre `.largeTitle`, pas de carousel ni de "Passer".
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
D="Sources/Features/Auth/Onboarding/WelcomeScreen.swift"
B=$(grep -rn 'Button(' "$D" | wc -l | tr -d ' ')
L=$(grep -rn 'largeTitle' "$D" | wc -l | tr -d ' ')
P=$(grep -rn 'Passer' "$D" | wc -l | tr -d ' ')
[ "$B" -eq 1 ] && [ "$L" -ge 1 ] && [ "$P" -eq 0 ] && echo "PASS (Button=$B, largeTitle=$L, Passer=$P)" || echo "FAIL (Button=$B, largeTitle=$L, Passer=$P)"
```
Pre-state attendu: NON satisfaite (B=2 "Continuer"+"Passer", L=0, P=1).
Post-state attendu: satisfaite (B=1, L≥1, P=0).

### AC-06 [type: new]
Assertion: SuccessScreen = confirmation native : back désactivé via `.navigationBarBackButtonHidden(true)`, checkmark conservé, zéro `.toolbar(.hidden)`.
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
D="Sources/Features/Auth/Onboarding/SuccessScreen.swift"
BB=$(grep -rn 'navigationBarBackButtonHidden(true)' "$D" | wc -l | tr -d ' ')
CM=$(grep -rn 'checkmark.circle.fill' "$D" | wc -l | tr -d ' ')
TH=$(grep -rn 'toolbar(.hidden' "$D" | wc -l | tr -d ' ')
[ "$BB" -ge 1 ] && [ "$CM" -ge 1 ] && [ "$TH" -eq 0 ] && echo "PASS (backHidden=$BB, checkmark=$CM)" || echo "FAIL (backHidden=$BB, checkmark=$CM, toolbarHidden=$TH)"
```
Pre-state attendu: NON satisfaite (BB=0, back bloqué via toolbar(.hidden) ; CM=1 ; TH=1).
Post-state attendu: satisfaite (BB=1, CM=1, TH=0).

### AC-07 [type: regression]
Assertion: Orchestrateur inchangé : enum Step 5 cases, switch 5 cases, `path: [Step] = []` (jamais `.welcome` — pitfall mémoire `.opencode/memory.md:171-176`), NavigationStack(path:) + navigationDestination.
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
D="Sources/Features/Auth/Onboarding/OnboardingFlowView.swift"
C=$(grep -cE 'case \.(welcome|serverURL|verify|login|success)' "$D")
P=$(grep -F -c 'path: [Step] = []' "$D")
W=$(grep -F -c '[.welcome]' "$D")
N=$(grep -F -c 'NavigationStack(path: $path)' "$D")
ND=$(grep -F -c 'navigationDestination(for: Step.self)' "$D")
[ "$C" -ge 9 ] && [ "$P" -eq 1 ] && [ "$W" -eq 0 ] && [ "$N" -eq 1 ] && [ "$ND" -eq 1 ] && echo "PASS (cases=$C path=$P welcomeInPath=$W navstack=$N navdest=$ND)" || echo "FAIL (cases=$C path=$P welcomeInPath=$W navstack=$N navdest=$ND)"
```
Pre-state attendu: satisfaite (C=10 = 5 enum + 5 switch, P=1, W=0, N=1, ND=1).
Post-state attendu: satisfaite (identique).

### AC-08 [type: regression]
Assertion: ServerURLScreen et LoginScreen déclarent chacun un `@FocusState` (Login : `enum Field { case email, password }`) — pilotage clavier natif. Le check cible la DÉCLARATION (`^\s+@FocusState`), pas les doc-comments qui mentionnent le mot (leçon memory.md : entrée polish, pattern ancré).
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
S1=$(grep -cE '^\s+@FocusState' Sources/Features/Auth/Onboarding/ServerURLScreen.swift || true)
L1=$(grep -cE '^\s+@FocusState' Sources/Features/Auth/Onboarding/LoginScreen.swift || true)
L2=$(grep -c 'enum Field' Sources/Features/Auth/Onboarding/LoginScreen.swift || true)
[ "$S1" -eq 1 ] && [ "$L1" -eq 1 ] && [ "$L2" -eq 1 ] && echo "PASS (serverURL=$S1 login=$L1 field=$L2)" || echo "FAIL (serverURL=$S1 login=$L1 field=$L2)"
```
Pre-state attendu: satisfaite (déclarations ServerURLScreen.swift:14, LoginScreen.swift:18).
Post-state attendu: satisfaite.

### AC-09 [type: regression]
Assertion: Auto-focus premier champ via `.onAppear` (`isFocused = true` / `focus = .email`) ; clavier jamais fermé automatiquement après erreur (PRD §5.10).
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
M=$(grep -nE 'isFocused = true|focus = \.email' Sources/Features/Auth/Onboarding/ServerURLScreen.swift Sources/Features/Auth/Onboarding/LoginScreen.swift | wc -l | tr -d ' ')
[ "$M" -eq 2 ] && echo "PASS (autofocus=$M)" || echo "FAIL (autofocus=$M)"
```
Pre-state attendu: satisfaite (ServerURLScreen.swift:70, LoginScreen.swift:89).
Post-state attendu: satisfaite (M=2).

### AC-10 [type: regression]
Assertion: Chaînes de soumission clavier : serveur `.submitLabel(.continue)` + `onSubmit { connect() }` ; email `.next` → `focus = .password` ; password `.go` + `onSubmit { signIn() }`.
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
A=$(grep -c 'submitLabel' Sources/Features/Auth/Onboarding/ServerURLScreen.swift Sources/Features/Auth/Onboarding/LoginScreen.swift | awk -F: '{s+=$2} END{print s}')
O=$(grep -c 'onSubmit' Sources/Features/Auth/Onboarding/ServerURLScreen.swift Sources/Features/Auth/Onboarding/LoginScreen.swift | awk -F: '{s+=$2} END{print s}')
[ "$A" -ge 3 ] && [ "$O" -ge 3 ] && echo "PASS (submitLabel=$A onSubmit=$O)" || echo "FAIL (submitLabel=$A onSubmit=$O)"
```
Pre-state attendu: satisfaite (.continue:36, .next:37, .go:51, onSubmit ×3).
Post-state attendu: satisfaite.

### AC-11 [type: regression]
Assertion: keyboardType(.URL) serveur + keyboardType(.emailAddress) email + textInputAutocapitalization(.never) + autocorrectionDisabled + scrollDismissesKeyboard(.immediately) sur les 2 écrans.
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
K=$(grep -rnE 'keyboardType\(\.URL\)|keyboardType\(\.emailAddress\)|textInputAutocapitalization|autocorrectionDisabled' Sources/Features/Auth/Onboarding | wc -l | tr -d ' ')
S=$(grep -rc 'scrollDismissesKeyboard(.immediately)' Sources/Features/Auth/Onboarding/ServerURLScreen.swift Sources/Features/Auth/Onboarding/LoginScreen.swift | awk -F: '{s+=$2} END{print s}')
[ "$K" -ge 4 ] && [ "$S" -eq 2 ] && echo "PASS (keyboard=$K scroll=$S)" || echo "FAIL (keyboard=$K scroll=$S)"
```
Pre-state attendu: satisfaite (keyboardType ×2, autocap ×2, autocorrection ×2, scrollDismisses ×2).
Post-state attendu: satisfaite.

### AC-12 [type: regression]
Assertion: ZÉRO `Alert(` dans Onboarding/ — toutes les erreurs inline (PRD:251, jamais de popup bloquante).
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
N=$(grep -rF 'Alert(' Sources/Features/Auth/Onboarding/ | wc -l | tr -d ' ')
[ "$N" -eq 0 ] && echo "PASS (0)" || echo "FAIL ($N)"
```
Pre-state attendu: satisfaite (0 alert).
Post-state attendu: satisfaite (0 alert).

### AC-13 [type: new]
Assertion: ServerURLScreen : erreur rendue inline SOUS le champ (le rendu d'erreur précède le CTA dans le source) + bouton "Réessayer" NATIF présent dans le fichier écran quand `serverStatus == .unreachable` (PRD:237/252). Le label vivait dans InlineErrorBadge.swift:13 (supprimé) → le fichier écran doit maintenant le porter. Marqueurs robustes : première occurrence `errorMessage` vs label CTA "Vérifier la connexion" (indépendant de la syntaxe Button).
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
D="Sources/Features/Auth/Onboarding/ServerURLScreen.swift"
ORDER=$(awk '/errorMessage/ && !e {e=NR} /Vérifier la connexion/ {b=NR; exit} END{if (e>0 && b>0 && e<b) print "OK"; else print "ERR e="e" b="b}' "$D")
R=$(grep -c 'Réessayer' "$D" || true)
[ "$ORDER" = "OK" ] && [ "$R" -ge 1 ] && echo "PASS (order=$ORDER retry=$R)" || echo "FAIL (order=$ORDER retry=$R)"
```
Pre-state attendu: NON satisfaite — ordre OK (erreur l.44-46 < CTA l.56) MAIS R=0 ("Réessayer" vit dans InlineErrorBadge.swift:13, pas dans l'écran) → assertion globale non satisfaite.
Post-state attendu: satisfaite (erreur avant CTA + Réessayer natif dans l'écran).

### AC-14 [type: regression]
Assertion: LoginScreen : `errorMessage` rendu inline sous les champs, avant le CTA dans le source (première occurrence), jamais Alert (recoupe AC-12). Marqueur : première `errorMessage` vs label CTA "Se connecter" (robuste à la syntaxe Button).
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
D="Sources/Features/Auth/Onboarding/LoginScreen.swift"
ORDER=$(awk '/errorMessage/ && !e {e=NR} /Se connecter/ {b=NR; exit} END{if (e>0 && b>0 && e<b) print "OK"; else print "ERR e="e" b="b}' "$D")
[ "$ORDER" = "OK" ] && echo "PASS (order=$ORDER)" || echo "FAIL (order=$ORDER)"
```
Pre-state attendu: satisfaite (première errorMessage l.63 < label "Se connecter" l.74 ; l'occurrence l.83 `.animation(value: auth.errorMessage)` est APRÈS le CTA mais la première occurrence suffit).
Post-state attendu: satisfaite.

### AC-15 [type: regression]
Assertion: États disabled préservés avec les CONDITIONS exactes : ServerURL `disabled(...serverURLString.isEmpty...isLoading)`, Login `disabled(...email.isEmpty...password.isEmpty...isLoading)` ; Verify : bouton Continue gated par `case .reachable` + ProgressView pendant .checking.
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
S=$(grep -cE 'disabled\([^)]*serverURLString\.isEmpty[^)]*isLoading' Sources/Features/Auth/Onboarding/ServerURLScreen.swift || true)
L=$(grep -cE 'disabled\([^)]*email\.isEmpty[^)]*password\.isEmpty[^)]*isLoading' Sources/Features/Auth/Onboarding/LoginScreen.swift || true)
V=$(grep -c 'ProgressView' Sources/Features/Auth/Onboarding/ServerVerifyScreen.swift || true)
R=$(grep -cE 'case \.reachable' Sources/Features/Auth/Onboarding/ServerVerifyScreen.swift || true)
[ "$S" -eq 1 ] && [ "$L" -eq 1 ] && [ "$V" -ge 1 ] && [ "$R" -ge 1 ] && echo "PASS (serverURL=$S login=$L verifyPV=$V reachable=$R)" || echo "FAIL (serverURL=$S login=$L verifyPV=$V reachable=$R)"
```
Pre-state attendu: satisfaite (ServerURLScreen.swift:60, LoginScreen.swift:78, Verify ProgressView l.21 + case .reachable l.30).
Post-state attendu: satisfaite.

### AC-16 [type: regression]
Assertion: Les 3 stubs TODO conservés aux mêmes emplacements : $PHASE_QR (ServerURLScreen), $PHASE_CERT (ServerVerifyScreen), $PHASE_OAUTH (LoginScreen).
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
Q=$(grep -c 'TODO: \$PHASE_QR' Sources/Features/Auth/Onboarding/ServerURLScreen.swift || true)
C=$(grep -c 'TODO: \$PHASE_CERT' Sources/Features/Auth/Onboarding/ServerVerifyScreen.swift || true)
O=$(grep -c 'TODO: \$PHASE_OAUTH' Sources/Features/Auth/Onboarding/LoginScreen.swift || true)
[ "$Q" -eq 1 ] && [ "$C" -eq 1 ] && [ "$O" -eq 1 ] && echo "PASS (qr=$Q cert=$C oauth=$O)" || echo "FAIL (qr=$Q cert=$C oauth=$O)"
```
Pre-state attendu: satisfaite (ServerURLScreen.swift:49, ServerVerifyScreen.swift:67, LoginScreen.swift:59).
Post-state attendu: satisfaite.

### AC-17 [type: new]
Assertion: Les 4 fichiers PVInputGroup.swift / PVFieldSurface.swift / PVHeaderBadge.swift / InlineErrorBadge.swift sont ABSENTS de Sources/DesignSystem/Components/.
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
FOUND=""
for f in PVInputGroup PVFieldSurface PVHeaderBadge InlineErrorBadge; do
  test -f "Sources/DesignSystem/Components/$f.swift" && FOUND="$FOUND $f"
done
[ -z "$FOUND" ] && echo "PASS (4 fichiers absents)" || echo "FAIL (présents:$FOUND)"
```
Pre-state attendu: NON satisfaite (4 fichiers présents).
Post-state attendu: satisfaite.

### AC-18 [type: new]
Assertion: Zéro référence restante aux 4 noms dans tout Sources/.
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
N=$(grep -rE 'PVInputGroup|PVFieldSurface|PVHeaderBadge|InlineErrorBadge' Sources/ | wc -l | tr -d ' ')
[ "$N" -eq 0 ] && echo "PASS (0)" || echo "FAIL ($N)"
```
Pre-state attendu: NON satisfaite (références dans Onboarding/).
Post-state attendu: satisfaite (N=0).

### AC-19 [type: new]
Assertion: PVButtonStyle.swift intact : structs PVPrimaryButtonStyle + PVSubtleButtonStyle toujours définies ; usages onboarding purgés (4→0) ; usages hors onboarding préservés (RootView, TrashView, TimelineView).
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
S=$(grep -c 'struct PVPrimaryButtonStyle\|struct PVSubtleButtonStyle' Sources/DesignSystem/Components/PVButtonStyle.swift || true)
F=$(grep -rl 'PVPrimaryButtonStyle' Sources/ | wc -l | tr -d ' ')
O=$(grep -rl 'PVPrimaryButtonStyle' Sources/Features/Auth/Onboarding | wc -l | tr -d ' ')
[ "$S" -eq 2 ] && [ "$F" -eq 4 ] && [ "$O" -eq 0 ] && echo "PASS (structs=$S files=$F onboarding=$O)" || echo "FAIL (structs=$S files=$F onboarding=$O)"
```
Pre-state attendu: NON satisfaite (F=8 fichiers : PVButtonStyle + 4 écrans onboarding + RootView:81 + TrashView:106 + TimelineView:153 ; O=4).
Post-state attendu: satisfaite (2 structs, F=4, O=0).

### AC-20 [type: new]
Assertion: `xcodegen generate` régénère le pbxproj sans erreur et sans référence aux 4 fichiers supprimés.
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
xcodegen generate >/dev/null 2>&1 && echo "regen OK" || echo "regen FAIL"
N=$(grep -cE 'PVInputGroup|PVFieldSurface|PVHeaderBadge|InlineErrorBadge' ImmichSwiftUI.xcodeproj/project.pbxproj || true)
[ "$N" -eq 0 ] && echo "PASS (pbxproj clean)" || echo "FAIL (pbxproj refs=$N)"
```
Pre-state attendu: NON satisfaite (pbxproj référence encore les fichiers supprimés).
Post-state attendu: satisfaite.

### AC-21 [type: regression]
Assertion: Build complet OK après suppression + regen.
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
xcodebuild -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED' | tail -1
```
Pre-state attendu: satisfaite (baseline build vert).
Post-state attendu: satisfaite (BUILD SUCCEEDED).

### AC-22 [type: regression]
Assertion: Suite de tests complète toujours verte (baseline 153 ; aucun test ne référençait les 4 composants ni les écrans).
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
xcodebuild -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E 'Executed [0-9]+ tests, with [0-9]+ failure' | tail -1
```
Pre-state attendu: satisfaite (153 tests, 0 failures).
Post-state attendu: satisfaite (même total, 0 failures — si le total dévie, documenter l'écart ; "0 tests ran" = assertion non prouvée).

### AC-23 [type: new]
Assertion: Fonds natifs : Form (insetGrouped) ou ScrollView natif sur les écrans ; zéro fond COULEUR custom `.background(Color...)` (plus de Color.bgPrimary.ignoresSafeArea(), fond système conservé). `.background(.regularMaterial)` reste autorisé (modificateur système légitime, pattern Settings bottom-CAT).
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
FS=$(grep -cE 'Form \{|ScrollView' Sources/Features/Auth/Onboarding/*.swift | awk -F: '{s+=$2} END{print s}')
B=$(grep -rnE '\.background\(\s*Color\.' Sources/Features/Auth/Onboarding/ | wc -l | tr -d ' ')
[ "$FS" -ge 3 ] && [ "$B" -eq 0 ] && echo "PASS (formScroll=$FS colorBackground=$B)" || echo "FAIL (formScroll=$FS colorBackground=$B)"
```
Pre-state attendu: NON satisfaite (ScrollView ×3 mais `.background(Color.bgPrimary.ignoresSafeArea())` ×3).
Post-state attendu: satisfaite.

### AC-24 [type: new]
Assertion: Polices sémantiques système présentes dans Onboarding/ (≥5 usages de .largeTitle/.title2/.title3/.headline/.body/.subheadline/.footnote/.caption), zéro font custom.
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
N=$(grep -rEo '\.(largeTitle|title2|title3|headline|body|subheadline|footnote|caption)' Sources/Features/Auth/Onboarding/ | wc -l | tr -d ' ')
[ "$N" -ge 5 ] && echo "PASS (semantic=$N)" || echo "FAIL (semantic=$N)"
```
Pre-state attendu: NON satisfaite (usage .pvH1/.pvBody/.pvCaption etc.).
Post-state attendu: satisfaite (N≥5).

### AC-25 [type: new]
Assertion: WelcomeScreen = structure native Apple : icône SF Symbol + titre + sous-titre + UN CTA (recoupe AC-05) ; contenu textuel natif (pas de carousel, pas de gradient — recoupé par AC-04).
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
D="Sources/Features/Auth/Onboarding/WelcomeScreen.swift"
E=$(grep -c 'Image(systemName' "$D" || true)
T=$(grep -c 'Text(' "$D" || true)
B=$(grep -c 'Button(' "$D" || true)
[ "$E" -ge 1 ] && [ "$T" -ge 2 ] && [ "$B" -eq 1 ] && echo "PASS (icon=$E texts=$T button=$B)" || echo "FAIL (icon=$E texts=$T button=$B)"
```
Pre-state attendu: NON satisfaite (carousel 3 slides, 2 boutons, icônes animées dans WelcomeSlideView).
Post-state attendu: satisfaite.

### AC-26 [type: regression]
Assertion: Scope-lock : gate RootView intact (`auth.isAuthenticated ? TabView : OnboardingFlowView()`), API surface AuthViewModel intacte (les méthodes/propriétés utilisées par l'onboarding restent référencées), project.yml identity inchangée.
Check post-impl:
```bash
cd /Users/20015659/immich_swiftui
G=$(grep -c 'OnboardingFlowView()' Sources/RootView.swift || true)
A=$(grep -cE 'func (connectServer|login)\(|var (serverURLString|serverStatus|serverConfig|errorMessage|isLoading|isAuthenticated)' Sources/Features/Auth/AuthViewModel.swift || true)
P=$(grep -c 'fr.millianlmx.immich-ios' project.yml || true)
[ "$G" -eq 1 ] && [ "$A" -ge 7 ] && [ "$P" -eq 1 ] && echo "PASS (gate=$G api=$A identity=$P)" || echo "FAIL (gate=$G api=$A identity=$P)"
```
Pre-state attendu: satisfaite (RootView.swift:44, AuthViewModel, project.yml:45).
Post-state attendu: satisfaite.

### Failure modes (top 3 + quel AC les détecte)

- **FM-1 — Suppression composants casse build hors onboarding** : usage oublié d'un des 4 composants hors Onboarding/ ou pbxproj stalé (regen oublié) → compile error. Détecté : AC-18 (grep global 0) + AC-20 (regen + pbxproj clean) + AC-21 (build). AC-19 verrouille le cas symétrique (PVButtonStyle ne doit PAS être supprimé).
- **FM-2 — Sur-ingénierie déguisée en raw SwiftUI** : l'impl re-fabrique des wrappers custom (nouveau composant DS, fond couleur custom, font custom, carousel) au lieu de Form/TextField/Button natifs → le produit final reste "custom", le reproche user n'est pas réglé. Bug le plus coûteux (silencieux, compile-friendly). Détecté : AC-03 (zéro token/couleur/surface), AC-04 (zéro artefact), AC-23 (zéro fond couleur, Form/ScrollView natif), AC-24 (polices sémantiques), AC-25 (structure Welcome native), complété par vérif manuelle visuelle.
- **FM-3 — Comportements PRD perdus par "simplification"** : en réécrivant, oubli d'un état — clavier fermé auto après erreur, conditions disabled affaiblies, erreur placée après le CTA, stubs $PHASE_* supprimés, Alert réintroduit, Réessayer perdu (vivait dans le composant supprimé). Passent le build mais violent PRD §5.10. Détecté : AC-09 (clavier jamais fermé auto), AC-12 (0 Alert), AC-13 (ordre erreur + Réessayer natif), AC-14 (ordre erreur Login), AC-15 (conditions disabled EXACTES), AC-16 (stubs), AC-08/10/11 (focus/soumission/clavier).
- **FM-4 — Scope creep hors Onboarding/** : modification de AuthViewModel/RootView/project.yml pendant le restyle (le plus à risque : xcodegen regen + ondes de choc compile). Détecté : AC-26 (gate + API surface + identity verrouillés) + AC-21/22 (build + 153 tests).

## Vérifications manuelles (hors auto-feedback loop)

Lancer l'app sur sim iPhone 17 (logout ou reset content si authentifié). Parcourir les 5 écrans :

1. **Rendu visuel 5 écrans** : Welcome = icône + titre largeTitle + sous-titre + CTA borderedProminent, fond système uni (PAS de gradient) ; ServerURL = Form insetGrouped, champ URL bien encadré, fond gris système ; Verify = spinner pendant .checking, carte infos serveur native, Continue désactivé tant que pas .reachable ; Login = 2 champs en Section + CTA pleine largeur ; Success = checkmark vert + back interdit.
2. **Feel natif Form** : pull-to-scroll, groupes insetGrouped, haptique standard ; clavier s'ouvre au tap, scrollDismissesKeyboard(.immediately) le ferme au scroll ; barre de navigation titre + back natifs.
3. **Parcours erreurs (PRD §5.10)** : URL invalide → erreur inline SOUS le champ, clavier TOUJOURS ouvert, bouton Réessayer sur .unreachable ; mauvais mot de passe → erreur inline sous les champs, jamais d'Alert.
4. **Dynamic Type** : "Texte plus grand" max → rien ne tronque, champs/CTA suivent, les 5 écrans défilent.
5. **Dark mode** : fonds natifs gris foncé, textes lisibles, tint immichPrimary sur CTA cohérent.
6. **VoiceOver** : ordre logique (champ → erreur → bouton), traits .isHeader sur titres, labels TextField corrects, aucun élément caché focusable.
7. **Clavier petit écran** : champ actif visible au-dessus du clavier, Réessayer accessible, orientation paysage OK.
8. **Retour navigateur** : Login → back → Verify → ServerURL → Welcome, aucun dead-end ; depuis Success, back interdit.
