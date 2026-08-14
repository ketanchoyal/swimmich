# Task: slideshow v2 — "spectacle" + fix stop/stall

Status: plan — à implémenter (suite audit 2026-08-13)
Baseline tests: 351 (slideshow v1), source: `.opencode/memory.md` 2026-08-12.

Objectif: corriger les bugs de contrôle (impossible d'arrêter, figement vidéo-échec,
latence post-vidéo, fuite de gestes) ET donner une sensation de "spectacle"
(Photos/Apple-TV): Ken Burns, transitions soignées, chrome auto-masqué, avance
immédiate après vidéo, Live Photos animées, shuffle.

Contraintes conservées (non négociables):
- Slideshow = **overlay ZStack interne** du PhotoViewer, jamais de nouvelle couche
  de présentation (leçon 2026-08-05, cover-inside-cover = teardown crash).
- VM pur, **sans Timer ni AVFoundation** (unit-testable) — le ticker reste dans le view.
- Reduce Motion honoré (AC-019): Ken Burns et transitions désactivés → crossfade simple.
- Reduce Transparency honoré pour les surfaces glass.

---

## 1. Bugs (P0) — causes racines + fixes

### B1. "Impossible d'arrêter" — la pause ne fige pas la vidéo
Cause: `togglePlayPause()` ne gate que le ticker (`SlideshowViewModel.swift:57`).
L'AVPlayer continue → sur slide vidéo, tap pause = rien de visible.
Fix: coupler l'état pause du slideshow au `VideoPlayerView` (voir §4.3, param
`isPaused` externe). Pause → `vm.pause()` vidéo ; reprise → `vm.play()` si
`.paused` seulement.

### B2. Figement sur vidéo en échec
Cause: `slideChanged()` arme `isVideoActive = true` pour toute slide vidéo
(`SlideshowViewModel.swift:96-102`). `videoEnded()` n'est appelé que sur `.ended`
(`VideoPlayerView.swift:94-98`). Si `.failed`, `isVideoActive` reste `true` à vie
→ `advance()` no-op à jamais → slideshow bloqué, et `controlsVisible:false`
masque le Retry.
Fix: `videoEnded()` appelé sur `.ended` **et** `.failed` (on saute la vidéo
cassée, comportement Photos). Voir §4.3 `onStatusChange`.

### B3. Latence post-vidéo (frame figée jusqu'à `speed` sec)
Cause: le ticker ne poll que toutes les `speed` sec ; après `videoEnded()`,
l'avance attend jusqu'à `speed` sec (`SlideshowView.swift:56-63`).
Fix: `videoEnded()` avance **immédiatement** (Photos) — `videoEnded()` appelle
`advance()` après avoir levé `isVideoActive`. + `isVideoActive` rejoint `tickerKey`
pour ré-armer le ticker quand une slide vidéo devient active/inactive. Voir §4.1.

### B4. Gestes du PhotoViewer fuient à travers l'overlay
Cause: `dismissDrag` est un `.simultaneousGesture` sur le GeometryReader parent
(`PhotoViewer.swift:214`) qui englobe `SlideshowView`. Pendant le slideshow:
swipe-down → ferme TOUT le viewer ; swipe-up → ouvre la sheet EXIF AU-DESSUS du
slideshow (`showInfo` reste actif dessous).
Fix: le drag devient inerte quand `slideshowVM != nil`. Options (retenir A):
- A) `.simultaneousGesture(dismissDrag(...), including: slideshowVM == nil ? .all : .none)`
- B) condition dans `dismissDrag.onChanged/.onEnded` : `guard slideshowVM == nil`.

### B5. Menu vitesse chevauche le bouton next
Cause: `bottomBar` overlay `Menu` en `bottomTrailing` recouvre `chevron.right`.
Fix: déplacer la vitesse hors du chevauchement (voir §4.2 nouveau chrome).

---

## 2. Spectacle — features

### F1. Ken Burns (stills)
Zoom/pan lent et continu (scale 1.0→1.06 + translation subtile) sur les photos.
Désactivé si Reduce Motion (image statique). Nouveau composant `KenBurnsImageView`
(§4.5). Activation: style de transition `kenBurns` (F3).

### F2. Avance immédiate après vidéo
Couvre B3 — la vidéo cède la main à la slide suivante dès `.ended`.

### F3. Transitions sélectionnables
`enum SlideshowTransitionStyle` : `.dissolve` (défaut), `.slide` (directionnel),
`.kenBurns` (stills animés). Menu dans le chrome (symbole + checkmark).

### F4. Live Photos animées
Une Live Photo (`livePhotoVideoId != nil`) joue sa motion (1 boucle) comme slide,
comme une vidéo: branche `VideoPlayerView(assetID: pairID)` au lieu de
`ZoomableImageView`. `onStatusChange(.ended)` → `videoEnded()`.

### F5. Shuffle
`shuffle()` dans le VM : réordonne l'ordre de lecture (tableau d'indices) au départ
ou à la demande. Bouton `shuffle` dans le chrome.

### F6. Chrome auto-masqué
Tap = afficher/masquer le chrome (aujourd'hui `onSingleTap: {}` = tap mort).
Auto-hide après ~3 s d'inactivité. Fade in/out des contrôles (0.25–0.4 s).

### F7. Fade in/out global + haptique
Fondu noir à l'ouverture/fermeture ; `.sensoryFeedback(.selection)` au changement
de slide (optionnel, gate reduce-motion).

### F8. Durée adaptative vidéo
Slide vidéo = durée réelle du clip (via onStatusChange), pas `speed` fixe.

### F9. Progression discrète
Mini-barre ou dots en bas (optionnel, non bloquant).

---

## 3. Design (HIG / iOS 26)

- Chrome **Liquid Glass**: `GlassEffectContainer` + `.glassEffectID(_:in:)` pour un
  morphing fluide des contrôles (pas d'opacity/blur à la main). `appearsActive`
  respecté.
- Contrôles flottants minimalistes, cibles ≥ 44 pt, safe-area aware (top sous l'île,
  bottom au-dessus du home indicator).
- Vitesse : `Menu` à symboles (`tortoise.fill`/`hare.fill` ou texte "2 s/3 s/5 s/10 s")
  + checkmark, positionné SANS chevauchement (centré sous play/pause, B5).
- Transitions : crossfade long (0.6–0.8 s) ou slide 0.4 s ; Ken Burns continu.
  `.animation` scopé au plus petit sous-arbre (perf 120 Hz, pas de `withAnimation` global).
- Ken Burns via `TimelineView` (boucle continue) — pas de `Timer`, pas d'`AnyView`.
- A11y : labels existants conservés ; `accessibilityReduceMotion` → crossfade simple,
  Ken Burns off ; `accessibilityReduceTransparency` → fond solide noir.

---

## 4. Implémentation — fichier par fichier

### 4.1 `Sources/Features/PhotoViewer/SlideshowViewModel.swift`
- Supprimer `videoStarted()` (dead code) — l'armement reste via `slideChanged()`.
  Documenter : "arm point = slideChanged(), release point = videoEnded()".
- `videoEnded()` :
  ```swift
  func videoEnded() {
      isVideoActive = false
      advance() // Photos: on passe à la slide suivante dès la fin
  }
  ```
- `shuffle()` : `order = (0..<count).shuffled()` ; `currentIndex` devient l'index
  dans `order` ; `currentAsset` lit `assets[order[currentIndex]]`.
- Ajouter `enum SlideshowTransitionStyle` (dissolve/slide/kenBurns) + `var transition`.
- Conserver : clamp init, wrap, `next()/previous()` paused-autorisés, `goTo` (le
  supprimer si toujours inutilisé après refactor, sinon le brancher).
- Corriger le doc-comment périmé (ligne 7: "runs a `Timer.publish`" → `.task(id:)`).

### 4.2 `Sources/Features/PhotoViewer/SlideshowView.swift`
- **Ticker** : `tickerKey` = `"\(speed)-\(isPlaying)-\(isVideoActive)"` ; loop :
  ```swift
  .task(id: tickerKey) {
      guard vm.isPlaying, !vm.isVideoActive else { return }
      while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(vm.speed.rawValue))
          guard vm.isPlaying, !vm.isVideoActive else { return }
          vm.advance()
      }
  }
  ```
- **Contenu slide** : branche `asset.isVideo` → `VideoPlayerView(assetID:, isPaused:,
  onStatusChange:)` ; `asset.livePhotoVideoId != nil` (si F4) → `VideoPlayerView`
  du pair ; sinon `KenBurnsImageView` ou `ZoomableImageView` selon transition.
- **onStatusChange** branché : `.ended`/`.failed` → `vm.videoEnded()` ;
  `.playing` → (rien, armement via slideChanged).
- **Chrome** : `@State showControls = true` ; tap → toggle ; auto-hide via `.task`
  (3 s, annulé sur interaction). Restructurer `bottomBar` (vitesse centrée, B5).
- **Transition** : `.transition` selon `vm.transition` ; crossfade via `.opacity`,
  slide via `.move(edge:)` directionnel, kenBurns via contenu animé. Scope
  `.animation(PVMotion.adaptive(...), value: vm.currentIndex)` au Group de la slide.
- `onClose` conserve `vm.stop(); onClose()`.

### 4.3 `Sources/Features/PhotoViewer/VideoPlayerView.swift`
- Ajouter :
  ```swift
  var isPaused: Bool = false            // pause externe (slideshow)
  var onStatusChange: ((VideoPlaybackStatus) -> Void)? = nil
  ```
- `.onChange(of: isPaused)` : si `true` → `vm.pause()` ; si `false` et
  `vm.status == .paused` → `vm.play()`.
- `.onChange(of: vm.status)` : appeler `onStatusChange?(newStatus)` puis, si
  `.ended`, `onPlaybackEnded?()` (compat Live Photo existante).

### 4.4 `Sources/Features/PhotoViewer/PhotoViewer.swift`
- `presentSlideshow()` : créer le VM, **pas de `vm.start()` ici** (le view le fait
  dans `onAppear`, évite le double start).
- Isoler les gestes (B4) : désactiver `dismissDrag` quand `slideshowVM != nil`.
- Passer `transition`/`shuffle` au VM si les réglages sont persistés.

### 4.5 Nouveau `Sources/Features/PhotoViewer/KenBurnsImageView.swift`
- Wrap l'image (via `AuthenticatedAsyncImage` ou `ZoomableImageView` statique) avec
  un zoom/pan lent piloté par `TimelineView(.animation)` ; `@Environment
  (\.accessibilityReduceMotion)` → image statique (pas d'animation).
- Scope : uniquement stills, uniquement si `transition == .kenBurns`.

### 4.6 `Tests/SlideshowViewModelTests.swift`
Nouveaux tests (VM pur, pas d'AVFoundation) :
- `videoEnded_advancesImmediately` (B3).
- `videoEnded_noopWhenPaused` (la vidéo se termine mais paused → pas d'avance).
- `videoEnded_afterFailed_treatedAsEnded` (B2, simulé : `slideChanged` sur vidéo
  puis `videoEnded` → avance).
- `shuffle_preservesCountAndCoversAllIndices`.
- `transition_defaultDissolve`.

---

## 5. Critères d'acceptation (checks post-impl)

- **AC-1** (B1) : `VideoPlayerView` expose `isPaused` et l'applique (`grep -q "isPaused" VideoPlayerView.swift` + `grep -q "onChange(of: isPaused)"`).
- **AC-2** (B2/B3) : `SlideshowViewModel.videoEnded()` appelle `advance()` et
  `isVideoActive` ∈ `tickerKey` ; `onStatusChange` branché `.ended` et `.failed`.
- **AC-3** (B4) : `PhotoViewer.swift` ne déclenche pas `dismissDrag` quand
  `slideshowVM != nil` (`grep -q "slideshowVM"` dans le guard du drag).
- **AC-4** (B5) : le Menu vitesse n'est plus en overlay `bottomTrailing` recouvrant
  `chevron.right` (layout vérifié).
- **AC-5** (F3/F6) : `SlideshowTransitionStyle` existe ; `showControls` + auto-hide
  présents ; `onSingleTap` non-vide.
- **AC-6** (Ken Burns + Reduce Motion) : `KenBurnsImageView` présent ; garde
  `accessibilityReduceMotion` → statique.
- **AC-7** : suite verte, ≥ 356 tests (351 + 5 nouveaux), `TEST SUCCEEDED`.

Check générique : `xcodebuild test` (voir commande historique dans
`.opencode/memory.md` §P1 slideshow) + `grep -o "Executed [0-9]* tests" ... | sort -n | tail -1`.

---

## 6. Ordre de migration (réversible par commits atomiques)

1. B1 + B2 + B3 (contrôle vidéo correct) — VM + SlideshowView + VideoPlayerView.
2. B4 + B5 (gestes + layout).
3. F3 transitions (dissolve/slide) + F6 auto-hide chrome.
4. F1 Ken Burns + F4 Live Photos.
5. F5 shuffle + F7 haptique/fade + F9 progress.
6. Tests (4.6) après chaque étape où le VM change.

Risques: refactor `order`/`shuffle` touche `currentIndex` → garder l'API `goTo/next/
previous` stable ; le couplage pause vidéo ne doit pas rejouer une vidéo `.ended`
(reprise réservée à `.paused`).

---

## 7. Réflexion par tâche — impl (Apple/Liquid Glass), bugs anticipés, tests

Cadre transverse (appliqué partout):
- Motion optionnelle : Reduce Motion → crossfade, Ken Burns off, slide→dissolve.
- Durées standard 250–400 ms ; crossfade slideshow 0.4–0.8 s justifié.
- Pas d'`AnyView`, pas de `withAnimation` global, `.animation` scopé au plus petit sous-arbre.
- Glass uniquement via `GlassEffectContainer`/`glassEffectID`, pas de blur/opacity à la main.
- Tests en XCTest (convention repo), VM/helpers purs — jamais de Timer ni AVFoundation.

### B1 — Pause ne fige pas la vidéo
- **Impl** : `VideoPlayerView` + `var isPaused: Bool = false` ; `onChange(of: isPaused)`
  → `vm.pause()` / reprise si `.paused`. SlideshowView passe `isPaused: !vm.isPlaying`.
  HIG : un player qui tourne pendant que l'UI affiche "pause" est une violation (contrôles = état réel).
- **Bugs** : (1) course `onReady` — l'auto-play vit dans `VideoPlaybackViewModel.onReady`
  (`play()`), donc si `isPaused == true` avant `.ready`, la vidéo démarre quand même →
  gate aussi dans `onChange(of: vm.status)` (`.ready`/`.playing` && `isPaused` → `pause()`).
  (2) reprise depuis `.ended` : `play()` ne relance pas un player fini → ne reprendre que si `.paused`.
- **Tests** : helper pur `resumePolicy(status)` → unit ; transitions `pause`/`togglePlayPause` déjà couvertes.

### B2 — Figement vidéo-échec
- **Impl** : `VideoPlayerView.onChange(of: vm.status)` → `onStatusChange?(newStatus)`.
  SlideshowView : `.ended` **et** `.failed` → `vm.videoEnded()` (on saute la vidéo cassée).
  `videoEnded()` idempotent :
  ```swift
  func videoEnded() {
      let wasVideo = isVideoActive
      isVideoActive = false
      if wasVideo { advance() }
  }
  ```
- **Bugs** : double fire (`ended` puis `failed`) → `advance()` 2× → saute 2 slides ; neutralisé par `wasVideo`. `.failed` pendant `.preparing` d'un asset suivant : impossible (une vidéo à la fois via `.id(asset.id)`).
- **Tests** : `videoEnded_noopOnStillSlide` ; `videoEnded_advancesOnceWhenVideoActive` (appelé 2× → 1 seul avancement).

### B3 — Latence post-vidéo
- **Impl** : couvert par B2 (`videoEnded()` avance immédiatement). `tickerKey` =
  `"\(speed)-\(isPlaying)-\(isVideoActive)"`. Loop :
  ```swift
  .task(id: tickerKey) {
      guard vm.isPlaying, !vm.isVideoActive else { return }
      while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(vm.speed.rawValue))
          guard vm.isPlaying, !vm.isVideoActive else { return }
          vm.advance()
      }
  }
  ```
- **Bugs** : photo→vidéo : `advance()` puis `slideChanged()` arme dans le même run loop → pas de saut. vidéo→vidéo via `videoEnded().advance()` → `slideChanged()` ré-arme, nouveau player s'auto-play.
- **Tests** : `videoEnded_advancesImmediately` ; `videoEnded_noopWhenPaused`. `tickerKey` = view (manuel, ou helper pur si extrait).

### B4 — Fuite des gestes
- **Impl** : garde dans les closures (pas `GestureMask`, subtil dans `body`). `dismissDrag.onChanged/.onEnded` → `guard slideshowVM == nil else { dragOffset = .zero; return }`. `PhotoViewerSwipeDecision` intact.
- **Bugs** : oublier la garde dans un des deux handlers → `dragOffset` non remis à zéro, viewer décalé à la sortie. Le swipe-up (`openInfo`) passe par la même garde → plus de sheet EXIF au-dessus du slideshow.
- **Tests** : `PhotoViewerSwipeDecision` existants inchangés ; helper pur `shouldIgnoreViewerGestures(slideshowActive:)` si extrait, sinon manuel.

### B5 — Menu vitesse chevauche next
- **Impl** : sortir le `Menu` de l'overlay `bottomTrailing`. Bottom bar = `GlassEffectContainer`
  unique, 5 éléments en `HStack` ≥ 44 pt : `[shuffle | prev | play/pause | next | speed]`.
- **Bugs** : label `Menu` < 44 pt → `.frame(minWidth: 44, minHeight: 44)`. Garder les slots prev/next quand `count < 2` (disabled) pour éviter le saut de layout.
- **Tests** : manuel (layout). Pas de snapshot infra.

### F1 — Ken Burns
- **Impl** : `KenBurnsImageView` + `TimelineView(.animation)` → phase continue, `scaleEffect`
  1.0→1.06 + `offset` subtil, période 12–18 s. Reduce Motion → image **statique** (pas "plus lente").
  Perf 120 Hz : pas de `GeometryReader` imbriqué, image via `AuthenticatedAsyncImage` (cache), phase = struct pure.
- **Bugs** : `TimelineView` réévalue `body` chaque frame → phase triviale, chargement image hors chemin animé. Oscillation ~0.2 Hz interdite (HIG) → mouvement unidirectionnel. Slides Ken Burns non-zoomables (tap = toggle chrome) → pas de conflit pinch.
- **Tests** : `KenBurnsPhase(time:reduceMotion:)` pur → identity si `reduceMotion`, bornes `[1.0, 1.06]`, monotonie.

### F3 — Transitions sélectionnables
- **Impl** : `enum SlideshowTransitionStyle { dissolve, slide, kenBurns }` + `Menu` checkmark + `@AppStorage`.
  `dissolve` → `.transition(.opacity)` ; `slide` → `.transition(.move(edge:).combined(with: .opacity))`
  (bord selon direction). `@ViewBuilder` switch — **jamais d'`AnyView`**. Reduce Motion → force `dissolve`.
- **Bugs** : wrap last→first avec `.move(.trailing)` : direction cohérente au wrap (delta d'index, pas "index croissant"). `AnyView` interdit dans la hiérarchie animée.
- **Tests** : `slideEdge(from:to:count:)` pur → bord au wrap (last→first = trailing, first→last = leading).

### F4 — Live Photos animées
- **Impl** : `SlideContentView` — si `asset.livePhotoVideoId != nil` → `VideoPlayerView(assetID: pairID, ...)`
  comme une vidéo. Helper `isPlayableMotion(asset) = isVideo || livePhotoVideoId != nil`.
  Priorité : live photo > Ken Burns (un still avec motion ne prend pas Ken Burns).
- **Bugs** : pair absent → `prepareLivePhoto` → `.failed` → `videoEnded()` (B2). Exclusion Ken Burns via `isPlayableMotion`. `.id` du slide reste `asset.id` (pair rendu dans le même slot).
- **Tests** : `isPlayableMotion` pur (video → true, livePhotoVideoId → true, still → false).

### F5 — Shuffle
- **Impl** : `private(set) var order: [Int]` (position → index asset). `shuffle()` : mélange puis
  **repositionne le pointeur sur l'asset courant** (pas de saut) ; introuvable → clamp. `currentAsset = assets[order[currentIndex]]`.
- **Bugs** : shuffle pendant une vidéo → `.id(asset.id)` inchangé si l'asset courant est déplacé → pas de re-préparation, mais le pointeur suit. Single/empty → no-op.
- **Tests** : `shuffle_coversAllIndices`, `shuffle_preservesCurrentAsset`, `shuffle_singleAssetNoop` (invariants, pas l'ordre — aléatoire).

### F6 — Chrome auto-masqué
- **Impl** : `@State showControls = true` ; `onSingleTap` (image ET vidéo) → toggle. Auto-hide :
  `.task(id: showControls)` → 3 s → `false` ; toute interaction relance. Fade 0.25–0.4 s.
  Glass : la matière ne s'anime pas à la main ; fade du groupe via `opacity` + `glassEffectID` stable.
- **Bugs** : `Menu` ouvert pendant l'auto-hide → ne pas masquer (track interaction). Fuite timer : `.task` auto-cancel au close (`slideshowVM = nil`).
- **Tests** : manuel. Constante `autoHideDelay` triviale si extraite.

### F7 — Fade + haptique
- **Impl** : fondu noir à l'ouverture/fermeture. `.sensoryFeedback(.selection, trigger:)` sur
  **toggle play/pause uniquement** (pas à chaque slide auto).
- **Bugs** : haptique par slide à 2 s = irritant → gate. Pas de flash >3 Hz.
- **Tests** : manuel.

### F8 — Durée adaptative vidéo
- **Impl** : déjà satisfait par B2/B3 (durée réelle du clip). Option cap "advance après N s" laissée ouverte.
- **Bugs** : vidéo longue = slideshow long (attendu, documenté).
- **Tests** : couvert par B2/B3.

### F9 — Progression
- **Impl** : mini-barre (`Capsule` progress `currentIndex+1 / count`) ou dots pour petit `count`. Discrète, a11y label.
- **Bugs** : pas de flash (transition lente).
- **Tests** : manuel.
