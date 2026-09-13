# ImmichSwiftUI — Backlog d'Implémentation

> **Objectif** : Porter l'intégralité des fonctionnalités du client Flutter Immich upstream vers ImmichSwiftUI (iOS 26, SwiftUI, MVVM).
>
> **Architecture cible** : MVVM strict 4 couches — Core/Protocols, Core/Types, Services, Features, DesignSystem.
>
> **Validation** : `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 17'` — baseline **719 tests** (mesurée le 2026-09-13, TEST SUCCEEDED).

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
| 1 | **Backup Auto** | P2 | AC-BK01–BK10 | .omp/backup-auto/ | Voir §2.1 | ✅ Terminé | — | suite 692 verte | 7/10 AC (BK05, BK06, BK08 obsolètes) |
| 2 | **OAuth2 UI** | P5 | AC-3000–3007 | .omp/oauth2-ui/ | Voir §2.2 | ✅ Terminé | — (wire) | 6 `test_oauth_*` | 8/8 AC |
| 3 | **Partners UI** | P3 | AC-3100–3109 | .omp/partners-ui/ | Voir §2.3 | 🟡 Plan | createPartner, getPartners(dir) | 0/6 | 0/10 AC |
| 4 | **Memories Complete** | P4 | AC-3200–3208 | .omp/memories-complete/ | Voir §2.4 | 🟡 Plan | 7 (CRUD + stats) | 0/8 | 0/9 AC |
| 5 | **Push Notifications** | P5 | AC-3300–3308 | .omp/push-notifications/ | Voir §2.5 | 🟡 Plan | device-token reg/unreg | 0/9 | 0/9 AC |
| 6 | **Shared Links Enriched** | P3 | AC-3400–3409 | .omp/shared-links-enriched/ | Voir §2.6 | 🟡 Plan | getPublic, uploadTo, checkPW | 0/7 | 0/10 AC |
| 7 | **Offline Download** | P4 | AC-3500–3508 | .omp/offline-download/ | Voir §2.7 | 🟡 Plan | — (FileManager) | 0/8 | 0/9 AC |
| 8 | **Widgets Home Screen** | P5 | AC-3600–3608 | .omp/widgets-homescreen/ | Voir §2.8 | 🟡 Plan | — (WidgetKit) | 0/4 | 0/9 AC |
| 9 | **Stacks UI** | P3 | AC-3700–3709 | .omp/stacks-ui/ | Voir §2.9 | ✅ Terminé | — (100% wire) | 13 + 7 + 3 + 1 | 10/10 AC |
| 10 | **i18n Completing** | P5 | AC-3800–3807 | .omp/i18n/ | Voir §2.10 | 🟡 Plan | — (localisation) | 0/3 | 0/8 AC |
| 11 | **Backup — Live Photos** | P2 | AC-LP01–LP07 | .omp/backup-auto/backup-live-photos.specs.md | Voir §2.11 | ✅ Terminé | — (updateAsset wire) | 11 | 7/7 AC |
| 12 | **Backup — Album Scoping** | P2 | AC-AS01–AS08 | .omp/backup-auto/backup-album-scoping.specs.md | Voir §2.12 | ✅ Terminé | — | 5 + 3 | 8/8 AC |
| 13 | **Backup — Ledger Reconciliation** | P2 | AC-LR01–LR08 | .omp/backup-auto/backup-ledger-reconciliation.specs.md | Voir §2.13 | ✅ Terminé | — (bulk-upload-check wire) | 13 | 8/8 AC |
| 14 | **Backup — Network Policy** | P2 | AC-NP01–NP07 | .omp/backup-auto/backup-network-policy.specs.md | Voir §2.14 | ✅ Terminé | — | 7 | 7/7 AC |
| 15 | **Backup — Library Observer** | P2 | AC-LO01–LO08 | .omp/backup-auto/backup-library-observer.specs.md | Voir §2.15 | ✅ Terminé | — (PhotosKit) | 6 | 7/8 AC (LO08 manuel) |

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

### 2.1. Backup Auto (P2) — ✅ Terminé (2026-09-09, clôturé le 2026-09-10)

**Fichier spec** : `.omp/backup-auto/backup-auto.specs.md` (section « État au 2026-09-09 »)
**Card AC** : `.opencode/scratch/backup-auto.acceptance.md`
**UI brief** : `.omp/backup-auto/backup-auto.ui.md`
**AC Cards** : AC-BK01 – AC-BK10
**Phase** : P2 — Backup

#### Résultat
AC-BK01, BK02, BK03, BK04, BK07, BK10 **PASS**. Suite complète **691 tests, TEST SUCCEEDED** (iPhone 17, 2026-09-10). Les 5 suites P2 (§2.11 – §2.15) et les cards `backup-engine` / `backup-live-activity` sont vertes sur leurs checks grep — révision du 2026-09-10 de 8 checks périmés (signatures de protocole et surfaces évoluées entre-temps, un check `grep -qA3 | grep` structurellement inopérant, trois summaries /tmp orphelins).

**AC-BK05 et AC-BK06 sont OBSOLÈTES** : `UploadProgressBanner` a été supprimé volontairement et remplacé par l'anneau de progression autour de l'avatar (`TimelineView.avatarBackupRing`). Les critères pinnent une surface UI abandonnée — ne pas les « réparer ».

**AC-BK08 est OBSOLÈTE depuis le 2026-09-10** : la sheet Backfill (glass morphing) a été retirée — doublon du scoping d'albums + « Run now ». AC-BK03/BK04/BK07 ont été révisés en conséquence, et AC-BK10 couvre le remplacement (mode d'albums tri-état).

**Le toggle « Require Face ID » a quitté l'écran Backup le 2026-09-10** pour ProfileView (« Me » → Security) : l'app lock garde l'application entière, pas la sauvegarde (AC-114 suit la surface).

#### Livré
- `BackupSettingsStore` : `isEnabled`, `onlyOnWiFi`, `onlyWhenCharging`, `allowCellularForPhotos`, `allowCellularForVideos`, `autoDetectNewPhotos`, mode d'albums tri-état + les deux ensembles d'albums, persistés clés `photoBackup*` (`UploadViewModel.swift:24-160`) — ⚠ `excludeCameraRoll`/`excludeWhatsApp` ont été SUPPRIMÉS par §2.12 (heuristiques nom-de-fichier fausses sur iOS)
- `UploadViewModel` : `resumeUpload()`, `uploadHistory`, `kickOffAutoBackupIfConfigured()` — ⚠ le backfill (`runBackfill`/`BackfillSheet`) a été **retiré le 2026-09-10** : doublon du scoping d'albums + « Run now », et le libellé « Reorganize » mentait (aucune réorganisation côté serveur)
- `BackupSettingsView` (Auto backup + Albums + Progress + Backup tracking/Server check/Reset), `AlbumPickerView`, `BackupFailuresSheet`, `BackupThumbnailView`
- Pipeline durci : export→SHA1 streamé→upload séquentiel (mémoire bornée par `maxBatchBytes`), `ContinuationGate`, `BackupLedger` anti-re-download, bucket `deferredCount` pour l'iCloud pas encore local
- Chaîne BGTask auto-resoumise en tête de handler (`ImmichSwiftUIApp.swift:44-63`), assertion background UIKit, Live Activity + Dynamic Island, anneau in-app
- Tests : `BackupEngineTests` (55 tests), `UploadViewModelTests` + `UploadViewModelLiveActivityTests`, `BackupLedgerReconciliationTests`, `PhotoLibraryChangeMonitorTests`

#### Suites (écarts réels restants vs Flutter)
Cinq items séparés, tous en P2 et **livrés** : §2.11 Live Photos, §2.12 Album Scoping, §2.13 Ledger Reconciliation, §2.14 Network Policy, §2.15 Library Observer.

#### Résidu connu (hors périmètre backup)
15 chaînes d'UI neuves de l'écran Backup (dont « Run now », « Retry failed », « Use cellular for photos/videos », « Last server check », « Tracked photos », « Albums to back up/skip ») **n'ont pas d'entrée dans `Resources/Localizable.xcstrings`** — elles s'affichent en anglais, comme les 126 autres littéraux de `Sources/` déjà sans clé. Couvert par la card §2.10 i18n (Status: plan), pas par cette feature.

---

### 2.2. OAuth2 UI (P5) — ✅ Terminé (2026-09-08, réconcilié le 2026-09-10)

**Fichier spec** : `.omp/oauth2-ui/oauth2-ui.specs.md`
**Card AC** : `.opencode/scratch/oauth2-ui.acceptance.md`
**UI brief** : `.omp/oauth2-ui/oauth2-ui.ui.md`
**AC Cards** : AC-3000 – AC-3007
**Phase** : P5 — Auth & Platform

#### Résultat
AC-3000 – AC-3007 **PASS** (8/8, vérifiés par exécution de chaque check le 2026-09-10). Suite complète **692 tests, TEST SUCCEEDED** (iPhone 17, baseline 691).

#### Livré
- `AuthViewModel` (`Sources/Features/Auth/AuthViewModel.swift`) : `oauthRedirectURI = "app.immich:///oauth-callback"` (l.32), `oauthSessionHandler: (URL) async -> URL?` injectable (l.35-37), `canOAuthLogin` gate sur `serverConfig.oauthButtonText` (l.239), `startOAuthFlow()` — authorize (PKCE) → session navigateur → `exchangeOAuthCode` → `applySession` partagé avec le login mot de passe (l.248-289)
- `OAuthPKCE` (`Sources/Core/Utilities/OAuthPKCE.swift`) : `state`, `codeVerifier`, `codeChallenge` = base64url(SHA256(verifier)) sans padding
- `OAuthSessionPresenter` (`Sources/Services/OAuthSessionPresenter.swift`) : `ASWebAuthenticationSession` + ancre première `UIWindowScene` key-window, `callbackScheme = "app.immich"` (doit matcher `CFBundleURLTypes`, `Resources/Info.plist:25-33`)
- `LoginScreen` (`Sources/Features/Auth/Onboarding/LoginScreen.swift`) : bouton SSO conditionnel libellé par le serveur (fallback « Sign in with SSO »), séparateur `orDivider` « OU », spinner in-flight (l.53-74, 110-119)
- Tests : 6 `test_oauth_*` dans `Tests/AuthViewModelTests.swift` (gate serveur, succès complet, annulation, URL malformée, erreur serveur, serveur sans OAuth)

#### Réconciliation (2026-09-10)
Les critères d'origine pinnaient une surface **jamais construite** et écartée par la conception : `oauthResult`/`oauthAuthorizationURL`/`handleOAuthCallback(url:)`, `OAuthLoadingView.swift` (sheet glass), `.onOpenURL` dans `ImmichSwiftUIApp`, littéral « Sign in with Provider ». Le callback est capturé par `ASWebAuthenticationSession` (`callbackURLScheme`) — un handler de deep link serait du code mort. Carte, spec et UI brief réécrits sur la surface réelle ; même classe de dérive que les 8 checks réécrits le même jour pour `backup-engine`/`backup-live-activity`.

#### Correctif trouvé pendant la réconciliation
`startOAuthFlow()` sortait par `return` sur annulation et sur URL provider malformée **avant** `isLoading = false` → le CTA de login restait désactivé et le bouton SSO grisé définitivement. Corrigé par `defer { isLoading = false }` (l.256) + `test_oauth_cancelLeavesStateUntouched` et `test_oauth_malformedProviderURLResetsLoading` (échec prouvé avant correctif, PASS après).

#### Limite assumée
Flow non vérifiable bout-en-bout sans serveur Immich avec provider OIDC : la session navigateur est injectée, la vérification reste manuelle.

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

### 2.9. Stacks UI (P3) — ✅ Terminé (2026-09-13)

**Fichier spec** : `.omp/stacks-ui/stacks-ui.specs.md`
**Card AC** : `.opencode/scratch/stacks-ui.acceptance.md`
**UI brief** : `.omp/stacks-ui/stacks-ui.ui.md`
**AC Cards** : AC-3700 – AC-3709
**Phase** : P3 — Social

#### Résultat (2026-09-13)
AC-3700 – AC-3709 **PASS** (10/10, checks rejoués depuis la carte). Suite complète **719 tests, TEST SUCCEEDED** (iPhone 17, baseline mesurée 695 avant implémentation). Vérification d'exécution réelle : XCUITest `ImmichRenderScreenshots/test_03_stacksBadgeDetailAndHub` — badge de pile sur la tuile du timeline → tap → détail de la pile → retour → hub «Me» → «Stacks» liste la pile (captures `/tmp/shot-11-timeline-stack-badge.png`, `/tmp/shot-12-stack-detail.png`, `/tmp/shot-15-stacks-hub.png`).

#### Livré
- **NEW** `Sources/Features/Stacks/StacksViewModel.swift` — liste + CRUD (`loadStacks`, `loadStack`, `createStack`, `deleteStack`, `updatePrimary`, `removeAssetFromStack`) + flux de création (picker paginé via `searchMetadata`, sélection, `canLoadMoreAssets`)
- **NEW** `Sources/Features/Stacks/StackView.swift` — liste (couverture + compte + «Cover: fichier»), création, swipe «Unstack», navigation vers le détail. Pas de `NavigationStack` propre (poussée depuis la sheet «Me», TagsView pattern)
- **NEW** `Sources/Features/Stacks/StackDetailView.swift` — couverture en grand, autres membres, «Make cover», «Remove from stack», «Unstack» (confirmation), tap → viewer **sur les membres** (pas le timeline plat)
- **NEW** `Sources/Features/Stacks/CreateStackSheet.swift` — grille multi-sélection (≥2), compteur + règle explicite, **pas de champ «nom»** (le serveur n'en accepte pas)
- `AssetReactItem` — `stack` documenté (tuple wire `[stackId, count]`, count sérialisé en **chaîne**) + `stackId`, `stackCount`, `stackedExtraCount` ; `isStacked` teste l'id, plus la vacuité
- `TimelineViewModel` — `withStacked = true` sur les 6 appels ; `stackSelected()` ordonne les ids selon la grille (le `Set` n'a pas d'ordre et le serveur fait du 1er id la couverture) ; la corbeille reste en `nil`
- `AssetThumbnailCell` — badge de pile avec icône + `+N` (`stackedExtraCount`), un seul élément d'accessibilité («3 photos in a stack», `identifier: stackBadge`)
- `TimelineView` — `navigationDestination(item:)` : une tuile empilée ouvre le détail de la pile au lieu du pager plat
- `ProfileView` — lien «Stacks» dans la section Management ; `DependencyContainer.makeStacksViewModel()` ; VM unique partagé entre le timeline et le hub (`RootView`)
- `StackSheet` (PhotoViewer) **inchangée** : elle faisait déjà couverture/membre/dissolution (c'était l'AC-3704 d'origine, déjà PASS avant implémentation)
- Tests (+24) : `StacksViewModelTests` (13), transport des 7 routes/paramètres stacks (`ImmichAPIClientTests`), timeline stacking (3 dans `TimelineViewModelTests`), décodage du tuple wire (`DTOEncodingTests`)

#### Écarts vs la carte d'origine (tous corrigés dans la carte)
1. AC-3704 était **déjà PASS en pré-état** (la `StackSheet` existante) → réécrit sur le routage du tap timeline.
2. AC-3705 grepait `withStacked` dans `TimelineView.swift` (où il n'existe pas) → repointé sur le VM + le badge.
3. AC-3703 exigeait un champ nom de pile que l'API n'a pas → retiré.
4. AC-3708 bornait la suite à `-ge 200` pour une baseline de 695 → recalé.

#### Pièges à retenir
- `withStacked` **retire** les non-primaires du bucket (filtre `NOT EXISTS stack.primaryAssetId != asset.id` côté serveur) : toute vue qui l'active doit router le tap vers la pile, sinon ces photos sont inatteignables.
- Le compteur du tuple est une **chaîne** et inclut la couverture → `stack.count` vaut toujours 2, le badge lit `Int(stack[1]) - 1`.
- Un `.accessibilityLabel` posé sur un conteneur **fusionne** ses enfants : le texte du badge disparaît de l'arbre XCUITest (utiliser `children: .ignore` + `identifier`).
- La 1re rangée du timeline vit sous le header de date flottant ; le hub «Me» est une `Form` paresseuse (rows sous le pli absents de l'arbre) → le harnais UI doit scroller avant d'assertir.

#### Endpoint API
- 7 endpoints déjà wire, aucun ajout : `searchStacks`, `createStack`, `getStack`, `updateStack`, `deleteStack`, `removeAssetFromStack` (+ `addAssetToStack`, toujours sans appelant — l'ajout d'un asset à une pile existante n'est pas exposé par l'UI)

#### Suivi (non bloquant)
- `addAssetToStack` (`POST /api/assets/:stackId/assets`) reste **sans appelant** : l'UI sait créer une pile et en retirer des membres, pas en ajouter à une pile existante. À ouvrir comme item dédié si le besoin apparaît.
- `TrashViewModel` continue de demander la liste plate (`withStacked: nil`) — volontaire : la corbeille doit montrer chaque asset.
- Le harnais UI dépend d'un stub local `/tmp/immich_stub_stacks.py` (comme le reste du fichier) : il se skippe sans lui.

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

### 2.11. Backup — Live Photos (P2)

#### Résultat (2026-09-10)
AC-LP01 – AC-LP07 **PASS**. `LivePhotoBackupTests` (11 tests) : ordre vidéo→photo, id renvoyé porté par la photo, rattachement rétroactif via `Result.assetId` + `updateAsset`, skip si `isTrashed`, defer du pair = defer de l'asset, échec dur du pair = échec sans upload, nettoyage des temps (fin de run + annulation), non-régression image simple.

**Fichier spec** : `.omp/backup-auto/backup-live-photos.specs.md`
**Card AC** : `.opencode/scratch/backup-live-photos.acceptance.md`
**AC Cards** : AC-LP01 – AC-LP07
**Phase** : P2 — Backup

#### Objectif
Sauvegarder les Live Photos **comme des Live Photos**. `BackupEngine.processBatch` upload aujourd'hui avec `livePhotoVideoId: nil` en dur (`BackupEngine.swift:410`) et n'exporte jamais la ressource `.pairedVideo` : le serveur reçoit une image morte et le `.MOV` n'existe nulle part ailleurs que sur l'appareil.

#### Points d'entrée
- `BackupCandidate` — ajouter `isLivePhoto` (défaut `false`, dernière position, init memberwise préservé)
- `BackupAssetSource` — `exportPairedVideo(for:onState:) -> URL?`
- `PhotoLibraryServiceImpl` — `mediaSubtypes.contains(.photoLive)`, ressource `.pairedVideo`, extraction de `writeResource` (la boucle de retry iCloud 1005 + `StallWatchdog` NE DOIT PAS être dupliquée)
- `BackupEngine` — staging à 4 champs, upload vidéo `visibility: .hidden` avant la photo, helper unique `removeStaged` pour le nettoyage des temps

#### Endpoint API
- `POST /api/assets` — existant (`visibility`, `livePhotoVideoId` déjà supportés)
- `PATCH /api/assets/:id` — existant (`updateAsset` + `UpdateAssetDto.livePhotoVideoId`)

#### Étapes d'implémentation
1. `BackupCandidate.isLivePhoto` + `exportPairedVideo` au protocole
2. `PhotoLibraryServiceImpl` : `writeResource` partagé, sélection `.pairedVideo` / `.fullSizePairedVideo`
3. `BackupEngine` : export + hash du pair au staging, `batchBytes` cumule les deux tailles
4. Chemin `accept` : vidéo `.hidden` → `response.id` → photo avec `livePhotoVideoId`
5. Chemin `reject` : `Result.assetId` (présent sur les rejects) → vidéo + `updateAsset(livePhotoVideoId:)` — **seul moyen de réparer les Live Photos déjà montées en images mortes**
6. Mocks (ordre des uploads, `visibility`, `updateAsset`) + tests

#### Tests attendus
- `Tests/BackupEngineTests.swift` → `LivePhotoBackupTests` ≥7 tests : ordre d'upload, id renvoyé, rattachement rétroactif, defer du pair, unité de progression unique, nettoyage temp à l'annulation, non-régression image simple
- Regression : suite ≥ 645

---

### 2.12. Backup — Album Scoping (P2)

#### Résultat (2026-09-10)
AC-AS01 – AC-AS08 **PASS**. `BackupEngineExclusionTests` (5 tests) + migration/persistance dans `BackupSettingsStoreTests` (3) : la source résout l'exclusion par soustraction d'identifiants (un `PHAsset.fetchAssets` par album exclu au lieu d'un `fetchAssetCollectionsContaining` par asset), smart albums exposés avec des ids stables (`BackupAlbum.SmartID`), anciennes clés supprimées après migration one-shot de `excludeScreenshots`.

**Fichier spec** : `.omp/backup-auto/backup-album-scoping.specs.md`
**Card AC** : `.opencode/scratch/backup-album-scoping.acceptance.md`
**AC Cards** : AC-AS01 – AC-AS08
**Phase** : P2 — Backup

#### Objectif
Remplacer les exclusions heuristiques par nom de fichier par une vraie sélection/exclusion d'albums. `excludeCameraRoll` = `!hasPrefix("IMG_")` exclut presque toute une pellicule iPhone ; `excludeWhatsApp` = `!contains("WhatsApp")` ne filtre rien sur iOS. `excludeScreenshots` compare `albumName`, qui n'est **qu'un** album par asset.

#### Points d'entrée
- `BackupSettings` / `BackupSettingsStore` — `excludedAlbumIDs` (clé `photoBackupExcludedAlbums`), suppression des 3 anciens booléens + migration one-shot de `excludeScreenshots`
- `BackupAssetSource` — `fetchCandidates(in:excluding:)`, `BackupAlbum.isSmart`, suppression de `BackupCandidate.albumName`
- `PhotoLibraryServiceImpl` — smart albums (`smartAlbumScreenshots`…) dans `fetchAlbums`, exclusion par `Set<String>` de `localIdentifier`, suppression de `assetAlbumName`
- `BackupSettingsView` / `AlbumPickerView` — « Albums to back up » + « Albums to skip », picker paramétré par `Binding<Set<String>>`

#### Endpoint API
- Aucun (PhotosKit uniquement)

#### Étapes d'implémentation
1. Protocole : `excluding:`, `isSmart`, retrait de `albumName`
2. Source : ensemble d'exclusion calculé en amont — supprime au passage le `fetchAssetCollectionsContaining` **par asset** du scan complet
3. Engine : suppression des 3 `filter` (l.209-217) et de `screenshotsAlbumName`
4. Store : nouvelle clé + migration + `removeObject` des clés mortes
5. UI : deux périmètres d'albums, plus aucun toggle d'exclusion heuristique
6. Tests

#### Tests attendus
- `Tests/UploadViewModelTests.swift` → `BackupEngineExclusionTests` réécrite, ≥5 tests : transmission du scoping, `IMG_0001.HEIC` sauvegardé, migration `excludeScreenshots`, persistance, clés legacy supprimées
- Regression : TEST SUCCEEDED (le compte peut baisser — les tests qui pinnaient les filtres nom-de-fichier meurent avec le code)

---

### 2.13. Backup — Ledger Reconciliation (P2)

#### Résultat (2026-09-10)
AC-LR01 – AC-LR08 **PASS**. `BackupLedgerReconciliationTests` (13 tests) : fichier v2 versionné + v1 toujours lisible, checksum mémorisé aux deux `markBackedUp`, passe hebdo par chunks de `checkChunkSize` (100), `isTrashed` conservé, erreur réseau silencieuse, asset oublié re-uploadé dans le même run, `deviceAssetId`/`deviceId` envoyés, `DeviceIdentity` (UUID persisté, pas `identifierForVendor`).

**Fichier spec** : `.omp/backup-auto/backup-ledger-reconciliation.specs.md`
**Card AC** : `.opencode/scratch/backup-ledger-reconciliation.acceptance.md`
**AC Cards** : AC-LR01 – AC-LR08
**Phase** : P2 — Backup

#### Objectif
Rendre `BackupLedger` auto-réparant. Il n'est jamais confronté au serveur : un asset supprimé côté serveur reste marqué « backed up », est filtré avant export (`BackupEngine.swift:224`) et ne remonte **jamais**. Le client Flutter n'a pas ce trou (dédup = `remote_asset_entity` réalimentée par `/api/sync/stream`).

#### Points d'entrée
- `BackupLedgerStoring` / `BackupLedger` — `markBackedUp(id:signature:checksum:)`, `entriesForReconciliation()`, `forget(ids:)`, `lastReconciliation`, fichier JSON **versionné** (v1 `[String: String]` reste lisible)
- `BackupEngine` — `reconcileLedgerIfDue()` avant `fetchCandidates`, chunks de `checkChunkSize`, `reconcileInterval = 7 jours`
- `ImmichAPIClient.uploadAsset` — ajouter `deviceAssetId` + `deviceId` aux champs multipart (l.480-491 : **aucun des deux n'est envoyé** aujourd'hui)
- **NEW** `Sources/Services/DeviceIdentity.swift` — UUID persisté (⚠ pas `identifierForVendor`)
- `BackupSettingsView` — « Last server check » + action non destructive « Check server now » à côté du reset

#### Endpoint API
- `POST /api/assets/bulk-upload-check` — existant : `action == "accept"` = le serveur ne l'a pas. Le checksum est **déjà calculé** par le run, donc la réconciliation ne coûte aucun octet de média.
- `GET /api/assets/device/:deviceId` — **écarté** (inutilisable sur l'historique : champs device jamais envoyés ; dépend de la version serveur)

#### Étapes d'implémentation
1. Protocole + `BackupLedger` v2 (`Entry { signature, checksum? }`, `lastReconciliation`) avec fallback v1
2. Passer le checksum aux deux `markBackedUp` (reject l.362-364, upload l.414)
3. `reconcileLedgerIfDue()` off-main ; une erreur réseau n'est **pas** un échec de run (ni `lastError` ni `failures`)
4. `deviceAssetId` / `deviceId` + `DeviceIdentity`
5. UI Backup tracking + tests, puis `xcodegen generate`

#### Tests attendus
- `Tests/BackupLedgerReconciliationTests.swift` ≥10 tests : migration v1, round-trip v2, oubli des entrées absentes du serveur, conservation des rejects, `isTrashed` conservé, throttle, erreur réseau silencieuse, chunking, ré-upload dans le même run, entrées sans checksum ignorées, `deviceAssetId`/`deviceId` envoyés
- Regression : suite ≥ 655

#### Pièges cadrés dans la spec
- `isTrashed == true` ⇒ le serveur l'a : **ne pas** oublier l'entrée
- Changement de compte : vider le ledger explicitement (sinon la réconciliation le vide à l'aveugle → re-backup complet d'une photothèque iCloud)

---

### 2.14. Backup — Network Policy (P2)

#### Résultat (2026-09-10)
AC-NP01 – AC-NP07 **PASS**. `NetworkPolicyTests` (7 tests) : gate `isOnline` global, décision par asset avant export (zéro download iCloud pour un asset reporté), `allowCellularForPhotos`/`ForVideos`, report typé (`BackupDeferralReason`) jamais compté en échec, run manuel hors politique, `test_backup_wifiGateBlocksRun` remplacé.

**Fichier spec** : `.omp/backup-auto/backup-network-policy.specs.md`
**Card AC** : `.opencode/scratch/backup-network-policy.acceptance.md`
**AC Cards** : AC-NP01 – AC-NP07
**Phase** : P2 — Backup

#### Objectif
Politique réseau par type de média (parité `useCellularForPhotos` / `useCellularForVideos`) et vraie notion de hors-ligne. Aujourd'hui le gate est tout-ou-rien (`BackupEngine.swift:186-189`) et un run hors ligne exporte, hashe, puis compte **tous** les assets en `failedCount` — exactement la classe de faux échecs que le bucket `deferred` a éliminée pour l'iCloud.

#### Points d'entrée
- `BackupEnvironment` — `isOnline` (le `NWPathMonitor` de `SystemBackupEnvironment` reçoit déjà le `path`)
- `BackupSettings` — `allowCellularForPhotos`, `allowCellularForVideos`
- `BackupEngine` — gate global `isOnline` + `isUploadAllowedNow(candidate:settings:)` testé **avant** `exportOriginal` ; résultat = `deferredCount`, pas `failedCount` ; `BackupDeferralReason`
- `BackupSettingsView` — 2 toggles indentés sous « Wi-Fi only » + légende « Waiting for Wi-Fi » vs « Waiting for iCloud »

#### Endpoint API
- Aucun (Network.framework)

#### Étapes d'implémentation
1. `isOnline` au protocole + cache `NWPathMonitor`
2. Gate global hors-ligne (branche `!manual` uniquement)
3. Décision par asset → defer avant tout export (aucun download iCloud pour un asset reporté)
4. `deferralReason` + libellés UI
5. Tests

#### Tests attendus
- `Tests/BackupEngineTests.swift` → `NetworkPolicyTests` ≥7 tests : hors-ligne = pipeline non entré, photo uploadée / vidéo reportée en cellulaire, asset reporté jamais exporté, pas de `lastError`, Wi-Fi ignore les toggles, run manuel ignore la politique, raison du report
- `test_backup_wifiGateBlocksRun` pinne l'ancien contrat tout-ou-rien : **remplacé**, pas re-pinné
- Regression : suite ≥ 645

---

### 2.15. Backup — Library Observer (P2)

#### Résultat (2026-09-10)
AC-LO01 – AC-LO07 **PASS**, AC-LO08 **manuel** (non simulable : `PHPhotoLibraryChangeObserver`). `PhotoLibraryChangeMonitorTests` (6 tests) : règle `shouldObserveLibraryChanges`, réveil unique malgré deux insertions, réveil ignoré pendant un run. `PhotoLibraryChangeMonitor` filtre sur `insertedObjects` (une édition ne déclenche pas de scan complet) et débounce 5 s.

**Fichier spec** : `.omp/backup-auto/backup-library-observer.specs.md`
**Card AC** : `.opencode/scratch/backup-library-observer.acceptance.md`
**AC Cards** : AC-LO01 – AC-LO08
**Phase** : P2 — Backup

#### Objectif
Faire que « Auto-detect new photos » détecte réellement les nouvelles photos. Aucun `PHPhotoLibraryChangeObserver` n'existe dans `Sources/` : le toggle n'autorise qu'un scan à l'activation de scène (`DependencyContainer.kickOffAutoBackup` ← `ImmichSwiftUIApp.swift:24`). Le libellé promet ce que le code ne fait pas.

#### Points d'entrée
- **NEW** `Sources/Core/Protocols/PhotoLibraryChangeMonitoring.swift` — `onAssetsInserted`, `start()`, `stop()`
- **NEW** `Sources/Services/PhotoLibraryChangeMonitor.swift` — baseline `PHFetchResult`, réveil **uniquement** si `changeDetails.insertedObjects` non vide, débounce 5 s, hop `@MainActor`
- `DependencyContainer` — `libraryMonitor` injectable + `syncLibraryMonitor()`
- `ImmichSwiftUIApp` — `sync` sur `.active`, `stop()` sur `.background`
- `BackupSettingsView` — libellé « Back up new photos automatically » + footer qui assume les deux régimes (temps réel au premier plan, BGTask sinon)

#### Contrainte plateforme
iOS n'a pas d'équivalent des content-URI triggers Android utilisés par Flutter (étude §3.3). Les seuls déclencheurs sont : activation au premier plan, fenêtres `BGTaskScheduler`, et `PHPhotoLibraryChangeObserver` **pendant que l'app tourne**.

#### Étapes d'implémentation
1. Protocole + monitor (filtre insertions, débounce, idempotent, `deinit` → `stop`)
2. Câblage `DependencyContainer` + cycle de vie de scène
3. Libellé + footer honnêtes
4. `MockLibraryMonitor` + tests, puis `xcodegen generate` (2 fichiers NEW)

#### Tests attendus
- `Tests/PhotoLibraryChangeMonitorTests.swift` ≥6 tests (via mock) : start/stop selon les 2 toggles, callback → un seul run, ignoré pendant un run, débounce coalescant
- **AC-LO08 manuel** : app ouverte, ajout d'une photo, run déclenché en <10 s (anneau visible autour de l'avatar) — non simulable en unitaire
- Regression : suite ≥ 645

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
| POST | /api/oauth/authorize | authorizeOAuth() | OAuth2 |
| POST | /api/oauth/callback | exchangeOAuthCode() | OAuth2 |
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

**Champs manquants (pas des endpoints)** — `POST /api/assets` n'envoie ni `deviceAssetId` ni `deviceId` (`ImmichAPIClient.swift:480-491`). Corrigé par §2.13 ; prérequis de toute réconciliation par appareil.

---

## Checklists de vérification

### Checklist commune à TOUTES les features

- [ ] `xcodebuild build` réussit sans warning nouveau
- [ ] `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 17'` — suite ≥ 719 tests
- [ ] Mock dans `MockImmichClient` mis à jour
- [ ] `DependencyContainer` injecte le nouveau ViewModel
- [ ] `ProfileView` navigation mise à jour si feature ajoutée
- [ ] Test files nommés `*Tests.swift` avec `func test_` prefix
- [ ] No new warnings in `xcodebuild build` output

### Checklist par feature

**Backup Auto** : ✅ terminé (691 tests verts, 5 suites P2 livrées le 2026-09-10, cards `backup-engine`/`backup-live-activity` re-vérifiées le même jour). Suites : Live Photos §2.11, Album Scoping §2.12, Ledger Reconciliation §2.13, Network Policy §2.14, Library Observer §2.15 — chacune a sa card AC dans `.opencode/scratch/backup-*.acceptance.md` — ⚠ §2.12 **supprime** `excludeCameraRoll`/`excludeWhatsApp` : ne pas les greper comme critère de succès.
**OAuth2 UI** : ✅ terminé (692 tests verts, 8/8 AC PASS le 2026-09-10). Check : `grep -q "ASWebAuthenticationSession" Sources/Services/OAuthSessionPresenter.swift` ✓ — ⚠ la session vit dans le **service**, pas dans `AuthViewModel` (qui ne connaît que `oauthSessionHandler`) ; pas de `handleOAuthCallback`, pas d'`OAuthLoadingView`, pas d'`.onOpenURL` : ces surfaces ont été écartées par la conception, ne pas les « rétablir ».
**Partners UI** : Créer `PartnerShellViewModel.swift` + `PartnerShellView.swift` + `InvitePartnerSheet.swift`
**Memories Complete** : 7 nouvelles méthodes ImmichClient + `CreateMemorySheet.swift`
**Push Notifications** : 4 nouveaux fichiers (Service, Store, ViewModel, View) + 3 intégrations
**Shared Links Enriched** : 3 nouvelles méthodes + `ExternalLinkPreviewView.swift` + `UploadFromLinkView.swift`
**Offline Download** : `OfflineAssetStore.swift` + `OfflineDownloadViewModel.swift` + `OfflineAssetsView.swift`
**Widgets** : 3 Widget + `WidgetDataProvider.swift` + ImmichWidgetsBundle
**Stacks UI** : ✅ terminé (719 tests verts, 10/10 AC PASS le 2026-09-13). Fichiers : `StacksViewModel.swift` + `StackView.swift` + `StackDetailView.swift` + `CreateStackSheet.swift` (`Sources/Features/Stacks/`) ; `withStacked = true` dans `TimelineViewModel` + badge `+N` dans `AssetThumbnailCell` + routage du tap vers la pile dans `TimelineView` ; lien «Stacks» dans `ProfileView`. ⚠ `StackSheet` (PhotoViewer) est **inchangée** — elle faisait déjà couverture/membre/dissolution ; l'AC d'origine qui la visait était déjà PASS avant implémentation.
**i18n** : Localizable.xcstrings ≥200 clés + tous les Views migrés + `LanguageSettingsView.swift` + `AppDateFormat.swift`

---

*Généré depuis les specs .omp/ et les acceptance cards .opencode/scratch/ — 2026-09-08, mis à jour le 2026-09-13 (Stacks UI ✅ clôturé : 10/10 AC PASS, carte AC réécrite sur la surface réelle + harnais XCUITest de bout en bout — baseline 695 → 719 tests. Précédemment : Backup Auto ✅ clôturé le 2026-09-10 avec ses 5 suites P2 ; OAuth2 UI ✅ clôturé le 2026-09-10, 8/8 AC PASS après réécriture de la carte/spec/UI brief sur la surface réelle et correction de la fuite de `isLoading`).*
