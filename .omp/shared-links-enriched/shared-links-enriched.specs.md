# Task: shared-links-enriched

**Objectif** : Enrichir l'expérience des shared links dans ImmichSwiftUI. Le CRUD de base (create/edit/revoke) est fait, mais il manque le prévisualisation externe, le copy-link, l'upload-from-link, et l'expiration UI. Parité avec Flutter `SharedLinkRoute`, `SharedLinkEditRoute`.

**Hypothèses** :
- `SharedLinksView.swift` + `SharedLinksViewModel.swift` existants.
- `SharedLinkSheet.swift` + `EditSharedLinkSheet.swift` existants.
- `SharedLinkResponseDto` (DTOs+SharedLink.swift) expose `id`, `description`, `password`, `key`, `type`, `createdAt`, `expiresAt`, `allowUpload`, `allowDownload`, `showMetadata`, `slug`.
- Le slug est le chemin URL : `https://immich.domain.com/share/{slug}`.
- `SharedLinkCreateDto` : type, albumId, assetIds, description, password, expiresAt, allowUpload, allowDownload, showMetadata.
- `SharedLinkEditDto` : password, expiresAt, allowUpload, allowDownload, showMetadata, description.
- `SharedLinksView` a déjà un "create" sheet (CreateSharedLinkSheet).
- La navigation vers une page de prévisualisation peut se faire via `URLSession.shared.load` pour récupérer la preview HTML.

**Endpoints à ajouter** :
- `POST /api/shared-links/{id}/password` — vérifier le password (déjà dans Flutter).
- `GET /api/shared-links/{slug}` — accès public (sans token) pour preview.
- `POST /api/shared-links/{slug}/assets` — upload depuis un lien public.

**Approche retenue** : A — ajouter preview WebView, copy-to-clipboard, upload-from-link sheet, expiry date picker, et password check.
- **B (rejetée)** : nouvelle tab dédiée. Inutile, le Shared tab existe déjà.
- **C (rejetée)** : juste copy-link. C'est 20% de la feature.

## Étapes

1. **ImmichClient** — Ajouter :
   - `func getSharedLinkPublic(slug: String) async throws -> SharedLinkResponseDto` (GET public, no auth).
   - `func uploadToSharedLink(slug: String, dto: AssetBulkUploadCheckRequest.Item) async throws -> AssetMediaResponseDto` (POST upload from public link).
   - `func checkSharedLinkPassword(slug: String, password: String) async throws -> Bool` (POST password check).
2. **ImmichAPIClient** — Implémenter les 3 nouvelles méthodes.
3. **SharedLinksViewModel** — Étendre avec :
   - `func copyLink(slug: String)` — copier l'URL dans le clipboard (UIPasteboard).
   - `func buildPublicURL(slug: String) -> URL` — construire `baseURL/share/{slug}`.
   - `func openPreview(slug: String)` — ouvrir dans un WKWebView (sheet).
   - `func startUploadFromLink(slug: String)` — picker d'assets → upload.
   - `func checkPassword(slug: String, password: String) async throws -> Bool`.
   - `var editingPassword: String?` pour le edit sheet.
4. **SharedLinksView** — Étendre :
   - Bouton "Copy link" (share icon) sur chaque shared link row.
   - Bouton "Preview" (globe icon) → WKWebView sheet.
   - Ajouter "expires at" date picker dans EditSharedLinkSheet (déjà DTO existant, juste l'UI).
   - Bouton "Upload from link" → picker d'assets → call uploadToSharedLink.
5. **Public link preview sheet** — NEW `SharedLinkPreviewView` :
   - WKWebView naviguant vers `baseURL/share/{slug}`.
   - Toolbar avec "Copy link", "Close", "Download".
6. **Tests** — `SharedLinksViewModelTests` + tests (copy link, public URL build, upload from link, password check).
7. **xcodegen + suite**.

## Acceptance Contract

### Approches candidates
**A (retenue)** : Copy link + public preview WKWebView + upload from link + expiry picker + password check. Couvre les gaps listés dans l'audit.
**B** : Nouvelle tab. Inutile, le Shared tab existe.
**C** : Juste copy-link. 20% de la feature.

### Approche retenue + rationale
**A**. Toutes les opérations de lien partagés enrichies en une seule extension de SharedLinksView/ViewModel, réutilisant les DTOs existants.

### Critères

```
### AC-SL01 [type: new]
Assertion: ImmichClient expose getSharedLinkPublic(slug:), uploadToSharedLink(slug:), checkSharedLinkPassword(slug:password:).
Check post-impl: sh -c 'f=Sources/Core/Protocols/ImmichClient.swift; grep -q "func getSharedLinkPublic" "$f" && grep -q "func uploadToSharedLink" "$f" && grep -q "func checkSharedLinkPassword" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-SL02 [type: new]
Assertion: SharedLinksViewModel expose copyLink, buildPublicURL, openPreview, startUploadFromLink, checkPassword.
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/SharedLinksViewModel.swift; grep -q "func copyLink" "$f" && grep -q "func buildPublicURL" "$f" && grep -q "func openPreview" "$f" && grep -q "func startUploadFromLink" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-SL03 [type: new]
Assertion: EditSharedLinkSheet intègre un UIDatePicker pour expiresAt.
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/EditSharedLinkSheet.swift; grep -q "DatePicker\|expiresAt" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (si pas de picker)
Post-state attendu: PASS
```

```
### AC-SL04 [type: new]
Assertion: SharedLinksView expose Copy link button + Preview button + Upload from link sur chaque row.
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/SharedLinksView.swift; grep -q "copyLink\|openPreview\|uploadToSharedLink\|UIPasteboard" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-SL05 [type: new]
Assertion: ImmichAPIClient implémente les 3 méthodes public/shared-link.
Check post-impl: sh -c 'f=Sources/Services/ImmichAPIClient.swift; grep -q "getSharedLinkPublic" "$f" && grep -q "uploadToSharedLink" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-SL06 [type: new]
Assertion: MockImmichClient implémente les 3 méthodes.
Check post-impl: sh -c 'f=Tests/Mocks/MockImmichClient.swift; grep -q "getSharedLinkPublic" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-SL07 [type: regression]
Assertion: Suite ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_sharedlinks_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_sharedlinks_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
