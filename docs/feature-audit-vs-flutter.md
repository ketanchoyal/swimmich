# Feature Audit — ImmichSwiftUI vs Flutter Immich client

> Status: active — 2026-08-12. Source of truth for the parity program; scope verified against all `Sources/` files, `ImmichClient` protocol, `memory.md` decision logs, and `project.yml` (single app target, iOS 26).

## A. Implemented features (12 surfaces)

| Surface | Implemented |
|---|---|
| **Auth/onboarding** | 3-step flow (welcome → server URL w/ inline verify: ping+config+version, → login). Session persist/restore (Keychain token + URL). Auto `https://` normalization. Logout. App Lock (Face ID). |
| **Timeline** | Bucket pagination, continuous grid, pinned floating year + "Weekday d Month" header, pinch-zoom 2–7 cols, pull-to-refresh, scroll-to-top |
| **Multi-select** | Long-press, selection mode, batch favorite/delete/add-to-album |
| **Photo viewer** | Pager swipe, pinch + double-tap zoom, filmstrip, favorite/edit/delete/restore inline, share sheet (system share, share-to-user albums, public link w/ allowDownload+showMetadata), EXIF detail panel (geocoded place, description), glass chrome |
| **Editor** | Non-destructive: exposure/contrast/saturation/warmth, straighten ±45°, crop + aspect ratios, rotate 90°, rule-of-thirds, revert, local disk persistence |
| **Albums** | List/create/detail, add/remove assets, batch favorite, cover set, delete album, **shared-album user mgmt** (invite, EDITOR/VIEWER roles, revoke), per-album shared links (password + description) |
| **Shared tab** | All-links list, revoke, create album link |
| **Search** | Debounced live, metadata + CLIP smart, Explore places w/ counts + EXIF drill-down (city/country/make/model/state/lensModel), recents (cap 8), pagination |
| **Map** | Clustered markers w/ real badge counts (sum = sheet total), subsampling, cell-select filter, marker→viewer, paginated photo panel, disk cache |
| **Trash** | Restore / restore-all / delete-permanent / empty |
| **Upload** | API + multipart wired & unit-tested. **UI = scaffold only** (BackupSettingsView: "roadmap item") |
| **Profile** | Account info, links to Trash/Backup, logout |

## B. Missing vs Flutter client

**Upload/backup (biggest gap — Flutter's flagship feature):**
1. Real auto-backup: album selection, Wi-Fi-only, charging-only, exclude screenshots
2. Background upload (`BGTaskScheduler`) — zero BG tasks in repo
3. Upload queue, per-asset status, progress banner, Live Activity
4. Checksum dedup — `bulkUploadCheck` wired in client, unused

**Media playback:**
5. Video playback — NO `AVPlayer`/`AVKit` anywhere. Viewer shows video badge, plays nothing
6. Live Photo playback/upload (livePhotoVideoId in DTO, no UI)
7. Slideshow

**Server-backed modules:**
8. People & faces (grid, rename, merge, person albums) — `searchMetadata(personIds:)` support exists, no UI
9. Memories / On-this-day
10. Archive — `isArchived` param exists in client, `nil` hardcoded everywhere, no UI
11. Duplicates detection
12. Partner sharing
13. Shared-album activity feed (comments, reactions, new assets)
14. OAuth2 — TODO `$PHASE_OAUTH` comment only
15. Storage/quota stats in profile ("deferred")

**Platform features:**
16. Push notifications (no APNs, no `UNUserNotificationCenter`)
17. Widgets / Live Activities / App Intents / Shortcuts — no extra targets, single app target
18. QR server-config scan — TODO `$PHASE_QR`
19. Self-signed cert trust flow — TODO `$PHASE_CERT`; blanket `NSAllowsArbitraryLoads: true`
20. Multi-server/account switching — single server only
21. iCloud Keychain — device Keychain only
22. Offline: no offline browse, no download-for-offline, no save-to-Photos (no `PHPhotoLibrary` write path)

**Partial gaps:**
23. Search lacks: people results, date-range/type/orientation filters
24. Album rename/description edit — `updateAlbum` exists in client, unused (V2 backlog)
25. Shared-link expiry UI — `expiresAt` in DTO, no picker (V2 backlog)
26. Map lacks: external-map navigation, location adjust/move asset
27. Favorites-only filter in timeline — plumbing (`filterIsFavorite`) exists, no UI entry
28. i18n — hardcoded FR/EN mix, partial Localizable catalog
29. Timeline → viewer lacks zoom transition (matchedGeometry only in Albums)

## C. Wired-but-unused API surface
`bulkUploadCheck`, `updateAlbum`, `getUsers` (used), `uploadAsset`, `getExploreData`. `PhotoLibraryService` (PHPhotoLibrary) injected but never called — backup foundation dormant.