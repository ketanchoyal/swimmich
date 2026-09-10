# Backup auto — étude du client Flutter upstream (immich-app/immich, branch `main`)

Étude faite le 2026-09-08 à partir du code source du dépôt GitHub. Alimente la spec `backup-auto.specs.md`.
Tous les chemins sont relatifs à `mobile/` dans le repo immich-app/immich.

## 1. Vue d'ensemble

Le backup auto est un pipeline en 5 étapes, déclenché par 3 mécanismes (resume foreground, iOS BGTaskScheduler, Android WorkManager) :

1. **Local sync** — réconcilie la photothèque device (albums + assets) dans la DB locale Drift, via pigeon `NativeSyncApi` (PHPhotoLibrary côté iOS, MediaStore côté Android). Delta sync avec checkpoint (`PHPersistentChangeToken` iOS / `getMediaChanges`), sinon full sync.
2. **Remote sync** — `/api/sync/stream` (version-aware) : récupère les assets serveur, deletions, exif, albums, users… dans `remote_asset_entity` (checksums inclus). C'est la **base de dedup**.
3. **Hash** — calcule les checksums SHA1 (base64) des assets locaux pas encore hashés, natif (CryptoKit iOS / MediaStore+hash Android), par batch de `kBatchHashFileLimit` = 32 (iOS) / 512 (Android) fichiers, uniquement pour les albums `backupSelection == selected`.
4. **Sélection des candidates** — requête SQL locale : assets des albums *selected* − assets des albums *excluded* − assets dont le checksum existe déjà dans `remote_asset_entity` pour cet utilisateur. **Pas d'appel API bulk-upload-check** ; le dedup serveur (POST /api/assets renvoie l'asset existant) sert de backstop.
5. **Upload** — soit HTTP multipart foreground (3 workers concurrents), soit tâches URLSession background (iOS, via paquet `background_downloader`), soit upload séquentiel en isolate (worker background Android).

Fichiers clés :
- `lib/infrastructure/repositories/backup.repository.dart` — candidates + compteurs (1 seule requête SQL pour total/remainder/processing).
- `lib/services/foreground_upload.service.dart` — upload HTTP + worker pool.
- `lib/services/background_upload.service.dart` — enqueue URLSession (iOS).
- `lib/domain/services/background_worker.service.dart` — moteur exécuté dans le **second Flutter engine** (background).
- `lib/domain/services/local_sync.service.dart`, `lib/domain/services/sync_stream.service.dart`, `lib/domain/services/hash.service.dart`.
- `lib/providers/backup/backup.provider.dart` — état UI (compteurs, uploadItems, erreurs).
- `lib/providers/app_life_cycle.provider.dart` — déclenchement au resume.
- Natif : `ios/Runner/Background/BackgroundWorkerApiImpl.swift`, `ios/Runner/Background/BackgroundWorker.swift`, `android/.../background/BackgroundWorkerApiImpl.kt`, `BackgroundWorker.kt`, `MediaObserver.kt`, `PeriodicWorker.kt`.
- Contrat pigeon : `pigeon/background_worker_api.dart`.

## 2. Configuration (`lib/domain/models/config/backup_config.dart`)

| Clé | Défaut | Usage |
|---|---|---|
| `enabled` | false | Gate global, vérifié dans le worker Dart (pas côté natif) |
| `useCellularForVideos` | false | Autorise cellulaire pour les vidéos |
| `useCellularForPhotos` | false | Autorise cellulaire pour les photos |
| `requireCharging` | false | Android : contrainte WorkManager (MediaObserver + PeriodicWorker) |
| `triggerDelay` | 30 s | Android : délai content-URI (5/30/120/600 s) |
| `syncAlbums` | false | Sync album lié (feature bêta séparée) |

Persistance : table `settings` (Drift), `SettingsRepository` (snapshot `AppConfig`).

## 3. Les 3 déclencheurs

### 3.1 Resume foreground (`lib/providers/app_life_cycle.provider.dart`)

`ImmichAppState.didChangeAppLifecycleState(resumed)` → `AppLifeCycleNotifier.handleAppResume()` → `_handleBetaTimelineResume()` :
- lock du moteur (`BackgroundWorkerLockService.lock()`, Android) ;
- `cancelResumeSyncs()` — jette toute sync figée pendant la suspension (bug #28082) ;
- en parallèle : `syncLocal(full: Android)`, `syncRemote()` ;
- si `syncRemote` réussit → `hashAssets()` + `_resumeBackup()` (x2) ; sinon hash seulement ;
- `_resumeBackup()` : si `backup.enabled` + user connecté → `backupProvider.startForegroundBackup(userId)` (HTTP, 3 workers).
- Au pause : `stopForegroundBackup(reason: "app being sent to background")` + unlock + disconnect websocket. Le backup foreground est donc **annulé** quand l'app passe en background — le relais est pris par le worker natif.

### 3.2 iOS — BGTaskScheduler (`ios/Runner/Background/BackgroundWorkerApiImpl.swift`)

Deux tâches enregistrées au `didFinishLaunching` (`registerBackgroundWorkers()`), schedulées par `enable()` (appelé **inconditionnellement** au démarrage de l'app, `lib/main.dart` → `backgroundWorkerFgServiceProvider.enable()`) :

| Tâche | Type | Re-schedule | Budget |
|---|---|---|---|
| `app.alextran.immich.background.refreshUpload` | BGAppRefreshTask | earliestBeginDate +5 min, re-soumise au moment du tir | **20 s** (`maxSeconds=20`) |
| `app.alextran.immich.background.processingUpload` | BGProcessingTask, `requiresNetworkConnectivity=true` | earliestBeginDate +15 min, re-soumise au moment du tir | illimité (`maxSeconds=nil`) |

- Un sémaphore (`taskSemaphore`) garantit qu'une seule tâche tourne à la fois ; une deuxième cède le temps (`setTaskCompleted(success: false)`).
- `expirationHandler` → `backgroundWorker.close()` → `flutterApi.cancel` (Dart draine) → `setTaskCompleted`.
- Chaque tâche **démarre un second Flutter engine** (`FlutterEngine(name: "BackgroundImmich")`, entrypoint `backgroundSyncNativeEntrypoint`, library `background_worker.service.dart`), plugins enregistrés, puis `onInitialized()` → `flutterApi.onIosUpload(isRefresh, maxSeconds)`.
- `disable()` : annule les deux requêtes BGTaskScheduler. `configure()` : no-op sur iOS (Android only).

### 3.3 Android — WorkManager (`android/.../background/BackgroundWorkerApiImpl.kt`)

`enable()` enqueue :
- **`MediaObserver`** (one-time, `ExistingWorkPolicy.REPLACE`) : content-URI triggers sur `MediaStore.Images/Videos.Media.INTERNAL/EXTERNAL_CONTENT_URI`, `setTriggerContentUpdateDelay(triggerDelay)`, `setTriggerContentMaxDelay(triggerDelay × 10)`, `setRequiresCharging(requireCharging)`. Au tir : se ré-enqueue elle-même + `enqueueBackgroundWorker` si `triggeredContentUris` non vide.
- **`PeriodicWorker`** : période 1 h, flex 15 min, `setRequiresCharging(requireCharging)`, `ExistingPeriodicWorkPolicy.UPDATE` → `enqueueBackgroundWorker`.
- **`BackgroundWorker`** (one-time, `ExistingWorkPolicy.KEEP`, `BackoffPolicy.EXPONENTIAL` 1 min, contrainte `batteryNotLow`) : notification "Uploading media" (`IMPORTANCE_LOW`), promote en **foreground service** (`FOREGROUND_SERVICE_TYPE_DATA_SYNC`) si les optimisations batterie sont ignorées, puis lance le second Flutter engine → `onAndroidUpload(maxMinutes=20)`.
- Lock moteur : si `BackgroundWorkerPreferences.isLocked()` et un engine foreground est actif (`BackgroundEngineLock.connectEngines > 0`), le worker skip (`Result.success` immédiat). Lock posé au resume, retiré au pause/detach.
- `configure(settings)` : met à jour les prefs + ré-enqueue MediaObserver/PeriodicWorker. `disable()` : annule les 3 works.

## 4. Moteur background Dart (`lib/domain/services/background_worker.service.dart`)

`BackgroundWorkerBgService` tourne dans l'engine secondaire, avec sa propre DB Drift et son propre `ProviderContainer`. Un `Completer<void> _cancellationToken` est partagé avec LocalSync/Hash/SyncStream services.

### iOS — `onIosUpload(isRefresh, maxSeconds)`
- budget = `maxSeconds - 1` ;
- si task *processing* (maxSeconds == nil) : `_optimizeDB()` d'abord ;
- **4 phases en parallèle** (`Future.wait`) : local sync + remote sync + hash + `_handleBackup()`, le tout plafonné par le budget unique → timeout → `_cancellationToken.complete()` (annule sync/hash Dart + `nativeSyncApi.cancelHashing()`). Le choix parallèle est motivé dans le code : le refresh de 20 s doit avancer sur les 4 fronts, le dedup serveur rattrape les races ;
- `_handleBackup()` : si `backup.enabled` + user → `backupProvider.startBackupWithURLSession(userId)` (voir §5.2) ; sinon log "Backup is disabled. Skipping" ;
- `_cleanup()` : complète le token, `cancelHashing`, dispose worker manager, ferme les 2 DB, dispose le container, `onInitialized/close` au natif.

### Android — `onAndroidUpload(maxMinutes=20)`
- `_optimizeDB()` ;
- **séquentiel** : `_syncAssets(hashTimeout: 3 min si backup enabled, sinon 6 min)` = local sync → remote sync → hash ; si le remote sync échoue → **skip le backup** ;
- `_handleBackup()` avec `Timer(maxMinutes - 1)` qui complète le token (upload HTTP séquentiel `useSequentialUpload: true`, car les clients HTTP concurrents posent problème dans l'isolate background) ;
- cleanup identique.

## 5. Sélection des candidates et dedup (`lib/infrastructure/repositories/backup.repository.dart`)

- `BackupSelection` : `none | selected | excluded` sur `local_album_entity` (sélection d'albums via `BackupAlbumNotifier` : `selectAlbum`/`deselectAlbum`/`excludeAlbum`).
- `getCandidates(userId)` : albums selected ∩ assets, **moins** assets dont `checksum` ∈ `remote_asset_entity` (owner = user), **moins** assets d'un album excluded, tri `createdAt DESC`.
- `getAllCounts(userId)` : 1 seule requête SQL → `total` (assets des albums selected hors excluded), `processing` (checksum IS NULL), `remainder` (pas de remote asset correspondant).
- Le client ne fait **aucun** `bulk-upload-check` : la table `remote_asset_entity` (remplie par le remote sync) est la base de dedup, et le serveur re-dédupe au moment du POST (il renvoie l'asset existant). Note #27818 : `deviceAssetId`/`deviceId` ne sont plus requis côté serveur v4.0 mais restent envoyés.

## 6. Hash (`lib/domain/services/hash.service.dart` + natif)

- SHA1 du flux de bytes du fichier, encodé base64. iOS : `CryptoKit.Insecure.SHA1` sur `PHAssetResourceManager.requestData` (streaming, pas de chargement complet). Android : implémentation native équivalente dans `sync/MessagesImpl*.kt`.
- Itère `getBackupAlbums()` (albums selected triés), `getAssetsToHash(album)` (checksum NULL), batchs de 32 (iOS) / 512 (Android), `allowNetworkAccess: album.backupSelection == selected` (le hash d'un album selected peut télécharger l'asset iCloud).
- Annulable : `isCancelled` entre chaque batch + `cancelHashing()` natif via le token partagé.
- Android : hash aussi les assets trashés (`manageLocalMediaAndroid`).

## 7. Upload

### 7.1 Foreground (`lib/services/foreground_upload.service.dart` + `lib/repositories/upload.repository.dart`)
- `uploadCandidates(userId, cancelToken)` : candidates → `ConnectivityApi.getCapabilities()` ; `_executeWithWorkerPool` (3 workers, `currentIndex` atomique) ; `shouldSkip` = asset requiert WiFi et pas de WiFi.
- `uploadSingleAsset` : résout l'entité PHAsset ; si non dispo localement et iOS → téléchargement iCloud avec `PMProgressHandler` (progression exposée) ; live photo → la **vidéo d'abord** (`visibility=hidden`), puis la photo avec `livePhotoVideoId` ; champs : `deviceAssetId`, `deviceId`, `fileCreatedAt`, `fileModifiedAt`, `isFavorite`, `duration`, `metadata` (iOS cloudId `RemoteAssetMobileAppMetadata` pour la sync cloud-id) ; POST multipart `/api/assets` (`ProgressMultipartRequest` avec `abortTrigger = cancelToken.future` et stream de progression) ; **un seul resend** si `ClientException` avant réponse ; erreur 413 / quota ("Quota has been exceeded!") → abort global ; suppression des fichiers temporaires après upload (iOS).
- WiFi par asset : `_shouldRequireWiFi(asset)` = vrai sauf si `useCellularForVideos` (vidéo) / `useCellularForPhotos` (photo).

### 7.2 Background iOS — URLSession (`lib/services/background_upload.service.dart`)
- `uploadBackupCandidates(userId)` : `clearCache()` → `getCandidates` → **batch de 100 max** → 1 `UploadTask` par asset (`background_downloader`) → `enqueueTasks` → `resume()`.
- Tâche : POST `{server}/assets`, headers auth, `fileField: 'assetData'`, groupe `kBackupGroup` ('backup_group'), `priority: 5`, `retries: 3`, `requiresWiFi` par tâche, métadonnée JSON `UploadTaskMetadata` (localAssetId, isLivePhotos, livePhotoVideoId).
- Live photo : vidéo dans `kBackupGroup` ; à la complétion, le `responseBody` (JSON avec l'id) est parsé → la photo est enqueuée dans `kBackupLivePhotoGroup` avec `priority: 0` + `livePhotoVideoId`. Le cancel ne touche que le groupe vidéo.
- Résumé/resume : `getActiveTasks(kBackupGroup)` — s'il reste des tâches ENQUEUED/RUNNING (reprise après kill de l'app), `resume()` ; sinon nouvel enqueue.
- Les tâches URLSession survivent à la suspension de l'app : elles tournent dans le process système, pas dans l'engine Dart.

## 8. État et UI (`lib/providers/backup/backup.provider.dart`, `lib/pages/backup/backup.page.dart`)

- `BackupState` : `totalCount`, `backupCount`, `remainderCount`, `processingCount`, `isSyncing`, `error` (`none|syncFailed`), `uploadItems` (progression/speed par asset, `errorCount` = items `isFailed`), `iCloudDownloadProgress`.
- `startForegroundBackup(userId)` : annule le run existant ("restarting the backup"), reset l'erreur, **re-baseline les compteurs sur la même lecture DB que les candidates** (bug #26215), lance l'upload avec callbacks.
- `stopForegroundBackup(reason)` : complète le cancel token, vide `uploadItems`.
- `BackupPage` : `WakelockPlus.enable()` pendant l'affichage ; à l'ouverture → `syncRemote()` puis `getBackupStatus()` ; toggle : ON → écrit `.backupEnabled` + `startBackup()` (syncRemote si nécessaire → `startForegroundBackup`) ; OFF → `stopForegroundBackup`. Bannière d'erreur si `syncFailed`.
- Options (`lib/widgets/settings/backup_settings/backup_settings.dart`) : cellulaire vidéos/photos ; Android uniquement : `requireCharging` (ré-applique `configure()`), slider `triggerDelay` (5 s / 30 s / 2 min / 10 min) ; sync albums (bêta).
- Le **gate `enabled`** n'est pas appliqué par le natif : les workers sont toujours schedulés (enable inconditionnel au boot) et le check se fait dans le Dart background (`_handleBackup` skip si désactivé — la sync/hash, eux, tournent quand même pour maintenir la DB à jour).

## 9. Gating récapitulatif

| Gate | Où | Valeur |
|---|---|---|
| `backup.enabled` | Dart `_handleBackup` (bg) + `_resumeBackup` (fg) | setting |
| WiFi | Par asset : `_shouldRequireWiFi` (fg : skip ; bg : `requiresWiFi` de la tâche URLSession) | `useCellularFor*` |
| Charging | Android only : contraintes WorkManager | `requireCharging` |
| Battery not low | Android : contrainte BackgroundWorker | fixe |
| Delay après changement média | Android : `triggerContentUpdateDelay` | `triggerDelay` |
| Budget | iOS refresh 20 s ; Android worker 20 min | fixe |
| Quota | abort global foreground | erreur serveur |
| Lock moteur | skip si engine foreground actif (Android) | `BackgroundEngineLock` |

## 10. Points notables pour le port SwiftUI

1. **Pas de `bulk-upload-check`** : la dedup est une jointure SQL locale sur les checksums des assets distants, maintenue par le remote sync. ImmichSwiftUI appelle `bulkUploadCheck` — équivalent fonctionnel, mais l'approche Flutter déplace la base de dedup côté client (table `remote_asset_entity`).
2. **Check "remote sync OK" avant tout backup auto** : si `/api/sync/stream` échoue, le backup auto ne démarre pas (Android bg et resume fg). Évite d'uploader en aveugle sur une base de dedup périmée.
3. **Annulation au passage en background** : le backup HTTP foreground est stoppé au `paused` ; sur iOS le relais est un batch de ≤100 tâches URLSession (dont le cycle de vie est géré par le système), sur Android un worker de 20 min max.
4. **Budget parallèle iOS** : local/remote sync + hash + backup tournent en parallèle dans le budget unique du BGAppRefreshTask (20 s), avec token d'annulation partagé.
5. **Hash natif streaming SHA1** : jamais de chargement complet du fichier ; batch 32 fichiers sur iOS (cf. le bug jetsam du BackupEngine ImmichSwiftUI, souvenir [2df93d54]).
6. **Live photo en 2 uploads** : vidéo (hidden) puis photo avec `livePhotoVideoId` ; en bg, la photo est enqueuée après la réponse du POST de la vidéo (priorité 0).
7. **Compteurs re-baselinés** à chaque run sur la même lecture DB que la liste des candidates (bug #26215) — sinon un resume compte en double des succès.
8. **Gate `enabled` côté Dart**, pas côté natif : la sync/hash continuent même backup désactivé, seul l'upload est skippé.
9. iOS BGTaskScheduler : refresh (+5 min, 20 s) et processing (+15 min, illimité, réseau requis) re-soumises à chaque tir ; sémaphore anti-concurrence ; expiration → cancel Dart → `setTaskCompleted`.
10. Android : détection de nouveaux médias par content-URI trigger (délai configurable), periodic 1 h, foreground service + notification ; skip si l'engine principal tourne (lock).
