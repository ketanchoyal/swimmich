# Task: video-playback

Status: shipped — AC-900..AC-909 PASS 2026-08-12 (336 tests, 0 failures).

## Plan

**Objectif**: Vidéo native dans PhotoViewer. Asset vidéo → page player (AVPlayer + HLS `/video/playback`), contrôles Photos-grade (play/pause, −15/+15, scrubber, replay), chrome + filmstrip + info panels conservés, auth Bearer via AVURLAssetHTTPHeaderFieldsKey. Aucun AVPlayer dans les tests unitaires (isolation: VM testée via mock engine).

**Hypothèses**:
- `ImmichAssetURL.videoPlayback(assetId:baseURL:)` existe déjà (Sources/Services/ImmichAssetURL.swift:26) — URL = `{base}/api/assets/{id}/video/playback`.
- `AssetReactItem.isVideo` = `!isImage` (Sources/Core/Types/AssetReactItem.swift:34); `duration` = secondes (Int?); format mm:ss = `AssetThumbnailCell.formattedDuration` (Sources/Features/Timeline/AssetThumbnailCell.swift:195).
- Pager = `TabView(selection:)` + `ZoomableImageView` + `.id(asset.id)` (PhotoViewer.swift:291-314) — reset d'état par page via `.id` (pattern ZoomableImageView reset).
- Middleware protocol → DI → `@Observable @MainActor` VM → view stateless; `@unchecked Sendable` pour AVPlayer (pattern ImmichAPIClient).
- Immich serve HLS (`video/playback` → m3u8, segments sous même base authentifiée) — en-tête `Authorization: Bearer` suffit via `AVURLAssetHTTPHeaderFieldsKey`.
- Pas de `videoInfo` DTO coté client (grep vide) — durées via `AssetReactItem.duration`, pas de codec/bitrate au détail (hors scope, card storage-stats/P3).

**Approche retenue**: A — Engine protocol (`VideoPlaybackEngine`) wrappant AVPlayer + `AVVideoPlaybackEngine` concret + `VideoPlaybackViewModel` @Observable @MainActor + `VideoPlayerView` SwiftUI (AVPlayerLayer UIViewRepresentable) + contrôles glass. Page pager branchée sur `asset.isVideo`. Mock engine dans tests.
**B**: `VideoPlayer` (AVKit/SwiftUI) direct dans le pager. AVKit contrôle render implicite, pas de VM → intégrable ni testable (notification end, état, erreurs), chrome iOS 26 cassé.
**C**: FullScreenCover player séparé par-dessus le viewer. Présentations sérialisées sur iOS 26 (SheetBridge crash history) — deadlock cover-over-cover.

**Étapes**:
1. `Sources/Core/Protocols/VideoPlaybackEngine.swift` — protocol (AnyObject): `prepare(url:token:) async throws`, `play()`, `pause()`, `seek(to:)`, `reload()`, `var duration: Double`, `isReady: Bool`, hooks `onTimeUpdate/onStatusChange/onEnded/onFailure` (+ getters). Enum `VideoPlaybackStatus: Sendable` {idle, preparing, ready, playing, paused, ended, failed}.
2. `Sources/Services/AVVideoPlaybackEngine.swift` — wrap AVPlayer; prepare = AVURLAsset(url, options: [AVURLAssetHTTPHeaderFieldsKey: ["Authorization": "Bearer \(token)"]]) + AVAudioSession .playback; time observer 0.5s; NotificationCenter .AVPlayerItemDidPlayToEndTime → onEnded; KVO → status.
3. `Sources/Features/PhotoViewer/VideoPlaybackViewModel.swift` — @Observable @MainActor; `init(engine: any VideoPlaybackEngine = AVVideoPlaybackEngine())`; `prepare(asset:)` construit URL via `ImmichAssetURL.videoPlayback`; `progress` 0...1, `currentTime`, `duration`, `status`, `errorMessage`; `togglePlayPause()`, `seekBy(seconds:)`, `replay()`, `retry()`.
4. `Sources/Features/PhotoViewer/VideoPlayerView.swift` — AVPlayerLayer container + overlay: spinner (preparing), play/pause capsule, −15/+15, scrubber (Slider), temps mm:ss, bouton replay sur end, retry + message sur failed. Glass chrome cohérent (PVStyle tokens, pas de couleurs brutes).
5. `PhotoViewer.swift` — pager: `if asset.isVideo { VideoPlayerView(...) } else { ZoomableImageView(...) }`; filmstrip: badge play + durée pour les vidéos (pattern AssetThumbnailCell.videoBadge).
6. `Tests/Mocks/MockVideoPlaybackEngine.swift` + `Tests/VideoPlaybackViewModelTests.swift` (+ test URL/capture préparée, pas d'AVPlayer).
7. Card checks + `xcodegen generate` (pbxproj refs explicites — leçon P0) + build + suite complète.
8. memory.md entry + report AC.

## Acceptance Contract

### Approches candidates
**A (retenue)**: engine protocol + VM @Observable + view stateless. Testable (mock), intégrable au chrome + pager, HIG/Photos-parity. AVKit `VideoPlayer` et cover-over-cover écartés (B/C ci-dessus).
**B**: AVKit VideoPlayer direct. Non testable, chrome iOS 26 fragile, fin de lecture non capturable proprement.
**C**: Cover séparé. Deadlock présentation iOS 26 (leçon SheetBridge).

### Critères

```
### AC-900 [type: new]
Assertion: Un protocole `VideoPlaybackEngine` (AnyObject, Sendable) existe dans Sources/Core/Protocols/ avec prepare(url:token:) async throws, play(), pause(), seek(to:), reload(), duration, isReady et hooks onTimeUpdate/onStatusChange/onEnded/onFailure; l'enum `VideoPlaybackStatus` (idle/preparing/ready/playing/paused/ended/failed) l'accompagne.
Check post-impl: sh -c 'f=Sources/Core/Protocols/VideoPlaybackEngine.swift; grep -qE "protocol VideoPlaybackEngine" "$f" && grep -qE "func prepare" "$f" && grep -qE "func play\(\)" "$f" && grep -qE "func pause\(\)" "$f" && grep -qE "func seek" "$f" && grep -qE "onEnded" "$f" && grep -qE "enum VideoPlaybackStatus" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier inexistant)
Post-state attendu: PASS
```

```
### AC-901 [type: new]
Assertion: AVVideoPlaybackEngine (Sources/Services/AVVideoPlaybackEngine.swift) passe le token Bearer via AVURLAssetHTTPHeaderFieldsKey ("Authorization: Bearer {token}") et configure AVAudioSession .playback.
Check post-impl: sh -c 'f=Sources/Services/AVVideoPlaybackEngine.swift; grep -qE "AVURLAssetHTTPHeaderFieldsKey" "$f" && grep -qE "Authorization" "$f" && grep -qE "AVAudioSession" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-902 [type: new]
Assertion: VideoPlaybackViewModel (@Observable @MainActor) expose status, progress (0...1), duration, currentTime, errorMessage; engine injectable via init (défaut AVVideoPlaybackEngine).
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/VideoPlaybackViewModel.swift; grep -qE "@Observable" "$f" && grep -qE "@MainActor" "$f" && grep -qE "var status" "$f" && grep -qE "var progress" "$f" && grep -qE "var duration" "$f" && grep -qE "init\(engine" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-903 [type: new]
Assertion: Le VM construit l'URL de lecture via ImmichAssetURL.videoPlayback(assetId:baseURL:) — aucun chemin "/video/playback" littéral hors ImmichAssetURL.
Check post-impl: sh -c 'grep -qE "videoPlayback\(assetId" Sources/Features/PhotoViewer/VideoPlaybackViewModel.swift && test "$(grep -rc "video/playback" Sources/Features/PhotoViewer/VideoPlaybackViewModel.swift)" -eq 0 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-904 [type: new]
Assertion: VideoPlayerView (SwiftUI) contient un UIViewRepresentable pour la couche vidéo (AVPlayerLayer) + contrôles: play/pause, seek −15/+15, scrubber Slider, temps mm:ss, replay sur ended, message + retry sur failed.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/VideoPlayerView.swift; grep -qE "UIViewRepresentable" "$f" && grep -qE "AVPlayerLayer" "$f" && grep -qE "play\(\)|pause\(\)|playPause" "$f" && grep -qE "15" "$f" && grep -qE "Slider" "$f" && grep -qE "Retry|retry" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-905 [type: new]
Assertion: Le pager du PhotoViewer branche chaque page: vidéo → VideoPlayerView, image → ZoomableImageView (branch sur asset.isVideo) + filmstrip affiche badge play + durée sur les vidéos.
Check post-impl: sh -c 'grep -qE "asset\.isVideo" Sources/Features/PhotoViewer/PhotoViewer.swift && grep -qE "VideoPlayerView" Sources/Features/PhotoViewer/PhotoViewer.swift && grep -qE "isVideo" Sources/Features/PhotoViewer/PhotoViewer.swift | grep -q filmstrip || grep -qE "filmstrip" Sources/Features/PhotoViewer/PhotoViewer.swift; t=$(grep -c "VideoPlayerView" Sources/Features/PhotoViewer/PhotoViewer.swift); test "$t" -ge 1 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-906 [type: new]
Assertion: Aucun `import AVFoundation` (ou AVKit) dans le dossier Tests/ — isolation unitaire AVPlayer (VM testée via mock).
Check post-impl: sh -c 'test "$(grep -rl "import AV" Tests/ | wc -l | tr -d " ")" -eq 0 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-907 [type: new]
Assertion: Tests VideoPlaybackViewModelTests (MockVideoPlaybackEngine) couvrent: prepare → url+token capturés (chemin /api/assets/{id}/video/playback), transitions status (preparing→ready, play→playing, pause→paused), ended → replay, failure → errorMessage, progress = timeUpdate/duration, seekBy par rapport à currentTime.
Check post-impl: sh -c 'f=Tests/VideoPlaybackViewModelTests.swift; test -f "$f" && n=$(grep -cE "func test" "$f"); test -f Tests/Mocks/MockVideoPlaybackEngine.swift && test "$n" -ge 6 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-908 [type: regression]
Assertion: Suite complète verte après implémentation, ≥ 326 tests.
Check post-impl: sh -c 'grep -E "Executed .* tests|passed" /tmp/immich_video_test_summary.txt | tail -1'
Pre-state attendu: suite P0 = 326 tests, 0 fail
Post-state attendu: PASS (≥ 326, 0 fail)
```

```
### AC-909 [type: regression]
Assertion: La mémoire projet documente la card (memory.md, tag feature) et le statut de la card passe à shipped.
Check post-impl: sh -c 'grep -q "video-playback" .opencode/scratch/video-playback.acceptance.md && grep -q "shipped" .opencode/scratch/video-playback.acceptance.md && grep -q "video-playback" .opencode/memory.md && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```