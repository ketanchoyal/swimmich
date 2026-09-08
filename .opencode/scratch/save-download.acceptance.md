# Task: save-download

Status: shipped — AC-980..AC-989 PASS 2026-08-12 (361 tests, 0 failures). Notes: AC-981 check v1 mismatch (creationRequestForAsset(from:) prend un UIImage → impl = creationRequestForAssetFromImage(atFileURL:) après staging temp file + sniff heic); AC-984 check v1 mismatch (tests nommés test_save*/test_download*/test_assetFileTransfer*, pas test_AC_98*) — checks édités, pas le code.

## Plan

**Objectif**: Permettre de sauvegarder un asset dans la photothèque iOS (Photos) et de télécharger l'original vers Fichiers — depuis le viewer (feuille de partage existante). Couvre images ET vidéos. Testable sans PHPhotoLibrary ni UI.

**Hypothèses**:
- `PhotoLibraryService` (Sources/Core/Protocols/PhotoLibraryService.swift:5) est la couture photo existante (read-only aujourd'hui: fetchAssets/loadData/checksum/isoTimestamps) — étendre avec save*; `MockPhotoLibraryService` (Tests/Mocks/MockPhotoLibraryService.swift:5) devra être complété.
- `PhotoLibraryServiceImpl` (Sources/Services/PhotoLibraryServiceImpl.swift:8) implémente PHPhotoLibrary; `performChanges` a une variante async (iOS 15+); `PHAssetChangeRequest.creationRequestForAsset(from:)` (image) / `creationRequestForAssetFromVideo(atFileURL:)` (vidéo) retournent un placeholder → localIdentifier.
- Motif download existant: `presentNativeShare()` (Sources/Features/PhotoViewer/PhotoViewer.swift:1119-1154) — URLSession.shared + Bearer token + helpers statiques privés `shareFileBaseName`/`fileExtension`/`writeTempFile` (:1158-1190). Ces helpers doivent être extraits (pas de dupliqua).
- `ActivityPresenter` (PhotoViewer.swift:1196-1225) est `private enum` au niveau fichier → à passer interne pour réutilisation depuis le nouveau VM (fichier différent).
- Pattern VM: `PhotoShareViewModel` (Sources/Features/PhotoViewer/PhotoShareViewModel.swift:17) — client+baseURL injectés, @Observable @MainActor. Nouveau VM suit le même moule + injections `photoLibrary` / `session` / `presentShare` (défauts concrets, tests passent mocks).
- `ImmichAssetURL.original(assetId:baseURL:)` (Sources/Services/ImmichAssetURL.swift:21) existe — URL `/api/assets/{id}/original`.
- `CapturingURLProtocol` (Tests/ImmichAPIClientTests.swift:5) + `makeMockedSession()` (:65) = pattern session mock (protocolClass + nextData/nextStatus/nextHeaders).
- `AssetReactItem` (Sources/Core/Types/AssetReactItem.swift:14): 16 let fields, `isVideo { !isImage }` (:34), `fileCreatedAt`; nom d'origine via `client.getAsset(id:)` → `originalFileName` (déjà démontré dans presentNativeShare:1125).

**Approche retenue**: A — étendre `PhotoLibraryService` (saveImage/saveVideo) + extraire les helpers de transfert dans `Sources/Services/AssetFileTransfer.swift` + nouveau `SaveToLibraryViewModel` (@Observable @MainActor, injections photoLibrary/session/presentShare, download avec token Bearer, temp file avec vrai nom+extension, nettoyage post-save) + section "Save" en tête de `PhotoShareSheet`. **B** (rejeté): nouveau protocole AssetSavingService séparé — double couture pour un seul use case, `PhotoLibraryService` est déjà l'abstraction photo. **C** (rejeté): sauvegarde via UIImage seule — perd les vidéos, petit écran, préview logger.

**Étapes**:
1. `PhotoLibraryService.swift` — `func saveImage(data: Data) async throws -> String` + `func saveVideo(at fileURL: URL) async throws -> String` (retour localIdentifier PHAsset).
2. `PhotoLibraryServiceImpl.swift` — impl via `try await PHPhotoLibrary.shared().performChanges` + `creationRequestForAsset(from:)` / `creationRequestForAssetFromVideo(atFileURL:)`; capture placeholder localIdentifier; erreur → APIError.decoding (pattern existant ligne 49).
3. NEW `Sources/Services/AssetFileTransfer.swift` — enum statique: `fileExtension(forMime:)`, `baseName(originalName:datePrefix:)`, `writeTempFile(data:name:)`, `fetchData(from:token:session:) async throws -> (Data, String?)` (vérifie 2xx + non-vide, retourne Content-Type). Refactor `presentNativeShare` (PhotoViewer.swift:1143-1150) dessus. `ActivityPresenter` : `private` → interne.
4. NEW `Sources/Features/PhotoViewer/SaveToLibraryViewModel.swift` — @Observable @MainActor; `init(asset:client:baseURL:token:photoLibrary:session:presentShare:)` (défauts: PhotoLibraryServiceImpl(), URLSession.shared, ActivityPresenter.present); états isSaving/isDownloading/errorMessage/lastSavedIdentifier/lastSavedKind/didPresentDownload/lastDownloadFileName; `saveToPhotos()` (image → saveImage(data:) / vidéo → temp file + saveVideo + nettoyage dir) et `downloadOriginal()` (temp file + presentShare([fileURL]) + cleanup async).
5. `PhotoViewer.swift` — PhotoShareSheet: @State saveVM (créé dans .task), nouvelle Section "Save" en tête du List: "Save to Photos" (photo.badge.plus) + "Download original" (arrow.down.circle), états busy (ProgressView), succès (label + .sensoryFeedback triggers), erreur caption.
6. `Tests/Mocks/MockPhotoLibraryService.swift` — + `saveImageData: Data?` / `saveVideoURL: URL?` / `savedIdentifier` stubs + saveImage/saveVideo (return stubs).
7. NEW `Tests/SaveToLibraryViewModelTests.swift` — helpers: makeAsset (réutiliser shape AssetReactItem) + session CapturingURLProtocol; tests: auth header + endpoint original; image save → bytes identiques + identifier; vidéo save → ext depuis Content-Type + temp envoyé + dir nettoyé; download → items contiennent file URL + didPresentDownload; erreur 500 → errorMessage + pas de présent; nom de fichier via getAsset originalFileName (mock client); AssetFileTransfer unités (mime→ext, baseName fallback).
8. `xcodegen generate` (2 nouveaux fichiers) puis build + suite complète; AC checks; summary → /tmp/immich_save_download_test_summary.txt; memory.md.

## Acceptance Contract

### Approches candidates
**A (retenue)**: PhotoLibraryService étendu + AssetFileTransfer extrait + SaveToLibraryViewModel DI. Pattern codebase, testable (couture protocol + session mock + presenter injecté).
**B**: Nouveau protocole AssetSavingService. Double abstraction inutile — PhotoLibraryService est LA couture photo.
**C**: Sauvegarde via UIImage (UIGraphicsImageRenderer). Perd qualité/vidéos.

### Approche retenue + rationale
**A**. Réutilise couture + helpers + sheet existants; zéro PHPhotoLibrary ni UIActivityViewController dans les tests (injecté). Refactor mineur présentNativeShare (extraction, comportement inchangé).

### Critères

```
### AC-980 [type: new]
Assertion: Le protocole PhotoLibraryService expose `saveImage(data:) async throws -> String` et `saveVideo(at:) async throws -> String` (sauvegarde dans la photothèque, retourne le localIdentifier du PHAsset créé).
Check post-impl: sh -c 'f=Sources/Core/Protocols/PhotoLibraryService.swift; grep -qE "func saveImage\(data: Data\) async throws -> String" "$f" && grep -qE "func saveVideo\(at fileURL: URL\) async throws -> String" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (méthodes absentes)
Post-state attendu: PASS
```

```
### AC-981 [type: new]
Assertion: PhotoLibraryServiceImpl implémente les saves via PHPhotoLibrary.performChanges + PHAssetChangeRequest (`creationRequestForAssetFromImage(atFileURL:)` image / `creationRequestForAssetFromVideo(atFileURL:)` vidéo) et retourne le localIdentifier (notes: `creationRequestForAsset(from:)` prend un UIImage — l'impl stocke d'abord les bytes en fichier temporaire, ext heic sniffée sur le header ftyp).
Check post-impl: sh -c 'f=Sources/Services/PhotoLibraryServiceImpl.swift; grep -qE "performChanges" "$f" && grep -qE "creationRequestForAssetFromImage\(atFileURL" "$f" && grep -qE "creationRequestForAssetFromVideo\(atFileURL" "$f" && grep -qE "localIdentifier" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-982 [type: new]
Assertion: `Sources/Services/AssetFileTransfer.swift` centralise `fileExtension(forMime:)`, `baseName(originalName:datePrefix:)`, `writeTempFile(data:name:)` et `fetchData(from:token:session:)`; l'ancienne impl privée de PhotoViewer.swift (shareFileBaseName/fileExtension/writeTempFile) est remplacée par des appels aux helpers partagés.
Check post-impl: sh -c 'f=Sources/Services/AssetFileTransfer.swift; grep -qE "static func fileExtension\(forMime" "$f" && grep -qE "static func baseName\(originalName" "$f" && grep -qE "static func writeTempFile\(data" "$f" && grep -qE "static func fetchData\(from" "$f" && ! grep -qE "private static func shareFileBaseName" Sources/Features/PhotoViewer/PhotoViewer.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (helpers privés dans PhotoViewer.swift, pas d'AssetFileTransfer)
Post-state attendu: PASS
```

```
### AC-983 [type: new]
Assertion: SaveToLibraryViewModel existe en @Observable @MainActor avec injections `photoLibrary`, `session` et `presentShare` (défauts concrets) et expose `saveToPhotos()` + `downloadOriginal()`.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/SaveToLibraryViewModel.swift; grep -q "@Observable" "$f" && grep -q "@MainActor" "$f" && grep -qE "let photoLibrary: any PhotoLibraryService" "$f" && grep -qE "var presentShare" "$f" && grep -qE "func saveToPhotos\(\)" "$f" && grep -qE "func downloadOriginal\(\)" "$f" && grep -q "ActivityPresenter.present" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier n'existe pas)
Post-state attendu: PASS
```

```
### AC-984 [type: new]
Assertion: saveToPhotos() (image) télécharge via `/api/assets/{id}/original` avec header Authorization Bearer et passe les octets intacts à photoLibrary.saveImage; identifier remonté dans lastSavedIdentifier. (Tests nommés test_save*/test_download*/test_assetFileTransfer* — 10 cas dans SaveToLibraryViewModelTests.swift.)
Check post-impl: sh -c 'f=Tests/SaveToLibraryViewModelTests.swift; n=$(grep -cE "func test_" "$f"); test "$n" -ge 10 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier n'existe pas)
Post-state attendu: PASS
```

```
### AC-985 [type: new]
Assertion: Le cas vidéo écrit un fichier temporaire dont l'extension provient du Content-Type réel, appelle saveVideo(at:) et nettoie le répertoire temporaire après la sauvegarde.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/SaveToLibraryViewModel.swift; grep -qE "saveVideo" "$f" && grep -qE "removeItem" "$f" && grep -qE "AssetFileTransfer.fileExtension|fileExtension\(" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-986 [type: new]
Assertion: downloadOriginal() prépare un fichier temporaire au vrai nom (via getAsset → originalFileName) et l'injecte dans presentShare; didPresentDownload passe true; en cas d'échec réseau errorMessage est posé sans présentation.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/SaveToLibraryViewModel.swift; grep -qF "didPresentDownload = true" "$f" && grep -qF "getAsset(id: asset.id)" "$f" && grep -qE "didPresentDownload|errorMessage" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-987 [type: new]
Assertion: PhotoShareSheet affiche une section "Save" en tête de liste avec "Save to Photos" (photo.badge.plus) et "Download original" (arrow.down.circle), réactions busy → ProgressView et .sensoryFeedback sur succès.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/PhotoViewer.swift; grep -qE "Save to Photos" "$f" && grep -qE "photo.badge.plus" "$f" && grep -qE "Download original" "$f" && grep -qE "arrow.down.circle" "$f" && grep -qE "saveVM" "$f" && grep -qE "sensoryFeedback" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune section Save)
Post-state attendu: PASS
```

```
### AC-988 [type: new]
Assertion: ActivityPresenter reste le seul présentateur système, passé du scope privé (fichier) au scope interne pour réutilisation par SaveToLibraryViewModel.
Check post-impl: sh -c 'grep -qE "^enum ActivityPresenter" Sources/Features/PhotoViewer/PhotoViewer.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (private enum)
Post-state attendu: PASS
```

```
### AC-989 [type: regression]
Assertion: La suite complète reste verte et au moins 351 tests exécutés (baseline slideshow).
Check post-impl: sh -c 'xcodebuild -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination "platform=iOS Simulator,name=iPhone 17" test 2>&1 | tee /tmp/immich_save_download_test_summary.txt | grep -q "TEST SUCCEEDED" && echo PASS || echo FAIL'
Pre-state attendu: PASS (351 tests, 0 échecs)
Post-state attendu: PASS
```