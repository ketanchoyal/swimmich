# Task: ocr-text

Status: planifié — **aucune AC ouverte** (écart G8 du registre `.omp/backlog/ImmichSwiftUI-backlog.md`).

## Plan (résumé)

**Objectif** : dans le viewer photo, une bascule « texte détecté » dessine sur l'image les quadrilatères
renvoyés par `GET /api/assets/{id}/ocr` et les garde solidaires du zoom et du déplacement ; dans Recherche,
une seconde bascule restreint les résultats via `filter.ocr.matches` de `POST /api/search/metadata`.

**Approche retenue** : A — la donnée OCR traverse `ZoomableImageView` et l'overlay y est dessiné, dans le même
repère que les gestes (le zoom vit dans cette vue : `scale`/`offset` en `@State private`,
`ZoomableImageView.swift:43-44`). Le calque frère dans `PhotoViewer` et le panneau texte-only sont rejetés.

**Étapes** : (1) NEW `AssetOcrDTOs.swift` (13 champs `required`) ; (2) EDIT `ImmichClient.swift`
(`getAssetOcr(id:)`) ; (3) EDIT `ImmichAPIClient.swift` (suffixe `/ocr`) ; (4) EDIT `MockImmichClient.swift` ;
(5) NEW `OcrOverlayViewModel.swift` ; (6) NEW `OcrOverlayView.swift` ; (7) EDIT `ZoomableImageView.swift` ;
(8) EDIT `PhotoViewer.swift` (bascule `viewerOcrToggle`) ; (9) NEW `SearchFilterDTOs.swift` + EDIT
`SearchDTOs.swift` / `SearchViewModel.swift` / `SearchView.swift` (`searchOcrFilterToggle`) ; (10) i18n du
catalogue ; (11) NEW `Tests/OcrOverlayViewModelTests.swift` + EDIT `SearchViewModelTests.swift` et
`DTOEncodingTests.swift` ; (12) `xcodegen generate` puis suite complète.

**Incertitudes** : origine exacte d'`offset` (centre du conteneur vs coin haut-gauche) ; repère EXIF des
coordonnées (image originale vs preview redressée) ; réponse de la route quand l'OCR est désactivé côté
serveur (aucun `4xx` documenté) ; articulation `query` + `filter` sur `/search/metadata`.

## Critères

```
### AC-5070 [type: new]
Assertion: le type de réponse est le miroir exact de `AssetOcrResponseDto` de l'OpenAPI — les 13 champs
`required` (dont les huit coordonnées `x1..x4` / `y1..y4` en `Double`, normalisées 0-1), des `CodingKeys`
explicites pour ne pas dépendre du décodage automatique des clés d'une lettre, le quadrilatère à quatre coins
(y compris les diagonales `topLeft`/`bottomRight`, donc pas une bbox axis-aligned) et le seuil de confiance
local `isConfident`.
Check post-impl: sh -c 'f=Sources/Core/Types/AssetOcrDTOs.swift; test -f "$f" && grep -qE "struct AssetOcrResponseDto" "$f" && grep -qE "let id: String" "$f" && grep -qE "let assetId: String" "$f" && grep -qE "let text: String" "$f" && grep -qE "let boxScore: Double" "$f" && grep -qE "let textScore: Double" "$f" && test "$(grep -cE "let [xy][1-4]: Double" "$f")" -eq 8 && grep -qE "enum CodingKeys" "$f" && grep -qE "struct OcrQuad" "$f" && grep -qE "let topLeft: CGPoint" "$f" && grep -qE "let bottomRight: CGPoint" "$f" && grep -qE "var quad: OcrQuad" "$f" && grep -qE "var isConfident: Bool" "$f" && grep -qE "textScore >= 0.5" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`test -f` échoue — `grep -ril ocr Sources` est vide, aucun type OCR n'existe)
Post-state attendu: PASS
Note: le comptage à 8 coordonnées est délibéré — quatre paires suffisent à décrire un quadrilatère incliné,
une bbox `CGRect` n'en demanderait que quatre au total et passerait un check nom-par-nom.
```

```
### AC-5071 [type: new]
Assertion: la route traverse les deux couches du transport — l'exigence est déclarée dans le bloc assets du
protocole et `ImmichAPIClient` la réalise sur le chemin réel de l'OpenAPI, dans le corps de `getAssetOcr`
lui-même (adjacence vérifiée par `grep -A6`), avec le constructeur qui pose l'en-tête authentifié.
Check post-impl: sh -c 'p=Sources/Core/Protocols/ImmichClient.swift; c=Sources/Services/ImmichAPIClient.swift; grep -qE "func getAssetOcr\(id: String\) async throws -> \[AssetOcrResponseDto\]" "$p" && grep -qE "func getAssetOcr\(id: String\) async throws -> \[AssetOcrResponseDto\]" "$c" && grep -A6 "func getAssetOcr" "$c" | grep -qE "id\)/ocr\"" && grep -qE "sendAuthed\(\.GET" "$c" && grep -qE "ImmichAPI.assets.path" "$c" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune méthode OCR sur le protocole : `grep -rn "getAssetOcr" Sources` est vide ; `:171` s'arrête à `getFaces(assetId:)`)
Post-state attendu: PASS
Note: l'adjacence `grep -A6` vise le **corps** de la fonction — un doc-comment citant `GET /api/assets/{id}/ocr`
ne peut pas satisfaire le check, et un `"/ocr"` posé ailleurs ne compte pas.
```

```
### AC-5072 [type: new]
Assertion: le double de test suit le protocole étendu, sinon la suite ne compile plus — le stub rend le
tableau OCR par asset et sait lever une erreur, comme les autres routes du mock.
Check post-impl: sh -c 'f=Tests/Mocks/MockImmichClient.swift; test -f "$f" && grep -qE "func getAssetOcr\(id: String\) async throws -> \[AssetOcrResponseDto\]" "$f" && grep -qE "ocrByAssetId" "$f" && grep -qE "try errorToThrow" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -rn "getAssetOcr" Tests` est vide — le mock n'a aucune notion d'OCR)
Post-state attendu: PASS
```

```
### AC-5073 [type: new]
Assertion: l'état de l'overlay est un ViewModel injecté, pas un `@State` de vue — chargement paresseux
(`load()` sort avant tout appel si `didLoad || isLoading`, donc un seul appel réseau par asset), cache par
asset, états exposés en lecture seule, erreur de chargement dans `errorMessage`, annulation avalée, et ordre
de lecture stable (score décroissant).
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/OcrOverlayViewModel.swift; test -f "$f" && grep -qE "final class OcrOverlayViewModel" "$f" && grep -qE "@Observable" "$f" && grep -qE "@MainActor" "$f" && grep -qE "let assetId: String" "$f" && grep -qE "private let client: any ImmichClient" "$f" && grep -qE "private\(set\) var boxes: \[AssetOcrResponseDto\] = \[\]" "$f" && grep -qE "private\(set\) var isLoading" "$f" && grep -qE "private\(set\) var didLoad" "$f" && grep -qE "var errorMessage: String\?" "$f" && grep -qE "func load\(\) async" "$f" && grep -qE "didLoad \|\| isLoading" "$f" && grep -qE "CancellationError|URLError.cancelled|isCancellation" "$f" && grep -qE "textScore" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — `Sources/Features/PhotoViewer/` ne contient que `PhotoViewer.swift`, `ZoomableImageView.swift` et `AssetDetailViewModel.swift`)
Post-state attendu: PASS
Note: le cache par asset est porté par l'instance (un VM par `assetId`, recréé au changement de page comme
`AssetDetailViewModel`), et non par un dictionnaire global — c'est ce qui rend l'idempotence de `load()` vraie.
```

```
### AC-5074 [type: new]
Assertion: la vue de dessin est pure et non interactive — elle reçoit les boîtes, le rect de l'image, le
facteur et la translation du zoom et la taille du viewport, trace un quadrilatère à quatre points par boîte
(et non un `CGRect`), et déclare `allowsHitTesting(false)` sans poser aucun geste : c'est ce qui garantit que
le pinch, le double-tap et le pan du viewer continuent d'atteindre `ZoomableImageView`.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/OcrOverlayView.swift; test -f "$f" && grep -qE "struct OcrOverlayView" "$f" && grep -qE "let boxes: \[AssetOcrResponseDto\]" "$f" && grep -qE "let imageRect: CGRect" "$f" && grep -qE "let scale: CGFloat" "$f" && grep -qE "let offset: CGSize" "$f" && grep -qE "let viewportSize: CGSize" "$f" && grep -qE "Canvas" "$f" && grep -qE "allowsHitTesting\(false\)" "$f" && ! grep -qE "gesture\(" "$f" && ! grep -qE "DragGesture|MagnificationGesture|TapGesture|onTapGesture" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: la négation sur les gestes encode l'exigence d'AC-5075 (le tap du viewer ouvre la barre de chrome, le
double-tap zoome) : un overlay qui capte les touches casse les deux, et un layout `CGRect` masquerait
l'inclinaison des boîtes (coordonnées = quatre coins, pas une bbox).
```

```
### AC-5075 [type: new]
Assertion: l'overlay est dessiné **dans** `ZoomableImageView`, avec `scale` et `offset` passés au calque et
deux paramètres optionnels de valeur par défaut vide — les appels existants de la vue (viewer simple,
aperçus) ne changent pas de signature et l'OCR est éteint par défaut.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/ZoomableImageView.swift; grep -qE "var ocrBoxes: \[AssetOcrResponseDto\] = \[\]" "$f" && grep -qE "var showOcr: Bool = false" "$f" && grep -qE "if showOcr" "$f" && grep -qE "OcrOverlayView\(" "$f" && grep -A4 "OcrOverlayView\(" "$f" | grep -qE "scale: scale" && grep -A4 "OcrOverlayView\(" "$f" | grep -qE "offset: offset" && grep -qE "GeometryReader" "$f" && grep -qE "imageRect" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun `ocrBoxes`, aucun `showOcr`, aucun `OcrOverlayView` — `grep -rn "ocr" Sources/Features/PhotoViewer/ZoomableImageView.swift` est vide)
Post-state attendu: PASS
Note: `scale: scale` / `offset: offset` sont vérifiés dans l'appel : sans eux la vue compilerait toujours
(défauts vides) mais les boîtes resteraient figées sous le doigt — c'est exactement le mode de défaillance qui
a fait rejeter l'approche B.
```

```
### AC-5076 [type: new]
Assertion: la bascule vit dans la barre du viewer (`topBar`, à côté de Slideshow/Info), avec son identifiant
d'accessibilité, son libellé, l'icône `text.viewfinder`, le garde `isImage` (pas de bascule sur une vidéo),
le VM recréé au changement de page comme `AssetDetailViewModel`, et l'erreur de chargement rendue dans le
chrome (capsule) plutôt qu'en alerte bloquante.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/PhotoViewer.swift; grep -qE "viewerOcrToggle" "$f" && grep -qE "text.viewfinder" "$f" && grep -qE "Detected text" "$f" && grep -qE "func refreshOcr" "$f" && grep -qE "private var ocrVM: OcrOverlayViewModel\?" "$f" && grep -qE "private var showOcr = false" "$f" && grep -qE "OcrOverlayViewModel\(assetId:" "$f" && grep -qE "isImage" "$f" && grep -qE "ocrBoxes: ocrVM" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun `ocr` dans `PhotoViewer.swift` ; la barre n'a que Slideshow/Info/Back)
Post-state attendu: PASS
Note: l'identifiant est posé sur le bouton (`viewerOcrToggle`), jamais sur un conteneur — un
`.accessibilityLabel` sur un conteneur ne rend pas l'élément atteignable et un identifiant de conteneur ne
localise pas le contrôle (piège mesuré : mémo `3acc19d3`).
```

```
### AC-5077 [type: new]
Assertion: la recherche passe par le remplaçant v3.2.0 et pas par le champ déprécié — `StringSimilarityFilterDto`
ne porte que `matches`, `SearchFilterDto` n'expose que `ocr` (sous-ensemble strict, le serveur interdit les
propriétés additionnelles), `MetadataSearchDto.filter` est optionnel pour que la clé disparaisse quand aucun
filtre n'est actif, **aucun champ scalaire `ocr` n'est ajouté** au DTO, et le ViewModel bascule `query` en
`nil` au profit du filtre ; la vue porte sa bascule.
Check post-impl: sh -c 'a=Sources/Core/Types/SearchFilterDTOs.swift; b=Sources/Core/Types/SearchDTOs.swift; c=Sources/Features/Search/SearchViewModel.swift; d=Sources/Features/Search/SearchView.swift; test -f "$a" && grep -qE "struct StringSimilarityFilterDto" "$a" && grep -qE "var matches: String" "$a" && grep -qE "struct SearchFilterDto" "$a" && grep -qE "var ocr: StringSimilarityFilterDto\?" "$a" && grep -qE "var filter: SearchFilterDto\?" "$b" && ! grep -qE "var ocr: String" "$b" && grep -qE "var ocrFilterEnabled = false" "$c" && grep -qE "dto.filter = SearchFilterDto\(ocr: StringSimilarityFilterDto\(matches:" "$c" && grep -qE "dto.query = nil" "$c" && grep -qE "searchOcrFilterToggle" "$d" && grep -qE "text.viewfinder" "$d" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (ni `SearchFilterDTOs.swift`, ni `ocrFilterEnabled` ; `MetadataSearchDto`
(`SearchDTOs.swift:8-24`) n'a ni `ocr` ni `filter` — 15 champs scalaires)
Post-state attendu: PASS
Note: c'est l'arbitrage de la spec rendu exécutable. `MetadataSearchDto.ocr` est `deprecated: true`
(`Deprecated v3.2.0`, même cycle que la feature) et son remplaçant explicite est `filter.ocr` de type
`StringSimilarityFilter { matches, minLength 1 }` — une similarité, pas une égalité. Le `! grep "var ocr: String"`
interdit de réintroduire le scalaire déprécié dans le DTO de recherche ; `dto.query = nil` encode l'exclusion
mutuelle constatée sur la branche de filtre existante (`SearchViewModel.swift:320`).
```

```
### AC-5078 [type: new]
Assertion: les trois tests prévus par la spec existent — la suite du ViewModel d'overlay avec le mock partagé
(chargement, tableau vide, second `load()` sans appel, erreur, annulation), le cas de filtre OCR dans
`SearchViewModelTests` (le DTO émis porte `filter.ocr` renseigné) et l'encodage dans `DTOEncodingTests`
(`filter.ocr.matches` présent, pas de DTO à champ scalaire).
Check post-impl: sh -c 'a=Tests/OcrOverlayViewModelTests.swift; b=Tests/SearchViewModelTests.swift; c=Tests/DTOEncodingTests.swift; test -f "$a" && test "$(grep -cE "func test_" "$a")" -ge 5 && grep -qE "MockImmichClient" "$a" && grep -qE "@MainActor" "$a" && grep -qE "didLoad" "$a" && grep -qE "errorMessage" "$a" && grep -qE "ocrFilterEnabled" "$b" && grep -qE "StringSimilarityFilterDto" "$c" && grep -qE "matches" "$c" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — `Tests/` ne contient aucune suite OCR)
Post-state attendu: PASS
Note: un `Tests/*.swift` n'est compilé ni exécuté qu'après `xcodegen generate` — sans la régénération, la
suite resterait « verte » par omission.
```

```
### AC-5079 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests,
`-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED.
Check post-impl: sh -c 'l=/tmp/immich_ocr_text_test.log; test -f "$l" && grep -qE "TEST SUCCEEDED" "$l" && n=$(grep -oE "Executed [0-9]+ tests" "$l" | grep -oE "[0-9]+" | sort -n | tail -1) && test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log `/tmp/immich_ocr_text_test.log` absent — la suite n'a pas encore été relancée avec les nouveaux fichiers)
Post-state attendu: PASS
Note: le `test -f` en tête évite l'erreur « integer expression expected » quand le log n'existe pas : le
check rend FAIL proprement, sans bruit.
```
