# Task: map-extras

Status: shipped — AC-1020..AC-1026 PASS 2026-08-12. Check edits (not code): AC-1021 réécrit en ciblant PhotoViewer.swift (openInMaps vit là, pas dans PhotoInfoPanel), AC-1023 token `lastUpdateBody = body` (pas lastUpdateAssetBody). Suite 372 → 376 green.

## Plan

**Objectif**: Extras carte (cahier §5) — (1) "Open in Maps" depuis le panneau EXIF (lancement Apple Plans via `MKMapItem.openInMaps`, coordonnées EXIF → fallback bucket), (2) "Adjust Location" — feuille avec carte interactive à épingle draggable réglant la position de l'asset via PATCH `/api/assets/:id` (UpdateAssetDto.latitude/longitude), (3) re-geocoding du lieu après réglage.

**Hypothèses** (ground truth vérifié lecture):
- `PhotoInfoPanel` (Sources/Features/PhotoViewer/PhotoInfoPanel.swift:8-23) a UN SEUL call site: PhotoViewer.swift:285 — extension sûre sans défaut cassant (params optionnels à défaut nil → boutons cachés si non câblés).
- `ExifInfoPanel` (PhotoInfoPanel.swift:157-162) contient `whereCard` (:207-227) avec lat = `exif.latitude ?? fallbackLatitude`, lon = `exif.longitude ?? fallbackLongitude` + `MiniMapView` non interactif (:360-407, isUserInteractionEnabled=false).
- `AssetDetailViewModel` (Sources/Features/AssetDetail/AssetDetailViewModel.swift:6-77): `geocoded` guard `@ObservationIgnored private var` (:25), `reverseGeocodeIfNeeded()` privée (:47-61) — reset `geocoded=false` avant re-requête pour re-geocoder après changement de position. `lastUpdateBody`/`lastUpdateAssetId` captures (:28-29) pattern AC-010.
- `UpdateAssetDto` (DTOs.swift:206-215): `var latitude: Double?`/`longitude: Double?` — PATCH omit-nil.
- `MockImmichClient.updateAsset` (:278-289): bump + globalError + captures lastUpdateAssetId/lastUpdateAssetBody/lastUpdateMethod=.PATCH + `updateAssetResponse ?? echo getAsset (isFavorite togglé)`.
- `MockLocationGeocoding` (Tests/Mocks/MockLocationGeocoding.swift:6): callCount + result/error injectable.
- PhotoViewer racine: `fullScreenCover(item: $item)` :49; déjà DEUX `.sheet` coexistants (presentEdit :266, presentShare :271) → 3e sheet (presentAdjustLocation) suit le pattern prouvé (SheetBridge lessons = vues éphémères/thumbnails, pas racine viewer).
- Top bar viewer :380-451; info panel MARK :594; boutons oùCard à insérer sous MiniMapView.

**Approche retenue**: A — vieux pattern: callbacks optionnels sur ExifInfoPanel/PhotoInfoPanel (`onOpenInMaps`, `onAdjustLocation`), `MKMapItem.openInMaps()` direct (pas de service — pas de test unitaire possible sur le lancer système, testabilité portée par closure câblée + VM), `AdjustLocationSheet` (nouveau fichier, UIViewRepresentable `DraggablePinMapView` marqueur draggable + boutons Cancel/Save) présentée en 3e sheet racine viewer, `AssetDetailViewModel.setLocation(latitude:longitude:)` en PATCH + reset geocoded + re-geocode. B) Composants géocodage réutilisés (AppleGeocoder existant). C) Rien — rejetté car cartes = PHP dédié au gap (audit item 26).

**Étapes**:
1. Card file (ce fichier).
2. `AssetDetailViewModel.setLocation(latitude: Double, longitude: Double) async` — guard coords valides (90/-180 bornes), PATCH UpdateAssetDto(latitude:longitude:), capture lastUpdateBody/lastUpdateAssetId, success → detail = updated, geocoded = false, `await reverseGeocodeIfNeeded()`; catch → errorMessage.
3. `PhotoInfoPanel.swift` — params optionnels `onOpenInMaps: ((Double, Double) -> Void)? = nil` + `onAdjustLocation: (() -> Void)? = nil` propagés à ExifInfoPanel; whereCard: si coords présentes → rangée boutons sous MiniMapView: "Open in Maps" (map) + "Adjust Location" (mappin.and.ellipse), style InfoCard (gray.opacity(0.12) capsule), .pvBody medium; callbacks seulement si non-nil.
4. NEW `Sources/Features/PhotoViewer/AdjustLocationSheet.swift` — `DraggablePinMapView` (UIViewRepresentable MKMapView standard, MKMarkerAnnotationView isDraggable=true, didChange dragState .ending/.canceling → onCoordinateChange, region span 0.05) + `AdjustLocationSheet` (asset, vm, coords initiales, @State lat/lon, boutons Cancel/Save, isSaving ProgressView, errorMessage si vm.errorMessage, onDone(saved: Bool)).
5. `PhotoViewer.swift` — `@State presentAdjustLocation = false`; branche info panel :285 passe `onOpenInMaps` (MKMapItem.openInMaps w/ placemark + name placeLabel) + `onAdjustLocation: { presentAdjustLocation = true }`; 3e `.sheet(isPresented: $presentAdjustLocation)` (détents .fraction(0.75), si currentAsset + infoVM non-nil → AdjustLocationSheet; .task { infoVM = AssetDetailViewModel... } pas nécessaire — infoVM existe déjà; sheet utilise vm existant).
6. `xcodegen generate` (1 nouveau fichier).
7. Tests `AssetDetailViewModelTests.swift` — §setLocation (3 tests): PATCH coords + captures, re-geocode via MockLocationGeocoding (detail exif lat/lon injecté via updateAssetResponse, placeName == mock), échec (globalError) → errorMessage + detail inchangé.
8. Build + suite complète (attendu ≥ 372).
9. Checks AC + memory.md + Status shipped.

## Acceptance Contract

### Approches candidates
**A (retenue)**: callbacks optionnels panel + MKMapItem direct + AdjustLocationSheet 3e sheet racine + setLocation PATCH + re-geocode. Pattern codebase (callbacks PhotoViewer/AssetThumbnailCell), pas de service superflu, testabilité via VM + closures.
**B**: Service `MapOpening` protocol + DI. Overkill pour une ligne openInMaps; le lancer système n'est pas unit-testable de toute façon.
**C**: Intégrer l'ajustement dans PhotoShareSheet/SaveSection. Mauvaise sémantique (feuille de partage), scope collision.

### Approche retenue + rationale
**A**. Callbacks optionnels = zéro régression des surfaces existantes. adjustLocation vit dans la feuille (position = éphémère) ; PATCH via VM existant ; re-geocode = réutilisation du pipeline AC-205.

### Critères

```
### AC-1020 [type: new]
Assertion: PhotoInfoPanel + ExifInfoPanel exposent `onOpenInMaps` et `onAdjustLocation` optionnels, et whereCard affiche les boutons "Open in Maps" / "Adjust Location" quand les coordonnées existent.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/PhotoInfoPanel.swift; grep -q "onOpenInMaps" "$f" && grep -q "onAdjustLocation" "$f" && grep -q "Open in Maps" "$f" && grep -q "Adjust Location" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun de ces tokens dans le fichier actuel)
Post-state attendu: PASS
```

```
### AC-1021 [type: new]
Assertion: Le clic "Open in Maps" lance Apple Plans via MKMapItem.openInMaps avec placemark nommé (placeLabel/placeName). L'implémentation vit dans PhotoViewer (openInMaps private func) — pas PhotoInfoPanel.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/PhotoViewer.swift; grep -q "MKMapItem(" "$f" && grep -q "\.openInMaps()" "$f" && grep -q "MKPlacemark(" "$f" && grep -q "func openInMaps" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune occurrence MKMapItem)
Post-state attendu: PASS
```

```
### AC-1022 [type: new]
Assertion: Nouveau fichier AdjustLocationSheet.swift contient DraggablePinMapView (épingle draggable) + AdjustLocationSheet (Cancel/Save, coords d'état, Save → vm.setLocation).
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/AdjustLocationSheet.swift; grep -q "DraggablePinMapView" "$f" && grep -q "isDraggable" "$f" && grep -q "AdjustLocationSheet" "$f" && grep -q "setLocation" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier n'existe pas)
Post-state attendu: PASS
```

```
### AC-1023 [type: new]
Assertion: AssetDetailViewModel gagne `setLocation(latitude:longitude:)` qui PATCH via client et capture lastUpdateAssetId/lastUpdateBody, puis force re-geocode.
Check post-impl: sh -c 'f=Sources/Features/AssetDetail/AssetDetailViewModel.swift; grep -q "func setLocation" "$f" && grep -q "lastUpdateBody = body" "$f" && n=$(grep -c "geocoded = false" "$f"); test "$n" -ge 1 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1024 [type: new]
Assertion: PhotoViewer présente la feuille d'ajustement en 3e sheet racine et câble les deux callbacks du panneau.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/PhotoViewer.swift; grep -q "presentAdjustLocation" "$f" && grep -cE "^[[:space:]]*\.sheet\(isPresented:" "$f" | grep -q "3" && grep -q "onOpenInMaps:" "$f" && grep -q "onAdjustLocation: { presentAdjustLocation = true }" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (2 sheets seulement, aucun callback)
Post-state attendu: PASS
```

```
### AC-1025 [type: new]
Assertion: Tests unitaires du réglage de position — PATCH coords, re-geocode, échec (≥ 3 tests test_setLocation_*).
Check post-impl: sh -c 'f=Tests/AssetDetailViewModelTests.swift; n=$(grep -c "func test_setLocation_" "$f"); test "$n" -ge 3 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun test test_setLocation_)
Post-state attendu: PASS
```

```
### AC-1026 [type: regression]
Assertion: La suite complète reste verte au-dessus du baseline (372 tests) après ajout de la 3e sheet + nouveaux tests (≥ 375 attendu).
Check post-impl: sh -c 'rtk grep -q "TEST SUCCEEDED" /tmp/immich_map_extras_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_map_extras_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 375 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier de summary inexistant)
Post-state attendu: PASS
```