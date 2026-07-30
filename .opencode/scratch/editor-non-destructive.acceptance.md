# Task: editor-non-destructive

## Plan

### Objectif
Implémenter la feature "Édition non destructive" (cahier §5 L117-130) pour PhotoVault. Éditeur Core Image reconstruit façon Photos.app : crop (grille tiers + ratios), rotation fine, ajustements lumière/couleur, état non-destructif local persisté en JSON, bouton "Revenir à l'original".

### Hypothèses (vérifiées specialist fichier:ligne)
- Aucun `import CoreImage`/`CIFilter` dans Sources/ actuellement → feature neuve.
- `AssetDetailView` toolbar vide (`Sources/Features/AssetDetail/AssetDetailView.swift:28-30`) → ajout bouton Edit.
- `AssetDetailViewModel` @Observable @MainActor, `asset: AssetReactItem`, `detail: AssetResponseDto?`.
- `ImmichAssetURL.original(assetId:baseURL:)` → `/api/assets/:id/original` (`Sources/Services/ImmichAssetURL.swift:21`). Récupération full-res auth via Bearer token.
- `ImmichAPIClient.token` + `baseURL` accessibles (`Sources/Services/ImmichAPIClient.swift:39-40`). Pattern injectable: `ImmichAPIClient(session:)` + `CapturingURLProtocol` (`Tests/ImmichAPIClientTests.swift:5-61`).
- `AuthenticatedAsyncImage` utilise `ImageCache.shared` + Bearer header.
- `AssetReactItem.id` (String) + `ratio` (Double) ; `AssetResponseDto.isEdited` (Bool) ; `width`/`height` (Int?).
- `JSONEncoder.immich` / `JSONDecoder.immich` disponibles (`Sources/Services/JSONCoding.swift:7-13`).
- `project.yml` auto-discover Sources/ + Tests/. iOS 17.0, SWIFT_STRICT_CONCURRENCY=minimal.
- Suite existante : **110 tests verts** (post-Albums). Pas 101.

### Décisions de scope (trim MVP session)
1. **INCLUDE** : crop (grille des tiers + ratios prédéfinis), rotation fine (-45°..+45° slider + boutons 90° CW/CCW), ajustements (exposure/contrast/saturation/warmth via CIFilter), état non-destructif local (EditState Codable JSON), bouton "Revenir à l'original", persistance locale keyed by assetId, entry depuis AssetDetailView bouton Edit.
2. **DEFER V1.5** : redressement automatique de l'horizon (cahier L121 MVP mais nécessite Vision/CoreML horizon detection, lourd, hors budget session). Rotation manuelle slider + boutons couvre l'usage principal.
3. **DEFER V2** : filtres prédéfinis avec aperçus miniatures (L124 V2), sync serveur (L128 V2), export/save-to-camera-roll (L125 "jamais ré-encodage tant que non exporté" → MVP ne ré-encode jamais, preview live CIFilter uniquement).
4. **DEFER V3** : retouche locale au pinceau (L127 V3).

### Approches candidates
- **A — SwiftUI natif + CIContext VM** (retenue) : VM détient CIContext Metal-backed, après chaque mutation EditState recalcule pipeline CIFilter → UIImage publié via @Observable → Image(uiImage:). Crop via GeometryReader + DragGesture pur SwiftUI. Persistance Codable EditState → actor EditStateStore (Application Support). Rationale : aligné codebase 100% SwiftUI, testable (pipeline = fonction pure `(CIImage, EditState) -> CIImage`), perf suffisante (CIContext.createCGImage < 8ms sur A15+ pour 12MP), budget session.
- **B — MTKView UIViewRepresentable** : perf max garantie mais UIViewRepresentable + state bridging délicat, désaligne codebase, double budget. Rejetée.
- **C — CIContext.render + debounce manuel** : similaire A mais throttling Task explicite. Redondant (SwiftUI onChange débatche déjà). Rejetée.

### Approche retenue + rationale
**A — SwiftUI natif + CIContext VM**. Alignement codebase, testabilité maximale (pipeline pure-func), perf suffisante, budget session maîtrisé.

### Étapes d'implémentation
1. NEW `Sources/Core/Types/EditState.swift` — `struct EditState: Codable, Equatable, Sendable` (cropRect: CGRect? [NORMALIZED 0..1 relatif à l'extent ORIGINAL], orientationSteps: Int [0/1/2/3 = 0°/90°/180°/270°], straightenDeg: Double [-45,+45], aspectRatio: CropAspectRatio?, exposure: Double, contrast: Double, saturation: Double, warmth: Double) + `static let neutral` + `var hasEdits: Bool` + `var totalRotationDeg: Double { straightenDeg + Double(orientationSteps % 4) * 90 }`. `enum CropAspectRatio: String, CaseIterable, Codable, Sendable { freeform, square, fourByThree, threeByTwo, twoByThree, sixteenByNine, nineBySixteen; var value: CGFloat? }`. NOTE: orientationSteps (boutons 90°) et straightenDeg (slider fin) sont DES contrôles INDÉPENDANTS façon Photos.app (pas de clobber). hasEdits = cropRect!=nil || orientationSteps!=0 || straightenDeg!=0 || aspectRatio!=nil || exposure!=0 || contrast!=0 || saturation!=0 || warmth!=0.
2. NEW `Sources/Core/Utilities/EditPipeline.swift` — DEUX fonctions NON-isolées (pure-func, testable) :
   - `func buildEditFilters(for state: EditState) -> [CIFilter]` — retourne tableau de CIFilter dans l'ordre déterministe : exposure(CIExposureAdjust EV) → color(CIColorControls UNIQUE avec inputContrast + inputSaturation combinés) → warmth(CITemperatureAndTint neutral→temp). Neutral values → filtre omis du tableau (vide si .neutral). Testable par `filter.filterName()` names + count.
   - `func applyEditState(to image: CIImage, state: EditState) -> CIImage` — wrapper : applique buildEditFilters séquentiellement, PUIS crop (CICrop avec cropRect converti normalized→pixel sur l'extent ORIGINAL courant si cropRect!=nil, sinon pas de crop) — NOTE: conversion normalized→pixel DOIT flipper l'axe Y (origine CoreImage = bottom-left, origine UIKit = top-left ; normalized.y_pixel = (1 - normalized.y - normalized.height) * imageHeight), PUIS rotate (CGAffineTransform rotation totale = state.totalRotationDeg autour du centre du crop si cropRect!=nil, SINON autour du centre de l'extent original). Ordre final : **filters → crop → rotate** (crop dans espace original-normalized, rotate du résultat cropé). Neutral state = identity (output extent == input extent, pas de filtre/crop/rotate).
3. NEW `Sources/Services/EditStateStore.swift` — `actor EditStateStore` : dossier Application Support `/EditStates/`. `save(state:forAssetId:)`, `load(assetId:) -> EditState?`, `delete(assetId:)`, `resetAll()`. JSON via JSONEncoder.immich.
4. NEW `Sources/Features/Editor/PhotoEditorViewModel.swift` — `@Observable @MainActor`. Props assetId, originalImage UIImage?, previewImage UIImage?, editState EditState, isLoading, errorMessage String?, **`urlSession: URLSession = .shared` (injectable pour tests — pattern ImmichAPIClient(session:) `ImmichAPIClientTests.swift:5-61` via CapturingURLProtocol)**. CIContext lazy Metal-backed. `loadOriginal(url:token:)` async via `urlSession.data(for:)` + Bearer, set originalImage, sur erreur (401/timeout/UIImage nil) set errorMessage. `renderPreview()` recalcule pipeline → UIImage. Mutators setExposure/setContrast/setSaturation/setWarmth/setStraighten/setCropRect/setAspectRatio/resetToOriginal + rotate90CW()/rotate90CCW() (chacun mute editState + renderPreview). `saveState()`/`loadState()` via EditStateStore. `func gestureRectToNormalized(_ rect: CGRect, in displaySize: CGSize) -> CGRect` (pure helper, délègue à EditPipeline ou local) pour conversion View→state.
5. NEW `Sources/Features/Editor/PhotoEditorView.swift` — SwiftUI. GeometryReader crop zone + RuleOfThirdsOverlay (Path 3×3) + DragGesture corners. RotationSliderView (slider -45..+45 + boutons 90°). AdjustmentSlidersView (4 sliders). CropAspectPickerView (HStack ratios). Bouton "Revenir à l'original" disabled quand !hasEdits. `.task` loadOriginal + loadState, `.onDisappear` saveState.
6. EDIT `Sources/Features/AssetDetail/AssetDetailView.swift` — bouton toolbar "Edit" (slider.horizontal.3) + NavigationLink → PhotoEditorView.
7. EDIT `Sources/DependencyContainer.swift` — `makePhotoEditorViewModel(asset:)`.
8. NEW `Tests/EditStateTests.swift` — AC-600, 601, 602, 603, 607.
9. NEW `Tests/EditorViewModelTests.swift` — AC-604, 605, 606, 608, 609, 610, 611, 612, 616.
10. `xcodegen generate` + build + test.

## Acceptance Contract

### Approches candidates
(Voir Plan ci-dessus.)

### Approche retenue + rationale
A — SwiftUI natif + CIContext VM.

### Critères

```
### AC-600 [type: new]
Assertion: EditState est Codable, Equatable, Sendable avec champs cropRect: CGRect?, orientationSteps: Int, straightenDeg: Double, aspectRatio: CropAspectRatio?, exposure: Double, contrast: Double, saturation: Double, warmth: Double. static let neutral produit état sans édition (cropRect=nil, orientationSteps=0, straightenDeg=0, adjustments=0.0). var totalRotationDeg: Double = straightenDeg + Double(orientationSteps % 4) * 90.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditStateTests/test_AC_600_neutral_state -only-testing:ImmichSwiftUITests/EditStateTests/test_AC_600_roundtrip -only-testing:ImmichSwiftUITests/EditStateTests/test_AC_600_totalRotationDeg
Pre-state attendu: new — 0 tests ran (EditState n'existe pas).
Post-state attendu: new — 3 tests pass (neutral champs + JSON encode→decode == original + totalRotationDeg calcul pour 0/1/2/3 steps + straighten).
```

```
### AC-601 [type: new]
Assertion: CropAspectRatio enum a cas freeform/square/fourByThree/threeByTwo/twoByThree/sixteenByNine/nineBySixteen, est CaseIterable+Codable+Sendable. var value: CGFloat? retourne nil pour freeform, 1.0 square, 4.0/3.0 fourByThree, 3.0/2.0 threeByTwo, 2.0/3.0 twoByThree, 16.0/9.0 sixteenByNine, 9.0/16.0 nineBySixteen.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditStateTests/test_AC_601_cropRatioValues
Pre-state attendu: new — 0 tests.
Post-state attendu: new — 1 test pass (tous cas → bon CGFloat).
```

```
### AC-602 [type: new]
Assertion: EditState.hasEdits retourne true si cropRect!=nil || orientationSteps!=0 || straightenDeg!=0 || aspectRatio!=nil || exposure!=0 || contrast!=0 || saturation!=0 || warmth!=0. Retourne false pour .neutral.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditStateTests/test_AC_602_hasEdits_neutral_false -only-testing:ImmichSwiftUITests/EditStateTests/test_AC_602_hasEdits_each_field_true
Pre-state attendu: new — 0 tests.
Post-state attendu: new — 2 tests pass (neutral false + chaque champ modifié true, incluant orientationSteps=1 et straightenDeg=5).
```

```
### AC-603 [type: new]
Assertion: EditStateStore (actor) persiste/charge EditState par assetId. Dossier Application Support /EditStates/. save(state:forAssetId:) écrit JSON. load(assetId:) décode ou retourne nil si absent. delete(assetId:) supprime. resetAll() vide le dossier.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditStateTests/test_AC_603_save_load_roundtrip -only-testing:ImmichSwiftUITests/EditStateTests/test_AC_603_load_nonexistent_nil -only-testing:ImmichSwiftUITests/EditStateTests/test_AC_603_delete
Pre-state attendu: new — 0 tests.
Post-state attendu: new — 3 tests pass (roundtrip Equatable + absent nil + delete).
```

```
### AC-604 [type: new]
Assertion: PhotoEditorViewModel @Observable @MainActor. Props assetId, originalImage UIImage?, previewImage UIImage?, editState EditState, isLoading Bool. loadOriginal(url:token:) charge full-res via URLSession+Bearer, set originalImage. CIContext Metal-backed lazy. Après chaque mutation editState, renderPreview() met à jour previewImage.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_604_loadOriginal_success -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_604_mutation_triggers_render
Pre-state attendu: new — 0 tests.
Post-state attendu: new — 2 tests pass (load via URLProtocol mock + mutation → previewImage non-nil/mis-à-jour).
```

```
### AC-605 [type: new]
Assertion: Mutateurs setExposure/setContrast/setSaturation/setWarmth/setStraighten/setCropRect/setAspectRatio/resetToOriginal + rotate90CW()/rotate90CCW() modifient editState et déclenchent renderPreview. setAspectRatio ajuste cropRect pour préserver centre dans nouveau ratio. rotate90CW incrémente orientationSteps (mod 4), rotate90CCW décrémente.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_605_all_mutators
Pre-state attendu: new — 0 tests.
Post-state attendu: new — 1 test pass (tous mutateurs testés : setStraighten straightenDeg=10, rotate90CW orientationSteps 0→1→2→3→0, rotate90CCW 0→3, setCropRect/exposure/etc chacun modifie son champ + renderCounter incrémenté).
```

```
### AC-606 [type: new]
Assertion: resetToOriginal() remet editState à .neutral (cropRect=nil, orientationSteps=0, straightenDeg=0, adjustments=0). previewImage reflète original. hasEdits devient false.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_606_resetToOriginal
Pre-state attendu: new — 0 tests.
Post-state attendu: new — 1 test pass (state == .neutral + hasEdits == false après modifications préalables incluant rotate90 + crop).
```

```
### AC-607 [type: new]
Assertion: buildEditFilters(for state: EditState) -> [CIFilter] NON-isolée pure-func retourne tableau dans ordre déterministe : exposure(CIExposureAdjust) → contrast(CIColorControls) → saturation(CIColorControls) → warmth(CITemperatureAndTint). Neutral values → filtre omis (tableau vide pour .neutral). applyEditState(to:state:) wrapper applique buildEditFilters séquentiellement PUIS crop (CICrop cropRect normalized→pixel sur extent) PUIS rotate (totalRotationDeg autour centre crop). Neutral state = identity (output extent == input extent). Test vérifie (a) filter.filterName() chain names dans l'ordre pour state non-neutral, (b) tableau vide pour .neutral, (c) applyEditState neutral identity (extent inchangé).
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditStateTests/test_AC_607_buildFilters_chain_order -only-testing:ImmichSwiftUITests/EditStateTests/test_AC_607_buildFilters_neutral_empty -only-testing:ImmichSwiftUITests/EditStateTests/test_AC_607_applyEditState_neutral_identity
Pre-state attendu: new — 0 tests.
Post-state attendu: new — 3 tests pass (filter names ordre + neutral empty array + applyEditState extent inchangé pour .neutral).
```

```
### AC-608 [type: new]
Assertion: PhotoEditorViewModel expose var isGridVisible: Bool (true quand editState.aspectRatio != nil OU editState.cropRect != nil, i.e. mode crop actif). La grille des tiers (RuleOfThirdsOverlay) est rendue quand isGridVisible == true.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_608_grid_visibility_logic && grep -c "RuleOfThirdsOverlay" Sources/Features/Editor/PhotoEditorView.swift | xargs test 1 -le
Pre-state attendu: new — 0 tests + grep 0.
Post-state attendu: new — 1 test pass (logique isGridVisible) + grep ≥1 (overlay référencé dans la vue).
```

```
### AC-609 [type: new]
Assertion: VM expose rotate90CW() (orientationSteps = (orientationSteps+1) % 4) et rotate90CCW() (orientationSteps = (orientationSteps+3) % 4). setStraighten(Double) clamp straightenDeg dans [-45, +45]. orientationSteps et straightenDeg SONT INDÉPENDANTS (rotate90 ne touche pas straightenDeg, setStraighten ne touche pas orientationSteps — pas de clobber). totalRotationDeg = straightenDeg + orientationSteps*90.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_609_rotate90_cw -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_609_rotate90_ccw -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_609_setStraighten_clamped -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_609_rotate90_straighten_independent
Pre-state attendu: new — 0 tests.
Post-state attendu: new — 4 tests pass (rotate90 cycle 0→1→2→3→0 + setStraighten clamp + indépendance : rotate90 après setStraighten(20) garde straightenDeg==20).
```

```
### AC-610 [type: new]
Assertion: Mutateurs acceptent ranges : setExposure [-2.0, +2.0], setContrast [-1.0, +1.0], setSaturation [-1.0, +1.0], setWarmth [-1.0, +1.0]. Clamp appliqué si valeur hors range.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_610_adjustment_ranges_clamped
Pre-state attendu: new — 0 tests.
Post-state attendu: new — 1 test pass (valeur > max clampée, valeur < min clampée).
```

```
### AC-611 [type: new]
Assertion: setAspectRatio(CropAspectRatio) set editState.aspectRatio et réajuste cropRect au centre selon ratio.value. nil value (freeform) → cropRect libre.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_611_setAspectRatio_adjusts_crop
Pre-state attendu: new — 0 tests.
Post-state attendu: new — 1 test pass (square → cropRect carré centré sur original extent).
```

```
### AC-612 [type: new]
Assertion: var canRevert: Bool retourne editState.hasEdits. PhotoEditorView bouton "Revenir à l'original" .disabled(!vm.canRevert).
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_612_canRevert && grep -c "Revenir à l'original\|resetToOriginal" Sources/Features/Editor/PhotoEditorView.swift | xargs test 1 -le
Pre-state attendu: new — 0 tests + grep 0.
Post-state attendu: new — 1 test pass + grep ≥1.
```

```
### AC-613 [type: new]
Assertion: AssetDetailView affiche bouton "Edit" toolbar (icône slider.horizontal.3). NavigationLink pousse PhotoEditorView dans NavigationStack existant.
Check post-impl: grep -c "PhotoEditorView" Sources/Features/AssetDetail/AssetDetailView.swift | xargs test 1 -le
Pre-state attendu: new — grep 0.
Post-state attendu: new — grep ≥1.
```

```
### AC-614 [type: regression]
Assertion: Suite existante (110 tests post-Albums) reste verte après ajout Editor.
Check post-impl: xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
Pre-state attendu: regression — 110 tests passent, TEST SUCCEEDED.
Post-state attendu: regression — ~141 tests nominaux (110 existants + ~31 nouveaux Editor: AC-600×3 + 601 + 602×2 + 603×3 + 604×2 + 605 + 606 + 607×3 + 608 + 609×4 + 610 + 611 + 612 + 613 + 615 + 616×3 + 617×3 + 618 + 619), TEST SUCCEEDED, 0 failure.
```

```
### AC-615 [type: new]
Assertion: DependencyContainer.makePhotoEditorViewModel(asset:) retourne PhotoEditorViewModel avec client + editStateStore (partagé).
Check post-impl: grep -c "makePhotoEditorViewModel" Sources/DependencyContainer.swift | xargs test 1 -le
Pre-state attendu: new — grep 0.
Post-state attendu: new — grep ≥1.
```

```
### AC-616 [type: new]
Assertion: PhotoEditorViewModel.saveState() persiste editState via EditStateStore.save(state:forAssetId:assetId) si hasEdits, SINON appelle store.delete(assetId:) (préserve garantie "Revenir à l'original" au-delà du kill d'app — évite fichier orphelin résiduel). loadState() charge via store.load(assetId:) et set editState (si non-nil) puis renderPreview.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_616_save_state_persists -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_616_load_state_restores -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_616_neutral_deletes_persisted
Pre-state attendu: new — 0 tests.
Post-state attendu: new — 3 tests pass (save+reload Equatable, load absent nil, reset→save→load == .neutral via delete).
```

```
### AC-617 [type: new]
Assertion: loadOriginal(url:token:) gère les erreurs réseau : (a) HTTP 401/403 → errorMessage set, originalImage nil, isLoading false ; (b) données non-image (HTML/JSON) UIImage(data:)→nil → errorMessage set ; (c) timeout/erreur réseau → errorMessage set. VM ne crash jamais. previewImage reste nil tant que originalImage nil.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_617_loadOriginal_401_error -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_617_loadOriginal_invalid_data -only-testing:ImmichSwiftUITests/EditorViewModelTests/test_AC_617_loadOriginal_network_error
Pre-state attendu: new — 0 tests.
Post-state attendu: new — 3 tests pass (via URLProtocol mock injectant 401 + data HTML + erreur URLError ; errorMessage non-nil + originalImage nil pour chacun).
```

```
### AC-618 [type: new]
Assertion: Pure helper `func gestureRectToNormalized(_ gestureRect: CGRect, in displaySize: CGSize) -> CGRect` divise origin/size par displaySize → CGRect normalized 0..1. Testable sans UI (VM ou EditPipeline). Vérifie : gestureRect pleine largeur displaySize → normalized (0,0,1,1). gestureRect moitié → (0,0,0.5,0.5).
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditStateTests/test_AC_618_gestureRectToNormalized
Pre-state attendu: new — 0 tests.
Post-state attendu: new — 1 test pass (3 cas : full, half, quarter).
```

```
### AC-619 [type: new]
Assertion: applyEditState avec cropRect normalized non-nil + rotation non-zéro produit un CIImage d'extent attendu. Test: input CIImage extent 1000×1000 (origine 0,0), state = cropRect (0.2, 0.2, 0.6, 0.6) + straightenDeg 0 + orientationSteps 1 (90°). Output extent attendu : largeur=600 (crop hauteur 600), hauteur=600 (crop largeur 600), rotation 90° → extent 600×600 (rotation 90° de carré = même dimension). Test affirme `output.extent.width ≈ 600 && output.extent.height ≈ 600` (tolérance 1pt). Valide (a) conversion normalized→pixel CICrop correcte, (b) rotation appliquée après crop, (c) coordonnées CoreImage respectées.
Check post-impl: xcodebuild test -only-testing:ImmichSwiftUITests/EditStateTests/test_AC_619_crop_plus_rotate_extent
Pre-state attendu: new — 0 tests.
Post-state attendu: new — 1 test pass (extent attendu pour crop carré 600×600 + rotation 90° = 600×600 ; test séparé avec rotation 45° vérifie extent ≈ 849×849 (600*sqrt(2)) ).
```

### Failure modes (top 3 + quel AC les détecte)
- **FM-1** Pipeline CIFilter ordre incorrect → rendu visuel faux. Détecté: AC-607 (buildEditFilters filter-name chain order + neutral empty + applyEditState neutral identity).
- **FM-2** EditState JSON corrompu/incomplet après roundtrip → perte silencieuse edits. Détecté: AC-603 (roundtrip Equatable exact) + AC-600 (roundtrip + totalRotationDeg).
- **FM-3** resetToOriginal partiel → champ résiduel. Détecté: AC-606 (state == .neutral + hasEdits false après rotate90+crop+adjustments).
- **FM-4** cropRect coordinate space ambigu (normalized vs pixel). RÉSOLU: cropRect stocké en NORMALIZED 0..1 relatif à l'extent ORIGINAL. Conversion normalized→pixel faite dans applyEditState au moment du CICrop. Helper AC-618 teste la conversion gesture→normalized.
- **FM-5** rotate+crop interaction : RÉSOLU par ordre pipeline **filters → crop → rotate**. cropRect en espace original-normalized (appliqué AVANT rotation sur l'extent original), rotate du résultat cropé (centre rotation = centre crop). Plus de conversion post-rotation nécessaire. orientationSteps (90°) et straightenDeg (slider fin) séparés (pas de clobber — AC-609 indépendance).
- **FM-6 (pré-mortem)** loadOriginal réseau échoue (401/timeout/data invalide) → spinner infini ou crash. RÉSOLU: errorMessage set, originalImage nil, previewImage nil. Détecté: AC-617.

## Vérifications manuelles (hors auto-feedback loop)
- Fluidité sliders : drag exposure/contrast → preview suit sans lag >1 frame à 60fps.
- Précision crop pixel : crop carré sur image 4000×3000 → rendu exactement carré.
- Gesture UX crop : drag coin = resize, drag centre = translate, gestures exclusives.
- Perf render : image 12MP, renderPreview < 20ms, CPU < 50% sur drag rapide (iPhone 15+).
- Rotation visuelle : slider -45° tourne autour centre sans clipping ; bouton 90° CW = rotation exacte ; orientation+straighten combinés (ex: 90° + 10° straighten) rendent correctement.
- Grille des tiers : apparence identique éditeur Photos (lignes blanches semi-transparentes ~1pt).
- Bouton Revenir : crop+saturation → Revenir → image revient instantanément original.
- Persistance app kill : éditer, fermer app, relancer, ouvrir même asset → état restauré.
- Navigation : AssetDetail → Edit → Back → AssetDetail (original affiché, pas ré-encodage).
- Erreur réseau : éditer asset inaccessible (serveur off) → message d'erreur affiché, pas de crash.

## Concerns résolus en loop 1 (historique)
1. ~~AC-607 pixel-test fragilité~~ → RÉSOLU: buildEditFilters retourne [CIFilter] testable par filterName(), applyEditState neutral identity testé par extent (pas pixel).
2. ~~cropRect coordinate space (FM-4)~~ → RÉSOLU: normalized 0..1 original, conversion au render. AC-618 helper.
3. ~~rotate+crop interaction (FM-5)~~ → RÉSOLU: ordre filters→crop→rotate, cropRect espace original.
4. Test count 110 (pas 101) — AC-614 corrigé.
5. Simulator iPhone 17 Pro (pas iPhone 16) — cohérence projet.
6. ~~loadOriginal réseau en VM (MVVM smell)~~ → ACCEPTÉ: URLSession direct acceptable (pas de service partagé full-res). errorMessage set sur erreur (AC-617).
7. ~~angleDeg clobber rotate90 vs slider (S1)~~ → RÉSOLU: séparation orientationSteps + straightenDeg (AC-609 indépendance).
