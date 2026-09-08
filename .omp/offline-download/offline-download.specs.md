# Task: offline-download

**Objectif** : Implémenter le téléchargement d'assets pour consultation hors-ligne (parité Flutter). ImmichSwiftUI n'a pas de cache offline des assets — `getAsset` récupère toujours le fichier depuis le serveur. Le Flutter utilise Isar (SQLite locale) pour stocker les assets téléchargés.

**Hypothèses** :
- `SaveToLibraryViewModel.swift` + `SaveToLibraryView` existent déjà pour sauvegarder dans la bibliothèque photo système (PHPhotoLibrary).
- `PhotoLibraryService` protocol (Core/Protocols/) expose `saveImage(data:)` + `saveVideo(at:)` — mais c'est la bibliothèque système, pas un cache offline.
- `KeychainStore` (Core/Protocols/) gère le token. On pourrait utiliser un mécanisme similaire pour un cache local.
- `AssetResponseDto` expose `originalPath` — URL pour télécharger l'asset original.
- iOS 26 — `WKWebsiteDataStore` + `URLCache` ou un custom SQLite cache.
- Le Flutter utilise Isar (SQLite multi-platform). On peut utiliser `SQLite.swift` ou `GRDB` ou un `FileManager` + `URLSession` cache.
- `SaveToLibraryViewModel` est déjà utilisé dans le viewer — on peut le réutiliser comme base.

**Approche retenue** : A — un `OfflineAssetStore` basé sur `FileManager` + `URLCache` (simple, pas de nouveau dependency) avec un `OfflineDownloadViewModel` dédié. Sync manuel (pas automatique).
- **B (rejetée)** : GRDB (nouveau dependency). On veut éviter les nouvelles deps si `FileManager` suffit.
- **C (rejetée)** : utilisation de `WKWebsiteDataStore` (web-only). Pas adapté pour une app photo.
- **D (rejetée)** : Isar (même que Flutter). Trop de dépendance platform-specific.

## Étapes

1. **OfflineAssetStore** — NEW `Sources/Services/OfflineAssetStore.swift` :
   - `downloadAsset(id: String, originalPath: String) async throws` — télécharge depuis le serveur dans un cache local (`FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appPathComponent("offline_assets/{id}")`).
   - `getCachedAsset(id: String) async throws -> Data` — lit depuis le cache local.
   - `isCached(id: String) -> Bool` — vérifie si l'asset est en cache.
   - `removeCachedAsset(id: String)` — supprime du cache.
   - `clearAllCachedAssets()` — nettoie tout le cache.
   - `cachedAssets: [CachedAssetInfo]` — liste des assets en cache.
   - `CachedAssetInfo` : `id`, `fileName`, `cachedAt`, `size` bytes.
   - Cache max size configurable (UserDefaults "offlineMaxSize" — par défaut 5GB).
2. **OfflineDownloadViewModel** — NEW `Sources/Features/Offline/OfflineDownloadViewModel.swift` :
   - `var cachedAssets: [CachedAssetInfo]` — liste des assets téléchargés.
   - `func downloadAsset(id: String, originalPath: String) async throws` — call store.
   - `func removeFromOffline(id: String)` — supprime du cache.
   - `func clearAll()` — supprime tout.
   - `var cacheUsage: Int64` — espace utilisé.
3. **OfflineAssetsView** — NEW `Sources/Features/Offline/OfflineAssetsView.swift` :
   - Liste des assets en cache avec vignettes.
   - Bouton "Download for offline" dans le viewer → call downloadAsset.
   - Bouton "Remove from offline" sur chaque asset.
   - Indicateur de stockage utilisé vs limite.
   - Bouton "Clear all offline assets".
4. **Viewer integration** — Ajouter un bouton "Download for offline" dans le share sheet du PhotoViewer (ou un bouton séparé en plus de "Save to library").
5. **Timeline integration** — Indicateur visuel (icône cloud/téléchargé) sur chaque asset en timeline.
6. **Tests** — `OfflineAssetStoreTests` (download, cache hit/miss, remove, clear, size limit), `OfflineDownloadViewModelTests`.
7. **xcodegen + suite**.

## Acceptance Contract

### Approches candidates
**A (retenue)** : FileManager cache + OfflineAssetStore offline. Simple, pas de nouvelles deps, testable.
**B** : GRDB. Nouvelle dépendance.
**C** : Isar. Couplage avec Flutter.
**D** : WKWebsiteDataStore. Web only.

### Approche retenue + rationale
**A**. Cache file simple, pas de dépendance externe, compatible avec le système de tests existant (mock FileManager). Parity Flutter mais plus simple.

### Critères

```
### AC-OF01 [type: new]
Assertion: OfflineAssetStore existe (NEW file) avec downloadAsset, getCachedAsset, isCached, removeCachedAsset, clearAll, cachedAssets, CacheUsage.
Check post-impl: sh -c 'f=Sources/Services/OfflineAssetStore.swift; test -f "$f" && grep -q "func downloadAsset" "$f" && grep -q "func getCachedAsset" "$f" && grep -q "func isCached" "$f" && grep -q "func clearAllCachedAssets" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-OF02 [type: new]
Assertion: OfflineDownloadViewModel expose cachedAssets, downloadAsset, removeFromOffline, clearAll, cacheUsage.
Check post-impl: sh -c 'f=Sources/Features/Offline/OfflineDownloadViewModel.swift; test -f "$f" && grep -q "func downloadAsset" "$f" && grep -q "func removeFromOffline" "$f" && grep -q "var cacheUsage" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-OF03 [type: new]
Assertion: OfflineAssetsView existe avec liste assets + download button + remove + storage indicator.
Check post-impl: sh -c 'f=Sources/Features/Offline/OfflineAssetsView.swift; test -f "$f" && grep -q "cachedAssets" "$f" && grep -q "removeFromOffline\|removeCached" "$f" && grep -q "cacheUsage" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-OF04 [type: new]
Assertion: PhotoViewer (PhotoViewer.swift) intègre un bouton "Download for offline" (en plus de Save to library).
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/PhotoViewer.swift; grep -q "offline\|Offline" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-OF05 [type: new]
Assertion: Timeline (TimelineView.swift) affiche un indicateur visuel sur les assets en cache offline.
Check post-impl: sh -c 'f=Sources/Features/Timeline/TimelineView.swift; grep -q "cached\|offline" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-OF06 [type: new]
Assertion: Tests OfflineAssetStoreTests ≥ 5 tests (download, cache-hit, miss, remove, clear).
Check post-impl: sh -c 'f=Tests/OfflineAssetStoreTests.swift; test -f "$f" && n=$(grep -c "func test_" "$f"); test "$n" -ge 5 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-OF07 [type: regression]
Assertion: Suite ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_offline_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_offline_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
