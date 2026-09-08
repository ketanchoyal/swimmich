# Task: multi-server

Status: shipped — AC-1160..AC-1163 PASS 2026-08-12 (480 tests, +5).

## Plan
**Objectif**: Multi-serveurs (parity Flutter): liste des serveurs enregistrés, bascule rapide, ajout de nouveau serveur. Session = par serveur (switch → reset → re-login pré-rempli).

**Hypothèses**:
- AuthViewModel: serverURLDefaultsKey "authServerURL", resetSession() (:187-199, garde l'URL), connectServer() (:123-145+), baseURL.
- ProfileView (Sources/Features/Profile/ProfileView.swift, ~100L): Form sections Compte/Stockage/Gestion/déconnexion.
- RootView gate: isAuthenticated → TabView sinon OnboardingFlowView (resetSession + URL vide → onboarding).

**Approche retenue**: A — `savedServers: [String]` dans AuthViewModel (UserDefaults "authServerList"), addCurrentServerToSaved() (appelé sur connectServer succès + login, dédup), removeSavedServer(at:) , switchServer(to:) (serverURLString = url + resetSession → onboarding pour re-login), addNewServer() (URL vide + resetSession). UI: section "Serveurs" dans ProfileView (rows checkmark si courant, tap → switch, trash delete, bouton "Ajouter un serveur" → addNewServer). **B** (rejetée): tokens multi-serveurs simultanés — surkill, scope parity réduit. **C** (rejetée): popup switcher global.

**Étapes**:
1. Card écrite.
2. AuthViewModel: savedServers + addCurrentServerToSaved/removeSavedServer/switchServer/addNewServer.
3. ProfileView: section Serveurs.
4. Tests: AuthViewModelTests + (add dédup, remove, switch resets + URL, addNewServer vide).
5. Suite → /tmp/immich_multiserver_test_summary.txt + checks + memory.md.

## Acceptance Contract

### Approches candidates
**A (retenue)**: Liste UserDefaults + switch = reset + re-login.
**B**: Tokens simultanés. Surkill.
**C**: Switcher global popup. Hors pattern.

### Approche retenue + rationale
**A**. Simple, testable, flux onboarding réutilisé.

### Critères

```
### AC-1160 [type: new]
Assertion: AuthViewModel.savedServers + addCurrentServerToSaved + removeSavedServer + switchServer + addNewServer.
Check post-impl: sh -c 'f=Sources/Features/Auth/AuthViewModel.swift; grep -q "savedServers" "$f" && grep -q "func addCurrentServerToSaved" "$f" && grep -q "func switchServer" "$f" && grep -q "func addNewServer" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1161 [type: new]
Assertion: ProfileView section Serveurs: rows + checkmark courant + delete + Ajouter un serveur.
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfileView.swift; grep -q "Serveurs" "$f" && grep -q "switchServer" "$f" && grep -q "addNewServer" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1162 [type: new]
Assertion: Tests ≥ 4 (dédup/persist/remove/switch).
Check post-impl: sh -c 'f=Tests/AuthViewModelTests.swift; n=$(grep -c "func test_.*[Ss]erver" "$f"); test "$n" -ge 4 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1163 [type: regression]
Assertion: Suite ≥ 475, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_multiserver_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_multiserver_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 475 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
