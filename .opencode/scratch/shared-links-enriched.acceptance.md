# Task: shared-links-enriched

Status: plan

## Plan

**Objectif**: Enrichir les shared links — preview WKWebView, copy-link, upload-from-link, expiry date picker. CRUD de base existant.

**Hypothèses** (ground truth vérifié):
- `SharedLinksView` + `SharedLinksViewModel` + `SharedLinkSheet` + `EditSharedLinkSheet` existants.
- `SharedLinkResponseDto` expose `slug`, `type`, `expiresAt`, `allowUpload`, `allowDownload`, `showMetadata`.
- `SharedLinkCreateDto` / `SharedLinkEditDto` wire dans ImmichClient.
- `SharedLinksView` a déjà un create sheet + partner section + PartnerRow.
- `EditSharedLinkSheet` existe mais pas d'expiry picker.

**Approche retenue**: A — public/shared-link endpoints + SharedLinksViewModel étendu + WKWebView preview + expiry picker + upload-from-link sheet.
**B (rejetée)**: Nouvelle tab → inutile.
**C (rejetée)**: Juste copy-link → 20% de la feature.

**Étapes**:
1. EDIT `ImmichClient.swift` — Ajouter `getSharedLinkPublic(slug:)`, `uploadToSharedLink(slug:)`, `checkSharedLinkPassword(slug:,password:)`.
2. EDIT `ImmichAPIClient.swift` — Implémenter les 3 méthodes.
3. EDIT `SharedLinksViewModel.swift` — copyLink(slug:), buildPublicURL(slug:), openPreview(slug:), startUploadFromLink(slug:), checkPassword(slug:,password:).
4. EDIT `SharedLinksView.swift` — Add MoreActionsButton (preview/copy/upload/edit/revoke), expiry date picker dans EditSharedLinkSheet.
5. NEW `ExternalLinkPreviewView.swift` — WKWebView in-app preview avec toolbar glass (Close/Copy URL/Share).
6. NEW `UploadFromLinkView.swift` — Form: choose photos + link info + upload CTA.
7. Tests — `SharedLinksViewModelTests` +6 (copy link, public URL, upload from link, password check, error handling).
8. Build + suite complète.

## Acceptance Contract

### Approches candidates
**A (retenue)**: Copy link + preview WKWebView + upload from link + expiry picker + password check.
**B**: Nouvelle tab → inutile.
**C**: Juste copy-link → 20%.

### Approche retenue + rationale
**A**. Toutes les opérations shared links enrichies, réutilisant DTOs existants.

### Critères

```
### AC-3400 [type: new]
Assertion: ImmichClient expose getSharedLinkPublic(slug:), uploadToSharedLink(slug:), checkSharedLinkPassword(slug:,password:) dans ImmichClient.swift.
Check post-impl: sh -c 'f=Sources/Core/Protocols/ImmichClient.swift; grep -qE "func getSharedLinkPublic" "$f" && grep -qE "func uploadToSharedLink" "$f" && grep -qE "func checkSharedLinkPassword" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3401 [type: new]
Assertion: SharedLinksViewModel expose copyLink(slug:), buildPublicURL(slug:), openPreview(slug:), startUploadFromLink(slug:), checkPassword(slug:,password:) dans SharedLinksViewModel.swift.
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/SharedLinksViewModel.swift; grep -qE "func copyLink" "$f" && grep -qE "func buildPublicURL" "$f" && grep -qE "func openPreview" "$f" && grep -qE "func startUploadFromLink" "$f" && grep -qE "func checkPassword" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3402 [type: new]
Assertion: EditSharedLinkSheet expose UIDatePicker pour expiresAt avec quick presets (1 day, 7 days, 30 days, Never).
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/EditSharedLinkSheet.swift; grep -qE "DatePicker" "$f" && grep -qE "1 day\|7 days\|30 days\|Never" "$f" && grep -qE "expiresAt" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (si pas de picker)
Post-state attendu: PASS
```

```
### AC-3403 [type: new]
Assertion: SharedLinksView expose Copy link button + Preview button + Upload from link dans MoreActionsButton sur chaque row.
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/SharedLinksView.swift; grep -qE "copyLink\|Copy Link" "$f" && grep -qE "openPreview\|Preview" "$f" && grep -qE "startUploadFromLink\|Upload" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3404 [type: new]
Assertion: ExternalLinkPreviewView expose WKWebView avec toolbar Close/Copy URL/Share dans Features/SharedLinks/ExternalLinkPreviewView.swift.
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/ExternalLinkPreviewView.swift; test -f "$f" && grep -qE "WKWebView" "$f" && grep -qE "Close" "$f" && grep -qE "Copy URL\|Copy Link" "$f" && grep -qE "Share" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3405 [type: new]
Assertion: UploadFromLinkView expose choose photos + upload to shared link CTA dans Features/SharedLinks/UploadFromLinkView.swift.
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/UploadFromLinkView.swift; test -f "$f" && grep -qE "uploadToSharedLink" "$f" && grep -qE "Choose Photos" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3406 [type: new]
Assertion: ImmichAPIClient expose getSharedLinkPublic(slug:), uploadToSharedLink(slug:).
Check post-impl: sh -c 'f=Sources/Services/ImmichAPIClient.swift; grep -qE "func getSharedLinkPublic" "$f" && grep -qE "func uploadToSharedLink" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3407 [type: new]
Assertion: MockImmichClient expose getSharedLinkPublic + uploadToSharedLink.
Check post-impl: sh -c 'f=Tests/Mocks/MockImmichClient.swift; grep -qE "getSharedLinkPublic" "$f" && grep -qE "uploadToSharedLink" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3408 [type: new]
Assertion: SharedLinksViewModelTests expose ≥6 tests (copy link, public URL, upload from link, password check, error, expiry picker).
Check post-impl: sh -c 'f=Tests/SharedLinksViewModelTests.swift; n=$(grep -cE "func test_shared.*link\|func test_copy\|func test_preview\|func test_upload_from_link\|func test_check_password" "$f"); test "$n" -ge 6 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3409 [type: regression]
Assertion: Suite complète ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_sharedlinks_test_summary.txt && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_sharedlinks_test_summary.txt | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
