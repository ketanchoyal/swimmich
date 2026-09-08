# Task: live-photo

Status: shipped — AC-950..AC-956 PASS 2026-08-12 (339 tests, 0 failures). AC-954 check fixé: impl destructure `let pairID` avant `assetID: pairID`.

## Plan
**Objectif**: Afficher + lire les Live Photos (paire image + vidéo) comme l'app Flutter : badge "LIVE" sur la grille, lecture de la paire vidéo dans le viewer. Upload multipart livePhotoVideoId déjà supporté (ImmichAPIClient.swift:343).

**Hypothèses**:
- `AssetReactItem.livePhotoVideoId: String?` existe (AssetReactItem.swift:26) — clé de la paire.
- `VideoPlaybackViewModel.prepare(asset:baseURL:token:)` (VideoPlaybackViewModel.swift:44) construit l'URL via `ImmichAssetURL.videoPlayback(assetId:)` en réutilisant `asset.id` — pour la paire il faut l'ID vidéo (livePhotoVideoId).
- `VideoPlayerView` (VideoPlayerView.swift) prépare sur `asset.id` dans onAppear (:82) + Retry (:192) — besoin d'un override d'ID.
- Pager PhotoViewer: branche `asset.isVideo` (:295) — ajouter branche paire live photo.
- AssetThumbnailCell badges: material-pill (:149), badges existants favorite/projection/video — ajouter badge LIVE bottomLeading (Apple Photos: label "LIVE" bas-gauche).
- Aucun nouveau fichier source → pas de xcodegen.

**Approche retenue**: A — Réutiliser l'engine vidéo AVPlayer existant via un override d'assetID dans `VideoPlayerView` + nouvelle `prepare(assetID:)` dans le VM. Viewer: `livePlayingIDs: Set<String>` par page; overlay bouton "LIVE" (tap → lecture paire, re-tap/pause fin → retour photo). Badge grille "LIVE" bottomLeading. Upload: champ déjà supporté, passer à P2 (backup-engine) pour l'extraction PHAsset des paires.
**B**: Nouvelles classes LivePhotoEngine + LivePhotoViewModel. Redondant — l'engine vidéo est générique (URL + token), rien n'est vidéo-spécifique.
**C**: Lecture plein écran `PHLivePhoto` téléchargé. Nécessite téléchargement paire complète (heavy), pas de HLS, UX moins native.

**Étapes**:
1. `VideoPlaybackViewModel`: refactor `prepare(asset:)` → délègue à nouvelle `prepare(assetID:baseURL:token:)` (URL via ImmichAssetURL.videoPlayback, aucun littéral de chemin — AC-951). Ajouter `prepareLivePhoto(asset:baseURL:token:)`: guard pair non-nil/non-vide sinon `.failed(...)` (AC-952).
2. `VideoPlayerView`: `var assetID: String? = nil` (override paire), `var onPlaybackEnded: (() -> Void)? = nil`; onAppear/Retry utilisent `assetID ?? asset.id`; `.onChange(of: vm.status)` → `.ended` déclenche `onPlaybackEnded` (AC-953).
3. `PhotoViewer.swift`: `@State livePlayingIDs: Set<String>`; pager: branche `asset.livePhotoVideoId != nil && livePlayingIDs.contains` → VideoPlayerView(assetID: paire, onPlaybackEnded: remove); branche photo → ZStack ZoomableImageView + overlay LIVE (bouton capsule bottom, toggle lecture); `.onChange(of: selectedIndex)` → removeAll (AC-954).
4. `AssetThumbnailCell`: badge LIVE (Text "LIVE", capsule existante, bottomLeading, caché en selectionMode) quand `livePhotoVideoId != nil` (AC-950).
5. Tests `VideoPlaybackViewModelTests`: test_P1_livePhoto_* (paire → URL pair id; prepare(assetID:) override; paire manquante → failed sans engine.prepare) (AC-955).
6. Build + suite complète (baseline ≥ 336 verts) → /tmp/immich_live_photo_test_summary.txt (AC-956).
7. Card status shipped + entrée memory.md.

## Acceptance Contract

### Approches candidates
**A (retenue)**: Réutilisation AVPlayer existant (override assetID + Set état viewer). Pas de nouveau fichier source, pas de nouveau framework, pattern pager déjà en place (video-playback).
**B**: Engine/VM Live Photo dédiés. Redondance pure — aucune logique vidéo spécifique.
**C**: PHLivePhoto téléchargé. Heavy (paire complète), HLS perdu, artefacts iOS 26 inutiles.

### Approche retenue + rationale
**A**. Le viewer sait déjà lire l'URL `/assets/{id}/video/playback` avec token — les Live Photos ne sont qu'un cas particulier d'ID. État `livePlayingIDs` par page = swap still↔player reversibles. Badge grille = même traitement material-pill que video/favorite/360°.

### Critères

```
### AC-950 [type: new]
Assertion: AssetThumbnailCell affiche un badge "LIVE" (bottomLeading, capsule) quand asset.livePhotoVideoId != nil, masqué en selectionMode.
Check post-impl: sh -c 'f=Sources/Features/Timeline/AssetThumbnailCell.swift; grep -q "LIVE" "$f" && grep -q "livePhotoVideoId != nil" "$f" && grep -q "bottomLeading" "$f" && grep -q "!selectionMode" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun badge LIVE)
Post-state attendu: PASS
```

```
### AC-951 [type: new]
Assertion: VideoPlaybackViewModel expose prepare(assetID:baseURL:token:) construisant l'URL via ImmichAssetURL.videoPlayback sans littéral "/video/playback" dans le fichier VM.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/VideoPlaybackViewModel.swift; grep -q "func prepare(assetID: String, baseURL: URL, token: String?)" "$f" && grep -q "ImmichAssetURL.videoPlayback" "$f" && ! grep -q "video/playback" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (prepare(asset:) construit via asset.id; aucun assetID param)
Post-state attendu: PASS
```

```
### AC-952 [type: new]
Assertion: prepareLivePhoto échoue en .failed amont (message non vide) quand asset.livePhotoVideoId est nil, sans appeler engine.prepare.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/VideoPlaybackViewModel.swift; grep -q "func prepareLivePhoto" "$f" && grep -q ".failed(" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-953 [type: new]
Assertion: VideoPlayerView accepte assetID override + onPlaybackEnded closure (utilise assetID ?? asset.id; .ended → onPlaybackEnded).
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/VideoPlayerView.swift; grep -q "var assetID: String?" "$f" && grep -q "onPlaybackEnded" "$f" && grep -q "assetID ?? asset.id" "$f" && grep -q ".onChange(of: vm.status)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun override/closure)
Post-state attendu: PASS
```

```
### AC-954 [type: new]
Assertion: PhotoViewer maintient livePlayingIDs (Set<String>), branche pager paire live → VideoPlayerView(assetID: pairID, onPlaybackEnded: remove), overlay bouton LIVE de re-bascule, reset livePlayingIDs au changement de page.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/PhotoViewer.swift; grep -q "livePlayingIDs" "$f" && grep -q "assetID: pairID" "$f" && grep -q "onPlaybackEnded" "$f" && grep -q "livePlayingIDs.removeAll()" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune lecture live)
Post-state attendu: PASS
```

```
### AC-955 [type: new]
Assertion: Tests video-playback étendus avec test_P1_livePhoto_pairUsesPairAssetID (URL = id paire), test_P1_livePhoto_prepareByID_override, test_P1_livePhoto_missingPair_fails (failed sans prepare).
Check post-impl: sh -c 'f=Tests/VideoPlaybackViewModelTests.swift; grep -q "test_P1_livePhoto_pairUsesPairAssetID" "$f" && grep -q "test_P1_livePhoto_prepareByID" "$f" && grep -q "test_P1_livePhoto_missingPair_fails" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-956 [type: regression]
Assertion: Suite complète verte ≥ 336 tests (baseline video-playback), résumé copié dans /tmp/immich_live_photo_test_summary.txt.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_live_photo_test_summary.txt && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_live_photo_test_summary.txt | grep -oE "[0-9]+"); test "${n:-0}" -ge 336 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```