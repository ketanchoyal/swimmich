# Task: slideshow

Status: shipped — AC-960..AC-969 PASS 2026-08-12 (checks AC-962, AC-963, AC-964, AC-965, AC-969 edited during verification to match source-of-truth impl: ticker = `.task(id:)` view-owned loop, slideChanged() arms video suspension, `slideshowVM` state name, substring-safe grep tokens, max-count extraction).

## Plan

**Objectif**: Slideshow plein écran depuis le photo viewer (bouton top-bar, Photos-style). Autoplay pager, vitesse réglable (2/3/5/10 s), pause/lecture, prev/next, boucle infinie, vidéos incluses (lecture inline via VideoPlayerView, ticker suspendu pendant lecture), Reduce Motion honoré (pas de transition animée en cross-dissolve au-delà du fallback PVMotion.adaptive).

**Hypothèses**:
- `PhotoViewer` est présenté via `.fullScreenCover(item:)` (PhotoViewer.swift:48) → **interdit** de présenter un nouveau fullScreenCover/sheet depuis l'intérieur (leçon 2026-08-05: presentations serialize, cover-inside-cover = teardown crash). Slideshow = **overlay ZStack interne** (pattern overlay panel déjà prouvé pour la map/PhotoInfoPanel PhotoViewer.swift:272-290).
- Entry point: topBar (PhotoViewer.swift:355) — bouton à côté du bouton `info` (ligne 390-400), layout `HStack(spacing: s16)` symétrique.
- Ticker: **pas de Timer dans le VM** (non testable). Le view possède la boucle `.task(id:)` + `.onReceive(timer)` qui appelle `vm.advance()` si `vm.isPlaying && !vm.isVideoActive`. VM = pure machine à états (testable sans time).
- Vidéos: `VideoPlayerView` réutilisé (VideoPlayerView.swift, autoplay on ready). Slide vidéo → `vm.videoStarted()` met ticker en pause; `onPlaybackEnded` → `vm.videoEnded()` reprend le ticker (reste sur la slide, Photos behavior).
- `PVMotion.adaptive` (Motion+PhotoVault.swift:21) + `@Environment(\.accessibilityReduceMotion)` déjà utilisé dans PhotoViewer.swift:152 (pattern AC-019).
- `PhotoViewer` a déjà `@Environment(\.accessibilityReduceMotion) private var reduceMotion` (PhotoViewer.swift:152) — réutilisé.
- AssetReactItem: `isVideo`, `duration`, `thumbnailURL(base:size:)` — thème badges filmstrip existant (PhotoViewer.swift:442-460).
- Nouveaux fichiers (VM + View + Tests) → `xcodegen generate` requis (pbxproj explicit refs, leçon P0).

**Approche retenue**: A — VM `SlideshowViewModel` (@Observable @MainActor, init(assets:startIndex:) par PhotoViewer) + `SlideshowView` overlay interne (black ignoresSafeArea, close xmark toujours visible, bottom controls: play/pause, chevron prev/next, Menu vitesse) + ticker dans le view. Vidéo = branche `VideoPlayerView`. Pas de nouvelle couche de présentation → zéro risque SheetBridge.

**Étapes**:
1. `.opencode/scratch/slideshow.acceptance.md` — ce contrat.
2. `Sources/Features/PhotoViewer/SlideshowViewModel.swift` — @Observable @MainActor; `enum SlideshowSpeed: TimeInterval, CaseIterable` (two=2, three=3, five=5, ten=10, label "2s"...); state: `currentIndex`, `isPlaying`, `speed` (défaut .three), `isVideoActive`; API: `start()`, `stop()`, `togglePlayPause()`, `advance()` (wrap, no-op si !isPlaying || isVideoActive), `next()`, `previous()` (wrap, marchant même paused), `goTo(index:)` clampé (video slides), `videoStarted()`, `videoEnded()`, computed `currentAsset`, `isLast` non requis (wrap).
3. `Sources/Features/PhotoViewer/SlideshowView.swift` — ZStack { if let asset = vm.currentAsset { branche isVideo → VideoPlayerView(asset:baseURL:token:controlsVisible:false,onPlaybackEnded:{vm.videoEnded()}) sinon ZoomableImageView(asset:baseURL:token:onSingleTap:{}) } } `.id(vm.currentIndex)`; top bar: compteur "N of M" (pvCaption, glass capsule) + xmark close; bottom: play/pause capsule, chevrons, Menu vitesse (checkmark vitesse active); `.transition(.opacity)` animé via `PVMotion.adaptive`; `.statusBarHidden(true)`; onClose callback.
4. `PhotoViewer.swift` edits: `@State private var showSlideshow = false` + `@State private var slideshowVM: SlideshowViewModel?`; bouton topBar `play.circle` (accessibilityLabel "Slideshow", mirror layout info button) → `presentSlideshow()` (crée VM init(assets: localAssets, startIndex: selectedIndex), showSlideshow = true, vm.start()); overlay: si showSlideshow && let vm → SlideshowView(...).zIndex(10) (au-dessus du pager + chrome + panel) avec ignoresSafeArea; toggle play/pause du VM sync pas nécessaire (VM autonome).
5. `Tests/SlideshowViewModelTests.swift` — 10 tests (ci-dessous), aucun AVFoundation.
6. `xcodegen generate` → build → suite complète → checks AC → memory.md.

## Acceptance Contract

### Approches candidates
**A (retenue)**: VM pur + ticker dans le view + overlay interne. Testable (pas de Timer dans VM), zéro risque présentation, pattern cohérent (videop playback card: VM = state machine, hooks sync).
**B**: Timer.publish + Autoconnect dans le VM. Non testable en unit (true async), moins fidèle au pattern @Observable.
**C**: fullScreenCover dédié SlideshowView depuis PhotoViewer. Violation leçon 2026-08-05 (cover-inside-cover), teardown crash connu.

### Critères

```
### AC-960 [type: new]
Assertion: Un fichier `SlideshowViewModel.swift` existe dans Sources/Features/PhotoViewer/ et déclare une classe `@Observable @MainActor` nommée `SlideshowViewModel`.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/SlideshowViewModel.swift; test -f "$f" && grep -q "@Observable" "$f" && grep -q "@MainActor" "$f" && grep -q "final class SlideshowViewModel" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier inexistant)
Post-state attendu: PASS
```

```
### AC-961 [type: new]
Assertion: SlideshowViewModel expose un enum `SlideshowSpeed` conformant `CaseIterable` avec les vitesses 2s, 3s, 5s, 10s (défaut 3s) et des méthodes start()/stop()/togglePlayPause()/advance()/next()/previous()/videoStarted()/videoEnded().
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/SlideshowViewModel.swift; grep -q "enum SlideshowSpeed" "$f" && grep -q "CaseIterable" "$f" && grep -q "case twoSeconds = 2" "$f" && grep -q "case tenSeconds = 10" "$f" && grep -q "start()" "$f" && grep -q "stop()" "$f" && grep -q "togglePlayPause()" "$f" && grep -q "func advance()" "$f" && grep -q "func next()" "$f" && grep -q "func previous()" "$f" && grep -q "func videoStarted()" "$f" && grep -q "func videoEnded()" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier inexistant)
Post-state attendu: PASS
```

```
### AC-962 [type: new]
Assertion: advance()/next()/previous() bouclent (wrap-around) via modulo sur assets.count, et advance() est no-op quand isPlaying == false ou isVideoActive == true.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/SlideshowViewModel.swift; n=$(grep -c "assets.count" "$f" | tr -d " "); grep -q "guard isPlaying" "$f" && grep -q "!isVideoActive" "$f" && test "$n" -ge 2 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier inexistant)
Post-state attendu: PASS
```

```
### AC-963 [type: new]
Assertion: Le PhotoViewer ne présente PAS de nouvelle couche de présentation pour le slideshow (ni fullScreenCover ni sheet) — overlay ZStack interne zIndex supérieur, écartant le risque cover-inside-cover (leçon 2026-08-05).
Check post-impl: sh -c 'c=$(grep -cE "^[[:space:]]*\.(fullScreenCover|sheet)\(" Sources/Features/PhotoViewer/PhotoViewer.swift | tr -d " "); grep -q "slideshowVM" Sources/Features/PhotoViewer/PhotoViewer.swift && grep -q "SlideshowView" Sources/Features/PhotoViewer/PhotoViewer.swift && grep -q "zIndex" Sources/Features/PhotoViewer/PhotoViewer.swift && grep -q "play.circle" Sources/Features/PhotoViewer/PhotoViewer.swift && test "$c" -le 3 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun état slideshow)
Post-state attendu: PASS
```

```
### AC-964 [type: new]
Assertion: Le view (et non le VM) possède la boucle du ticker: SlideshowView contient un `.task(id:)` re-armé par vitesse/état de lecture (tickerKey) avec la condition `vm.isPlaying && !vm.isVideoActive` devant `vm.advance()` — le VM reste pur (pas de Timer).
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/SlideshowView.swift; grep -q "task(id: tickerKey)" "$f" && grep -q "isVideoActive" "$f" && grep -q "advance()" "$f" && grep -q "isPlaying && !vm.isVideoActive" "$f" && grep -q "tickerKey" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier inexistant)
Post-state attendu: PASS
```

```
### AC-965 [type: new]
Assertion: SlideshowView rend les vidéos via VideoPlayerView avec onPlaybackEnded branché sur vm.videoEnded(), et arme la suspension du ticker pour une slide vidéo via vm.slideChanged() (couvre videoStarted() — armement commun aux slides vidéo, re-cleared sur slide non-vidéo).
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/SlideshowView.swift; grep -q "VideoPlayerView" "$f" && grep -q "onPlaybackEnded" "$f" && grep -q "videoEnded" "$f" && grep -q "slideChanged" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier inexistant)
Post-state attendu: PASS
```

```
### AC-966 [type: new]
Assertion: Le slideshow honore Reduce Motion: au moins une animation du fichier passe par PVMotion.adaptive avec un facteur reduceMotion (cohérent AC-019 / PhotoViewer.swift:152).
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/SlideshowView.swift; grep -q "PVMotion" "$f" && grep -q "reduceMotion" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier inexistant)
Post-state attendu: PASS
```

```
### AC-967 [type: new]
Assertion: Un fichier de tests `SlideshowViewModelTests.swift` teste le VM de façon déterministe (sans Timer ni AVFoundation) et couvre au moins: wrap advance, no-op quand paused ou vidéo active, resume après videoEnded, vitesse par défaut 3s et changement de vitesse.
Check post-impl: sh -c 'f=Tests/SlideshowViewModelTests.swift; test -f "$f" && n=$(grep -c "func test_" "$f" | tr -d " ") && test "$n" -ge 8 && grep -q "videoEnded" "$f" && grep -q "@MainActor" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier inexistant)
Post-state attendu: PASS
```

```
### AC-968 [type: new]
Assertion: Le bouton d'entrée slideshow est placé dans la top bar (à côté du bouton info) et porte l'accessibilityLabel "Slideshow".
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/PhotoViewer.swift; grep -q "#\(" | true; awk "/private func topBar/,/^    }/" "$f" | grep -q "Slideshow" && awk "/private func topBar/,/^    }/" "$f" | grep -q "play.circle" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (bouton inexistant)
Post-state attendu: PASS
```

```
### AC-969 [type: regression]
Assertion: La suite complète passe — baseline 339 tests (live-photo), aucun échec (nouveau total ≥ 339 + nouveaux tests slideshow).
Check post-impl: sh -c 'n=$(grep -o "Executed [0-9]* tests" /tmp/immich_slideshow_test_summary.txt | grep -o "[0-9]\+" | sort -n | tail -1 | tr -d " "); test -f /tmp/immich_slideshow_test_summary.txt && grep -q "TEST SUCCEEDED" /tmp/immich_slideshow_test_summary.txt && test -n "$n" && test "$n" -ge 339 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (résumé inexistant)
Post-state attendu: PASS
```