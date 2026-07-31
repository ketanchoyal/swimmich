# Task: prd-phase0-design-system-nav

## User intent (verbatim)
"I want you to implement @immich-swiftui-prd-design-system.md @ImmichColors.swift in the current project."
Scope choisi : **Full PRD Phase 0** (PRD §8 = Setup projet, client API généré, auth, design system composants de base — 3 semaines). Projet DÉJÀ mature. Tâche = aligner projet existant sur spec PRD Phase 0.

## Plan
**Objectif :** Aligner le projet SwiftUI Immich existant sur la Phase 0 du PRD `immich-swiftui-prd-design-system.md` — design system couleurs §5.2, navigation §4 (5 tabs Photos/Albums/Recherche/Partagé/Moi), onboarding 5 écrans §5.10 (scaffold, OAuth/QR/cert stubbés).

**Hypothèses (à vérifier par scout — fichier:ligne) :**
- `ImmichColors.swift` orphelin à la racine repo, PAS dans `Sources/` → pas compilé. project.yml:21 `sources: - path: Sources`.
- Color tokens actuels (`Sources/DesignSystem/Tokens/Color+PhotoVault.swift:11-24`) référencent Asset Catalog colorsets (`Color("BrandIndigo")` etc.). Valeurs divergent PRD §5.2.
- Asset Catalog colorsets dans `Resources/Assets.xcassets/*.colorset/Contents.json` (format JSON exact à vérifier par scout — decimal 0-1 vs 0x hex).
- RootView.swift:30-41 TabView 5 onglets = Timeline/Albums/Search/Trash/Backup. PRD §4 = Photos/Albums/Recherche/Partagé/Moi.
- SharedLinks feature existe (`Sources/Features/SharedLinks/`) mais pas tab. Trash/Backup doivent rester accessibles (via "Moi").
- Auth views dans `Sources/Features/Auth/` (ServerConnectView + LoginView + AuthViewModel). PRD §5.10 onboarding 5 écrans likely non implémenté.
- Tests DS : `Tests/DesignSystemTokensTests.swift` (testSpacingValues/testRadiusValues/testMotionAdaptiveReduceMotion/testColorTokenResolution). Toute mutation token DOIT updater ces tests.
- Env : Xcode 26.6, sims iPhone 17/17 Pro/17e/Air (iOS 26.5), jq /usr/bin/jq, PAS iPhone 16.
- project.yml:45-46 PRODUCT_BUNDLE_IDENTIFIER=fr.millianlmx.immich-ios, DEVELOPMENT_TEAM=2MJF39L8VY — MUST survive xcodegen.

**Décisions design importantes :**
- **Approche B retenue** : unification tokens (immich* canonical, anciens noms = aliases dépréciés) + retune Asset Catalog colorsets aux valeurs PRD + tab restructure + onboarding scaffold. Évite le full bulldozer (Dynamic Type semantic style swap = trop risqué pour 37 font call-sites ; OAuth/QR/cert réel = hors one-shot).
- **pvBody=17 STAYS** (iOS HIG, memory immich-redesign l.135) — ne PAS descendre à immich body=14. PRD §5.3 "Dynamic Type semantic styles" approximé par pv* tokens `.system(size:weight:)` qui supportent déjà Dynamic Type scaling natif.
- **OAuth/QR/cert-auto-signé stubbés** avec marqueurs `// TODO: $PHASE_OAUTH` / `$PHASE_QR` / `$PHASE_CERT` — flow structure correcte, impl réelle différée.
- **Trash relogé** : accessible depuis onglet "Moi" (pas suppression de feature).
- **Spacing PRD §5.5** (xs/sm/md/lg/xl = 4/8/16/24/32) = alias map vers PVSpacing existant (s4/s8/s16/s24/s32). Pas de nouveaux tokens si overlap.

**Étapes :**
1. Scout : vérifier chaque hypothèse + format JSON colorsets + contenu Auth/ + SharedLinks structure.
2. Intégrer `ImmichColors.swift` → `Sources/DesignSystem/Tokens/ImmichColors.swift` (déplacement + xcodegen).
3. Retuner Asset Catalog colorsets aux valeurs PRD §5.2 (BrandIndigo, LogoGreen, LogoRedPink, LogoYellow, AccentColor, BgSecondary, TextPrimary). Laisser BgPrimary=#FFF/#000 inchangé.
4. Ajouter aliases dans Color+PhotoVault.swift : `brandIndigo = immichPrimary` etc. (déprécation douce, call sites inchangés).
5. Restructurer RootView TabView → 5 tabs PRD (Photos=TimelineView, Albums, Recherche=SearchView, Partagé=SharedLinksView, Moi=new ProfileView avec logout + lien Trash + BackupSettings).
6. Scaffolder onboarding 5 écrans dans Sources/Features/Auth/ (WelcomeView, ServerURLView, ServerVerifyView, LoginView absorbé, SuccessView) + OnboardingViewModel. Marqueurs TODO pour OAuth/QR/cert.
7. Updater DesignSystemTokensTests si token signatures changent (probablement non — aliases transparents).
8. xcodegen generate → build iPhone 17 sim → test suite.
9. tester baselines A+B, reviewer.

## Acceptance Contract

### Approches candidates
- **A — Surgical Color Integration** : move ImmichColors.swift + update Assets seulement. Zero call-site migration. Risk: brand identity split, tabs/onboarding inchangés. Low value-per-effort pour scope "Full Phase 0".
- **B — Token Unification + Structural Phase 0** : A + immich* canonical (anciens = aliases) + tab restructure PRD §4 + onboarding scaffold (OAuth/QR/cert stubbés). RECOMMENDED.
- **C — Full Bulldozer** : B + Dynamic Type semantic style swap + OAuth/QR/cert réel + "Moi" complet + oklch 11-shade. Trop risqué one-shot (37 font call-sites, ASWebAuthenticationSession, TLS pinning).

### Approche retenue + rationale
**B**. Couvre Phase 0 structural (§5.2 couleurs, §4 tabs, §5.10 onboarding scaffold, §5.5 spacing alias) en respectant décisions existantes (pvBody=17, .system(size:) pour Dynamic Type). Aliases évitent 49 call-site rewrites. Stubs marqués pour sessions futures. Baseline 153 tests existe.

### Critères

### AC-001 [type: new]
Assertion: `Sources/DesignSystem/Tokens/ImmichColors.swift` est dans la target compilée et définit les 7 couleurs PRD §5.2 (`immichPrimary`, `immichBackground`, `immichForeground`, `immichGray`, `immichSuccess`, `immichError`, `immichWarning`).
Check post-impl: `rg 'static let immich(Primary|Background|Foreground|Gray|Success|Error|Warning)' Sources/DesignSystem/Tokens/ImmichColors.swift | wc -l` → `7`. ET `xcodebuild -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -c 'BUILD SUCCEEDED'` → `1`.
Pre-state attendu: NON satisfaite (fichier orphelin hors Sources/, `Color.immichPrimary` unresolvable dans module compilé).
Post-state attendu: satisfaite.

### AC-002 [type: new]
Assertion: Le fichier orphelin `/Users/20015659/immich_swiftui/ImmichColors.swift` n'existe plus à la racine du repo (déplacé dans Sources/, pas dupliqué).
Check post-impl: `test ! -f /Users/20015659/immich_swiftui/ImmichColors.swift && echo PASS || echo FAIL` → `PASS`.
Pre-state attendu: NON satisfaite (fichier existe à racine).
Post-state attendu: satisfaite.

### AC-003 [type: regression]
Assertion: `project.yml` préserve `PRODUCT_BUNDLE_IDENTIFIER: fr.millianlmx.immich-ios` et `DEVELOPMENT_TEAM: 2MJF39L8VY`.
Check post-impl: `rg 'PRODUCT_BUNDLE_IDENTIFIER: fr.millianlmx.immich-ios' project.yml && rg 'DEVELOPMENT_TEAM: 2MJF39L8VY' project.yml` → 2 matches.
Pre-state attendu: satisfaite (project.yml:45-46).
Post-state attendu: satisfaite.

### AC-004 [type: regression]
Assertion: La suite XCTest reste verte (≥153 tests, 0 failures) après intégration.
Check post-impl: `xcodebuild -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E '\*\* TEST (SUCCEEDED|FAILED)' ` → `** TEST SUCCEEDED **`.
Pre-state attendu: satisfaite (153 tests verts).
Post-state attendu: satisfaite.

### AC-005 [type: new]
Assertion: Les Asset Catalog colorsets reflètent les valeurs PRD §5.2 exactes (light/dark) pour BrandIndigo (#4250AF/#ACCBFA), LogoGreen (#81C784/#388E3C), LogoRedPink (#E57373/#D32F2F), LogoYellow (#FFB74D/#F57C00), AccentColor (#4250AF/#ACCBFA — transformation de format `idiom:universal` → composantes explicites + appearance dark), BgSecondary (#F6F6F4/#212121), TextPrimary (#000000/#E5E7EB). BgPrimary reste #FFFFFF/#000000.
Check post-impl: script python3 inline parsant chaque `Contents.json`, extrayant composantes RGB light (entry sans `appearances`) + dark (entry avec `appearances` contenant `luminosity:dark`), converties en hex, comparées aux attendus PRD (tolérance arrondi). Commande :
```
python3 - <<'PY'
import json
expected = {
  'BrandIndigo': ('4250AF','ACCBFA'), 'LogoGreen': ('81C784','388E3C'),
  'LogoRedPink': ('E57373','D32F2F'), 'LogoYellow': ('FFB74D','F57C00'),
  'AccentColor': ('4250AF','ACCBFA'), 'BgSecondary': ('F6F6F4','212121'),
  'TextPrimary': ('000000','E5E7EB'), 'BgPrimary': ('FFFFFF','000000'),
}
def to_hex(c): return '%02X%02X%02X' % tuple(round(float(c[k]) * 255) for k in ('red','green','blue'))
fails=[]
for name,(le,de) in expected.items():
    p='Resources/Assets.xcassets/%s.colorset/Contents.json'%name
    d=json.load(open(p)); cols=d['colors']
    light=next((x for x in cols if 'appearances' not in x), None)
    dark=next((x for x in cols if any(a.get('value')=='dark' for a in x.get('appearances',[]))), None)
    if not light or not dark: fails.append('%s missing light/dark entry'%name); continue
    lh=to_hex(light['color']['components']); dh=to_hex(dark['color']['components'])
    if lh!=le: fails.append('%s light %s!=%s'%(name,lh,le))
    if dh!=de: fails.append('%s dark %s!=%s'%(name,dh,de))
print('PASS' if not fails else 'FAIL: '+', '.join(fails))
PY
```
Attendu: `PASS`.
Pre-state attendu: NON satisfaite (valeurs actuelles divergent + AccentColor n'a pas de composantes explicites — challenger H3/objection 1).
Post-state attendu: satisfaite.

### AC-006 [type: new]
Assertion: `Sources/DesignSystem/Tokens/Color+PhotoVault.swift` expose les anciens noms (brandIndigo, brandIndigoMuted, statusSuccess, statusPending, statusError, accentInfo) comme aliases pointant vers les nouveaux tokens `immich*` — tout call site existant compile sans modification.
Check post-impl: `rg 'static (let|var) (brandIndigo|brandIndigoMuted|statusSuccess|statusError|statusPending|accentInfo)\b.*immich' Sources/DesignSystem/Tokens/Color+PhotoVault.swift | wc -l` → `≥6`. ET `rg 'Color\("(BrandIndigo|BrandIndigoMuted|LogoGreen|LogoRedPink|LogoYellow|LogoBlue)"\)' Sources/DesignSystem/Tokens/Color+PhotoVault.swift | wc -l` → `0` (plus aucun raw asset string reference pour ces 6 noms — accentInfo/LogoBlue inclus selon objection challenger 3).
Pre-state attendu: NON satisfaite (Color+PhotoVault.swift:12-17 référence Asset Catalog strings pour les 6).
Post-state attendu: satisfaite.

### AC-007 [type: new]
Assertion: `RootView.swift` expose 5 onglets PRD §4 ordonnés : Photos (TimelineView), Albums (AlbumsView), Recherche (SearchView), Partagé (SharedLinksView — fichier créé), Moi (ProfileView — fichier créé). Trash reste accessible via ProfileView. BackupSettingsView reste accessible via ProfileView. Le tab Trash est RETIRÉ du TabView racine.
Check post-impl:
- `rg -c '\.tabItem' Sources/RootView.swift` → `5`.
- `test -f Sources/Features/SharedLinks/SharedLinksView.swift && echo exists` → `exists` (FM-4).
- `test -f Sources/Features/Profile/ProfileView.swift && echo exists` → `exists` (FM-5).
- `rg 'Label\("(Partagé|Moi)"' Sources/RootView.swift | wc -l` → `2`.
- `rg 'person\.2\.fill' Sources/RootView.swift | wc -l` → `1`.
- `rg 'person\.crop\.circle' Sources/RootView.swift | wc -l` → `1`.
- `rg 'TrashView' Sources/Features/Profile/ProfileView.swift | wc -l` → `≥1` (FM-3 — Trash relogé).
- `rg 'BackupSettingsView' Sources/Features/Profile/ProfileView.swift | wc -l` → `≥1` (FM-6 — Backup relogé).
- `rg '\.tabItem' Sources/RootView.swift -A2 | rg -i 'trash' | wc -l` → `0` (tab Trash absent du TabView racine).
Pre-state attendu: NON satisfaite (RootView.swift:30-41 tabs Timeline/Albums/Search/Trash/Backup, aucun ProfileView/SharedLinksView, Trash est un tab).
Post-state attendu: satisfaite.

### AC-008 [type: new]
Assertion: Le flux onboarding PRD §5.10 comporte ≥5 structs View dans `Sources/Features/Auth/` couvrant les étapes Bienvenue / URL serveur / Vérification / Connexion / Succès. Flow existant absorbé.
Check post-impl: `rg '^struct .+: View' Sources/Features/Auth/ | wc -l` → `≥5`.
Pre-state attendu: NON satisfaite (2 Views : ServerConnectView, LoginView).
Post-state attendu: satisfaite.

### AC-009 [type: new]
Assertion: Les stubs OAuth/QR/cert-auto-signé sont marqués `// TODO: $PHASE_OAUTH`, `// TODO: $PHASE_QR`, `// TODO: $PHASE_CERT` dans `Sources/Features/Auth/` pour découverte future.
Check post-impl: `rg -c 'TODO: \$PHASE_OAUTH' Sources/Features/Auth/` → `≥1`. ET `rg -c 'TODO: \$PHASE_QR' Sources/Features/Auth/` → `≥1`. ET `rg -c 'TODO: \$PHASE_CERT' Sources/Features/Auth/` → `≥1`.
Pre-state attendu: NON satisfaite (aucun marqueur).
Post-state attendu: satisfaite.

### AC-010 [type: regression]
Assertion: `DesignSystemTokensTests` (testSpacingValues/testRadiusValues/testMotionAdaptiveReduceMotion/testColorTokenResolution) reste vert.
Check post-impl: `xcodebuild -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:ImmichSwiftUITests/DesignSystemTokensTests 2>&1 | grep -E '\*\* TEST (SUCCEEDED|FAILED)'` → `** TEST SUCCEEDED **`.
Pre-state attendu: satisfaite (4 tests verts).
Post-state attendu: satisfaite.

### AC-011 [type: regression]
Assertion: `xcodegen generate` régénère le `.pbxproj` depuis `project.yml` puis build réussit (ImmichColors.swift + SharedLinksView + ProfileView + onboarding Views enregistrés comme sources).
Check post-impl: `xcodegen generate --spec project.yml 2>&1 | tail -1` → `⚙ Generate tests project`. ET `xcodebuild -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -c 'BUILD SUCCEEDED'` → `1`.
Pre-state attendu: satisfaite (projet sain).
Post-state attendu: satisfaite.

### AC-012 [type: regression]
Assertion: Le auth gating de RootView reste fonctionnel — `auth.isAuthenticated == false` route vers le flow onboarding (pas vers le TabView), `true` route vers le TabView. La transition ServerConnectView → OnboardingView ne casse pas le gate.
Check post-impl: `rg 'isAuthenticated' Sources/RootView.swift | wc -l` → `≥1`. ET `rg '(OnboardingView|ServerConnectView)' Sources/RootView.swift | wc -l` → `≥1` (la branche non-auth pointe vers un View d'onboarding/auth, pas vers TabView).
Pre-state attendu: satisfaite (RootView.swift:29-45 gate isAuthenticated → ServerConnectView).
Post-state attendu: satisfaite (gate inchangé, branche non-auth pointe vers onboarding).

### Failure modes (top 3 + quel AC les détecte)
| # | Failure mode | AC détecteur | Mitigation |
|---|---|---|---|
| FM-1 | Retune Asset Catalog change silencieusement le rendu UI (statusError passe rose→rouge) sans casser build/tests — `DesignSystemTokensTests.testColorTokenResolution` ne valide que l'existence du token, pas sa valeur RGB. | aucun AC direct (rendu visuel non automatisable) | Vérif manuelle V-1. AC-005 valide les hex dans JSON mais pas le rendu View. |
| FM-2 | Alias rename casse un call site utilisant `Color("BrandIndigo")` raw string au lieu du token — compile OK, runtime couleur null/noire. | AC-006 (vérifie aliases + 0 raw string pour 6 noms) | Scout grep pré-migration `rg 'Color\("(BrandIndigo|BrandIndigoMuted|LogoGreen|LogoRedPink|LogoYellow|LogoBlue)"\)' Sources/` → doit être 0 hors Color+PhotoVault.swift. |
| FM-3 | Tab restructure orphelinise TrashView (tab Trash supprimé sans reloger). | AC-007 (`rg 'TrashView' Sources/Features/Profile/ProfileView.swift ≥1`) | ProfileView contient NavigationLink vers TrashView. |
| FM-4 | SharedLinksView non créé → tab Partagé vide ou build fail. | AC-007 (`test -f SharedLinksView.swift`) + AC-011 (build) | Créer `Sources/Features/SharedLinks/SharedLinksView.swift` réutilisant SharedLinkSheet. |
| FM-5 | ProfileView incomplet (pas logout, pas lien Trash, pas BackupSettings) → Moi tab vide. | AC-007 (vérifie TrashView + BackupSettingsView référencés dans ProfileView) | ProfileView scaffold = Form Section avec NavigationLink Trash + BackupSettings + bouton logout. |
| FM-6 | BackupSettingsView orpheliné après retrait tab Backup. | AC-007 (`rg 'BackupSettingsView' ProfileView ≥1`) | Relogé dans ProfileView. |
| FM-7 | Onboarding flow casse le auth gating RootView (ServerConnectView remplacé mais gate isAuthenticated cassé). | AC-012 (vérifie gate + branche non-auth route vers onboarding) | OnboardingView wrappé dans la branche `else` existante. |

## Vérifications manuelles (hors auto-feedback loop)
- **V-1** Rendu couleurs : sim iPhone 17 light + dark. Accent = #4250AF/#ACCBFA match logo Immich. Fond timeline #FFF/#000. Badges succès/erreur/warning bonnes teintes.
- **V-2** Flow onboarding 5 écrans : parcourir Bienvenue→URL→Vérification→Connexion→Succès. Chaque écran 1 CTA, pas mur formulaire.
- **V-3** Tab bar : Photos/Albums/Recherche/Partagé/Moi ordre + icônes PRD §5.4 (photo.on.rectangle.angled, square.stack, magnifyingglass, person.2.fill, person.crop.circle). Fond bgSecondary via immichBottomBar().
- **V-4** Dynamic Type XXL : textes lisibles non tronqués, CTA pleine largeur.
- **V-5** Trash accessible depuis onglet Moi.

## Scope boundary (NON couvert)
- OAuth réel (ASWebAuthenticationSession) — stubbé `$PHASE_OAUTH`.
- QR scan réel (AVFoundation/VisionKit) — stubbé `$PHASE_QR`.
- Cert auto-signé réel — stubbé `$PHASE_CERT`.
- Écran "Moi" complet (profil/serveur/stockage/à propos) — scaffold minimal (logout + lien Trash + BackupSettings).
- Dynamic Type semantic style swap (.title3/.headline) — pv* tokens .system(size:) restent (supportent déjà Dynamic Type).
- oklch 11-shade palette (PRD §5.2 note) — seules couleurs base (500).
- Pinch-to-zoom grille (PRD §5.5) — Phase 1.
