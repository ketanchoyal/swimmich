# Feature Parity Plan — ImmichSwiftUI vs Flutter client

> Status: active — 2026-08-12. Sequential card program; each card = `.opencode/scratch/<slug>.acceptance.md` contract → implementation → tests → memory.md entry → AC pass/fail report.

## Program rules (each card enforces)

1. **Native SwiftUI only** — no UIKit windows, no Flutter patterns. Layered architecture immutable: protocol (L1) → DI (container) → `@Observable @MainActor` VM (L3) → stateless View (L4). Single app target unless a card explicitly adds one (widgets, Live Activity).
2. **Tested** — XCTest per VM with mocks (`Tests/Mocks/MockImmichClient` pattern); every card runs the **full suite** (baseline regression) plus new AC checks; baseline today ≈ 214 green.
3. **Documented** — memory.md decision entry per shipped card (tag: feature) + doc-comments on public surface; server fields verified against OpenAPI / `.opencode/scratch/dto-reference.md` before encoding.
4. **xcodegen** — regen `project.yml` after every new file; identity fields never touched (memory 2026-07-29 pitfall).
5. Validation: `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 17'` (iOS 26.5; no iPhone 16 sim in this install).

## Phase map

| Phase | Cards | Blocks |
|---|---|---|
| P0 API foundation | `api-surface-expansion` | everything |
| P1 Core UX | `video-playback`, `live-photo`, `slideshow`, `save-download`, `archive`, `favorites-filter`, `map-extras`, `storage-stats` | — |
| P2 Real backup | `backup-engine`, `backup-live-activity` | P0 (bulkUploadCheck exists) |
| P3 Social | `people-faces`, `partner-sharing`, `activity-feed`, `shared-link-edit`, `album-edit` | P0 (clients) |
| P4 Discovery | `memories`, `duplicates` | P0 (clients) |
| P5 Auth & platform | `oauth`, `qr-scan`, `selfsigned-cert`, `multi-server`, `widgets-appintents`, `i18n-catalog` | P0 (serverConfig) |
| Backlog (cards written, Status: backlog) | `push-notifications` | server APNs config |

## Server endpoints per card (target Immich ≥ 1.116; verify against OpenAPI at impl time)

| Card | Endpoints |
|---|---|
| api-surface-expansion | `GET/PUT /people`, `GET /people/:id/assets`, `PUT /people/:id/merge`, `GET /memories`, `GET /duplicates`, `GET/PUT/DELETE /partners`, `GET/POST /activities`, `DELETE /activities/:id`, `GET /server/statistics`, `PUT /shared-links/:id`, `PUT /assets` (bulk archive/favorite), `GET /assets/:id/{video/playback, original, thumbnail, preview}` |
| video-playback | `GET /assets/:id/video/playback` (HLS m3u8) + `original` fallback; AVPlayer |
| live-photo | `livePhotoVideoId` (getAsset); upload pair via multipart field |
| slideshow | client-only (viewer pager + timer) |
| save-download | `GET /assets/:id/original`, `:id/thumbnail`; PHPhotoLibrary add |
| archive | `PUT /assets` (`isArchived`), timeline `visibility` + `isArchived` filters |
| favorites-filter | timeline `isFavorite` (already in client) |
| map-extras | MKMapItem external nav; asset location edit via `PATCH /assets/:id` |
| storage-stats | `GET /server/statistics` |
| backup-engine | `POST /assets` multipart, `POST /assets/bulk-upload-check` (wired), BGTaskScheduler, URLSession background |
| backup-live-activity | ActivityKit + widget extension (new target in project.yml) |
| people-faces | `GET/PUT /people`, `GET /people/:id/assets`, merge; search `personIds` deck |
| partner-sharing | `GET/PUT/DELETE /partners`; timeline `withPartners` filter (dto-reference:75) |
| activity-feed | `GET/POST/DELETE /activities`; album activity section |
| shared-link-edit | `PUT /shared-links/:id` (password/expiry/allowUpload/allowDownload/showMetadata) |
| album-edit | `PATCH /albums/:id` (updateAlbum already wired, unused) |
| memories | `GET /memories` |
| duplicates | `GET /duplicates` + per-group delete keep-newest |
| oauth | `POST /oauth/authorize` (redirect URI + PKCE state/challenge) + ASWebAuthenticationSession + `POST /oauth/callback` (state + code verifier); `oauthButtonText` already in ServerConfigDto |
| qr-scan | AVFoundation metadata; server URL screen; NSCameraUsageDescription |
| selfsigned-cert | URLSession delegate trust eval + Keychain trust store; drop blanket NSAllowsArbitraryLoads; PRD §5.10 |
| multi-server | server registry (UserDefaults + per-URL Keychain tokens), switcher UI |
| widgets-appintents | WidgetKit extension target + AppIntents (backup now, open album) + Spotlight |
| i18n-catalog | route all hardcoded FR/EN copy through Localizable.xcstrings |
| push-notifications | BACKLOG: UNUserNotificationCenter + APNs token → `PUT /notifications`; needs server APNs config |

## Timeline query-param expansion (needed by P1/P3/P4 — no new bucket plumbing)

`getTimeBuckets`/`getTimeBucket` gain optional: `personId`, `withPartners`, `visibility`, `withStacked`, `tagId`, `bbox` (dto-reference:75). Archive/favorites → `isArchived` on map markers already passthrough.

## API surface currently wired-but-unused (targets for near phases)

`bulkUploadCheck` (backup-engine), `updateAlbum` (album-edit), `uploadAsset` (backup-engine), `getUsers` (used), `getExploreData` (used). `PhotoLibraryService` dormant → backup-engine activates.

## Delivery order

1. `docs/feature-audit-vs-flutter.md` ✓
2. This plan ✓
3. `api-surface-expansion.acceptance.md` (P0)
4. P0 implementation + tests
5. Cards in phase order, one at a time, full-suite green before next card.