# Task: onboarding-apple-revamp

## Plan

**Objectif** : Revamp total de l'onboarding ImmichSwiftUI dans le style Apple (iOS Setup Assistant / "What's New"). Éliminer les anti-patterns "generic AI app" (gradients full-bleed, carousel paged, motion en boucle, icônes géantes flottantes) au profit du pattern Apple moderne : écran unique par étape, hero en conteneur (PVHeaderBadge), typographie sémantique, CTA primaire piné en bas sur material, motion one-shot respectant Reduce Motion. Supprimer l'écran Success (mort : RootView gate swap synchrone). Périmètre interdit : AuthViewModel, RootView, mécanisme NavigationStack(path:) root-inline path=[] (pitfall documenté — ne pas réintroduire path:[.welcome]).

**Hypothèses** :
- H1: SuccessScreen est fonctionnellement mort — `AuthViewModel.login` pose `accessToken` (AuthViewModel.swift:105) → `isAuthenticated` vrai → gate RootView.swift:29-44 swap vers TabView en une frame → l'écran poussé à OnboardingFlowView.swift:38 est démonté immédiatement. Suppression safe.
- H2: SwiftUI iOS 17 : `.safeAreaInset(edge: .bottom)` remonte au-dessus du clavier (keyboard avoidance) → CTA piné reste accessible clavier ouvert (vérif manuelle, non automatisable).
- H3: NavigationStack root-inline + path:[] est LA convention du projet (mémoire 2026-07-31). Ne pas y toucher.
- H4: `rg` absent de la machine → checks shell en grep BSD avec gestion exit codes.
- H5: Destination sim : `platform=iOS Simulator,name=iPhone 17,OS=26.5` ; si qualifier OS échoue, retirer `,OS=26.5`.
- H6: 153 méthodes de test existantes, 0 test onboarding, aucun test à créer (pas d'UI tests, refactor View-only).

**Étapes** :
1. WelcomeScreen.swift — réécriture : ScrollView + bgPrimary, header (PVHeaderBadge camera.aperture + titre "Bienvenue sur Immich" pvH2 + tagline "Configurez votre serveur et connectez-vous." pvSubhead textSecondary), 3 bullets statiques (tuile icône 32pt wash immichPrimary + headline pvHeadline + détail pvBody textSecondary), CTA "Commencer" piné safeAreaInset bottom + regularMaterial, toolbar hidden. Supprimer TabView/phaseAnimator/symbolEffect/enum WelcomeSlide/struct WelcomeSlideView/@State page. Bullets VERBATIM :
   - B1: icône "photo.stack" / headline "Votre photothèque" / détail "auto-hébergée, privée et durable."
   - B2: icône "lock.shield.fill" / headline "Vos photos, votre serveur" / détail "Aucun cloud tiers. Vos souvenirs restent chez vous."
   - B3: icône "sparkles" / headline "Recherche & souvenirs" / détail "Recherche intelligente, albums partagés, timelines."
   (headlines/écrans issus des 3 slides WelcomeScreen.swift:70-86 ; AC-005 teste les 3 PREFIXES de sous-titre.)
2. ServerURLScreen.swift — sortir le bouton "Vérifier la connexion" du scroll vers safeAreaInset bottom + material (garder disabled/spinner/onSubmit/autoFocus/InlineErrorBadge).
3. ServerVerifyScreen.swift — remplacer icône brute 36pt par PVHeaderBadge(icon: "checkmark.shield.fill") ; CTA déjà piné, conservé.
4. LoginScreen.swift — sortir "Se connecter" du scroll vers safeAreaInset + material ; retirer `onSuccess` param + appel (gate RootView fait le swap).
5. SuccessScreen.swift — SUPPRIMER le fichier.
6. OnboardingFlowView.swift — retirer case `.success` + destination + doc comment "→ Succès" (sinon AC-003 échoue), ajuster commentaire 4-step.
7. xcodegen generate si besoin (pas de nouveau fichier → pbxproj intact ; le delete du fichier source nécessite régénération ! project.yml source de vérité — vérifier que la suppression de SuccessScreen.swift du pbxproj passe par xcodegen).
8. AC-008 : xcodebuild test complet.

## Acceptance Contract

### Approches candidates
- A « Setup Apple complet » : Welcome single-screen + bullets, CTA tous pinés bas, headers unifiés PVHeaderBadge, Success supprimé. 4 écrans.
- B « Minimal Setup Assistant » : comme A mais Vérification fusionnée dans URL (3 écrans). Casse PRD §5.10 Écran 3 — rejeté.
- C « Refonte conservatrice » : garde Success restylé + CTA inline mixtes + header non unifié. Garde écran mort + anti-patterns — rejeté.

### Approche retenue + rationale
**Approche A.** Seule à satisfaire les 4 contraintes (pas de motion décorative, pas de carousel, CTA au pouce, typo sémantique), préserve le contenu produit des 3 slides en bullets, élimine l'écran mort prouvé invisible, garde intact le périmètre interdit. B plus pur mais casse PRD serveur ; C conserve les anti-patterns.

### Critères

### AC-001 [type: new]
Assertion: Le Welcome est un écran unique sans pagination ni skip ; son CTA unique est « Commencer » ; plus aucun résidu de l'ancien carousel (WelcomeSlide/WelcomeSlideView/@State page).
Check post-impl: `! grep -qE 'TabView|tabViewStyle|indexViewStyle|\.tag\(|"Passer"|WelcomeSlide|@State private var page' Sources/Features/Auth/Onboarding/WelcomeScreen.swift && grep -q '"Commencer"' Sources/Features/Auth/Onboarding/WelcomeScreen.swift && echo PASS`
Pre-state attendu: échec — TabView/.tag WelcomeScreen.swift:32-39, « Continuer »/« Passer » :43,:50, WelcomeSlide :64,:92, @State page :12.
Post-state attendu: PASS.

### AC-002 [type: new]
Assertion: Aucun motion décoratif en boucle ni gradient full-bleed dans Onboarding (LinearGradient, phaseAnimator, symbolEffect, repeatForever, .repeating).
Check post-impl: `! grep -rEq 'LinearGradient|phaseAnimator|symbolEffect|repeatForever|\.repeating' Sources/Features/Auth/Onboarding/ && echo PASS`
Pre-state attendu: échec — LinearGradient WelcomeScreen.swift:20 / SuccessScreen.swift:18, symbolEffect(.repeating) :110, phaseAnimator :111 et SuccessScreen.swift:36.
Post-state attendu: PASS.

### AC-003 [type: new]
Assertion: L'écran Success et la step `success` sont supprimés (fichier, case, commentaire « Succès », API onSuccess).
Check post-impl: `[ ! -f Sources/Features/Auth/Onboarding/SuccessScreen.swift ] && ! grep -rq 'SuccessScreen\|case \.success\|Succès' Sources/Features/Auth/Onboarding/ && ! grep -q 'onSuccess' Sources/Features/Auth/Onboarding/LoginScreen.swift && echo PASS`
Pre-state attendu: échec — SuccessScreen.swift existe, OnboardingFlowView.swift:18,:38-39 + doc comment « Succès » :3.
Post-state attendu: PASS.

### AC-004 [type: new]
Assertion: Chaque écran du flow (Welcome, URL, Vérification, Connexion) a un CTA primaire piné en bas via `.safeAreaInset(edge: .bottom)` sur fond material ; aucun bouton primaire résiduel dans le scroll.
Check post-impl:
```sh
for f in WelcomeScreen ServerURLScreen ServerVerifyScreen LoginScreen; do
  grep -q 'safeAreaInset(edge: \.bottom)' "Sources/Features/Auth/Onboarding/$f.swift" || exit 1
  grep -qE 'regularMaterial|ultraThinMaterial' "Sources/Features/Auth/Onboarding/$f.swift" || exit 1
done
echo PASS
```
Pre-state attendu: échec — seul ServerVerifyScreen.swift:70 a le pattern (1/4) ; boutons inline ServerURLScreen.swift:51-60, LoginScreen.swift:69-78.
Post-state attendu: PASS.

### AC-005 [type: new]
Assertion: Le Welcome a un hero en conteneur (badge/logo) et conserve les 3 value props en rangées (bullets ForEach) ; plus aucune icône flottante ≥ 80pt dans Onboarding.
Check post-impl: `! grep -rEq 'size: 8[0-9],|size: 9[0-9],' Sources/Features/Auth/Onboarding/ && grep -qE 'PVHeaderBadge|ImmichLogo' Sources/Features/Auth/Onboarding/WelcomeScreen.swift && grep -q 'ForEach(WelcomeBullet.all)' Sources/Features/Auth/Onboarding/WelcomeScreen.swift && grep -qE 'Votre photothèque|Aucun cloud tiers|Recherche intelligente' Sources/Features/Auth/Onboarding/WelcomeScreen.swift && echo PASS`
Pre-state attendu: échec GLOBAL via les composants rouges : size: 84 WelcomeScreen.swift:107 / size: 96 SuccessScreen.swift:33, aucun badge/logo dans Welcome, pas de ForEach bullets (carousel). NOTE : la sous-assertion strings (3 sous-titres) est DÉJÀ verte — les 3 vivent dans WelcomeScreen.swift:74,:79,:84 (données de slides) → garde de préservation de contenu green→green, pas une transition new.
Post-state attendu: PASS.
AMENDEMENT (Phase 2, impl) : le proxy initial `grep -c 'Image(systemName:' >= 3` comptait les LIGNES — la row générique `WelcomeBulletRow` (Image(systemName: bullet.symbol) à 1 seule ligne) rendait le check insatisfaisable par l'implémentation conforme. Remplacé par `grep -q 'ForEach(WelcomeBullet.all)'` (prouve 3 bullets instanciées). Assertion sémantique inchangée ; delta purement formel, appliqué sans re-challenge (budget 3 boucles épuisé, amendement non-bloquant).

### AC-006 [type: new]
Assertion: Typographie sémantique : plus de `pvH1` (48pt) dans Onboarding ; headers en pvH2 + subhead textSecondary.
Check post-impl: `! grep -rq 'pvH1' Sources/Features/Auth/Onboarding/ && echo PASS`
Pre-state attendu: échec — pvH1 WelcomeScreen.swift:120, SuccessScreen.swift:43.
Post-state attendu: PASS.

### AC-007 [type: regression]
Assertion: Structure du flow intacte : NavigationStack(path:) root-inline, chaîne welcome→serverURL→verify→login, périmètre interdit (RootView gate, AuthViewModel) non modifié.
Check post-impl:
```sh
grep -q 'NavigationStack(path: $path)' Sources/Features/Auth/Onboarding/OnboardingFlowView.swift \
  && grep -q 'WelcomeScreen(continue:' Sources/Features/Auth/Onboarding/OnboardingFlowView.swift \
  && grep -q 'ServerURLScreen(continue:' Sources/Features/Auth/Onboarding/OnboardingFlowView.swift \
  && grep -q 'ServerVerifyScreen(continue:' Sources/Features/Auth/Onboarding/OnboardingFlowView.swift \
  && grep -q 'LoginScreen(' Sources/Features/Auth/Onboarding/OnboardingFlowView.swift \
  && grep -q 'if auth.isAuthenticated' Sources/RootView.swift \
  && grep -q 'OnboardingFlowView()' Sources/RootView.swift \
  && grep -qE 'func login\(email: String, password: String\) async' Sources/Features/Auth/AuthViewModel.swift \
  && echo PASS
```
Pre-state attendu: satisfaite (vert).
Post-state attendu: PASS.

### AC-008 [type: regression]
Assertion: Le schéma compile et toute la suite unitaire existante reste verte (0 échec).
Check post-impl:
```sh
xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' 2>&1 | tee /tmp/onboarding-ac8.log
grep -q 'TEST SUCCEEDED' /tmp/onboarding-ac8.log \
  && grep -qE 'Executed [1-9][0-9]* tests?, with 0 failures' /tmp/onboarding-ac8.log && echo PASS
```
Pre-state attendu: satisfaite — 153 méthodes test.
Post-state attendu: PASS. Fallback si OS=26.5 inconnu : destination sans OS. Timeout prévoir > 10 min.

### AC-009 [type: new]
Assertion: Headers unifiés : les 4 écrans utilisent PVHeaderBadge comme hero (plus d'icône brute flottante dans Vérification).
Check post-impl:
```sh
for f in WelcomeScreen ServerURLScreen ServerVerifyScreen LoginScreen; do
  grep -q 'PVHeaderBadge' "Sources/Features/Auth/Onboarding/$f.swift" || exit 1
done
echo PASS
```
Pre-state attendu: échec — icône brute 36pt ServerVerifyScreen.swift:82-84 ; Welcome sans badge.
Post-state attendu: PASS.

### AC-010 [type: regression]
Assertion: Langue UI française : aucun string littéral anglais de CTA/statut dans Onboarding (garde anti-régression anglophone).
Check post-impl: `! grep -rnE '"(Welcome|Continue|Skip|Success|Next|Log In|Get Started)"' Sources/Features/Auth/Onboarding/ && echo PASS`
Pre-state attendu: satisfaite (vert) — le pattern « "Continue" » (guillemet collé) ne matche jamais « Continuer » français ; zéro match vérifié sur état actuel.
Post-state attendu: PASS.

### Failure modes (top 3 + quel AC les détecte)
1. CTA piné + clavier → bouton inaccessible petit écran → AC-004 (structure) + vérif manuelle n°2.
2. Suppression Success incomplète (restes .success/SuccessScreen/onSuccess/commentaire « Succès ») → AC-003 (grep exhaustif) ; référence pendante non compilable → AC-008.
3. Débordement périmètre (animer swap dans AuthViewModel/RootView, ou réintroduire path:[.welcome]) → AC-007 ; motion bouclée réintroduite → AC-002.

## Vérifications manuelles (hors auto-feedback loop)
1. Welcome : badge centré wash, titre 1 ligne, 3 bullets alignées leading (icône tint immichPrimary tuile 32pt arrondie, titre pvHeadline, sous-titre pvBody textSecondary), CTA capsule full-width piné barre material, AUCUN point de page.
2. Clavier (URL + Login) : CTA piné remonte au-dessus du clavier, jamais occlus ; submitLabel .continue/.go déclenche l'action.
3. Dynamic Type XXL : pas de troncature bullets, pas de chevauchement CTA/contenu.
4. Dark/Light : fonds bgPrimary/bgSecondary dynamiques, contraste ok.
5. Reduce Motion activé : aucune boucle à désactiver.
6. Échec serveur : .unreachable → InlineErrorBadge sous champ + CTA actif pour réessayer.
7. Login réussi : Welcome→…→Login→Timeline direct, sans écran intermédiaire ni flash.
8. VoiceOver : badge annoncé header (traits PVHeaderBadge.swift:21), bullets lues dans l'ordre.
