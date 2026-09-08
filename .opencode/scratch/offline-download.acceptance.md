# Task: offline-download

Status: plan

## Plan

**Objectif**: Implémenter le téléchargement d'assets pour consultation hors-ligne. No offline cache dans ImmichSwiftUI actuellement.

**Hypothèses** (ground truth vérifié):
- `SaveToLibraryViewModel` + `SaveToLibraryView` existent (save to system camera roll via PHPhotoLibrary).
- `PhotoLibraryService` expose saveImage(data:) + saveVideo(at:).
- `AssetResponseDto` expose `originalPath` (URL pour télécharger).
- iOS 26 → `FileManager` + `URLCache` pour le cache offline.
- `PhotoViewer` a un share sheet (save to library + action sheet).

**Approche retenue**: A — `OfflineAssetStore` basé sur FileManager (pas de nouvelles deps) + `OfflineDownloadViewModel` + `OfflineAssetsView`.
**B (rejetée)**: GRDB → nouvelle dépendance.
**C (rejetée)**: Isar → couplage avec Flutter.
**D (rejetée)**: WKWebsiteDataStore → web-only.

**Étapes**:
1. NEW `OfflineAssetStore.swift` (Services/) — downloadAsset(id:,originalPath:), getCachedAsset(id:), isCached(id:), removeCachedAsset(id:), clearAllCachedAssets(), cachedAssets, CachedAssetInfo, maxCacheSize configurable.
2. NEW `OfflineDownloadViewModel.swift` (Features/Offline/) — cachedAssets, downloadAsset, removeFromOffline, clearAll, cacheUsage.
3. NEW `OfflineAssetsView.swift` (Features/Offline/) — Liste cached assets + grid + clear all + storage indicator.
4. EDIT `PhotoViewer.swift` — Ajouter "Download for offline" dans share sheet + "Available offline" banner + download progress toast.
5. EDIT `AssetThumbnailCell.swift` — Ajouter cached indicator overlay (glass checkmark circle) si asset isCached.
6. EDIT `ProfileView.swift` — Ajouter "Offline Storage" navigation link.
7. Tests — `OfflineAssetStoreTests` +5 (download, cache hit/miss, remove, clear, size limit), `OfflineDownloadViewModelTests` +3.
8. Build + suite complète.

## Acceptance Contract

### Approches candidates
**A (retenue)**: FileManager cache + OfflineAssetStore. Simple, pas de nouvelles deps, testable.
**B**: GRDB → nouvelle dépendance.
**C**: Isar → couplage.
**D**: WKWebsiteDataStore → web-only.

### Approche retenue + rationale
**A**. Cache file simple, pas de dépendance externe, compatible tests existants.

### Critères

```
### AC-3500 [type: new]
Assertion: OfflineAssetStore expose downloadAsset(id:,originalPath:), getCachedAsset(id:), isCached(id:), removeCachedAsset(id:), clearAllCachedAssets(), cachedAssets, CachedAssetInfo{id,fileName,cachedAt,size} dans Sources/Services/OfflineAssetStore.swift.
Check post-impl: sh -c 'f=Sources/Services/OfflineAssetStore.swift; test -f "$f" && grep -qE "func downloadAsset" "$f" && grep -qE "func getCachedAsset" "$f" && grep -qE "func isCached" "$f" && grep -qE "func removeCachedAsset" "$f" && grep -qE "func clearAllCachedAssets" "$f" && grep -qE "CachedAssetInfo" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3501 [type: new]
Assertion: OfflineDownloadViewModel expose cachedAssets, downloadAsset(id:,originalPath:), removeFromOffline(id:), clearAll(), cacheUsage dans Sources/Features/Offline/OfflineDownloadViewModel.swift.
Check post-impl: sh -c 'f=Sources/Features/Offline/OfflineDownloadViewModel.swift; test -f "$f" && grep -qE "var cachedAssets" "$f" && grep -qE "func downloadAsset" "$f" && grep -qE "func removeFromOffline" "$f" && grep -qE "func clearAll" "$f" && grep -qE "var cacheUsage" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3502 [type: new]
Assertion: OfflineAssetsView expose asset grid (LazyVGrid), download indicator, storage usage card, clear all dans Sources/Features/Offline/OfflineAssetsView.swift.
Check post-impl: sh -c 'f=Sources/Features/Offline/OfflineAssetsView.swift; test -f "$f" && grep -qE "cachedAssets" "$f" && grep -qE "removeFromOffline" "$f" && grep -qE "cacheUsage" "$f" && grep -qE "LazyVGrid" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3503 [type: new]
Assertion: PhotoViewer expose "Download for offline" dans share sheet/menu contextuel.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/PhotoViewer.swift; grep -qE "downloadForOffline\|Download for Offline\|offline" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3504 [type: new]
Assertion: TimelineView / AssetThumbnailCell expose cached indicator overlay (checkmark circle) quand asset.isCached == true.
Check post-impl: sh -c 'f=Sources/Features/Timeline/AssetThumbnailCell.swift; grep -qE "isCached" "$f" && grep -qE "checkmark" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3505 [type: new]
Assertion: ProfileView expose "Offline Storage" navigation link vers OfflineAssetsView.
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfileView.swift; grep -qE "Offline" "$f" && grep -qE "OfflineAssetsView" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3506 [type: new]
Assertion: OfflineAssetStoreTests expose ≥5 tests (download, cache hit, cache miss, remove, clear, size limit).
Check post-impl: sh -c 'f=Tests/OfflineAssetStoreTests.swift; test -f "$f" && n=$(grep -cE "func test_" "$f"); test "$n" -ge 5 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3507 [type: new]
Assertion: OfflineDownloadViewModel expose toast de progression pendant le téléchargement avec ProgressView.
Check post-impl: sh -c 'f=Sources/Features/Offline/OfflineDownloadViewModel.swift; grep -qE "ProgressView\|progress\|Downloading" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3508 [type: regression]
Assertion: Suite complète ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_offline_test_summary.txt && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_offline_test_summary.txt | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
