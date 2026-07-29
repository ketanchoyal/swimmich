# Task: immich-swiftui-foundation

> User verbatim: "I want you to develop a clone of the immich app but the original
> one is made in flutter. I want you to implement a pure swiftui ios immich client
> with all actual features."

## Scope decision (hypothesis documented)

"All features" in one increment = impossible (Immich spans backup, timeline, albums,
search/CLIP, people, map, memories, shared links, partners, WS sync, OAuth). Reasonable
interpretation: deliver a well-architected FOUNDATION implementing the REAL Immich server
REST API + core vertical (auth, server discovery, timeline grid+pagination, asset detail
viewer, upload/backup scaffold), structured for extension. Remaining features = roadmap,
out of scope. This file is the handoff artifact.

## Plan

**Objectif**: Greenfield SwiftUI iOS client for Immich self-hosted server. Foundation first.

**Hypothèses** (grounded in specialist API research + challenger-verified against Immich
OpenAPI spec / server source — refs: api.immich.app/endpoints, github immich-app/immich
server/src/controllers/*.ts, PR #28859):
- Server base = user-supplied URL. API under `/api`. Auth header `Authorization: Bearer {jwt}`.
- Login: `POST /api/auth/login` body `{email,password}` → `{accessToken, userId, userEmail, name, isAdmin, profileImagePath, shouldChangePassword, isOnboarded}`.
- Logout: `POST /api/auth/logout` → **200** with body `{redirectUri: String, successful: Boolean}` (LogoutResponseDto). Requires Bearer.
- validateToken: `POST /api/auth/validateToken` → `{authStatus: Boolean}` (flagged uncertain in research; treat as AuthStatusResponseDto, verify against live server in manual test).
- Server discovery: `GET /api/server/ping` → **JSON** `{"res":"pong"}` (ServerPingResponse, content-type application/json, NOT text/plain); `GET /api/server/version`; `GET /api/server/config`.
- Timeline: `GET /api/timeline/buckets` → `[{timeBucket,count}]` (NO `size` param — server picks bucket granularity internally; query params: albumId,bbox,isFavorite,isTrashed,order,orderBy,personId,tagId,userId,visibility,withCoordinates,withPartners,withStacked). `GET /api/timeline/bucket?timeBucket=...` → **COLUMNAR** response (parallel arrays id[],ratio[],thumbhash[],isFavorite[],isImage[],fileCreatedAt[],localOffsetHours[],duration[],stack[],livePhotoVideoId[]... ~17 fields) zipped by index into AssetReactItem[]. Pagination = BUCKET-level (loadMore fetches next bucket from the buckets list), NOT page-level within a bucket.
- Asset media: `GET /api/assets/:id/thumbnail?size=thumbnail|preview` (binary); `/original` (binary); `/video/playback` (Range streaming).
- Asset actions: **`PATCH /api/assets/:id`** body `{isFavorite?, visibility?}` (UpdateAssetDto) → AssetResponseDto. NOTE: `PUT /api/assets/:id` is DEPRECATED (PR #28859, v3: both verbs accepted, v4: PUT dropped) — greenfield uses PATCH. `DELETE /api/assets` body `{ids:[uuid], force?}` (AssetBulkDeleteDto) → 204.
- Upload: multipart `POST /api/assets` fields `assetData`,`sidecarData`(opt),`fileCreatedAt`(ISO8601),`fileModifiedAt`(ISO8601),`duration`(ms,opt),`isFavorite`,`visibility`,`filename`,`livePhotoVideoId`(opt). Two SEPARATE dedup mechanisms: (a) `x-immich-checksum` header (sha1 base64) on the upload request for server-side dedup; (b) `POST /api/assets/bulk-upload-check` body `{assets:[{id,checksum}]}` → `{results:[{id,action:"accept"|"reject"}]}` for client-side pre-check. Both used together.
- Thumbnail cache-busting `?c={thumbhash}` is a CLIENT convention (not a server API param) — server ignores unknown query params.

**Étapes**:
1. Scaffold Xcode project (`ImmichSwiftUI.xcodeproj`, app target `ImmichSwiftUI`, test target `ImmichSwiftUITests`). iOS 17.0. No storyboards, SwiftUI lifecycle.
2. Core layer: DTOs (Codable matching verified Immich JSON — incl. ServerPingResponse `{res}`, LogoutResponseDto `{redirectUri,successful}`), protocols (`ImmichClient`, `KeychainStore`, `PhotoLibraryService`), APIError, Constants, AssetReactItem (columnar→object zip helper), global 401 interceptor.
3. Services: `ImmichAPIClient` (URLSession async/await), `KeychainStoreImpl` (Security framework), `PhotoLibraryServiceImpl`, multipart builder, sha1.
4. DI root: `DependencyContainer`, `ImmichAppApp`, `RootView` (auth-gated router).
5. Auth feature: ServerConnectView (ping → ServerPingResponse), LoginView, AuthViewModel (@Observable), ServerInfoViewModel, logout (handle 200 body).
6. Timeline feature: TimelineView (lazy grid, date sections, infinite scroll), TimelineViewModel (load buckets → load bucket columnar → zip → paginate next bucket), AssetThumbnailCell, DayGroupHeader.
7. AssetDetail feature: AssetDetailView (image/video/metadata), AssetDetailViewModel (PATCH favorite/archive/trash), VideoPlayerView (AVPlayer wrap), MetadataSheet.
8. Upload feature: UploadViewModel, UploadManager (background-capable, x-immich-checksum + bulk-upload-check), BackupSettingsView, local-id→remote-id tracking.
9. XCTest suite: MockImmichClient/MockKeychainStore/MockPhotoLibraryService, view-model tests, URLProtocol-based client tests (incl. multipart shape + 401), Codable round-trip tests, columnar-zip correctness test.

**Stack**: SwiftUI, iOS 17.0+, `@Observable` macro, URLSession async/await, Keychain (Security), Photos/AVFoundation, XCTest. No third-party deps.

## Acceptance Contract

### Approches candidates

1. **Single-Module Monolith + MVVM + `@Observable`** — one target, feature folders, protocol-backed services. Simplest, fast iteration. Risk: boundaries blur over time.
2. **SPM Multi-Module** — `ImmichAPI`/`ImmichAuth`/`ImmichTimeline`/`ImmichUpload`/`ImmichCore` packages, app target composes. Strict boundaries, parallel builds. Trade-off: boilerplate, cross-package type sharing needs Core pkg.
3. **TCA (Composable Architecture)** — Point-Free lib, single Store, reducer composition, TestStore. Exhaustive testability. Trade-off: heavy dep, steep learning curve, non-idiomatic SwiftUI.

### Approche retenue + rationale

**Approach 1 — Single-Module Monolith + MVVM + `@Observable`.**
Greenfield; monolith ships foundation fastest. Feature folders give logical separation
without SPM overhead. Protocols in `Core/Protocols/` make future package extraction a
single-file move. `@Observable` (iOS 17+) removes `@Published`/Combine boilerplate. Scope
(auth/timeline/detail/upload scaffold) fits a monolith.

Module/layer breakdown:
- L0 Constants/Types (DTOs, AssetReactItem, APIError)
- L1 Protocols (ImmichClient, KeychainStore, PhotoLibraryService)
- L2 Services (ImmichAPIClient, KeychainStoreImpl, PhotoLibraryServiceImpl)
- L3 ViewModels (@Observable)
- L4 SwiftUI Views (stateless, VM-driven)
- L5 App entry + DI root

### Critères

```
### AC-001 [type: new]
Assertion: The Xcode project builds successfully with xcodebuild from a fresh clone.
Check post-impl: resolve an available simulator via `xcrun simctl list devices available | grep -m1 iPhone`, then `xcodebuild -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=<resolved>' build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED"`
Pre-state attendu: BUILD FAILED (no project exists).
Post-state attendu: ** BUILD SUCCEEDED **

### AC-002 [type: new]
Assertion: All unit tests pass via xcodebuild test.
Check post-impl: `xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=<resolved>' 2>&1 | grep -E "Test Suite|Executed.*tests"` (resolved simulator name via xcrun simctl list).
Pre-state attendu: 0 tests / failure (no test target).
Post-state attendu: contains 'Executed N tests, with 0 failures'.

### AC-003 [type: new]
Assertion: The login request sends correct JSON body {"email":...,"password":...} to POST /api/auth/login.
Check post-impl: XCTest AuthViewModelTests uses MockImmichClient to intercept login; assert lastLoginBody?.email == "test@example.com" && .password == "secret123".
Pre-state attendu: test fails (no impl).
Post-state attendu: test passes.

### AC-004 [type: new]
Assertion: On login success, AuthViewModel persists JWT accessToken to Keychain via KeychainStore protocol.
Check post-impl: XCTest — login() with mock client returning LoginResponseDto(accessToken:"fake-jwt"); assert mockKeychain.savedToken == "fake-jwt".
Pre-state attendu: test fails.
Post-state attendu: test passes.

### AC-005 [type: new]
Assertion: On logout, AuthViewModel clears Keychain token and sets isAuthenticated = false.
Check post-impl: XCTest — pre-warm keychain token; logout(); assert savedToken == nil && isAuthenticated == false.
Pre-state attendu: test fails.
Post-state attendu: test passes.

### AC-006 [type: new]
Assertion: TimelineViewModel paginates at BUCKET level — getTimeBuckets returns [bucket1,bucket2]; getTimeBucket returns the columnar response for each bucket; loadMore() loads the NEXT bucket (not a page within a bucket), accumulating assets across buckets with no duplicate IDs.
Check post-impl: XCTest — mock getTimeBuckets returns 2 buckets (timeBucket "2024-07-01","2024-06-01"); mock getTimeBucket returns columnar TimeBucketAssetResponseDto for each bucket with 3 ids each; call loadMore() twice; assert total accumulated assets == 6 and no duplicate ids; assert both buckets were requested.
Pre-state attendu: test fails.
Post-state attendu: test passes.

### AC-007 [type: new]
Assertion: Thumbnail URL for asset id `abc123` thumbhash `xyz` == {base}/api/assets/abc123/thumbnail?size=thumbnail&c=xyz (c= is client cache-busting convention).
Check post-impl: XCTest — ImmichAPIClient.thumbnailURL(assetId:"abc123", thumbhash:"xyz", baseURL:URL("https://example.com")!) == "https://example.com/api/assets/abc123/thumbnail?size=thumbnail&c=xyz".
Pre-state attendu: test fails.
Post-state attendu: test passes.

### AC-008 [type: new]
Assertion: ImmichAPIClient sends multipart upload with fields assetData, fileCreatedAt, fileModifiedAt, Content-Type multipart/form-data, AND the request carries a non-empty binary body AND the x-immich-checksum header (base64 sha1).
Check post-impl: XCTest via URLProtocol mock capturing URLRequest — method POST, path /api/assets, Content-Type starts multipart/form-data, body contains name="assetData", name="fileCreatedAt", name="fileModifiedAt", body byte length > multipart overhead (proves binary attachment present), request.value(forHTTPHeaderField:"x-immich-checksum") is non-empty.
Pre-state attendu: test fails.
Post-state attendu: test passes.

### AC-009 [type: new]
Assertion: MVVM testability — TimelineViewModel injectable with MockImmichClient+MockKeychainStore via constructor injection; state derivation asserted without real HTTP (mockClient.requestCount > 0). Mock contract: getTimeBuckets returns [TimeBucketResponseDto{timeBucket,count}], getTimeBucket returns columnar TimeBucketAssetResponseDto (parallel arrays — NOT pre-zipped AssetReactItem).
Check post-impl: XCTest — instantiate VM with mocks; call loadMore(); assert groupedAssets non-empty from mock columnar data; mockClient.requestCount > 0.
Pre-state attendu: test fails.
Post-state attendu: test passes.

### AC-010 [type: new]
Assertion: AssetDetailViewModel calls the NON-DEPRECATED `PATCH /api/assets/:id` (not PUT) with body `{"isFavorite":true}` when toggleFavorite() on a non-favorited asset.
Check post-impl: XCTest — mock client returns unfavorited AssetResponseDto; toggleFavorite(); assert mockClient.lastUpdateAssetMethod == "PATCH" && lastUpdateAssetId == assetId && lastUpdateAssetBody?.isFavorite == true.
Pre-state attendu: test fails.
Post-state attendu: test passes.

### AC-011 [type: new]
Assertion: LoginResponseDto, AssetResponseDto, ServerPingResponse `{res}`, and LogoutResponseDto `{redirectUri,successful}` are Codable round-trip JSON→struct→JSON without loss.
Check post-impl: XCTest — raw JSON samples (incl. `{"res":"pong"}` and `{"redirectUri":"","successful":true}`) decode→encode→compare; assert accessToken=="test-jwt", userId==uuid, pingRes.res=="pong", logoutRes.successful==true.
Pre-state attendu: test fails.
Post-state attendu: test passes.

### AC-012 [type: new]
Assertion: AuthViewModel validates server reachability before login — connectServer() on unreachable URL sets serverStatus = .unreachable, isAuthenticated == false. PING response is decoded as ServerPingResponse `{res}` (JSON), not bare string compare.
Check post-impl: XCTest — mock client ping() throws URLError(.cannotConnectToHost); connectServer(); assert serverStatus == .unreachable && isAuthenticated == false. (Second case: mock ping returns {"res":"pong"} JSON → serverStatus == .reachable.)
Pre-state attendu: test fails.
Post-state attendu: test passes.

### AC-013 [type: new]
Assertion: Columnar→object zip correctness — given a TimeBucketAssetResponseDto with parallel arrays where id=[a,b], ratio=[0.75,1.33], thumbhash=[tA,tB], isFavorite=[false,true], the zip produces AssetReactItem[a] with ratio 0.75, thumbhash tA, isFavorite false and AssetReactItem[b] with ratio 1.33, thumbhash tB, isFavorite true (correct index association, no off-by-one).
Check post-impl: XCTest — feed columnar fixture; assert zipped items count == 2 and each field matches its array index.
Pre-state attendu: test fails.
Post-state attendu: test passes.

### AC-014 [type: new]
Assertion: Global 401 handling — when any API call returns HTTP 401, ImmichAPIClient triggers auth reset (AuthViewModel.logout path): clears Keychain token and sets isAuthenticated=false, so the UI routes back to login.
Check post-impl: XCTest — URLProtocol mock returns 401 for any request; drive a timeline fetch via TimelineViewModel(client holding the real APIClient wired to a 401-mocking URLProtocol + an injected AuthViewModel); assert mockKeychain.savedToken == nil && authViewModel.isAuthenticated == false after the call.
Pre-state attendu: test fails.
Post-state attendu: test passes.
```

### Failure modes (top 3 + quel AC les détecte)

- **FM-1 Columnar timeline misalignment** — `/api/timeline/bucket` returns columnar parallel arrays (id[],ratio[],thumbhash[],isFavorite[]...); off-by-one/missing null-check → wrong thumbnail/ratio association. Detected by **AC-013** (zip correctness: id[i]↔ratio[i]↔thumbhash[i]↔isFavorite[i] index association) + AC-006 (bucket accumulation) + manual visual.
- **FM-2 Multipart upload field-name mismatch** — Immich expects `assetData`/`sidecarData`/`fileCreatedAt`(ISO8601); mismatch → silent 400/missing metadata. Detected by **AC-008** (field names + binary body + x-immich-checksum header) + real-server smoke test.
- **FM-3 Keychain access denied (background/first launch)** — wrong `kSecAttrAccessible` or missing access group → app appears logged-out. Detected by **AC-004, AC-005** + real-device regression.
- **FM-4 (added) 401 token expiry not handled globally** — session expires mid-use → cryptic errors/blank screens. Detected by **AC-014** (global 401 → auth reset).

## Vérifications manuelles (hors auto-feedback loop)

1. Real-server login flow (live Immich server URL + creds → JWT in Keychain → /api/auth/status valid).
2. Timeline rendering on device (grid lazy-loads, smooth scroll, no stretching/crop artifacts, date headers correct).
3. Full-size image load + pinch-zoom + swipe next asset.
4. Video playback from /api/assets/:id/video/playback with Range (scrub, play/pause).
5. Background upload (backup enabled → leave app → take photo → reopen → uploaded).
6. Trash/restore round-trip vs server web UI.
7. Token expiry handling (401 → redirect login).
8. Network error UX (bad URL → "Cannot connect"; wrong creds → "Invalid email/password").

## Out-of-scope roadmap (architecture must not preclude)

Albums (/api/albums/*), Search/CLIP (/api/search/smart, /api/search/suggestions), People/Faces
(/api/people/*, /api/faces/*), Map (/api/map/markers, MapKit), Memories (/api/memories/*), Shared
links (/api/shared-links/*), Partner sharing (/api/partners/*), WebSocket sync
(URLSessionWebSocketTask), OAuth (/api/oauth/* via ASWebAuthenticationSession), iCloud PHAsset
download, Folder view (/api/view/folder/*).

Extensibility pattern: add DTOs → add ImmichClient protocol method → implement in ImmichAPIClient
→ create Features/{Name}/ (views+VM) → wire into RootView.
