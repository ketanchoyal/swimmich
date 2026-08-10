# Task: exif-map-detail

Status: shipped — PhotoViewer/PhotoInfoPanel EXIF + Search/MapView present.

## Plan

### Objectif
Implement cahier lines 107-108 + 222: full EXIF info panel (Photos.app "i" style) + mini MapKit map when geolocated + reverse geocoding for named place. MVP scope: no fullscreen map, no tap-pin → Maps.app route, no editing.

### Hypothèses (grounded)
- `AssetResponseDto.exifInfo: ExifResponseDto?` returned inline by `GET /api/assets/:id` (ImmichAPIClient.swift:90). No separate EXIF fetch.
- `ExifResponseDto` (DTOs.swift:140-163) has 22 fields incl. lat/lon/city/state/country.
- `AssetReactItem` also has city/country/lat/lon (columnar bucket fallback).
- iOS 17+ SwiftUI `Map` available with `Map(position:)` initializer + `.mapStyle(.imagery(elevation:))`.
- `CLGeocoder.reverseGeocodeLocation` async variant iOS 16.4+.
- MapKit + CoreLocation system frameworks auto-linked via `import` (no project.yml change).
- Existing `AssetDetailViewModelTests` (1 test AC-010 toggleFavorite) must stay green.

### Approches candidates (specialist)
- **A) MetadataSheet inline monolithique** — étendre directement, CLGeocoder dans la View. Coût bas, testabilité nulle, MVVM violé.
- **B) Pure formatters + LocationGeocoding protocol + ViewModel-driven geocoding + MiniMapView** — testable, MVVM-aligned, extensible.
- **C) Snapshot statique MKMapSnapshotter + serveur-only geocoding** — non-Photos-like, pas de CLGeocoder granularity.

### Approche retenue + rationale
**B**. MVVM-fit (View ne fait pas de async work), testable (formatters pure-func + MockLocationGeocoder), extensible (futur plein-écran cahier:147). CLGeocoder on-device en premier (granularité Photos-like: subLocality/locality), fallback sur exif.city+state+country si CLGeocoder throws/offline.

### Étapes
1. NEW `Sources/Core/Utilities/ExifDisplayFormatter.swift` — extension ExifResponseDto computed props (focalLengthFormatted, dimensionsFormatted, fileSizeFormatted, apertureFormatted, isoFormatted, exposureFormatted, cameraFormatted, dateFormatted).
2. NEW `Sources/Services/LocationGeocodingService.swift` — `@MainActor protocol LocationGeocoding` + `@MainActor final class AppleGeocoder` wrapping CLGeocoder; placeName(lat,lon) async throws -> String (subLocality, locality, administrativeArea, country). (Path fix per scout H6b: services live in `Sources/Services/`, not `Sources/Core/Services/`.)
3. EDIT `Sources/Features/AssetDetail/AssetDetailViewModel.swift` — `@ObservationIgnored var geocoder: any LocationGeocoding = AppleGeocoder()`, `var placeName: String?`, `@ObservationIgnored private var geocoded = false`, extend `loadDetail()` to call `reverseGeocodeIfNeeded()` private (guard `!geocoded` to prevent double-invoke on reload — set geocoded=true after attempt success/failure); fallback to exif city/state/country joined on throw; no-op if lat/lon nil.
4. EDIT `Sources/Features/AssetDetail/AssetDetailView.swift` — rename MetadataSheet → ExifInfoPanel + add full EXIF rows using formatters + conditional MiniMapView(lat,lon,placeName).
5. NEW `Tests/ExifFormatterTests.swift` — AC-201.
6. NEW `Tests/Mocks/MockLocationGeocoder.swift` — configurable result/error + callCount.
7. NEW `Tests/AssetDetailGeocodingTests.swift` — AC-204, AC-205, AC-206.
8. `xcodegen generate` + build + test.

## Acceptance Contract

### AC-201 [type: new]
Assertion: Computed properties de formatage sur `ExifResponseDto` retournent les chaînes attendues pour valeurs connues (focalLengthFormatted="50 mm", dimensionsFormatted="4032 × 3024", fileSizeFormatted contient "MB", apertureFormatted="f/1.8", isoFormatted="ISO 400", exposureFormatted="1/250s", cameraFormatted="Canon EOS R", dateFormatted non-nil pour ISO8601).
Check post-impl: `xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ImmichSwiftUITests/ExifFormatterTests/test_AC_201_formatters` → `** TEST SUCCEEDED **`
Pre-state attendu: 0 tests ran (classe ExifFormatterTests inexistante).
Post-state attendu: ExifFormatterTests.test_AC_201_formatters passe, ≥8 asserts sur chaînes formatées.

### AC-201b [type: new]
Assertion: Les computed properties de formatage retournent `nil` quand le champ source est `nil` (FM-2: lat/lon présents mais exifImageWidth/Height nil ne doit pas crasher ni afficher "— × —"). Concerne: focalLengthFormatted, dimensionsFormatted, fileSizeFormatted, apertureFormatted, isoFormatted, exposureFormatted, cameraFormatted, dateFormatted.
Check post-impl: `xcodebuild test ... -only-testing:ImmichSwiftUITests/ExifFormatterTests/test_AC_201b_nil_cases` → `** TEST SUCCEEDED **`. Test: `ExifResponseDto()` vide (tous nil) → toutes les properties == nil.
Pre-state attendu: 0 tests ran.
Post-state attendu: test_AC_201b_nil_cases passe, toutes 8 properties == nil sur DTO vide.

### AC-202 [type: new]
Assertion: `ExifInfoPanel` (ex-MetadataSheet) affiche ≥ 12 champs EXIF distincts via `LabeledContent` quand le DTO est complet.
Check post-impl: `grep -c "LabeledContent" Sources/Features/AssetDetail/AssetDetailView.swift` retourne ≥ 12.
Pre-state attendu: 6 (Camera, Lens, Aperture, ISO, Exposure, Location actuels dans MetadataSheet).
Post-state attendu: ≥ 12.

### AC-203 [type: new]
Assertion: `MiniMapView` (ou `Map(` SwiftUI) apparaît dans AssetDetailView.swift uniquement à l'intérieur d'un bloc conditionnel testant `exif.latitude != nil` et `exif.longitude != nil`.
Check post-impl: `grep -nE "MiniMapView|Map\(" Sources/Features/AssetDetail/AssetDetailView.swift` retourne ≥ 1 match; contexte surrounding montre `if let lat = exif.latitude, let lon = exif.longitude`.
Pre-state attendu: 0 occurences.
Post-state attendu: ≥ 1 match + conditionnel lat/lon.

### AC-204 [type: new]
Assertion: `AssetDetailViewModel.placeName` est non-nil après `loadDetail()` quand exifInfo a lat/lon et CLGeocoder réussit.
Check post-impl: `xcodebuild test ... -only-testing:ImmichSwiftUITests/AssetDetailGeocodingTests/test_AC_204_geocode_success` → `** TEST SUCCEEDED **`. Test: MockLocationGeocoder configuré retourne "Test Place" → après loadDetail() avec lat=48.8566, lon=2.3522, `vm.placeName == "Test Place"`.
Pre-state attendu: 0 tests ran.
Post-state attendu: placeName == "Test Place".

### AC-205 [type: new]
Assertion: Si CLGeocoder throws, `placeName` est fallback-construit depuis exif.city + exif.state + exif.country (joints ", "). Si tous nil, placeName reste nil.
Check post-impl: `xcodebuild test ... -only-testing:ImmichSwiftUITests/AssetDetailGeocodingTests/test_AC_205_geocode_fallback` + `test_AC_205b_geocode_no_fallback_data` → `** TEST SUCCEEDED **`.
Pre-state attendu: 0 tests ran.
Post-state attendu: (1) throw + exif.city="Paris",state="IDF",country="France" → placeName=="Paris, IDF, France"; (2) throw + tous nil → placeName==nil.

### AC-206 [type: new]
Assertion: Si exifInfo.latitude == nil (ou longitude == nil), `reverseGeocodeIfNeeded` est no-op: `vm.placeName` reste nil et `MockLocationGeocoder.callCount == 0` après `loadDetail()`.
Check post-impl: `xcodebuild test ... -only-testing:ImmichSwiftUITests/AssetDetailGeocodingTests/test_AC_206_no_geocode_without_coords` → `** TEST SUCCEEDED **`.
Pre-state attendu: 0 tests ran.
Post-state attendu: callCount==0 && placeName==nil.

### AC-207 [type: regression]
Assertion: Tous les tests existants (67 pré-impl) restent verts + l'AC-010 toggleFavorite test continue de passer sans modification.
Check post-impl: `xcodebuild test -project ImmichSwiftUI.xcodeproj -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` → `** TEST SUCCEEDED **` avec ≥ 67 tests, 0 failure, dont `AssetDetailViewModelTests` intacts.
Pre-state attendu: 67 tests verts (AppLock:7, Detail:1, Auth:5, Date:7, DTO:7, Cache:3, API:3, Section:6, Timeline:12, Trash:16).
Post-state attendu: ≥ 67 tests verts, 0 failure.

### AC-208 [type: new]
Assertion: Appeler `loadDetail()` deux fois de suite sur le même `AssetDetailViewModel` n'invoque `geocoder.placeName(...)` qu'une seule fois (FM-3 mitigation: guard `!geocoded`).
Check post-impl: `xcodebuild test ... -only-testing:ImmichSwiftUITests/AssetDetailGeocodingTests/test_AC_208_geocode_no_double_invoke` → `** TEST SUCCEEDED **`. Test: vm.loadDetail() ×2 → `mock.callCount == 1`.
Pre-state attendu: 0 tests ran.
Post-state attendu: mock.callCount == 1 après 2 loadDetail.

### Failure modes (top 3 + quel AC les détecte)

- **FM-1 — CLGeocoder offline + exif.city=nil**: placeName reste nil, map affichée sans label. Détecté: AC-205b (no_fallback_data path).
- **FM-2 — lat/lon présents mais exifImageWidth/Height nil**: dimensionsFormatted retourne nil (optionnel), LabeledContent pas affiché. Détecté: AC-201 (test nil case return nil).
- **FM-3 — CLGeocoder double-invoke sur reload detail**: loadDetail rappelé plusieurs fois → plusieurs Tasks geocoding concurrents. Mitigation: `@ObservationIgnored private var geocoded = false` guard dans `reverseGeocodeIfNeeded()` (set true après attempt). Détecté: **AC-208** (callCount ≤ 1 après 2 loadDetail).

## Vérifications manuelles (hors contract)

- VM-1: MiniMapView ~180pt height, coins carrés (radius 0, cohérent Timeline tweak), `.allowsHitTesting(false)`, marker system, `.mapStyle(.imagery(elevation: .realistic))`.
- VM-2: placeName sous la carte, `.font(.caption).foregroundStyle(.secondary).lineLimit(1)`.
- VM-3: EXIF panel scrollable (ScrollView parent si contenu > écran).
- VM-4: dateTimeOriginal formaté selon locale (ex "30 juil. 2026 à 14:32").
- VM-5: pas de spinner bloquant geocoding (placeName apparaît async après EXIF load).
- VM-6: cornerRadius 0 aligné avec Timeline tweak (cahier = no radius partout). Décision: garder coins carrés (radius 0) pour cohérence stricte avec Timeline tweak déjà livré. VM-1 reflète cette décision.
