# ImmichSwiftUI — Feature Audit (2026-09-08)

> **Méthodologie**: lecture directe de tout `Sources/`, `Sources/Services/`, `Core/`, `Core/Protocols/`, `Core/Types/`, `Features/`, `RootView.swift`, `DependencyContainer.swift`, `project.yml`, et des contrats `.acceptance.md` du scratch.
>
> **Date du dépôt**: version en cours sur `main`.

---

## 1. Architecture (vue d'ensemble)

| Couche | Dossier | Rôle |
|---|---|---|
| Protocoles | `Sources/Core/Protocols/` | Abstractions immuables injectables |
| DTOs | `Sources/Core/Types/` | Modèles Codable+Equatable par domaine |
| Services | `Sources/Services/` | Implémentations concrettes (HTTP, caching, photos library, backup) |
| ViewModels | `Sources/Features/*/` | `@Observable` + `@MainActor`, injectent `ImmichClient` |
| Views | `Sources/Features/*/` | SwiftUI stateless, nommées `*View.swift` |
| DesignSystem | `Sources/DesignSystem/` | Tokens (color/spacing/font/motion/shadow) + composants (10 composants) |
| DI | `Sources/DependencyContainer.swift` | Singleton @MainActor, fabriques `make*ViewModel()` |
| Routing | `Sources/RootView.swift` | 5-tabs (Photos/Memories/Albums/Shared/Me) + `role: .search` bubble |

**Stack**: iOS 26, SwiftUI, `@Observable`, iOS 26 Liquid Glass, `Form`/`List`/`ContentUnavailableView`, `.searchable`/`.searchSuggestions`, `Tab(role: .search)`, Reduced Motion, haptic `.sensoryFeedback`.

---

## 2. Features implémentées (15 surfaces)

### 2.1 Authentification & Onboarding

| Fonctionnalité | Status | Fichiers clés |
|---|---|---|
| Welcome screen | ✅ Shipped | `WelcomeScreen.swift` |
| Server URL avec vérification inline (ping + config + version) | ✅ Shipped | `ServerURLScreen.swift` |
| QR Server Config Scan | ✅ Shipped | `QRScannerView.swift`, `QRServerConfigParser.swift` |
| Login email/password | ✅ Shipped | `LoginScreen.swift` |
| Onboarding 3-step flow (`NavigationStack(path:)`) | ✅ Shipped | `OnboardingFlowView.swift` |
| Session persistante (Keychain token + URL) | ✅ Shipped | `KeychainStoreImpl.swift`, `KeychainStore.swift` |
| Auto `https://` normalization | ✅ Shipped | `ServerURLScreen.swift` |
| Logout | ✅ Shipped | `AuthViewModel.swift` |
| App Lock Face ID / Touch ID | ✅ Shipped | `AppLockViewModel.swift`, `LockView` dans `RootView.swift` |
| Toggle App Lock dans BackupSettingsView | ✅ Shipped | `UploadViewModel.swift:BackupSettingsView` |
| OAuth2 (GET mobile URL, exchange code) | ✅ DTOs + Client, UI non implémentée | `OAuthMobileResponseDto`, `OAuthCallbackRequestDto`, `OAuthCallbackResponseDto` |

### 2.2 Timeline (Photos tab)

| Fonctionnalité | Status | Fichiers clés |
|---|---|---|
| Bucket pagination (GET /api/timeline/buckets) | ✅ Shipped | `TimelineView.swift`, `TimelineViewModel.swift` |
| Continuous grid, pinned floating year + "Weekday d Month" header | ✅ Shipped | `TimelineView.swift`, `DateHeaderFormatter.swift` |
| Pinch-zoom 2–7 columns | ✅ Shipped | `TimelineView.swift`, `TimelineGridZoom.swift` |
| Pull-to-refresh | ✅ Shipped | `TimelineView.swift` |
| Scroll-to-top | ✅ Shipped | `TimelineView.swift`, `PinnedHeaderResolver.swift` |
| Multi-select (long-press), selection mode | ✅ Shipped | `AssetThumbnailCell.swift`, `TimelineView.swift` |
| Batch favorite / delete / add-to-album | ✅ Shipped | `TimelineViewModel.swift` |
| Timeline section builder with pinned headers | ✅ Shipped | `TimelineSectionBuilder.swift` |

### 2.3 Photo Viewer

| Fonctionnalité | Status | Fichiers clés |
|---|---|---|
| Pager swipe, pinch + double-tap zoom | ✅ Shipped | `PhotoViewer.swift` |
| Filmstrip natif aspect-ratio | ✅ Shipped | `PhotoViewer.swift` |
| EXIF detail panel (geocoded place, description) | ✅ Shipped | `PhotoInfoPanel.swift` |
| Reverse geocoding via `LocationGeocodingService` | ✅ Shipped | `AssetDetailViewModel.swift` |
| Favorite / edit / delete / restore inline | ✅ Shipped | `PhotoViewer.swift` |
| Share sheet (system share, share-to-user albums, public link) | ✅ Shipped | `PhotoShareViewModel.swift` |
| Live Photo playback support | ✅ Shipped (badge + viewer support) | `PhotoViewer.swift`, `livePhotoVideoId` in DTO |
| Video playback | ✅ Shipped | `VideoPlayerView.swift`, `VideoPlaybackViewModel.swift` |
| Face assignment UI | ✅ Shipped | `FaceAssignSheet.swift`, `FaceThumbnailView.swift` |
| Stack management sheet | ✅ Shipped | `StackSheet.swift` |
| Asset tags sheet | ✅ Shipped | `AssetTagsSheet.swift` |
| Adjust date/time | ✅ Shipped | `AdjustDateSheet.swift` |
| Adjust location (MapPin draggable, PATCH coords, re-geocode) | ✅ Shipped | `AdjustLocationSheet.swift`, `DraggablePinMapView` |
| Open in Maps (MKMapItem.openInMaps) | ✅ Shipped | `PhotoViewer.swift` |
| Slideshow | ✅ Shipped | `SlideshowView.swift`, `SlideshowViewModel.swift` |
| Save to library / Download | ✅ Shipped | `SaveToLibraryViewModel.swift`, `SaveToLibraryView` |
| Glass chrome (8 `.glassEffect(.regular, in:)` controls) | ✅ Shipped | `PhotoViewer.swift` |
| Ken Burns effect for still images | ✅ Shipped | `KenBurnsImageView.swift` |
| Zoomable image view (pinch gesture handling) | ✅ Shipped | `ZoomableImageView.swift` |

### 2.4 Editor (Photo Editor)

| Fonctionnalité | Status | Fichiers clés |
|---|---|---|
| Non-destructive editing: exposure/contrast/saturation/warmth | ✅ Shipped | `PhotoEditorView.swift`, `PhotoEditorViewModel.swift` |
| Straighten ±45° | ✅ Shipped | `PhotoEditorView.swift` |
| Crop + aspect ratios | ✅ Shipped | `PhotoEditorView.swift` |
| Rotate 90° | ✅ Shipped | `PhotoEditorView.swift` |
| Rule of thirds overlay | ✅ Shipped | `PhotoEditorView.swift` |
| Revert to original | ✅ Shipped | `PhotoEditorView.swift` |
| Local disk persistence | ✅ Shipped | `EditStateStore.swift`, `EditPipeline.swift` |

### 2.5 Albums

| Fonctionnalité | Status | Fichiers clés |
|---|---|---|
| Album list view | ✅ Shipped | `AlbumsView.swift`, `AlbumsViewModel.swift` |
| Create album | ✅ Shipped | `CreateAlbumSheet.swift` |
| Album detail view (assets grid, metadata) | ✅ Shipped | `AlbumDetailView.swift`, `AlbumDetailViewModel.swift` |
| Add/remove assets from album | ✅ Shipped | `AddToAlbumPickerSheet.swift` |
| Batch favorite in albums | ✅ Shipped | `AlbumDetailView.swift` |
| Cover set | ✅ Shipped | `EditAlbumSheet.swift` |
| Delete album | ✅ Shipped | `AlbumDetailView.swift` |
| Shared-album user management (invite, EDITOR/VIEWER roles, revoke) | ✅ Shipped | `AlbumShareSheet.swift`, `AlbumShareViewModel.swift` |
| Per-album shared links (password, description, allowUpload, allowDownload, showMetadata, expiry) | ✅ Shipped | `SharedLinksView.swift`, `SharedLinksViewModel.swift`, `SharedLinkSheet.swift`, `EditSharedLinkSheet.swift` |
| Shared link edit (PUT /shared-links/:id) | ✅ Shipped | `EditSharedLinkSheet.swift` |
| Activity feed (comments, reactions) | ✅ Shipped | `ActivityFeedSheet.swift`, `ActivityFeedViewModel.swift` |
| Asset count display | ✅ Shipped | `AlbumDetailView.swift` |

### 2.6 Search

| Fonctionnalité | Status | Fichiers clés |
|---|---|---|
| Debounced live search (text query) | ✅ Shipped | `SearchView.swift`, `SearchViewModel.swift` |
| Metadata search (EXIF fields: city, country, make, model, lensModel, state, type, isFavorite, personIds, albumIds) | ✅ Shipped | `SearchViewModel.swift` |
| CLIP semantic search | ✅ Shipped | `SearchViewModel.swift` |
| Explore places (city/country/make/model/state/lensModel) with counts + EXIF drill-down | ✅ Shipped | `SearchView.swift`, `SearchModeGlassBar.swift` |
| Recent searches (cap 8) | ✅ Shipped | `RecentSearchesStore.swift` |
| Pagination | ✅ Shipped | `SearchViewModel.swift` |
| Saved searches | ✅ Shipped | `SavedSearchesStore.swift` |
| 3-mode switch: Live/Smart/Explore | ✅ Shipped | `SearchModeGlassBar.swift` |

### 2.7 Map

| Fonctionnalité | Status | Fichiers clés |
|---|---|---|
| Clustered markers with real badge counts (sum = sheet total) | ✅ Shipped | `MapView.swift`, `MapViewModel.swift` |
| Map subsampling | ✅ Shipped | `MapViewModel.swift` |
| Cell-select filter, marker → viewer | ✅ Shipped | `MapView.swift` |
| Paginated photo panel | ✅ Shipped | `MapView.swift` |
| Disk cache for markers | ✅ Shipped | `MapMarkerCache.swift` |
| Open in Maps | ✅ Shipped (via PhotoViewer) | `PhotoViewer.swift` |
| Adjust Location (MapPin draggable) | ✅ Shipped (via PhotoViewer) | `AdjustLocationSheet.swift` |

### 2.8 Memories

| Fonctionnalité | Status | Fichiers clés |
|---|---|---|
| Memories tab (On This Day) | ✅ Shipped | `MemoriesView.swift`, `MemoriesViewModel.swift` |
| Year cards with asset grids | ✅ Shipped | `MemoriesView.swift` |
| Memory tap → viewer | ✅ Shipped | `MemoriesView.swift` |
| Memory type support (on_this_day + unknown) | ✅ Shipped | `MemoryMomentView.swift` |

### 2.9 People

| Fonctionnalité | Status | Fichiers clés |
|---|---|---|
| People list view | ✅ Shipped | `PeopleView.swift`, `PeopleViewModel.swift` |
| People pagination + hidden toggle | ✅ Shipped | Client supports `page`, `withHidden` params |
| Create person | ✅ Shipped | `Client.createPerson()` wired |
| Update person (name, birthDate, color, featureFaceAssetId, isFavorite, isHidden) | ✅ Shipped | `Client.updatePerson()` wired |
| Merge people (POST /people/:id/merge) | ✅ Shipped | `Client.mergePeople()` wired |
| Person statistics | ✅ Shipped | `Client.getPersonStatistics()` wired |
| Face reassignment | ✅ Shipped | `Client.reassignFace()`, `Client.getFaces()` wired |
| Face thumbnail viewing in photo viewer | ✅ Shipped | `FaceThumbnailView.swift` |
| Person albums via searchMetadata(personIds:) | ✅ Shipped | `SearchViewModel.swift` supports `personIds` filter |

### 2.10 Trash

| Fonctionnalité | Status | Fichiers clés |
|---|---|---|
| Restore selected assets | ✅ Shipped | `TrashView.swift`, `TrashViewModel.swift` |
| Restore all | ✅ Shipped | `TrashViewModel.swift` |
| Delete permanent | ✅ Shipped | `TrashViewModel.swift` |
| Empty trash | ✅ Shipped | `TrashViewModel.swift` |
| Multi-select trash items | ✅ Shipped | `TrashView.swift` |

### 2.11 Tags

| Fonctionnalité | Status | Fichiers clés |
|---|---|---|
| Tags list view | ✅ Shipped | `TagsView.swift`, `TagsViewModel.swift` |
| Create tag | ✅ Shipped | `Client.createTag()` wired |
| Update tag (color) | ✅ Shipped | `Client.updateTag()` wired |
| Delete tag | ✅ Shipped | `Client.deleteTag()` wired |
| Tag / untag assets | ✅ Shipped | `Client.tagAssets()`, `Client.untagAssets()` wired |
| Asset tags sheet (in photo viewer) | ✅ Shipped | `AssetTagsSheet.swift` |

### 2.12 Admin

| Fonctionnalité | Status | Fichiers clés |
|---|---|---|
| Admin users list | ✅ Shipped | `AdminView.swift`, `AdminViewModel.swift` |
| Create admin user | ✅ Shipped | `Client.createAdminUser()` wired |
| Update admin user | ✅ Shipped | `Client.updateAdminUser()` wired |
| Delete / restore admin user | ✅ Shipped | `Client.deleteAdminUser()`, `Client.restoreAdminUser()` wired |
| Jobs status | ✅ Shipped | `Client.getJobsStatus()` wired |
| Job commands (start, pause, resume, empty, clear-failed) | ✅ Shipped | `Client.sendJobCommand()` wired |
| Libraries list | ✅ Shipped | `Client.getLibraries()` wired |
| Library scan / delete | ✅ Shipped | `Client.scanLibrary()`, `Client.deleteLibrary()` wired |
| API keys list/create/delete | ✅ Shipped | `Client.getAPIKeys()`, `Client.createAPIKey()`, `Client.deleteAPIKey()` wired |

### 2.13 Profile

| Fonctionnalité | Status | Fichiers clés |
|---|---|---|
| Account info (name, email, profile picture) | ✅ Shipped | `ProfileView.swift` |
| Storage stats (photos, videos, usage, quota bar) | ✅ Shipped | `StorageStatsViewModel.swift` |
| Links to Trash, Backup | ✅ Shipped | `ProfileView.swift` |
| Logout | ✅ Shipped | `ProfileView.swift` |

### 2.14 Upload / Backup

| Fonctionnalité | Status | Fichiers clés |
|---|---|---|
| Multipart upload (SHA1 dedup, livePhotoVideoId, checksum) | ✅ Shipped | `UploadViewModel.swift` |
| Bulk upload check | ✅ Shipped | `Client.bulkUploadCheck()` wired |
| Background backup scheduling | ✅ Shipped | `BackgroundBackupScheduling.swift` |
| Backup engine (upload loop, cancel, phases) | ✅ Shipped | `BackupEngine.swift` |
| Backup notification service | ✅ Shipped | `NotificationService.swift` (ex `BackupNotificationService.swift`) |
| Backup Live Activity (Dynamic Island + Lock Screen progress) | ✅ Shipped | `BackupLiveActivityService.swift`, `ImmichWidgets/BackupLiveActivity.swift` |
| Backup settings UI (Wi-Fi only, exclude albums, etc.) | ✅ Shipped | `UploadViewModel.swift:BackupSettingsView` |
| PhotoLibraryService (PHPhotoLibrary) injected | ✅ Shipped (wired, backup UI not yet exposed in root nav) | `PhotoLibraryServiceImpl.swift` |
| Background upload queue | ✅ Shipped | `BackupEngine.swift` |

### 2.15 Social (Partners, Activity, Duplicates)

| Fonctionnalité | Status | Fichiers clés |
|---|---|---|
| Partner list (getPartners) | ✅ Shipped (2026-09-13) | `PartnersView.swift` + `PartnersViewModel.swift` — `getPartners(direction:)` (le `direction` requis manquait : l'ancien appel rendait 400) |
| Partner timeline toggle | ✅ Shipped | `Client.updatePartner()` — borné aux lignes `shared-with` |
| Remove partner | ✅ Shipped | `Client.removePartner()` — borné aux lignes `shared-by` |
| Invite partner | ✅ Shipped | `Client.createPartner(sharedWithId:)` + `InvitePartnerSheet` (annuaire `GET /api/users`) |
| Activity feed (comments, likes) | ✅ Shipped | `ActivityFeedSheet.swift` (wired in album detail) |
| Create activity (comment, like) | ✅ Shipped | `Client.createActivity()` wired |
| Delete activity | ✅ Shipped | `Client.deleteActivity()` wired |
| Duplicates list | ✅ Shipped | `DuplicatesView.swift`, `DuplicatesViewModel.swift` |
| Duplicate detection endpoint | ✅ Shipped | `Client.getDuplicates()` wired |

---

## 3. Features partiellement implémentées (API wired but UI minimal)

| Feature | Client API | UI | Gap |
|---|---|---|---|
| **Archive filter** | `isArchived` param in buckets | `nil` hardcoded everywhere | No UI entry in Timeline/Search/Albums |
| **Stacks** | Full CRUD wired (search/create/get/update/delete/removeAsset) | `StackSheet.swift` in photo viewer | API methods wired but not full-stack UI |
| **People** | Full CRUD + merge + faces + statistics | `PeopleView.swift` basic list | No person albums grid, no face browsing from timeline |
| **Memories** | GET /memories wired | Basic tab with OnThisDay cards | No save/unsave, no create memory, no other memory types |
| **Partners** | Full CRUD wired | Only as DTO + client | No partner-sharing UI tab |
| **Shared Links** | Full CRUD + visitor routes wired | Shared tab with list, create/edit sheets and the **public viewer** (`SharedLinkViewerView`, entry point in the Shared toolbar) | No download action for a visitor |
| **Admin** | Full CRUD wired | Admin view | Admin tab only accessible for admin users |
| **Tags** | Full CRUD + asset tagging wired | Basic list + asset tags sheet | No tag search, no auto-tagging |
| **OAuth2** | Mobile URL + callback wired | No OAuth button in login | TODO, just DTOs + client |
| **Duplicates** | GET /duplicates wired | Basic list | No suggested-keep UI, no merge from duplicates |
| **Video playback** | AVPlayer wired | Video playback works | Only in viewer, no separate video-only tab |
| **Slideshow** | Full UI wired | Slideshow tab/viewer | No slideshow from albums |
| **Live Photo** | Playback support | Viewer badge + viewer support | No live photo playback button |
| **Save to Library / Download** | Full UI + PHPhotoLibrary write path | Photo viewer sheet | Implemented but may lack offline download |

---

## 4. Endpoints API — gap analysis

### 4.1 Endpoints implémentés (client + UI)

| Endpoint | Méthode | UI |
|---|---|---|
| `/api/auth/login` | POST | ✅ |
| `/api/auth/logout` | POST | ✅ |
| `/api/auth/validateToken` | POST | ✅ (auto-restore) |
| `/api/oauth/authorize` | POST | ✅ (DTOs wired) |
| `/api/oauth/callback` | POST | ✅ (DTOs wired) |
| `/api/server/ping` | GET | ✅ (onboarding) |
| `/api/server/version` | GET | ✅ (onboarding) |
| `/api/server/config` | GET | ✅ (onboarding) |
| `/api/server/statistics` | GET | ✅ (Profile/Storage) |
| `/api/timeline/buckets` | GET | ✅ (Timeline tab) |
| `/api/timeline/bucket` | GET | ✅ (Timeline tab) |
| `/api/assets/:id` | GET | ✅ (PhotoViewer) |
| `/api/assets/:id` | PATCH | ✅ (editor, favorite, info updates) |
| `/api/assets` | DELETE | ✅ (multi-select delete) |
| `/api/assets` | PUT | ✅ (bulkUpdateAssets — archive/visibility) |
| `/api/assets` | POST (multipart) | ✅ (Upload) |
| `/api/assets/bulk-upload-check` | POST | ✅ (Upload dedup) |
| `/api/trash/restore/assets` | POST | ✅ (Trash) |
| `/api/trash/restore` | POST | ✅ (Trash) |
| `/api/trash/empty` | POST | ✅ (Trash) |
| `/api/search/metadata` | POST | ✅ (Search) |
| `/api/search/smart` | POST | ✅ (Search) |
| `/api/search/explore` | GET | ✅ (Search explore) |
| `/api/search/cities` | GET | ✅ (Search explore) |
| `/api/search/statistics` | POST | ✅ (Search) |
| `/api/map/markers` | GET | ✅ (Map tab) |
| `/api/albums` | GET | ✅ (Albums tab) |
| `/api/albums` | POST | ✅ (Create album) |
| `/api/albums/:id` | GET | ✅ (Album detail) |
| `/api/albums/:id` | PATCH | ✅ (Update album) |
| `/api/albums/:id` | DELETE | ✅ (Delete album) |
| `/api/albums/:id/assets` | PUT | ✅ (Add to album) |
| `/api/albums/:id/assets` | DELETE | ✅ (Remove from album) |
| `/api/albums/:id/users` | PUT | ✅ (Share album to users) |
| `/api/albums/:id/user/:userId` | PUT | ✅ (Update user role) |
| `/api/albums/:id/user/:userId` | DELETE | ✅ (Remove user) |
| `/api/shared-links` | GET | ✅ (Shared tab) |
| `/api/shared-links` | POST | ✅ (Create link) |
| `/api/shared-links/:id` | PUT | ✅ (Edit link) |
| `/api/shared-links/:id` | DELETE | ✅ (Revoke link) |
| `/api/tags` | GET | ✅ (Tags tab) |
| `/api/tags` | POST | ✅ (Create tag) |
| `/api/tags/:id` | PUT | ✅ (Update tag) |
| `/api/tags/:id` | DELETE | ✅ (Delete tag) |
| `/api/tags/:id/assets` | PUT | ✅ (Tag assets) |
| `/api/tags/:id/assets` | DELETE | ✅ (Untag assets) |
| `/api/people` | GET | ✅ (People tab) |
| `/api/people` | POST | ✅ (Create person) |
| `/api/people/:id` | PUT | ✅ (Update person) |
| `/api/people/:id/merge` | POST | ✅ (Merge people) |
| `/api/people/:id/statistics` | GET | ✅ (Person stats) |
| `/api/faces/:personId` | PUT | ✅ (Reassign face) |
| `/api/faces` | GET | ✅ (Get faces by asset) |
| `/api/partners?direction=` | GET | ✅ (`direction` requis, envoyé depuis 2026-09-13) |
| `/api/partners` | POST | ✅ (corps `{sharedWithId}`) |
| `/api/partners/:id` | PUT | ✅ (lignes `shared-with` seulement) |
| `/api/partners/:id` | DELETE | ✅ (Client only) |
| `/api/activities` | GET | ✅ (Activity feed) |
| `/api/activities` | POST | ✅ (Create activity) |
| `/api/activities/:id` | DELETE | ✅ (Delete activity) |
| `/api/memories` | GET | ✅ (Memories tab) |
| `/api/duplicates` | GET | ✅ (Duplicates tab) |
| `/api/stacks` | GET | ✅ (Client only) |
| `/api/stacks` | POST | ✅ (Client only) |
| `/api/stacks/:id` | GET | ✅ (Client only) |
| `/api/stacks/:id` | PUT | ✅ (Client only) |
| `/api/stacks/:id` | DELETE | ✅ (Client only) |
| `/api/stacks/:id/assets/:assetId` | DELETE | ✅ (Client only) |
| `/api/admin/users` | GET | ✅ (Admin tab) |
| `/api/admin/users` | POST | ✅ (Admin tab) |
| `/api/admin/users/:id` | PUT | ✅ (Admin tab) |
| `/api/admin/users/:id` | DELETE | ✅ (Admin tab) |
| `/api/admin/users/:id/restore` | POST | ✅ (Admin tab) |
| `/api/jobs` | GET | ✅ (Admin tab) |
| `/api/jobs/:name` | PUT | ✅ (Admin tab) |
| `/api/libraries` | GET | ✅ (Admin tab) |
| `/api/libraries/:id/scan` | POST | ✅ (Admin tab) |
| `/api/libraries/:id` | DELETE | ✅ (Admin tab) |
| `/api/api-keys` | GET | ✅ (Admin tab) |
| `/api/api-keys` | POST | ✅ (Admin tab) |
| `/api/api-keys/:id` | DELETE | ✅ (Admin tab) |
| `/api/users` | GET | ✅ (User picker for share) |

### 4.2 Gaps marqués dans ImmichClient.swift

| Gap | Endpoint | Status | Détails |
|---|---|---|---|
| #1 | `/api/stacks/*` (tous) | ✅ Client wired | DTOs + toutes les méthodes, pas de navigation dédiée (StackSheet dans viewer) |
| #2 | `/api/tags/*` (tous) | ✅ Client wired | Tags tab + AssetTagsSheet dans viewer |
| #5 | `/api/faces` | ✅ Client wired | Face reassignment in viewer, face list |
| #12 | `/api/admin/*`, `/api/jobs`, `/api/libraries`, `/api/api-keys` | ✅ Client wired | Full admin view + all methods |

**Note**: Tous les "gaps" ont été résolus — DTOs + methods + UI implémentés.

---

## 5. Ce qui est wired (client API) mais pas dans la navigation

| Feature | Client | UI dans nav | Usage |
|---|---|---|---|
| Archive filter | `isArchived` param | Non | Timeline buckets, search |
| Partners | CRUD | Non | Shared-album partner management |
| Duplicates merge | `getDuplicates` | Liste, pas de merge UI | `getDuplicates()` wired, no merge action |
| Video-only tab | `VideoPlayerView` | Non | Only in viewer |
| Slideshow from albums | `SlideshowView` | Non | Only standalone memory-style |
| Map from profile | `MapView` | Non | Only in search tab |
| Favorites-only timeline filter | `isFavorite` param | Non | Timeline search filter |
| Album rename/description | `updateAlbum` PATCH | Non | `UpdateAlbumDto` supports desc/name, unused in UI |
| Shared-link expiry UI | `expiresAt` in `SharedLinkEditDto` | Non | No date picker in edit sheet |
| Multi-server | Single server only | Single | No account switcher |
| Self-signed cert trust | `TrustEvaluatingURLSessionDelegate` | Via QR onboarding | No cert manager UI |
| Widgets | `ImmichWidgets/` Live Activity only | No home-screen widgets | Live Activity shipped, widgets pending |
| App Intents / Shortcuts | `AppIntents.swift` | Minimal | Basic intent support |
| Push notifications | Permission screen (`UNUserNotificationCenter`) | Local notifications only | No APNs anywhere: the server has no device-token route and Flutter has no push stack. Permission screen shipped 2026-09-13 |
| iCloud Keychain | Device Keychain only | None | Not iCloud synced |
| Offline browsing | No offline | None | No download-for-offline |

---

## 6. Ce qui est manquant vs client Flutter

### Background Uploads (biggest gap)

| Feature | SwiftUI | Flutter |
|---|---|---|
| Auto-detect new photos | ✅ (PHPhotoLibraryChangeObserver + BGTask) | ✅ |
| Exclude screenshots / camera roll | ✅ (smart albums + mode tri-état, remplace les heuristiques par nom de fichier) | ✅ |
| Wi-Fi / cellular / charging toggles | ✅ (politique par type de média + gate hors-ligne) | ✅ |
| Upload queue with per-asset status | ✅ (BackupEngine) | ✅ |
| Per-asset progress | ✅ (Live Activity) | ✅ |
| Upload progress banner | ➖ remplacé par l'anneau autour de l'avatar | ✅ |
| Resume from interruption | ✅ (`resumeUpload`) | ✅ |
| Backfill reorganize | ➖ retiré 2026-09-10 (doublon du scoping d'albums + « Run now ») | ✅ |
| Dedup by checksum | ✅ (bulkUploadCheck + ledger réconcilié) | ✅ |
| Live Photos (vidéo appairée) | ✅ (upload `.hidden` + `updateAsset`) | ✅ |

### Server-backed modules (partial)

| Feature | SwiftUI | Flutter |
|---|---|---|
| Memories save/unsave | ❌ | ✅ |
| Create memory | ❌ | ✅ |
| Other memory types (first day, yearly recap) | ❌ | ✅ |
| Partner creation (by email) | ❌ | ✅ |
| Partner UI (invite/remove) | Client only | ✅ |
| Shared-album new assets notification | ❌ | ✅ |
| Notifications (local + permission) | ✅ | ✅ |
| Push notifications (APNs) | ❌ (no server contract — not implementable) | ❌ |

### Search enhancements

| Feature | SwiftUI | Flutter |
|---|---|---|
| Date range filter | ❌ | ✅ |
| Orientation filter | ❌ | ✅ |
| People in search results | ❌ | ✅ |
| Starred/favorite-only filter in search | Partial (parameter) | ✅ |

### Video / Live Photo

| Feature | SwiftUI | Flutter |
|---|---|---|
| Live Photo playback | Partial (badge + viewer) | ✅ |
| Video-only tab | ❌ | ✅ |
| Background video processing | ❌ | ✅ |

### Platform features

| Feature | SwiftUI | Flutter |
|---|---|---|
| Widgets (home screen) | ❌ | ❌ (same) |
| Widgets (Lock Screen) | ❌ | ❌ |
| App Intents (full Siri integration) | Partial | ❌ |
| Apple Watch | ❌ | ❌ |
| iPad split-view | Partial (audit notes issues) | ✅ |

### Settings / Platform

| Feature | SwiftUI | Flutter |
|---|---|---|
| Notification permission settings | ✅ | ✅ |
| Sync status | ❌ | ✅ |
| App log viewer | ❌ | ✅ |
| "What's New" screen | ❌ | ✅ |
| Profile picture crop | ❌ | ✅ |
| Asset troubleshoot | ❌ | ✅ |
| Download info | ❌ | ✅ |

---

## 7. Qualité & conventions

| Aspect | État |
|---|---|
| Architecture MVVM stricte | ✅ |
| Tous les VMs `@Observable` (pas `@ObservableObject`) | ✅ |
| Tous les VMs `@MainActor` | ✅ |
| Protocoles immuables | ✅ |
| DI via `DependencyContainer` | ✅ |
| Views stateless, nommées `*View.swift` | ✅ |
| Design system centralisé (10 composants + 6 tokens) | ✅ |
| iOS 26 Liquid Glass | ✅ |
| Reduce Motion | ✅ |
| Haptic feedback | ✅ |
| Accessibilité (grouping, headers, hints partial) | ✅ |
| Acceptance criteria méthodologie | ✅ (40+ cards) |
| Tests unitaires | ✅ (système de tests, pattern mock, AC-based) |
| i18n | ⚠️ Hardcoded FR/EN mix, partial `Localizable.xcstrings` |
| Color migration (brandIndigo → immichPrimary) | ⚠️ Incomplete, 10 files still use deprecated |
| DateFormatter hoisting | ⚠️ Per-call allocations in hot paths |
| Timeline perf (memoize section builder) | ⚠️ Per-render computation |
| Map marker cache eviction | ⚠️ Unbounded file cache |

---

## 8. Synthèse

**Total features implémentées**: 15 surfaces complètes + plusieurs partiels (client API wired but minimal UI).

**Points forts**:
- Archive solide de l'API Immich (presque tous les endpoints couverts)
- Photo viewer premium (Liquid Glass, filmstrip, slideshow, video, face assignment)
- Editor non-destructif complet
- Albums partagés avec feed d'activité
- Search complète (metadata + CLIP + explore + map)
- Memories / Duplicates / People / Admin / Tags / SharedLinks
- Backup avec Live Activity (première extension du projet)
- Visionneuse de lien partagé (visiteur : mot de passe + cookie, grille, upload invité) — feature sans équivalent Flutter
- Architecture propre, tests, acceptance contracts

**Gaps principaux**:
1. **Upload/backup auto** — le cœur du produit Immich (détection, exclusions, resume, backfill)
2. **Partners / sharing UI** — client API complet mais pas d'écran dédié
3. **Memories complet** — save/unsave, création, autres types
4. **i18n** — FR/EN hardcoded, catalogue `Localizable.xcstrings` partiel
5. **Widgets / App Intents** — Live Activity fait, le reste en attente
6. ~~**Push notifications**~~ — re-scopé le 2026-09-13 : l'écran d'autorisation OS est livré ; le reste (APNs) est **impossible** (aucun endpoint serveur, aucun push dans Flutter)
7. **Offline download**
