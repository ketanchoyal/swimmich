# Task: offline-download

Status: done — **13/13 AC PASS** (2026-09-13). Suite **805 → 831 tests, TEST SUCCEEDED** (iPhone 17, `-only-testing:ImmichSwiftUITests`) ; `test_09_offlineDownload` vert sur **deux runs consécutifs** contre le stub committé `UITests/stubs/immich_stub_offline.py`.

## Résultat (2026-09-13)

| AC | Résultat | Preuve |
|----|----------|--------|
| AC-3500 | PASS | `Sources/Services/OfflineAssetStore.swift` — 9 entrées d'API + `CachedAssetInfo` + `init(folderURL:transport:fileManager:defaults:)` |
| AC-3501 | PASS | `Sources/Features/Offline/OfflineDownloadViewModel.swift` |
| AC-3502 | PASS | `Sources/Features/Offline/OfflineAssetsView.swift` (LazyVGrid, carte d'occupation, suppression, Clear All, état vide) |
| AC-3503 | PASS | section `OfflineSection` du partage (`PhotoViewer.swift`) |
| AC-3504 | PASS | badge `offlineBadge` + image locale dans `AssetThumbnailCell` ; **vérifié au pixel** sur `/tmp/shot-43-timeline-offline-badge.png` |
| AC-3505 | PASS | `ProfileView` → `OfflineAssetsView(vm:)` (identifier `offlineStorageRow`) |
| AC-3506 | PASS | `Tests/OfflineAssetStoreTests.swift` — 17 cas |
| AC-3507 | PASS | progression déterminée (`MockFileDownloadTransport` rejoue (25,100)(50,100)(100,100)) + `test_downloadAsset_reportsDeterminateProgress` |
| AC-3508 | PASS | `test_localImage_rendersWithoutNetwork` + `test_downsampler_capsTheDecodedSize` + étape « serveur coupé » du scénario UI |
| AC-3509 | PASS | `Tests/OfflineDownloadViewModelTests.swift` — 8 cas |
| AC-3510 | PASS | **831 tests, TEST SUCCEEDED** (baseline 805) |
| AC-3511 | PASS | 24 clés EN+FR ajoutées à la main à `Resources/Localizable.xcstrings` |
| AC-3512 | PASS | stub committé + `test_09_offlineDownload` vert 2× |

**Tests ajoutés** : 17 unitaires sur le store (écriture+index, hit, miss, remove, clearAll, refus avant transfert, éviction, réconciliation, `.partial`, statut HTTP, payload vide, JPEG local, plafond du downsampler, extension serveur, jeton+progression), 8 sur le view model (load, download OK/KO, progression, remove, clearAll, recherche, anneau illimité).

**Preuve d'exécution réelle** (`/tmp/shot-4*.png`) : grille avant → viewer → « Available offline » après téléchargement → badge visible sur la 2ᵉ rangée du timeline → écran Stockage hors ligne (**serveur coupé** : 179 octets utilisés, 1 fichier, tuile réellement rendue depuis le disque) → suppression → état vide.

## Écarts constatés à l'implémentation (la carte les annonçait autrement)

1. **`fileSizeInByte` n'est pas sur l'asset.** `AssetResponseDto` ne porte pas de taille : elle vit dans `exifInfo.fileSizeInByte` (`Sources/Core/Types/DTOs.swift:145`). Le store reçoit donc `dto.exifInfo?.fileSizeInByte`. Sans cette taille annoncée, la garde « refus avant téléchargement » ne se déclenche jamais.
2. **`CachedAssetInfo` a gagné `originalFileName`.** Le fichier sur disque est nommé d'après l'`assetId` (unique, sûr) ; sans le nom serveur, l'écran n'affichait et ne cherchait qu'un UUID opaque. `displayName` retombe sur `fileName` pour un fichier orphelin adopté.
3. **Les tables de l'index doivent être OBSERVÉES.** Première version : `@ObservationIgnored` sur `byID`/`urlsByID` et `progressByID`/`downloadingIDs`. Conséquence : le badge du timeline ne se rafraîchissait jamais — un `body` qui lit `isCached(_:)` ne crée de dépendance que sur ce que la propriété lue touche. Trouvé par le scénario XCUITest, **invisible aux tests unitaires** (qui interrogent l'objet directement, sans passer par une observation SwiftUI).
4. **Arrêter le transfert ne suffit pas à prouver l'hors-ligne.** Avec le stub up, la grille peut se rafraîchir depuis `ImageCache`/`URLCache` et paraître « locale » à tort. Le stub committé expose donc `/__network?down=1` : tout `/api/assets/*` et `/api/timeline/*` répond alors 503 et **est journalisé `offline: true`**. Le scénario exige qu'aucune requête de ce type n'ait eu lieu pendant que l'écran s'affichait — c'est ce qui distingue « le cache contient un fichier » de « l'app est utilisable sans serveur ».
5. **`URLProtocol` ne peut pas tester la progression.** Ces doubles livrent le corps d'un bloc et n'appellent jamais le délégué de téléchargement : rien à mesurer, et pas de fichier écrit. D'où la couture `FileDownloadTransport` (`Core/Protocols/`) + `URLSessionFileDownloadTransport` (flux natif vers un fichier temporaire) + `MockFileDownloadTransport` (script de progression). Même raison pour `URLSession.download` plutôt que `data(for:)` : un cache d'originaux ne matérialise pas une vidéo en mémoire.
6. **Le titre du premier rang du timeline est masqué par l'en-tête de date flottant** : le scénario télécharge la photo de la 2ᵉ rangée et scrolle avant la capture (même piège que celui consigné pour le badge de pile).
7. **Identifiants d'accessibilité** : `assetTile_<id>` sur une tuile du timeline et `offlineStorageRow` sur la ligne du hub « Me » (le libellé est traduit, donc un littéral dépendrait de la locale) ; **aucun identifiant sur la carte d'occupation** — posé sur ce conteneur il écrasait `offlineUsageText` et `offlineUsageRing` (famille de pièges déjà connue).
8. **Écart d'UI assumé** : l'anneau affiche `<1%` au lieu de `0%` quand un fichier minuscule est en cache — « 0% » à côté d'une photo présente se lit comme un bug.
9. **Les VIDÉOS ne se lisaient pas hors-ligne** (trou comblé le 2026-09-13, après la première clôture). `VideoPlaybackViewModel.prepare` construisait toujours l'URL HLS du serveur : un asset téléchargé produisait donc une tuile en placeholder (ImageIO ne lit pas un `.mp4`) et un lecteur qui échouait sans réseau — « Download for Offline » mentait pour les vidéos. Correctif : `localFileURL` accepté par `prepare`/`VideoPlayerView`/`KenBurnsImageView`/`ZoomableImageView`, alimenté par `OfflineAssetIndex` (viewer **et** diaporama), lecture avec `token: nil` pour un fichier local, et `ImageDownsampler.videoPoster(at:)` (AVAssetImageGenerator) en repli de l'étage 0 pour la vignette. Preuves : `test_prepare_withLocalFile_playsFromDiskAndSendsNoToken`, `test_videoPoster_rendersAFrameFromALocalMovie` (vrai MP4 H.264 généré par `Tests/Mocks/VideoFixture.swift`), `test_videoPoster_returnsNilForANonVideo`.

## Plan

**Objectif** : télécharger les originaux d'assets dans un cache local durable et les **restituer sans réseau** — grille « Offline Storage » + viewer + indicateur sur le timeline + gestion de l'espace occupé. Parité Flutter (Isar), sans nouvelle dépendance.

**Hypothèses — vérifiées dans le dépôt et sur l'OpenAPI du 2026-09-13** :

| Fait | Preuve |
|---|---|
| `GET /api/assets/{id}/original` existe (`operationId: downloadAsset`, `application/octet-stream`, params `edited`/`key`/`slug`) | `jq '.paths["/assets/{id}/original"]' /tmp/immich-openapi-main.json` — aucune route fantôme dans cette fiche |
| Pas de route « offline » côté serveur : tout passe par l'original | 0 opération contenant `offline` dans `paths` de l'OpenAPI `main` |
| `AssetResponseDto.originalPath` = simple `"Original file path"` (string opaque), et le dépôt ne s'en sert pas | `Sources/Core/Types/DTOs.swift:106` ; précédent : `SaveToLibraryViewModel.transferOriginal()` construit l'URL |
| Le builder d'URL canonique existe | `ImmichAssetURL.original(assetId:baseURL:sharedLink:)` — `Sources/Services/ImmichAssetURL.swift:36` |
| Le client expose `getAsset(id:)` (origine du nom de fichier + de la taille) | `Sources/Core/Protocols/ImmichClient.swift:47`, `ImmichAPIClient.swift:146` |
| Précédent d'un store fichier injectable | `EditStateStore` (actor, Application Support, `init(folderURL:)` pour les tests, tolérance aux entrées absentes) — `Sources/Services/EditStateStore.swift` |
| `AuthenticatedAsyncImage` a 3 étages (NSCache → URLCache → réseau) et un `url: URL?` **déjà optionnel** | `Sources/Services/AuthenticatedAsyncImage.swift:11-80` |
| Aucun décodeur local : un fichier n'est jamais lu depuis le disque → le cache offline serait invisible | même fichier |
| `AssetThumbnailCell` porte déjà des badges `.overlay(alignment:)` + helper capsule `badge(_:)` | `Sources/Features/Timeline/AssetThumbnailCell.swift:37-45,128-138,178` |
| 6 sites instancient `AssetThumbnailCell` (Timeline, Albums, People, Search, Trash, SharedLinkViewer, AssetMultiSelectGrid) → l'état « en cache » doit venir de l'**environnement**, pas d'un paramètre | `grep -n "AssetThumbnailCell(" Sources` |
| `ProfileView` reçoit ses VM de `AuthenticatedRoot` et pousse déjà vers 6 hubs (Trash, Backup, Duplicates, People, Tags, Stacks, Partners) | `Sources/Features/Profile/ProfileView.swift:30-90`, `Sources/RootView.swift:88-116,188` |
| Le viewer partage `PhotoShareSheet` (feuille privée) et sait déjà télécharger l'original (Data en mémoire) | `Sources/Features/PhotoViewer/PhotoViewer.swift:259,907-1204`, `SaveToLibraryViewModel.swift:93-125` |
| `UserDefaults` sert déjà de réglage persistant pour la backup | `BackupSettingsStore` (même pattern pour `offlineMaxSize`) |
| Catalogue i18n = 370 clés, langues `en` + `fr` | `jq '.strings\|length' Resources/Localizable.xcstrings` |

**Approche retenue** : A — `OfflineAssetStore` (fichiers + index JSON, zéro dépendance) + lecture locale dans `AuthenticatedAsyncImage`.
**B rejetée** : GRDB/SQLite → nouvelle dépendance pour une table de N lignes.
**C rejetée** : Isar → couplage Flutter.
**D rejetée** : `.cachesDirectory` (spec d'origine) → **le système purge `Caches`** sous pression disque : un asset « disponible hors-ligne » disparaîtrait silencieusement. On écrit sous **Application Support** (précédent `EditStateStore`).

### Répertoire et fichiers sur disque

```
Application Support/OfflineAssets/
├── index.json                 # [CachedAssetInfo] — source de vérité des métadonnées
└── <assetId>.<ext>            # la charge utile (extension via AssetFileTransfer.fileExtension(forMime:))
```
L'`assetId` est un UUID : nom de fichier sûr tel quel (même politique que `EditStateStore.fileURL(for:)`).

### Décisions de conception (à ne pas re-débattre à l'implémentation)

1. **Rendu hors-ligne réel = étape 0 dans `AuthenticatedAsyncImage`.** Sans elle, le store n'est qu'une liste de tailles et « consultation hors-ligne » ne marche pas. Nouveau paramètre `localFileURL: URL?` : s'il est fourni et que le fichier existe, l'image est servie depuis le disque **avant** les 3 étages ; le `.task(id:)` est clé sur `localFileURL ?? url`.
2. **Jamais de décodage plein format dans une grille.** Un original de 12 Mpx décodé par cellule = mémoire et jank. `ImageDownsampler.image(at:maxPixelSize:)` (ImageIO, `CGImageSourceCreateThumbnailAtIndex`) sert les fichiers locaux, `maxPixelSize` 2048 par défaut.
3. **Téléchargement en flux, jamais en `Data`.** `URLSession.bytes(for:)` → écriture dans `<id>.<ext>.partial`, `moveItem` atomique à la fin. `SaveToLibraryViewModel` matérialise l'original en mémoire parce qu'il l'envoie au partage système ; un cache offline de vidéos ne peut pas se le permettre (précédent : `BackupEngine` « never materializes the whole asset in memory »).
4. **État « en cache » côté UI = `OfflineAssetIndex` observable en environnement.** Un actor n'est pas lisible de façon synchrone depuis un `body` ; l'index `@MainActor @Observable` publie `Set<String>` + URLs et est alimenté par le store.
5. **Politique de limite** : `maxCacheSize` (`UserDefaults` clé `offlineMaxSize`, défaut **5 Go**). Un asset dont la taille annoncée dépasse la limite → refus (`OfflineStoreError.exceedsCacheLimit`) **avant** téléchargement. Après écriture, on évince les plus anciens (`cachedAt`) jusqu'à repasser sous la limite, jamais l'asset qui vient d'être écrit.
6. **Réconciliation d'index** : à la lecture, l'index est confronté au disque (entrée sans fichier → retirée ; fichier sans entrée → adopté avec `size`/`cachedAt` des attributs). Un crash en cours d'écriture ne doit pas produire un « en cache » pointant un fichier absent.
7. **Périmètre refusé** : sync automatique (la spec dit « manuel »), chiffrement, cache partiel par plage vidéo, reprise de téléchargement interrompu.

### Étapes d'implémentation

1. NEW `Sources/Services/OfflineAssetStore.swift` — `actor OfflineAssetStore` + `struct CachedAssetInfo` + `enum OfflineStoreError`. API : `download(assetID:url:token:fileName:isVideo:ratio:fileCreatedAt:duration:maxCacheSizeHint:onProgress:)`, `cachedInfo(assetID:)`, `fileURL(assetID:)`, `allCached()`, `isCached(assetID:)`, `totalBytes()`, `remove(assetID:)`, `clearAll()`, `maxCacheSize` (`setMaxCacheSize(_:)` applique l'éviction), `init(folderURL:session:fileManager:)`.
2. NEW `Sources/Services/ImageDownsampler.swift` — `static func image(at:maxPixelSize:) -> UIImage?` (ImageIO).
3. EDIT `Sources/Services/AuthenticatedAsyncImage.swift` — `localFileURL: URL? = nil`, `localMaxPixelSize: Int = 2048`, étage 0 dans `load()`, clé de `.task`.
4. NEW `Sources/Features/Offline/OfflineAssetIndex.swift` — `@MainActor @Observable` : `byID: [String: CachedAssetInfo]`, `localURL(for:)`, `isCached(_:)`, `info(_:)`, `refresh(from:)`, `remove(id:)`, `clear()`.
5. NEW `Sources/Features/Offline/OfflineDownloadViewModel.swift` — `cachedAssets`, `cacheUsage`, `maxCacheSize`, `downloadAsset(id:)`, `removeFromOffline(id:)`, `clearAll()`, `load()`, `isDownloading(_:)`, `progress(for:)`, `errorMessage`, `lastDownloadedID`, `searchQuery` + `filteredAssets`.
6. NEW `Sources/Features/Offline/OfflineAssetsView.swift` + `OfflineAssetCell` + `StorageUsageCard` (anneau) — `LazyVGrid`, état vide, swipe/context « Remove », « Clear All » avec confirmation, tap → `PhotoViewer`.
7. EDIT `Sources/Features/Timeline/AssetThumbnailCell.swift` — badge `arrow.down.circle.fill` (identifier `offlineBadge`) sur les assets en cache + `localFileURL` passé à `AuthenticatedAsyncImage`.
8. EDIT `Sources/Features/PhotoViewer/ZoomableImageView.swift` — paramètre `localFileURL` transmis au même composant.
9. EDIT `Sources/Features/PhotoViewer/PhotoViewer.swift` — section « Offline » dans `PhotoShareSheet` : « Download for Offline » / « Remove from Offline » + indicateur de progression + pastille « Available offline ».
10. EDIT `Sources/Features/Profile/ProfileView.swift` — `@State var offline: OfflineDownloadViewModel` + `NavigationLink("Offline Storage")` dans la section Management.
11. EDIT `Sources/DependencyContainer.swift` — `offlineStore`, `offlineIndex`, `makeOfflineDownloadViewModel()` (instances process-wide : le badge du timeline et l'écran de gestion doivent voir le même index).
12. EDIT `Sources/RootView.swift` — `@State private var offline`, `.environment(offlineIndex)` + `.environment(offline)` sur la hiérarchie des tabs, `offline: offline` passé à `ProfileView`.
13. EDIT `Resources/Localizable.xcstrings` — clés EN+FR **ajoutées à la main** (piège : ne jamais committer le catalogue régénéré par un build Xcode incrémental).
14. NEW `Tests/OfflineAssetStoreTests.swift` (≥7) + `Tests/OfflineDownloadViewModelTests.swift` (≥5).
15. NEW `UITests/stubs/immich_stub_offline.py` (committé, self-contained, port 8421) + scénario `test_09_offlineDownload` dans `UITests/ImmichRenderScreenshots.swift`.
16. `xcodegen generate` + suite complète (`-only-testing:ImmichSwiftUITests`) + scénario UI à la main contre le stub.

## Acceptance Contract

### Approches candidates
**A (retenue)** : `OfflineAssetStore` fichiers + index JSON, lecture locale via `AuthenticatedAsyncImage`, index observable en environnement. Aucune dépendance, testable sans réseau, restitue réellement hors-ligne.
**B** : GRDB/SQLite → dépendance neuve pour N lignes de métadonnées.
**C** : Isar → couplage au client Flutter.
**D** : `.cachesDirectory` + `URLCache` seul → purgeable par l'OS, et `URLCache` ne sert pas une vue sans réseau de façon fiable.

### Approche retenue + rationale
**A**. Le disque est la seule source durable ; l'index JSON est reconstruit au besoin depuis les attributs des fichiers (pas de dualité irréparable).

### Critères

Chaque check est **exécutable tel quel** depuis la racine du dépôt. Les checks de comportement sont adossés à des tests nommés (lancer la suite d'une classe : `xcodebuild test … -only-testing:ImmichSwiftUITests/<Classe>`), jamais à une simple présence de mot (piège connu : `grep -q` matche aussi un commentaire ; cf. `.opencode/scratch/stacks-ui.acceptance.md` piège 5).

```
### AC-3500 [type: new]
Assertion: OfflineAssetStore existe comme actor dans Sources/Services/OfflineAssetStore.swift avec les 9 entrées d'API (download/cachedInfo/fileURL/allCached/isCached/totalBytes/remove/clearAll/maxCacheSize), CachedAssetInfo Codable et une init injectable folderURL:.
Check post-impl: sh -c 'f=Sources/Services/OfflineAssetStore.swift; test -f "$f" || { echo FAIL; exit; }; s=$(sed -n "/^actor OfflineAssetStore/,/^}/p" "$f"); for d in "func download(" "func cachedInfo(" "func fileURL(" "func allCached(" "func isCached(" "func totalBytes(" "func remove(" "func clearAll(" "maxCacheSize" "folderURL: URL?"; do printf "%s" "$s" | grep -qF "$d" || { echo "FAIL $d"; exit; }; done; grep -qE "struct CachedAssetInfo: .*Codable" "$f" || { echo FAIL schema; exit; }; echo PASS'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3501 [type: new]
Assertion: OfflineDownloadViewModel expose cachedAssets, cacheUsage, maxCacheSize, downloadAsset(id:), removeFromOffline(id:), clearAll(), load() dans Sources/Features/Offline/OfflineDownloadViewModel.swift.
Check post-impl: sh -c 'f=Sources/Features/Offline/OfflineDownloadViewModel.swift; test -f "$f" || { echo FAIL; exit; }; for d in "var cachedAssets" "var cacheUsage" "var maxCacheSize" "func downloadAsset(" "func removeFromOffline(" "func clearAll(" "func load("; do grep -qF "$d" "$f" || { echo "FAIL $d"; exit; }; done; echo PASS'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3502 [type: new]
Assertion: OfflineAssetsView existe avec LazyVGrid, carte d'occupation (anneau), suppression par asset, « Clear All » et état vide dans Sources/Features/Offline/OfflineAssetsView.swift.
Check post-impl: sh -c 'f=Sources/Features/Offline/OfflineAssetsView.swift; test -f "$f" || { echo FAIL; exit; }; for d in "LazyVGrid" "storageUsageCard" "removeFromOffline" "clearAll" "ContentUnavailableView" "accessibilityIdentifier"; do grep -qE "$d" "$f" || { echo "FAIL $d"; exit; }; done; echo PASS'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3503 [type: new]
Assertion: le partage du viewer porte l'action offline (« Download for Offline » / « Remove from Offline » + progression) dans Sources/Features/PhotoViewer/PhotoViewer.swift.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/PhotoViewer.swift; for d in "Download for Offline" "Remove from Offline" "downloadAsset" "offlineVM"; do grep -qE "$d" "$f" || { echo "FAIL $d"; exit; }; done; echo PASS'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3504 [type: new]
Assertion: AssetThumbnailCell affiche un badge d'asset en cache (identifier offlineBadge) alimenté par l'index d'environnement, et rend l'image depuis le fichier local.
Check post-impl: sh -c 'f=Sources/Features/Timeline/AssetThumbnailCell.swift; for d in "OfflineAssetIndex" "offlineBadge" "localFileURL" "isCached"; do grep -qE "$d" "$f" || { echo "FAIL $d"; exit; }; done; echo PASS'
Pre-state attendu: FAIL
Post-state attendu: PASS
Vérification de comportement: scénario XCUITest « test_09_offlineDownload » (badge visible après téléchargement).
```

```
### AC-3505 [type: new]
Assertion: ProfileView pousse « Offline Storage » vers OfflineAssetsView depuis la section Management.
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfileView.swift; grep -qE "OfflineAssetsView\(vm:" "$f" && grep -qE "Offline Storage" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3506 [type: new]
Assertion: Tests/OfflineAssetStoreTests.swift couvre au moins 7 cas nommés : write+index, cache hit, cache miss, remove, clearAll, éviction à la limite, réconciliation d'index.
Check post-impl: sh -c 'f=Tests/OfflineAssetStoreTests.swift; test -f "$f" || { echo FAIL; exit; }; n=$(grep -cE "^\s*func test_" "$f"); test "$n" -ge 7 || { echo "FAIL count=$n"; exit; }; for k in download cacheHit cacheMiss remove clear eviction reconcile; do grep -qiE "func test_.*$k" "$f" || { echo "FAIL $k"; exit; }; done; echo PASS'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3507 [type: new]
Assertion: la progression est déterminée pendant le téléchargement (octets reçus / Content-Length) et exposée par le VM (progress(for:) + isDownloading(_:)).
Check post-impl: sh -c 'sh -c "grep -qE \"onProgress\" Sources/Services/OfflineAssetStore.swift && grep -qE \"func progress\\(for\" Sources/Features/Offline/OfflineDownloadViewModel.swift && grep -qE \"func isDownloading\" Sources/Features/Offline/OfflineDownloadViewModel.swift && echo PASS || echo FAIL"'
Pre-state attendu: FAIL
Post-state attendu: PASS
Vérification de comportement: Tests/OfflineAssetStoreTests.test_download_reportsProgress (le stub sert un Content-Length > 0 et le test exige des valeurs strictement croissantes menant à 1.0) + Tests/OfflineDownloadViewModelTests.test_progress_publishesFraction.
```

```
### AC-3508 [type: new]
Assertion: un asset en cache s'affiche SANS réseau — AuthenticatedAsyncImage sert le fichier local (étage 0) et downsampe via ImageDownsampler au lieu de décoder l'original plein format.
Check post-impl: sh -c 'grep -qE "localFileURL" Sources/Services/AuthenticatedAsyncImage.swift && grep -qE "ImageDownsampler" Sources/Services/AuthenticatedAsyncImage.swift && test -f Sources/Services/ImageDownsampler.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
Vérification de comportement: Tests/OfflineAssetStoreTests.test_localImage_rendersWithoutNetwork (URLProtocol qui échoue pour toute requête ; le fichier local doit tout de même produire une UIImage) + ZoomableImageView/AssetThumbnailCell reçoivent localFileURL.
```

```
### AC-3509 [type: new]
Assertion: OfflineDownloadViewModelTests couvre load(), downloadAsset (succès + échec), removeFromOffline, clearAll, cacheUsage — au moins 5 cas nommés.
Check post-impl: sh -c 'f=Tests/OfflineDownloadViewModelTests.swift; test -f "$f" || { echo FAIL; exit; }; n=$(grep -cE "^\s*func test_" "$f"); test "$n" -ge 5 || { echo "FAIL count=$n"; exit; }; echo PASS'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3510 [type: regression]
Assertion: la suite unitaire complète passe, ≥ baseline 805, TEST SUCCEEDED.
Pré-requis (exécuté en préparation, 2026-09-13):
  sh -c 'xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:ImmichSwiftUITests > /tmp/immich_offline_baseline.txt 2>&1; grep -c "Test Case .* passed" /tmp/immich_offline_baseline.txt'
  → 805 / "** TEST SUCCEEDED **"
Check post-impl: sh -c 'xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:ImmichSwiftUITests > /tmp/immich_offline_test_summary.txt 2>&1; n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_offline_test_summary.txt | grep -oE "[0-9]+" | sort -n | tail -1); grep -q "TEST SUCCEEDED" /tmp/immich_offline_test_summary.txt && test "$n" -ge 805 && echo "PASS ($n)" || echo "FAIL ($n)"'
Pre-state attendu: PASS sur la baseline (805) — le critère porte sur la suite APRÈS implémentation : ≥ 805 + tests neufs, TEST SUCCEEDED.
Post-state attendu: PASS avec n ≥ 817 (805 + ≥12 tests neufs)
```

```
### AC-3511 [type: new]
Assertion: les chaînes d'UI neuves sont au catalogue avec leur traduction FR (« Offline Storage », « Download for Offline », « Remove from Offline », « Available offline », « Clear All Offline Photos », « No offline photos »), et le catalogue n'a pas été régénéré par un build Xcode incrémental.
Check post-impl: sh -c 'f=Resources/Localizable.xcstrings; for k in "Offline Storage" "Download for Offline" "Remove from Offline" "Available offline" "Clear All Offline Photos" "No offline photos"; do jq -e --arg k "$k" ".strings[\$k].localizations.fr" "$f" >/dev/null || { echo "FAIL $k"; exit; }; done; echo PASS'
Pre-state attendu: FAIL (clés absentes)
Post-state attendu: PASS
```

```
### AC-3512 [type: new]
Assertion: preuve de bout en bout — le stub committé UITests/stubs/immich_stub_offline.py sert le handshake + timeline + GET /api/assets/{id} + GET /api/assets/{id}/original, et test_09_offlineDownload passe à la main sur le simulateur : téléchargement depuis le viewer → badge dans le timeline → écran Offline Storage → suppression.
Check post-impl: sh -c 'test -f UITests/stubs/immich_stub_offline.py && grep -qE "original" UITests/stubs/immich_stub_offline.py && grep -qE "test_09_offlineDownload" UITests/ImmichRenderScreenshots.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (stub et scénario absents)
Post-state attendu: PASS (+ sortie du run XCUITest : `test_09_offlineDownload` vert, 2 runs consécutifs)
```

## État de préparation (2026-09-13)

> **Deux checks ont été corrigés pendant l'implémentation** — ils échouaient sur un `grep -qE` appliqué à des littéraux contenant des parenthèses non échappées (`func download(`, `func downloadAsset(`), et AC-3504 ne rendait aucun verdict (ni PASS ni FAIL). Formes retenues : `grep -qF` pour un littéral, et un `echo PASS` final obligatoire. Leçon : un check jamais rejoué contre une vraie sortie est un check inexistant.

| Pré-requis | État |
|---|---|
| Baseline de régression mesurée | ✅ 805 tests, TEST SUCCEEDED (`/tmp/immich_offline_baseline.txt`) |
| Contrat API vérifié sur l'OpenAPI `main` | ✅ `GET /assets/{id}/original` |
| Spec + UI brief relus et corrigés | ✅ révision ajoutée à `.omp/offline-download/offline-download.specs.md` |
| Backlog §2.7 + tableau de suivi | ✅ mis à jour |
| Issue #18 | ✅ corps corrigé (répertoire de cache, chemin de rendu local, AC) |
| Checks d'AC exécutables | ✅ rejoués verbatim en pré-état (FAIL documenté) puis en post-état (**13/13 PASS**) |
| Ordre d'implémentation | ✅ suivi : store + downsampler + étage local → tests du store → index/VM → écran → intégrations → câblage → i18n → stub + XCUITest → suite complète |

**Outillage vérifié**
- `xcodegen` (/opt/homebrew/bin/xcodegen), projet `ImmichSwiftUI.xcodeproj`, simulateur `iPhone 17` (booté, iOS 26).
- `project.yml` déclare `sources: - path: Sources`, `- path: Tests`, `- path: UITests` : **les nouveaux fichiers et le stub `.py` sont pris automatiquement** par `xcodegen generate` — aucune liste de fichiers à éditer.
- Le stub de bout en bout se lance à la main (`python3 UITests/stubs/immich_stub_offline.py 8421`) ; les tests UI se *skippent* sans lui, donc le scheme reste vert par défaut.
- Commande de régression : `xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ImmichSwiftUITests` (~5 min).

**Ordre d'exécution recommandé** : 1–3 (store + downsampler + étage local) → 14 (tests du store, **avant** l'UI : la politique d'éviction et la réconciliation d'index se valident sans écran) → 4–5 (index + VM) → 6 (écran) → 7–10 (intégrations) → 11–12 (câblage) → 13 (i18n) → 15 (stub + XCUITest) → 16 (suite complète).

**Points de rupture possibles**
- `AuthenticatedAsyncImage` est utilisé par toutes les grilles : l'étage local doit rester strictement opt-in (`localFileURL` par défaut `nil`) pour ne rien changer aux 6 autres appelants.
- Le badge de cache lit l'environnement : si `AuthenticatedRoot` oublie l'injection, `@Environment(OfflineAssetIndex.self)` vaut `nil` et le badge disparaît **silencieusement** — d'où l'AC-3504 vérifié par XCUITest, pas par grep.
- `bytes(for:)` ne fournit pas toujours `Content-Length` (chunked) : la progression doit retomber sur une barre indéterminée, pas sur 0 % figé.
- Réglage `offlineMaxSize` : les valeurs `UserDefaults` sont des `Int` (64 bits) — pas de stockage direct d'`Int64` non convertible.
