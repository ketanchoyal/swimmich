# ImmichSwiftUI — Backlog d'Implémentation

> **Objectif** : Porter l'intégralité des fonctionnalités du client Flutter Immich upstream vers ImmichSwiftUI (iOS 26, SwiftUI, MVVM).
>
> **Architecture cible** : MVVM strict 4 couches — Core/Protocols, Core/Types, Services, Features, DesignSystem.
>
> **Validation** : `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 17'` — baseline ~214 tests minimum.

---

## Table des matières

1. [Tableau de suivi](#tableau-de-suivi)
2. [Phases d'implémentation](#phases-dimplémentation)
3. [Fiches features détaillées](#fiches-features-détaillées)
4. [Référence API — endpoints ImmichClient](#référence-api--endpoints-immichclient)
5. [Checklists de vérification](#checklists-de-vérification)

---

## Tableau de suivi

| # | Feature | Phase | AC Cards | Spéc | Prompt | Status | Endpoints manquants | Tests | Progression |
|---|---------|-------|----------|------|--------|--------|---------------------|-------|-------------|
| 1 | **Backup Auto** | P2 | AC-BK01–BK09 | .omp/backup-auto/ | Voir §2.1 | 🔴 Pending | — (existants) | 10% (engine OK, UI manquante) | 12/9 AC |
| 2 | **OAuth2 UI** | P5 | AC-3000–3007 | .omp/oauth2-ui/ | Voir §2.2 | 🟡 Plan | — (wire) | 50% (5 tests existants) | 6/8 AC |
| 3 | **Partners UI** | P3 | AC-3100–3109 | .omp/partners-ui/ | Voir §2.3 | 🟡 Plan | createPartner, getPartners(dir) | 0/6 | 0/10 AC |
| 4 | **Memories Complete** | P4 | AC-3200–3208 | .omp/memories-complete/ | Voir §2.4 | 🟡 Plan | 7 (CRUD + stats) | 0/8 | 0/9 AC |
| 5 | **Push Notifications** | P5 | AC-3300–3308 | .omp/push-notifications/ | Voir §2.5 | 🟡 Plan | device-token reg/unreg | 0/9 | 0/9 AC |
| 6 | **Shared Links Enriched** | P3 | AC-3400–3409 | .omp/shared-links-enriched/ | Voir §2.6 | 🟡 Plan | getPublic, uploadTo, checkPW | 0/7 | 0/10 AC |
| 7 | **Offline Download** | P4 | AC-3500–3508 | .omp/offline-download/ | Voir §2.7 | 🟡 Plan | — (FileManager) | 0/8 | 0/9 AC |
| 8 | **Widgets Home Screen** | P5 | AC-3600–3608 | .omp/widgets-homescreen/ | Voir §2.8 | 🟡 Plan | — (WidgetKit) | 0/4 | 0/9 AC |
| 9 | **Stacks UI** | P3 | AC-3700–3708 | .omp/stacks-ui/ | Voir §2.9 | 🟡 Plan | — (100% wire) | 0/6 | 0/9 AC |
| 10 | **i18n Completing** | P5 | AC-3800–3807 | .omp/i18n/ | Voir §2.10 | 🟡 Plan | — (localisation) | 0/3 | 0/8 AC |

**Legend** :
- 🔴 **Pending** — Spéc existante, pas de card AC générée
- 🟡 **Plan** — Card AC générée, phase planifiée
- 🟢 **En cours** — Implémentation en cours
- ✅ **Terminé** — Tous les AC passent

---

## Phases d'implémentation

```
P0 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ API Foundation (DTOs, Endpoints)
P1 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ Core UX (Navigation, Auth, Settings)
P2 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ Backup (Auto-backup, Live Activity)
P3 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ Social (Partners, Stacks, Shared Links)
P4 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ Discovery (Memories, Offline, Search)
P5 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ Platform (Widgets, Push, OAuth2, i18n)
```

---

## Fiches features détaillées

### 2.1. Backup Auto (P2)

**Fichier spec** : `.omp/backup-auto/backup-auto.specs.md`
**Card AC** : `.opencode/scratch/backup-auto.acceptance.md`
**UI brief** : `.omp/backup-auto/backup-auto.ui.md`
**AC Cards** : AC-BK01 – AC-BK09
**Phase** : P2 — Backup

#### Objectif
Porter le backup automatique complet du client Flutter : contrôles d'exclusion (caméra externe, WhatsApp), détection auto de nouvelles photos, backfill reorganize, gestion resume, et banner de progression flottant.

#### Points d'entrée
- `BackupSettingsStore` — Ajouter `excludeCameraRoll`, `excludeWhatsApp`, `autoDetectNewPhotos` (UserDefaults clé `photoBackup*`)
- `UploadViewModel` — `runBackfill(albumId:)`, `showBackfillSheet`, `uploadHistory: [UploadHistoryEntry]`
- `UploadProgressBanner` — Floating glass bar dans Timeline pendant upload actif
- `BackfillSheet` — Sélection album + bouton reorganize, morph glass transition

#### Endpoint API
- `POST /api/assets` (multipart upload) — existant
- `POST /api/assets/bulk-upload-check` — existant

#### Étapes d'implémentation
1. Étendre `BackupSettingsStore` + `BackupSettings` avec 3 nouveaux booléens
2. Ajouter `runBackfill(albumId:)`, `uploadHistory`, `showBackfillSheet` dans `UploadViewModel`
3. Filtrer `excludeCameraRoll` + `excludeWhatsApp` dans `BackupEngine.run`
4. Créer `UploadProgressBanner` avec `.scrollEdgeEffectStyle(.floating)`
5. Créer `BackfillSheet` avec `@Namespace` / `glassEffectID` morphing
6. Intégrer dans `TimelineView` pendant upload actif
7. Créer `Tests/UploadViewModelTests.swift` ≥6 tests

#### Tests attendus
- `Tests/UploadViewModelTests.swift` ≥6 tests : resume, backfill settings, exclude filters, snapshot persistence
- Regression : suite ≥ baseline (~214 tests)

---

### 2.2. OAuth2 UI (P5)

**Fichier spec** : `.omp/oauth2-ui/oauth2-ui.specs.md`
**Card AC** : `.opencode/scratch/oauth2-ui.acceptance.md`
**UI brief** : `.omp/oauth2-ui/oauth2-ui.ui.md`
**AC Cards** : AC-3000 – AC-3007
**Phase** : P5 — Auth & Platform

#### Objectif
Ajouter le bouton OAuth2 dans LoginScreen pour connexion OIDC (SSO). Les DTOs et client sont wire mais pas d'interface.

#### Points d'entrée
- `AuthViewModel` — `startOAuthFlow()`, `handleOAuthCallback(url:)`, `oauthResult: OAuthResult?`, `oauthAuthorizationURL: URL?`
- `LoginScreen` — Bouton "Sign in with Provider" (globe SF symbol) + OR divider
- `OAuthLoadingView` — Sheet avec ProgressView pendant ASWebAuthenticationSession
- `ImmichSwiftUIApp` — `.onOpenURL` pour `immich://oauth-callback`

#### Endpoint API
- `GET /api/auth/oauth2/mobile` — existant (`getOAuthMobileURL`)
- `POST /api/auth/oauth2/exchange` — existant (`exchangeOAuthCode`)

#### Étapes d'implémentation
1. Ajouter `startOAuthFlow()`, `handleOAuthCallback(url:)` dans `AuthViewModel`
2. `ASWebAuthenticationSession` avec `immich://oauth-callback` dans `startOAuthFlow()`
3. Ajouter bouton OAuth + OR divider dans `LoginScreen`
4. Créer `OAuthLoadingView` dans `Sources/Features/Auth/`
5. Ajouter `.onOpenURL` handler dans `ImmichSwiftUIApp.swift`
6. Tests ≥4 dans `AuthViewModelTests`

#### Tests attendus
- `AuthViewModelTests` ≥4 tests : startOAuth, handleCallback, exchangeCode, cancel, error
- Regression : suite ≥ baseline

---

### 2.3. Partners UI (P3)

**Fichier spec** : `.omp/partners-ui/partners-ui.specs.md`
**Card AC** : `.opencode/scratch/partners-ui.acceptance.md`
**UI brief** : `.omp/partners-ui/partners-ui.ui.md`
**AC Cards** : AC-3100 – AC-3109
**Phase** : P3 — Social

#### Objectif
Interface complète de partage entre partenaires : écran dédié avec tabs "Shared with me" / "Sharing", invitation par email ou recherche utilisateur, toggle timeline par partenaire.

#### Points d'entrée
- `PartnerCreateDto` + `PartnerDirection` enum — `DTOs+People.swift`
- `PartnerShellView` — TabView segmenté + FAB "+" + liste partners
- `PartnerShellViewModel` — loadPartners, createPartner, togglePartner, removePartner
- `InvitePartnerSheet` — TextField email + UserSearchView
- `UserSearchView` — SearchField + liste users filtrée + checkmark

#### Endpoint API
- `POST /api/partners` — **manquant** (createPartner)
- `GET /api/partners?direction=` — **manquant** (getPartners with direction)
- `PATCH /api/partners/:id` — existant (updatePartner)
- `DELETE /api/partners/:id` — existant (removePartner)

#### Étapes d'implémentation
1. Créer `PartnerCreateDto` + `PartnerDirection` dans `DTOs+People.swift`
2. Ajouter `createPartner(email:)` + `getPartners(direction:)` dans `ImmichClient` + `ImmichAPIClient`
3. Créer `PartnerShellViewModel` dans `Sources/Features/SharedLinks/`
4. Créer `PartnerShellView` avec TabView segmenté + FAB
5. Créer `InvitePartnerSheet` + `UserSearchView`
6. Ajouter "Partners" link dans `ProfileView` → `PartnerShellView`
7. Mock `createPartner` + `getPartners` dans `MockImmichClient`
8. Tests ≥6

#### Tests attendus
- `Tests/PartnerShellViewModelTests.swift` ≥6 tests : create, toggle, remove, direction filter, empty state, error
- Regression : suite ≥ baseline

---

### 2.4. Memories Complete (P4)

**Fichier spec** : `.omp/memories-complete/memories-complete.specs.md`
**Card AC** : `.opencode/scratch/memories-complete.acceptance.md`
**UI brief** : `.omp/memories-complete/memories-complete.ui.md`
**AC Cards** : AC-3200 – AC-3208
**Phase** : P4 — Discovery

#### Objectif
Compléter le module Memories avec CRUD complet : save/unsave, create custom memory, delete, add/remove assets, et nouveaux types (first_day, yearly_recap). Currently read-only (`getMemories()` only).

#### Points d'entrée
- `MemoryCreateDto` + `MemoryUpdateDto` — `DTOs+Social.swift`
- `MemoryType` — Ajouter `.first_day`, `.yearly_recap`
- `MemoriesViewModel` — saveMemory, unsaveMemory, createMemory, deleteMemory, memoryTitle, memoryDate, selectedType, selectedPhotos
- `CreateMemorySheet` — Type selector + title + date picker + photo count

#### Endpoint API (7 nouveaux)
- `GET /api/memories/:id` — getMemory
- `PATCH /api/memories/:id` — updateMemory
- `DELETE /api/memories/:id` — deleteMemory
- `POST /api/memories` — createMemory
- `POST /api/memories/:id/assets` — addAssetsToMemory
- `DELETE /api/memories/:id/assets` — removeAssetsFromMemory
- `GET /api/memories/statistics` — getMemoriesStatistics

#### Étapes d'implémentation
1. Créer `MemoryCreateDto`, `MemoryUpdateDto`, ajouter `first_day`/`yearly_recap` à `MemoryType`
2. Ajouter 7 méthodes dans `ImmichClient` + `ImmichAPIClient`
3. Étendre `MemoriesViewModel` avec CRUD + state (title, date, type, photos)
4. Étendre `MemoriesView` avec save/unsave context menu, create FAB, type badges
5. Créer `CreateMemorySheet`
6. Mock + tests ≥8

#### Tests attendus
- `Tests/MemoriesViewModelTests.swift` ≥8 tests : save, unsave, create, delete, first_day, yearly_recap, type variants, error
- Regression : suite ≥ baseline

---

### 2.5. Push Notifications (P5)

**Fichier spec** : `.omp/push-notifications/push-notifications.specs.md`
**Card AC** : `.opencode/scratch/push-notifications.acceptance.md`
**UI brief** : `.omp/push-notifications/push-notifications.ui.md`
**AC Cards** : AC-3300 – AC-3308
**Phase** : P5 — Auth & Platform

#### Objectif
Notifications push APNs pour uploads terminés, activity de shared albums, et nouvelles photos de partenaires. Parité avec le client Flutter.

#### Points d'entrée
- `PushNotificationService` (Services) — requestAuthorization, registerDevice, unregisterDevice, handlePush, onBackupComplete, onNewActivity, onNewPartnerPhoto
- `PushNotificationStore` (Services) — Persist settings dans UserDefaults("pushNotificationSettings")
- `PushNotificationViewModel` (Features/Settings/) — loadSettings, saveSettings, registerDevice, unregisterDevice, isRegistered, connectionStatus
- `PushNotificationSettingsView` (Features/Settings/) — Master toggle + sub-toggles (backup, activity, partner)
- Intégration : `AuthViewModel` (register au login, unregister au logout), `UploadViewModel` (onBackupComplete), `ActivityFeedViewModel` (onNewActivity)

#### Endpoint API
- `POST /api/users/me/device-token` — **manquant** (device token registration)

#### Étapes d'implémentation
1. Créer `PushNotificationService` — APNs registration + callbacks dispatch
2. Créer `PushNotificationStore` — persist settings (notificationsEnabled, backupEnabled, activityEnabled, partnerEnabled)
3. Créer `PushNotificationViewModel` — settings + registration state
4. Créer `PushNotificationSettingsView` — master toggle + sub-toggles
5. Intégrer dans `AuthViewModel`, `UploadViewModel`, `ActivityFeedViewModel`
6. Ajouter link "Notifications" dans `ProfileView`
7. Tests ≥9 (Service + ViewModel)

#### Tests attendus
- `Tests/PushNotificationServiceTests.swift` ≥5 tests : auth, register, unregister, dispatch
- `Tests/PushNotificationViewModelTests.swift` ≥4 tests : settings, registration
- Regression : suite ≥ baseline

---

### 2.6. Shared Links Enriched (P3)

**Fichier spec** : `.omp/shared-links-enriched/shared-links-enriched.specs.md`
**Card AC** : `.opencode/scratch/shared-links-enriched.acceptance.md`
**UI brief** : `.omp/shared-links-enriched/shared-links-enriched.ui.md`
**AC Cards** : AC-3400 – AC-3409
**Phase** : P3 — Social

#### Objectif
Enrichir les shared links : preview WKWebView in-app, copy-link, upload-from-link, expiry date picker, password verification. CRUD de base existant.

#### Points d'entrée
- `SharedLinksViewModel` — copyLink, buildPublicURL, openPreview, startUploadFromLink, checkPassword
- `ExternalLinkPreviewView` — WKWebView + toolbar Close/Copy URL/Share
- `UploadFromLinkView` — Form choose photos + link info + upload CTA
- `EditSharedLinkSheet` — UIDatePicker expiresAt + quick presets (1d, 7d, 30d, Never)

#### Endpoint API (3 manquants)
- `GET /api/shared-links/public/:slug` — **manquant** (getSharedLinkPublic)
- `POST /api/shared-links/:slug/assets` — **manquant** (uploadToSharedLink)
- `POST /api/shared-links/:slug/check-password` — **manquant** (checkSharedLinkPassword)

#### Étapes d'implémentation
1. Ajouter 3 nouvelles méthodes dans `ImmichClient` + `ImmichAPIClient`
2. Étendre `SharedLinksViewModel` avec copy/link/preview/upload/password
3. Créer `ExternalLinkPreviewView` (WKWebView) dans `Features/SharedLinks/`
4. Créer `UploadFromLinkView` dans `Features/SharedLinks/`
5. Ajouter expiry picker dans `EditSharedLinkSheet`
6. Ajouter MoreActionsButton (preview/copy/upload/edit/revoke) dans `SharedLinksView`
7. Mock + tests ≥6

#### Tests attendus
- `Tests/SharedLinksViewModelTests.swift` ≥6 tests : copy link, public URL, upload from link, password check, error, expiry picker
- Regression : suite ≥ baseline

---

### 2.7. Offline Download (P4)

**Fichier spec** : `.omp/offline-download/offline-download.specs.md`
**Card AC** : `.opencode/scratch/offline-download.acceptance.md`
**UI brief** : `.omp/offline-download/offline-download.ui.md`
**AC Cards** : AC-3500 – AC-3508
**Phase** : P4 — Discovery

#### Objectif
Téléchargement d'assets pour consultation hors-ligne. Cache FileManager local, indicator de disponibilité offline, gestion de la taille de cache.

#### Points d'entrée
- `OfflineAssetStore` (Services) — downloadAsset, getCachedAsset, isCached, removeCachedAsset, clearAllCachedAssets, cachedAssets, CachedAssetInfo
- `OfflineDownloadViewModel` (Features/Offline/) — cachedAssets, downloadAsset, removeFromOffline, clearAll, cacheUsage
- `OfflineAssetsView` (Features/Offline/) — asset grid + clear all + storage indicator
- `PhotoViewer` — "Download for offline" dans share sheet
- `AssetThumbnailCell` — cached indicator overlay (checkmark circle)

#### Endpoint API
- `GET /api/assets/:id/original` — existant (download original file)

#### Étapes d'implémentation
1. Créer `OfflineAssetStore` — FileManager cache avec maxCacheSize configurable
2. Créer `OfflineDownloadViewModel` — gestion UI state + download progress
3. Créer `OfflineAssetsView` — LazyVGrid + storage usage card + clear all
4. Ajouter "Download for offline" dans `PhotoViewer` share sheet
5. Ajouter cached indicator dans `AssetThumbnailCell`
6. Ajouter link "Offline Storage" dans `ProfileView`
7. Tests ≥8 (Store + ViewModel)

#### Tests attendus
- `Tests/OfflineAssetStoreTests.swift` ≥5 tests : download, cache hit, cache miss, remove, clear, size limit
- `Tests/OfflineDownloadViewModelTests.swift` ≥3 tests : download progress, remove, clear
- Regression : suite ≥ baseline

---

### 2.8. Widgets Home Screen (P5)

**Fichier spec** : `.omp/widgets-homescreen/widgets-homescreen.specs.md`
**Card AC** : `.opencode/scratch/widgets-homescreen.acceptance.md`
**UI brief** : `.omp/widgets-homescreen/widgets-homescreen.ui.md`
**AC Cards** : AC-3600 – AC-3608
**Phase** : P5 — Auth & Platform

#### Objectif
3 widgets Home Screen (Grid, Memories, Favorites) + WidgetKit TimelineProvider + access Keychain token dans processus widget. Live Activity backup déjà existante.

#### Points d'entrée
- `ImmichGridWidget` — SystemSmall (2x2) + SystemMedium (4x2), LazyVGrid photos
- `ImmichMemoriesWidget` — SystemSmall + SystemMedium, OnThisDay card + asset grid + widgetURL
- `ImmichFavoritesWidget` — SystemSmall + SystemMedium, favorites grid + widgetURL
- `WidgetDataProvider` — fetchTimelineAssets, fetchMemories, fetchFavorites (Keychain + URLSession)

#### Endpoint API
- `GET /api/timeline/bucket` — existant (fetchTimelineAssets)
- `GET /api/memories` — existant (fetchMemories)
- `GET /api/assets?isFavorite=true` — existant (fetchFavorites)

#### Étapes d'implémentation
1. Créer `ImmichGridWidget` dans `ImmichWidgets/` — TimelineProvider + LazyVGrid
2. Créer `ImmichMemoriesWidget` dans `ImmichWidgets/` — OnThisDay + widgetURL
3. Créer `ImmichFavoritesWidget` dans `ImmichWidgets/` — favorites + widgetURL
4. Créer `WidgetDataProvider` — Keychain token + URLSession fetch
5. Register widgets dans `ImmichSwiftUIApp` (ajout au bundle existant)
6. Ajouter `.widgetURL` handler pour deep links (app.immich://asset/{id})
7. Tests ≥3

#### Tests attendus
- `Tests/WidgetDataProviderTests.swift` ≥3 tests : fetch timeline, fetch memories, fetch favorites
- Regression : suite ≥ baseline

---

### 2.9. Stacks UI (P3)

**Fichier spec** : `.omp/stacks-ui/stacks-ui.specs.md`
**Card AC** : `.opencode/scratch/stacks-ui.acceptance.md`
**UI brief** : `.omp/stacks-ui/stacks-ui.ui.md`
**AC Cards** : AC-3700 – AC-3708
**Phase** : P3 — Social

#### Objectif
Gestion complète des stacks photos : vue dédiée dans Me hub, StackSheet amélioré dans le viewer, groupement par stack dans le timeline. Endpoints 100% wire.

#### Points d'entrée
- `StacksViewModel` (Features/Stacks/) — loadStacks, createStack, deleteStack, updatePrimary, removeAssetFromStack
- `StackView` (Features/Stacks/) — Liste stacks + FAB "+" + nav vers StackDetailView
- `StackDetailView` (Features/Stacks/) — Primary asset (large) + autres assets + setPrimary + removeFromStack
- `CreateStackSheet` (Features/Stacks/) — Choose photos + optional name + CTA Create
- `StackSheet` (PhotoViewer) — Tous les assets du stack, "Set as primary", "Remove from stack"
- `TimelineView` — withStacked: true → composite thumbnail + "+N" badge

#### Endpoint API
- 7 endpoints déjà wire : searchStacks, createStack, getStack, updateStack, deleteStack, addAssetToStack, removeAssetFromStack

#### Étapes d'implémentation
1. Créer `StacksViewModel` dans `Sources/Features/Stacks/`
2. Créer `StackView` — liste + FAB + navigation
3. Créer `StackDetailView` — primary + other assets
4. Créer `CreateStackSheet` — photo picker + name
5. Étendre `StackSheet` (PhotoViewer) — setPrimary + removeAssetFromStack par asset
6. Intégrer `withStacked: true` dans `TimelineView` — groupement visuel
7. Ajouter link "Stacks" dans `ProfileView`
8. Tests ≥5

#### Tests attendus
- `Tests/StacksViewModelTests.swift` ≥5 tests : loadStacks, create, delete, updatePrimary, removeAsset
- Regression : suite ≥ baseline

---

### 2.10. i18n Completing (P5)

**Fichier spec** : `.omp/i18n/i18n.specs.md`
**Card AC** : `.opencode/scratch/i18n.acceptance.md`
**UI brief** : `.omp/i18n/i18n.ui.md`
**AC Cards** : AC-3800 – AC-3807
**Phase** : P5 — Auth & Platform

#### Objectif
Internationalisation complète : externaliser TOUS les textes hardcodés dans `Localizable.xcstrings` (≥200 clés), ajouter sélecteur de langue, formatter de dates réutilisés.

#### Points d'entrée
- `Localizable.xcstrings` — Compléter avec ≥200 clés (FR + EN minimum)
- Migration strings → `String(localized:)` / `Text("key", bundle: .module)` dans TOUS les Views
- `LanguageSettingsView` (Features/Settings/) — Liste langues + toggle "Use System Language"
- `LanguageSettingsViewModel` (Features/Settings/) — selectedLocale, useSystemLanguage, applyLanguage
- `AppDateFormat` (DesignSystem/) — DateFormatters singleton réutilisés

#### Étapes d'implémentation
1. Audit des strings hardcodés dans tous les Views
2. Compléter `Localizable.xcstrings` avec ≥200 clés (FR + EN)
3. Migrer TOUS les string literals → `String(localized:)` dans :
   - Auth: LoginScreen, WelcomeScreen, ServerURLScreen
   - Timeline: TimelineView
   - Viewer: PhotoViewer, PhotoInfoPanel, PhotoEditor
   - Albums: AlbumsView, AlbumDetailView
   - Search: SearchView, MapView
   - Memories: MemoriesView
   - People: PeopleView
   - Tags: TagsView
   - Admin: AdminView
   - Upload: BackupSettingsView, UploadViewModel
   - SharedLinks: SharedLinksView
   - Trash: TrashView
   - Profile: ProfileView
   - Settings: PushNotificationSettingsView, etc.
4. Créer `LanguageSettingsView` + `LanguageSettingsViewModel`
5. Créer `AppDateFormat` singleton dans DesignSystem
6. Tests ≥3 (vérifier traductions complètes pour 3 écrans)

#### Tests attendus
- `Tests/LocalizationTests.swift` ≥3 tests : traductions complètes pour 3 écrans
- Regression : suite ≥ baseline

---

## Référence API — endpoints ImmichClient

### Endpoints déjà wire (existants)

| Méthode | Endpoint | ImmichClient | Usage |
|---------|----------|-------------|-------|
| GET | /api/timeline/bucket | getTimeBuckets() | Timeline, widgets |
| POST | /api/assets | uploadAsset() | Upload, offline |
| POST | /api/assets/bulk-upload-check | bulkUploadCheck() | Backup dedup |
| POST | /api/assets/:id | updateAsset() | Modify |
| DELETE | /api/assets/:id | deleteAsset() | Trash |
| POST | /api/auth/login | login() | Auth |
| POST | /api/auth/logout | logout() | Auth |
| GET | /api/auth/oauth2/mobile | getOAuthMobileURL() | OAuth2 |
| POST | /api/auth/oauth2/exchange | exchangeOAuthCode() | OAuth2 |
| GET | /api/albums | getAlbums() | Albums |
| POST | /api/albums | createAlbum() | Albums |
| PATCH | /api/albums/:id | updateAlbum() | Albums |
| DELETE | /api/albums/:id | deleteAlbum() | Albums |
| GET | /api/users | getUsers() | Partners, shares |
| GET | /api/partners | getPartners() | Partners |
| PATCH | /api/partners/:id | updatePartner() | Partners |
| DELETE | /api/partners/:id | removePartner() | Partners |
| GET | /api/memories | getMemories() | Memories read |
| POST | /api/memories/:id/assets | addAssetsToMemory() | **NEW** |
| PATCH | /api/memories/:id | updateMemory() | **NEW** |
| DELETE | /api/memories/:id | deleteMemory() | **NEW** |
| POST | /api/memories | createMemory() | **NEW** |
| GET | /api/memories/:id | getMemory() | **NEW** |
| GET | /api/memories/statistics | getMemoriesStatistics() | **NEW** |
| DELETE | /api/memories/:id/assets | removeAssetsFromMemory() | **NEW** |
| POST | /api/shared-links | createSharedLink() | Shared links |
| DELETE | /api/shared-links/:id | deleteSharedLink() | Shared links |
| GET | /api/stacks | searchStacks() | Stacks |
| POST | /api/stacks | createStack() | Stacks |
| GET | /api/stacks/:id | getStack() | Stacks |
| PATCH | /api/stacks/:id | updateStack() | Stacks |
| DELETE | /api/stacks/:id | deleteStack() | Stacks |
| DELETE | /api/stacks/:id/assets/:assetId | removeAssetFromStack() | Stacks |
| POST | /api/assets/:stackId/assets | addAssetToStack() | Stacks |
| GET | /api/assets/:id/original | downloadAsset() | Offline |

### Endpoints manquants vs Flutter

| # | Endpoint | Feature | Priority |
|---|----------|---------|----------|
| 1 | `POST /api/partners` | Partners UI (create) | P3 |
| 2 | `GET /api/partners?direction=` | Partners UI (directional) | P3 |
| 3 | `GET /api/shared-links/public/:slug` | Shared Links Enriched | P3 |
| 4 | `POST /api/shared-links/:slug/assets` | Shared Links Enriched | P3 |
| 5 | `POST /api/shared-links/:slug/check-password` | Shared Links Enriched | P3 |
| 6 | `POST /api/users/me/device-token` | Push Notifications | P5 |

---

## Checklists de vérification

### Checklist commune à TOUTES les features

- [ ] `xcodebuild build` réussit sans warning nouveau
- [ ] `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 17'` — suite ≥ 214 tests
- [ ] Mock dans `MockImmichClient` mis à jour
- [ ] `DependencyContainer` injecte le nouveau ViewModel
- [ ] `ProfileView` navigation mise à jour si feature ajoutée
- [ ] Test files nommés `*Tests.swift` avec `func test_` prefix
- [ ] No new warnings in `xcodebuild build` output

### Checklist par feature

**Backup Auto** : `grep -q "excludeCameraRoll" Sources/Features/Upload/UploadViewModel.swift` ✓
**OAuth2 UI** : `grep -q "ASWebAuthenticationSession" Sources/Features/Auth/AuthViewModel.swift` ✓
**Partners UI** : Créer `PartnerShellViewModel.swift` + `PartnerShellView.swift` + `InvitePartnerSheet.swift`
**Memories Complete** : 7 nouvelles méthodes ImmichClient + `CreateMemorySheet.swift`
**Push Notifications** : 4 nouveaux fichiers (Service, Store, ViewModel, View) + 3 intégrations
**Shared Links Enriched** : 3 nouvelles méthodes + `ExternalLinkPreviewView.swift` + `UploadFromLinkView.swift`
**Offline Download** : `OfflineAssetStore.swift` + `OfflineDownloadViewModel.swift` + `OfflineAssetsView.swift`
**Widgets** : 3 Widget + `WidgetDataProvider.swift` + ImmichWidgetsBundle
**Stacks UI** : `StacksViewModel.swift` + `StackView.swift` + `StackDetailView.swift` + `CreateStackSheet.swift`
**i18n** : Localizable.xcstrings ≥200 clés + tous les Views migrés + `LanguageSettingsView.swift` + `AppDateFormat.swift`

---

*Généré automatiquement depuis les specs .omp/ et les acceptance cards .opencode/scratch/ — 2026-09-08*
