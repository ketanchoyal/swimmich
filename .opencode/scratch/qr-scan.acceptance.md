# Task: qr-scan

Status: shipped — AC-1140..AC-1144 PASS 2026-08-12 (468 tests, +9).

## Plan
**Objectif**: Scan d'un QR code de configuration serveur (parity Flutter) — pré-remplit `auth.serverURLString` depuis le payload `{"serverUrl": "..."}` ou une URL nue. Nettoie TODO `$PHASE_QR` (ServerURLScreen.swift:48).

**Hypothèses**:
- ServerURLScreen :48-49 TODO; champ TextField + auth.serverURLString; statusSection existante.
- AVCaptureMetadataOutput (AVFoundation) pour QR — pas de VisionKit nécessaire.
- NSCameraUsageDescription requis (project.yml info.properties).
- VM parse testable sans caméra.

**Approche retenue**: A — QRServerConfigParser (static parse(_ payload: String) -> URL? : `{"serverUrl": ...}` JSON sinon URL brute, https par défaut) + QRScannerView (UIViewRepresentable AVCaptureSession + metadataOutput, onFound callback, cameraPermission denied state) + bouton scan (qrcode.viewfinder) dans ServerURLScreen → sheet → payload → parser → auth.serverURLString (auto normalize + connect). **B** (rejetée): VisionKit (surkill). **C** (rejetée): sans permission flow (UX cassée).

**Étapes**:
1. Card écrite.
2. NEW `Sources/Features/Auth/Onboarding/QRServerConfigParser.swift`.
3. NEW `Sources/Features/Auth/Onboarding/QRScannerView.swift`.
4. ServerURLScreen: bouton scan + sheet + wiring.
5. project.yml NSCameraUsageDescription + xcodegen.
6. NEW `Tests/QRServerConfigParserTests.swift`.
7. Suite → /tmp/immich_qrscan_test_summary.txt + checks + memory.md.

## Acceptance Contract

### Approches candidates
**A (retenue)**: Parser pur + UIViewRepresentable AVFoundation + sheet.
**B**: VisionKit. Surkill.
**C**: Pas de permission. UX cassée.

### Approche retenue + rationale
**A**. Parser testable, caméra isolée en representable.

### Critères

```
### AC-1140 [type: new]
Assertion: QRServerConfigParser.parse gère JSON {"serverUrl":} + URL nue + invalide → nil.
Check post-impl: sh -c 'f=Sources/Features/Auth/Onboarding/QRServerConfigParser.swift; test -f "$f" && grep -q "serverUrl" "$f" && grep -q "func parse" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1141 [type: new]
Assertion: QRScannerView AVCaptureSession + metadataOutput + state caméra indisponible.
Check post-impl: sh -c 'f=Sources/Features/Auth/Onboarding/QRScannerView.swift; test -f "$f" && grep -q "AVCaptureSession" "$f" && grep -q "AVCaptureMetadataOutput" "$f" && grep -q "authorizationStatus" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1142 [type: new]
Assertion: ServerURLScreen: bouton qrcode.viewfinder + sheet scanner + wiring parser → serverURLString.
Check post-impl: sh -c 'f=Sources/Features/Auth/Onboarding/ServerURLScreen.swift; grep -q "qrcode.viewfinder" "$f" && grep -q "QRScannerView" "$f" && grep -q "QRServerConfigParser" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1143 [type: new]
Assertion: NSCameraUsageDescription dans project.yml + tests parser ≥ 3.
Check post-impl: sh -c 'grep -q "NSCameraUsageDescription" project.yml && f=Tests/QRServerConfigParserTests.swift; n=$(grep -c "func test_" "$f"); test "$n" -ge 3 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1144 [type: regression]
Assertion: Suite ≥ 459, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_qrscan_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_qrscan_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 459 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
