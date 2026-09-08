# Task: selfsigned-cert

Status: shipped — AC-1150..AC-1154 PASS 2026-08-12 (475 tests, +7).

## Plan
**Objectif**: Flow de confiance pour certificats auto-signés (parity Flutter, PRD §5.10). Quand la connexion échoue avec une erreur TLS (certificat inconnu/auto-signé), proposer "Trust this server" → l'hôte est persistant → les connexions suivantes acceptent le certificat via un delegate URLSession (SecTrustSetAnchorCertificates). Nettoie TODO `$PHASE_CERT` (ServerURLScreen).

**Hypothèses**:
- ImmichAPIClient init(session: URLSession = .shared) (:27) — la session est injectable.
- AuthViewModel.connectServer (:123-145) catch générique → serverStatus .unreachable.
- URLError codes: .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateHasBadDate, .serverCertificateNotYetValid.
- NSAllowsArbitraryLoads reste true (LAN http Immich) — scope: HTTPS auto-signé via delegate.
- Testable: store pur + VM flow; le delegate TLS réel n'est pas unit-testable (pas de TLS en tests).

**Approche retenue**: A — `TrustedServerStore` protocole (contains/add) + impl UserDefaults (clés "trustedServers", set de "host:port") ; `TrustEvaluatingURLSessionDelegate` (URLSessionDelegate: challenge .serverTrust → évaluation SecTrust par défaut; si échec + hôte dans le store → SecTrustSetAnchorCertificates(chaîne serveur) + ré-évaluation → pass sinon cancel) ; ImmichAPIClient.init(session:trustStore:) construit sa session déléguée ; AuthViewModel: pendingUntrustedHost (set quand URLError TLS) + trustPendingServer() (add + reconnect) ; ServerURLScreen: alert "Trust this server?" quand pendingUntrustedHost != nil. **B** (rejetée): pinning hard (fingerprints) — hors scope PRD. **C** (rejetée): NSAllowsArbitraryLoads seul — déjà le cas, pas un flow.

**Étapes**:
1. Card écrite.
2. NEW `Sources/Core/Protocols/TrustedServerStore.swift` + `Sources/Services/TrustedServerStoreImpl.swift`.
3. NEW `Sources/Services/TrustEvaluatingURLSessionDelegate.swift`.
4. ImmichAPIClient: init(session:trustStore:) — session déléguée si trustStore fourni; DependencyContainer passe TrustedServerStoreImpl.
5. AuthViewModel: pendingUntrustedHost + trustPendingServer(); connectServer catch URLError TLS → pendingUntrustedHost = baseURL.host (+errorMessage).
6. ServerURLScreen: alert "Trust this server?" → Task { await auth.trustPendingServer() }.
7. Tests: TrustedServerStoreTests (add/contains/persist), AuthViewModelTests + (connectServer TLS error → pendingUntrustedHost; trustPendingServer → store contains + reconnect).
8. Suite → /tmp/immich_cert_test_summary.txt + checks + memory.md.

## Acceptance Contract

### Approches candidates
**A (retenue)**: Trust store + delegate SecTrust anchors + flow explicite.
**B**: Pinning fingerprints. Hors scope.
**C**: Rien (ArbitraryLoads). Pas un flow.

### Approche retenue + rationale
**A**. Flow explicite utilisateur (Photos/iOS Mail-like), store persistant, delegate isolé.

### Critères

```
### AC-1150 [type: new]
Assertion: TrustedServerStore protocole contains/add + impl UserDefaults.
Check post-impl: sh -c 'grep -q "func contains" Sources/Core/Protocols/TrustedServerStore.swift && grep -q "func add" Sources/Core/Protocols/TrustedServerStore.swift && grep -q "trustedServers" Sources/Services/TrustedServerStoreImpl.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1151 [type: new]
Assertion: TrustEvaluatingURLSessionDelegate gère .serverTrust: évaluation + fallback anchor si hôte trusté.
Check post-impl: sh -c 'f=Sources/Services/TrustEvaluatingURLSessionDelegate.swift; test -f "$f" && grep -q "NSURLAuthenticationMethodServerTrust" "$f" && grep -q "SecTrustSetAnchorCertificates" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1152 [type: new]
Assertion: ImmichAPIClient init(session:trustStore:) + AuthViewModel.pendingUntrustedHost + trustPendingServer().
Check post-impl: sh -c 'grep -q "trustStore" Sources/Services/ImmichAPIClient.swift && grep -q "pendingUntrustedHost" Sources/Features/Auth/AuthViewModel.swift && grep -q "func trustPendingServer" Sources/Features/Auth/AuthViewModel.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1153 [type: new]
Assertion: ServerURLScreen alert "Trust this server?" + tests ≥ 4 (store 2 + VM 2).
Check post-impl: sh -c 'grep -q "Trust this server" Sources/Features/Auth/Onboarding/ServerURLScreen.swift && f1=Tests/TrustedServerStoreTests.swift; f2=Tests/AuthViewModelTests.swift; n1=$(grep -c "func test_" "$f1" 2>/dev/null || echo 0); n2=$(grep -c "func test_trust" "$f2"); test $((n1 + n2)) -ge 4 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1154 [type: regression]
Assertion: Suite ≥ 468, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_cert_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_cert_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 468 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
