# Task: app-lock-face-id

## Plan
**Objectif**: App Lock Face ID/Touch ID (cahier §1 MVP). Gate app launch + retour background via LocalAuthentication. Toggle persistant dans réglages. Fallback passcode. Apple-Photos-grade.

**Hypothèses**:
- Pattern existant: protocole → DI → @Observable @MainActor ViewModel → mock testable.
- `DependencyContainer` (@MainActor singleton) étendu avec `appLock`.
- `ImmichSwiftUIApp` observe `@Environment(\.scenePhase)`.
- `RootView` reçoit `appLock` + gate conditionnel.
- Testabilité: `MockAppLockService` sans biométrie.
- Build Xcode 26.6 + iPhone 17 Pro sim, iOS 17+.

**Approche retenue**: A — `AppLockService` protocole + `AppLockViewModel` (@Observable @MainActor wrap LAContext + @AppStorage), `scenePhase` dans App, gate dans RootView, Mock pour CI. **LAContext eval extrait derrière closure injectable** `() async -> AuthResult` pour testabilité intégration (objection challenger #2). **Init: isLocked = isEnabled** au lancement frais (objection #3). **NSFaceIDUsageDescription** ajouté Info.plist + project.yml (objection #1).

**Étapes**:
1. `Sources/Core/Protocols/AppLockService.swift` — protocole (isLocked, isEnabled, authenticate() async -> Bool, setEnabled, lock(), var isAuthenticating: Bool { get }).
2. `Sources/Features/Auth/AppLockViewModel.swift` — @Observable @MainActor impl. `init(evaluator: @escaping () async -> Bool = AppLockViewModel.systemEvaluator)`. `systemEvaluator` = wrapper statique sur LAContext.evaluatePolicy(.deviceOwnerAuthentication). @AppStorage("app_lock_enabled"). **`init` set `isLocked = isEnabled`** (fresh launch locked). Flag `isAuthenticating` anti-race: `lock()` no-op si `isAuthenticating == true`.
3. `Sources/DependencyContainer.swift` — expose `let appLock: AppLockViewModel` (**type concret @Observable**, pas `any AppLockService` — résolution objection loop 3: `.environment()` exige type concret conforme Observable, cf pattern `auth: AuthViewModel` dans RootView.swift). Protocol `AppLockService` reste pour abstraction + MockAppLockService pour futurs consumers.
4. `Sources/ImmichSwiftUIApp.swift` — observe scenePhase, lock au .background, unlock au .active (si enabled).
5. `Sources/RootView.swift` — reçoit appLock, gate: si locked && enabled → LockView overlay (blur material + bouton Unlock).
6. `Sources/Features/Upload/UploadViewModel.swift` (BackupSettingsView) — Toggle "Require Face ID" bindé sur appLock.setEnabled. **appLock reçu via `@Environment`** (ajouté `.environment(appLock)` dans RootView, cohérent avec `.environment(auth)`).
7. `Tests/Mocks/MockAppLockService.swift` — mock configurable.
8. `Tests/AppLockViewModelTests.swift` — tests AC: injecte evaluator fake (toujours true / toujours false) pour tester AppLockViewModel SANS LAContext réel. Couvre: init enabled=true → isLocked=true; setEnabled(false)→isLocked=false; lock()→isLocked=true; authenticate réussi→isLocked=false + isAuthenticating transitoire; authenticate échoue→isLocked reste true.
9. `project.yml`: ajouter `info.properties.NSFaceIDUsageDescription` + `Resources/Info.plist` clé correspondante. Puis `xcodegen generate`.
10. Build + tests.

## Acceptance Contract

### Approches candidates
**A (retenue)**: DI + ViewModel + scenePhase + RootView gate + Mock. Pattern codebase, testable, HIG-aligned. **LAContext eval derrière closure injectable** (objection #2), **init isLocked=isEnabled** (#3), **NSFaceIDUsageDescription** (#1).
**B**: Tout inline dans RootView. Casserait pattern MVVM/DI, non testable.
**C**: Double UIWindow UIKit bridging. Fragile scene lifecycle, overkill.

### Approche retenue + rationale
**A**. Alignée pattern existant. Testable via Mock. Photos.app = scenePhase + LAContext. Risque double-lock mitigé par `isAuthenticating` flag.

### Critères

```
### AC-100 [type: new]
Assertion: Au moins un fichier source importe le framework `LocalAuthentication`.
Check post-impl: sh -c 'n=$(grep -rl "import LocalAuthentication" Sources/ | wc -l | tr -d " "); test "$n" -ge 1 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun import LocalAuthentication actuellement)
Post-state attendu: PASS
```

```
### AC-101 [type: new]
Assertion: Un protocole `AppLockService` existe dans Sources/Core/Protocols/ avec isLocked, isEnabled, isAuthenticating, authenticate() async -> Bool, setEnabled(_:), lock(). Conforme AnyObject, Sendable (cohérent avec KeychainStore:4).
Check post-impl: sh -c 'f=Sources/Core/Protocols/AppLockService.swift; grep -qE "var isLocked" "$f" && grep -qE "var isEnabled" "$f" && grep -qE "var isAuthenticating" "$f" && grep -qE "func authenticate\(\) async -> Bool" "$f" && grep -qE "func setEnabled" "$f" && grep -qE "func lock\(\)" "$f" && grep -qE "AnyObject, Sendable" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier n'existe pas)
Post-state attendu: PASS
```

```
### AC-102 [type: new]
Assertion: DependencyContainer expose une propriété `appLock` de type concret `AppLockViewModel` (résolution loop 3: existential `any AppLockService` ne propage pas Observable → `.environment()` compilerait pas).
Check post-impl: sh -c 'grep -qE "let appLock: AppLockViewModel" Sources/DependencyContainer.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-103 [type: new]
Assertion: Toggle App Lock persistant via @AppStorage("app_lock_enabled").
Check post-impl: sh -c 'grep -rq "@AppStorage(\"app_lock_enabled\")" Sources/ && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun @AppStorage dans codebase)
Post-state attendu: PASS
```

```
### AC-104 [type: new]
Assertion: RootView gate le contenu principal quand appLock.isEnabled && appLock.isLocked, affichant un overlay de verrouillage.
Check post-impl: sh -c 'grep -qE "appLock\.isEnabled" Sources/RootView.swift && grep -qE "appLock\.isLocked" Sources/RootView.swift && (grep -qE "LockView|blur|overlay|ZStack" Sources/RootView.swift) && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-105 [type: new]
Assertion: ImmichSwiftUIApp observe @Environment(\.scenePhase) et verrouille/déverrouille selon transitions (.background → lock, .active → unlock si enabled).
Check post-impl: sh -c 'grep -qE "scenePhase" Sources/ImmichSwiftUIApp.swift && grep -qE "\.background" Sources/ImmichSwiftUIApp.swift && grep -qE "\.active" Sources/ImmichSwiftUIApp.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-106 [type: new]
Assertion: AppLockViewModel utilise LAContext.evaluatePolicy avec .deviceOwnerAuthentication (inclut fallback passcode).
Check post-impl: sh -c 'grep -qE "deviceOwnerAuthentication" Sources/Features/Auth/AppLockViewModel.swift && grep -qE "LAContext" Sources/Features/Auth/AppLockViewModel.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-107 [type: new]
Assertion: MockAppLockService existe dans Tests/Mocks/ avec authenticateResult configurable.
Check post-impl: sh -c 'grep -qE "class MockAppLockService.*AppLockService" Tests/Mocks/MockAppLockService.swift && grep -q "authenticateResult" Tests/Mocks/MockAppLockService.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-108 [type: new]
Assertion: Tests AppLockViewModel injectent un evaluator fake (jamais LAContext réel) et couvrent: (a) init avec isEnabled=true → isLocked==true (fresh launch locked), (b) setEnabled(false)→isLocked==false, (c) enabled+lock()→isLocked==true, (d) authenticate(fake=true)→isLocked==false, (e) authenticate(fake=false)→isLocked reste true, (f) lock() pendant isAuthenticating==true est no-op.
Check post-impl: xcodebuild test -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ImmichSwiftUITests/AppLockViewModelTests 2>&1 | grep -E '(\*\* TEST SUCCEEDED \*\*|TEST FAILED|error:)'
Pre-state attendu: 0 tests ran (AppLockViewModelTests n'existe pas)
Post-state attendu: ** TEST SUCCEEDED ** (≥6 cas de test couvrant a-f)
```

```
### AC-111 [type: new]
Assertion: AppLockViewModel expose un evaluator injectable via init (paramètre closure) ET un evaluator système par défaut (LAContext.evaluatePolicy(.deviceOwnerAuthentication)) utilisé en production via DependencyContainer. Permet tests sans LAContext réel.
Check post-impl: sh -c 'grep -qE "init\(.*evaluator.*async.*Bool" Sources/Features/Auth/AppLockViewModel.swift && grep -qE "systemEvaluator|LAContext" Sources/Features/Auth/AppLockViewModel.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-112 [type: new]
Assertion: NSFaceIDUsageDescription présent dans Info.plist ET project.yml info.properties (requis pour Face ID runtime, sinon LAError.launchFailure).
Check post-impl: sh -c 'grep -q "NSFaceIDUsageDescription" Resources/Info.plist && grep -q "NSFaceIDUsageDescription" project.yml && echo PASS || echo FAIL'
Pre-state attendu: FAIL (clé absente des deux)
Post-state attendu: PASS
```

```
### AC-113 [type: new]
Assertion: AppLockViewModel init set isLocked = isEnabled (fresh launch avec App Lock activé démarre verrouillé, pas de faille de sécurité au redémarrage).
Check post-impl: sh -c 'grep -qE "isLocked = isEnabled|isLocked = _isEnabled|isLocked = isEnabled" Sources/Features/Auth/AppLockViewModel.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-114 [type: new]
Assertion: BackupSettingsView expose un Toggle "Require Face ID" bindé sur appLock, et appLock est injecté via `@Environment(AppLockViewModel.self)` (type concret @Observable, cohérent avec @Environment(AuthViewModel.self) existant).
Check post-impl: sh -c 'grep -qE "Toggle.*Require Face ID|Toggle.*App Lock" Sources/Features/Upload/UploadViewModel.swift && grep -qE "@Environment\(AppLockViewModel.self\)" Sources/Features/Upload/UploadViewModel.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-109 [type: regression]
Assertion: Le projet compile et tous les tests existants restent verts (suite complète).
Check post-impl: xcodebuild test -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E '(\*\* TEST SUCCEEDED \*\*|TEST FAILED|error:|BUILD FAILED)'
Pre-state attendu: ** TEST SUCCEEDED **
Post-state attendu: ** TEST SUCCEEDED **
```

```
### AC-110 [type: regression]
Assertion: KeychainStore protocole conserve exactement ses 3 méthodes (saveToken, getToken, deleteToken).
Check post-impl: sh -c 'n=$(grep -c "func " Sources/Core/Protocols/KeychainStore.swift); test "$n" -eq 3 && echo PASS || echo FAIL'
Pre-state attendu: PASS (3 méthodes)
Post-state attendu: PASS (3, inchangé)
```

### Failure modes (top 3 + quel AC les détecte)
**FM-1 — Double-lock pendant prompt Face ID**: scenePhase=.inactive pendant LAContext.evaluatePolicy → lock() rappelé → re-lock après unlock. Mitigation: flag `isAuthenticating` dans lock(). Détection: vérif manuelle VM-4.
**FM-2 — Toggle off ne déverrouille pas**: setEnabled(false) oublie isLocked=false. AC-108 test (a) détecte.
**FM-3 — Bloqué au lancement sur simu sans biométrie**: .deviceOwnerAuthenticationWithBiometrics seul = pas de fallback passcode. AC-106 force .deviceOwnerAuthentication (inclut passcode). Détection: vérif manuelle simu.

## Vérifications manuelles (hors auto-feedback loop)
1. VM-1: Overlay blur material (.regular) + bouton "Unlock" pixel-perfect vs Photos.app.
2. VM-2: Transition lock/unlock fluide (spring 0.25s), pas de flash.
3. VM-3: Haptic success au déverrouillage (UINotificationFeedbackGenerator).
4. VM-4: Face ID prompt au retour background <1s; 3 fails → passcode auto.
5. VM-5: Toggle "Require Face ID" dans BackupSettingsView, natif Form, effet immédiat.
6. VM-6: App switcher montre blur overlay (snapshot système), pas contenu sensible.
