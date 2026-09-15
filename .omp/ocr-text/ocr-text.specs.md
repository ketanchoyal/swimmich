# Task: ocr-text

> **Audit 2026-09-15 — écart G8** : le client Flutter expose l'OCR sur deux surfaces
> (`mobile/lib/presentation/widgets/asset_viewer/ocr_overlay.widget.dart` + `ocr_toggle_button.widget.dart`,
> appuyés sur `mobile/lib/domain/services/ocr.service.dart` et `mobile/lib/domain/models/ocr.model.dart`,
> tous vérifiés présents dans `immich-app/immich@e55ac299`), alors que `grep -ril ocr Sources` ne retourne
> **aucun** fichier dans le dépôt iOS : ni overlay, ni bascule, ni filtre de recherche par texte détecté.

**Objectif** : dans le viewer photo, l'utilisateur peut basculer un mode « texte détecté » qui dessine sur
la photo les quadrilatères renvoyés par le serveur, avec le texte reconnu lisible au-dessus de chaque boîte ;
la bascule suit la photo quand elle est zoomée ou déplacée. Dans l'écran Recherche, il peut restreindre
les résultats aux seules photos dont le texte détecté correspond à la saisie, via le filtre
`filter.ocr.matches` de `POST /api/search/metadata`.

**Hors périmètre** : pas de déclenchement ni de pilotage du job OCR serveur (le contrat ne l'expose pas côté
client mobile) ; pas de sélection/copie du texte reconnu ni de recherche dans la visionneuse ; pas de
traduction du texte détecté ; pas d'application du filtre OCR à la recherche « smart » (`SmartSearchDto.ocr`
porte la même dépréciation v3.2.0 que `MetadataSearchDto.ocr` et n'est pas traité ici) ; pas de modification
de `SearchStatisticsDto`.

**Hypothèses** (vérifiées dans le dépôt et contre `immich-app/immich@main`, le 2026-09-15) :
- `GET /api/assets/{id}/ocr` (`operationId: getAssetOcr`, tag `Assets`, sécurité `bearer|cookie|api_key`)
  répond **200 avec un tableau** de `AssetOcrResponseDto` — pas un objet. Les 13 champs sont tous `required` :
  `id`, `assetId` (uuid), `text` (string, « Recognized text »), `boxScore` (double, « Confidence score for
  text detection box »), `textScore` (double, « Confidence score for text recognition »), `x1..x4` et
  `y1..y4` (double, « Normalized x/y coordinate of box corner N (0-1) »). Les coordonnées sont donc **quatre
  coins normalisés 0–1** (quadrilatère, pas une bbox axis-aligned) : la boîte peut être inclinée, il faut
  tracer un `Path` à 4 points et non un `CGRect`.
- `POST /api/search/metadata` : le champ `ocr` de `MetadataSearchDto` est `"type":"string"`,
  `"deprecated": true`, `x-immich-state: "Deprecated"`, historique
  `Added v1 / Stable v2 / Deprecated v3.2.0`. Son remplaçant explicite est **`filter.ocr`**
  (`MetadataSearchDto.filter` est marqué `Added v3.2.0`), de type `SearchFilter.ocr` →
  `StringSimilarityFilter` = `{ "matches": string, minLength 1 }`, `matches` **required**. La nouvelle forme
  est donc une **similarité de texte**, pas une égalité ; envoyer l'ancien `ocr` scalaire serait s'adosser à
  un champ déprécié au même cycle que la feature (v3.2.x). Même constat sur `SmartSearchDto.ocr` (même
  historique) → hors périmètre.
- L'activation de l'OCR n'est **pas** dans `ServerConfigDto` (clés réelles : `externalDomain`,
  `isInitialized`, `isOnboarded`, `loginPageMessage`, `maintenanceMode`, `mapDarkStyleUrl`,
  `mapLightStyleUrl`, `minFaces`, `oauthAccountManagementUrl`, `oauthButtonText`, `publicUsers`,
  `trashDays`, `userDeleteDelay`). Le seul témoin est `GET /api/users/me/preferences` (`getMyPreferences`) →
  `UserConfigDto.machineLearning.ocr` = `UserConfigOcrDto { enabled: Bool }` (required).
- Le dépôt n'a aucune trace d'OCR : `grep -ril ocr Sources` est vide. Le protocole `ImmichClient`
  (`Sources/Core/Protocols/ImmichClient.swift:10`) porte `getAsset(id:)` (`:47`) et `getFaces(assetId:)`
  (`:171`) mais rien pour l'OCR ; `ImmichAPIClient` (`Sources/Services/ImmichAPIClient.swift:15`) fait
  `try await sendAuthed(.GET, path: ImmichAPI.assets.path("/\(id)"))` (`:146-148`) et `getFaces` ajoute un
  `URLQueryItem` (`:412-415`) ; les chemins viennent de `ImmichAPI.assets = SubPath(root: "/assets")`
  (`Sources/Core/Constants.swift:12`) et `SubPath.path(_ suffix:)` (`:35`).
- `MetadataSearchDto` (`Sources/Core/Types/SearchDTOs.swift:8-24`) n'a **ni** `ocr` **ni** `filter` : 15
  champs scalaires seulement. `SearchViewModel` (`Sources/Features/Search/SearchViewModel.swift:34-38`) est
  `@Observable @MainActor` avec `enum SearchMode { case metadata, smart }`, et son `dispatchSearch(page:)`
  (`:315-328`) construit `MetadataSearchDto(query: query, page: page)` ; la route de filtre existante passe
  par `enum ExploreField` (`:44`) + `apply(_ value: String, to dto: inout MetadataSearchDto)` (`:58`), qui
  écrit des champs scalaires et met `dto.query = nil` (`:320`). DI :
  `DependencyContainer.makeSearchViewModel()` (`Sources/DependencyContainer.swift:100`).
- Le viewer ne passe pas par `DependencyContainer` pour ses VMs : `PhotoViewer.swift:637-643` construit
  `AssetDetailViewModel(asset:client:)` en ligne et rejoue l'appel à chaque changement de page
  (`refreshInfo()`, `:625`), et `PhotoViewer` (`:116`) est présenté par `.fullScreenCover(item:)`
  (`PhotoViewerPresentation`, `:36-50`) — **aucun `NavigationStack`**. La bascule d'OCR doit donc vivre dans
  `topBar(_:)` (`:367`, à côté de Slideshow/Info) avec un `@State`, pas dans une destination poussée.
- Le zoom vit **à l'intérieur** de `ZoomableImageView`
  (`Sources/Features/PhotoViewer/ZoomableImageView.swift:23`, `@State private var scale`/`offset`, `:43-44`)
  et n'est remonté au parent que par `onZoomChange: (CGFloat) -> Void` (`:31`, utilisé pour bloquer le
  swipe-to-dismiss) ; `PhotoViewer` ne connaît ni le facteur ni la translation. C'est ce fait qui tranche
  l'approche A contre B ci-dessous.

**Approche retenue** : A — la donnée OCR traverse `ZoomableImageView` et l'overlay y est dessiné, dans le
même repère que les gestes.
- **B (rejetée)** : dessiner l'overlay comme frère du `pager` dans `PhotoViewer` (calque posé sur la
  visionneuse, à côté de la filmstrip). `ZoomableImageView` garde `scale` et `offset` en `@State private`
  (`ZoomableImageView.swift:43-44`) : un calque frère ne peut pas les lire, donc dès 1,01× de pinch ou au
  moindre pan les boîtes restent fixes pendant que la photo bouge — décalage garanti et visible. Le corriger
  imposerait de faire remonter l'état de zoom (nouveaux bindings/callbacks en plus des 2 déjà exposés,
  `:30-33`) : plus de surface que de passer la donnée vers le bas.
- **C (rejetée)** : panneau texte-only (liste des `text` sans boîtes) ouvert comme la feuille Info.
  Contredit l'upstream (`ocr_overlay.widget.dart` dessine des boîtes sur l'image), supprime l'objectif «
  overlay », et n'économise rien : `OcrQuad` a besoin des 8 coordonnées déjà présentes dans la réponse. La
  liste reste utile comme repli d'accessibilité, pas comme implémentation.

## Étapes
1. **DTO de réponse** — NEW `Sources/Core/Types/AssetOcrDTOs.swift` :
   `struct AssetOcrResponseDto: Codable, Equatable, Identifiable, Sendable` avec exactement les 13 champs
   `required` de l'OpenAPI (`let id: String`, `let assetId: String`, `let text: String`,
   `let boxScore: Double`, `let textScore: Double`, `let x1: Double` … `let y4: Double`) + `enum CodingKeys`
   explicites (même mitigation FM-1 que `SearchResponseDto`, `Sources/Core/Types/SearchDTOs.swift:54-58`).
   Ajouter `var quad: OcrQuad` (struct `OcrQuad { let topLeft, topRight, bottomRight, bottomLeft: CGPoint }`
   en coordonnées **normalisées**) et `var isConfident: Bool { textScore >= 0.5 }` (seuil d'affichage, pas
   de filtre serveur).
2. **Contrat client** — EDIT `Sources/Core/Protocols/ImmichClient.swift` : déclarer
   `func getAssetOcr(id: String) async throws -> [AssetOcrResponseDto]` dans le bloc assets, juste après
   `getFaces(assetId:)` (`:171`).
3. **Transport** — EDIT `Sources/Services/ImmichAPIClient.swift` : implémenter après `getFaces` (`:412-415`)
   avec `try await sendAuthed(.GET, path: ImmichAPI.assets.path("/\(id)/ocr"))`, sur le modèle exact de
   `getAsset` (`:146-148`). Aucun `URLQueryItem` : la route ne prend que le path param.
4. **Mock** — EDIT `Tests/Mocks/MockImmichClient.swift` : ajouter le stub
   `func getAssetOcr(id: String) async throws -> [AssetOcrResponseDto]` (table
   `var ocrByAssetId: [String: [AssetOcrResponseDto]] = [:]` + `var errorToThrow`), pour que la suite
   compile avec le protocole étendu.
5. **ViewModel de l'overlay** — NEW `Sources/Features/PhotoViewer/OcrOverlayViewModel.swift` :
   `@Observable @MainActor final class OcrOverlayViewModel` avec `let assetId: String`,
   `private let client: any ImmichClient`, `init(assetId: String, client: any ImmichClient)`,
   `private(set) var boxes: [AssetOcrResponseDto] = []`, `private(set) var isLoading = false`,
   `private(set) var didLoad = false`, `var errorMessage: String?`, `func load() async`. `load()` sort
   immédiatement si `didLoad || isLoading`, avale les annulations comme `SearchViewModel.isCancellation`
   (`SearchViewModel.swift:305-309`), trie `boxes` par `textScore` décroissant puis par `topLeft.y` pour un
   ordre de lecture stable.
6. **Vue de dessin (pure)** — NEW `Sources/Features/PhotoViewer/OcrOverlayView.swift` :
   `struct OcrOverlayView: View` avec `let boxes: [AssetOcrResponseDto]`, `let imageRect: CGRect` (rect de
   l'image ajustée dans le viewport, **avant** zoom), `let scale: CGFloat`, `let offset: CGSize`,
   `let viewportSize: CGSize`. Un `Canvas` (ou un `ZStack` de `Path`) trace pour chaque boîte un
   quadrilatère arrondi (`strokedPath` 1,5 pt, teinte d'accent + voile `opacity(0.18)`) et pose `text` en
   étiquette au-dessus du coin haut-gauche, lisible en blanc sur capsule sombre. `.allowsHitTesting(false)`
   et pas de geste : la vue ne capture ni le pinch ni le tap du `ZoomableImageView`. Formule unique de
   mapping, à documenter dans le fichier :
   `p = CGPoint(x: imageRect.minX + nx * imageRect.width, y: imageRect.minY + ny * imageRect.height)` puis
   `p' = (p - viewportCenter) * scale + viewportCenter + offset`.
7. **Intégration zoom** — EDIT `Sources/Features/PhotoViewer/ZoomableImageView.swift` : ajouter
   `var ocrBoxes: [AssetOcrResponseDto] = []` et `var showOcr: Bool = false` (défauts vides → les appels
   existants ne changent pas), envelopper le contenu dans un `GeometryReader` pour obtenir `viewportSize`,
   calculer `imageRect` depuis `asset.ratio` (aspect-fit), puis
   `.overlay { if showOcr { OcrOverlayView(...) } }` en réutilisant `scale` et `offset` (`:43-44`) — c'est
   le seul endroit du dépôt qui les connaît.
8. **Bascule dans le viewer** — EDIT `Sources/Features/PhotoViewer/PhotoViewer.swift` :
   `@State private var showOcr = false`, `@State private var ocrVM: OcrOverlayViewModel?` à côté de
   `showInfo`/`infoVM` (`:138-139`) ; `private func refreshOcr()` calqué sur `refreshInfo()` (`:637-643`,
   idempotent par `assetId`, recréé au changement de page) ; bouton dans `topBar(_:)` (`:367`) entre
   Slideshow et Info — `Image(systemName: "text.viewfinder")`, `.accessibilityLabel("Detected text")`,
   `.accessibilityIdentifier("viewerOcrToggle")`, désactivé si `currentAsset?.isImage != true`
   (`AssetReactItem.isImage`, `Sources/Core/Types/AssetReactItem.swift:20`) ; passer
   `ocrBoxes: ocrVM?.boxes ?? []` et `showOcr:` au `ZoomableImageView` (`:328`). L'état d'erreur de
   chargement s'affiche dans le chrome (capsule « Detected text unavailable »), jamais en alerte bloquante.
9. **DTO de filtre** — NEW `Sources/Core/Types/SearchFilterDTOs.swift` :
   `struct StringSimilarityFilterDto: Codable, Equatable { var matches: String }` et
   `struct SearchFilterDto: Codable, Equatable { var ocr: StringSimilarityFilterDto? }` — sous-ensemble
   strict de `SearchFilter` (le serveur interdit les propriétés additionnelles,
   `additionalProperties: false`), `Optional` pour que la clé `filter` disparaisse quand aucun filtre n'est
   actif.
10. **Corps de recherche** — EDIT `Sources/Core/Types/SearchDTOs.swift` : ajouter
    `var filter: SearchFilterDto?` à `MetadataSearchDto` (`:8-24`), documenté comme le remplaçant v3.2.0 des
    champs scalaires dépréciés.
11. **Câblage ViewModel** — EDIT `Sources/Features/Search/SearchViewModel.swift` :
    `var ocrFilterEnabled = false` (à côté de `query`/`searchMode`, `:75-77`) ; dans `dispatchSearch(page:)`
    (`:315-328`), branche `.metadata` : si `ocrFilterEnabled` et `query` non vide →
    `dto.query = nil; dto.filter = SearchFilterDto(ocr: StringSimilarityFilterDto(matches: trimmedQuery))`,
    sinon comportement inchangé ; `resetToIdle()` (`:276`) ne touche pas au drapeau. `enum ExploreField`
    (`:44`) reste inchangé — le filtre OCR n'est pas un `ExploreField` (voir approche B).
12. **Bascule dans Recherche** — EDIT `Sources/Features/Search/SearchView.swift` : bouton à côté de
    `searchModeMenu` (`:138-153`) dans le même chrome partagé — icône `text.viewfinder`, état actif teinté,
    `.accessibilityLabel("Search by detected text")`, `.accessibilityIdentifier("searchOcrFilterToggle")`,
    action `vm.queryDidChange()` (`:141`) pour relancer la frappe débouncée avec le nouveau filtre.
13. **i18n** — EDIT `Resources/Localizable.xcstrings` : entrées `Detected text`, `Search by detected text`,
    `Detected text unavailable` avec traduction `fr` (« Texte détecté », « Rechercher par texte détecté », «
    Texte détecté indisponible »). Les libellés du viewer sont des littéraux (`"Back"`, `"Slideshow"`,
    `PhotoViewer.swift:381-427`) : suivre ce précédent plutôt que d'introduire un helper, et passer par le
    flux d'extraction du catalogue pour ne pas laisser les clés sans traduction.
14. **Test du ViewModel** — NEW `Tests/OcrOverlayViewModelTests.swift` : avec `MockImmichClient` —
    chargement, tableau vide (message « rien détecté », pas d'erreur), second `load()` qui ne refait pas
    d'appel (`didLoad`), erreur réseau exposée dans `errorMessage`, annulation non remontée. `XCTest`,
    `@MainActor`, même forme que `Tests/SearchViewModelTests.swift:1-25`.
15. **Test du filtre** — EDIT `Tests/SearchViewModelTests.swift` : `ocrFilterEnabled = true` + requête →
    asserter que la requête émise porte une clé `filter.ocr.matches` renseignée et **aucune** clé `ocr`
    scalaire (le mock capture le DTO reçu, comme les tests de filtre de ville existants).
16. **Test d'encodage** — EDIT `Tests/DTOEncodingTests.swift` :
    
    `MetadataSearchDto(query: nil, filter: SearchFilterDto(ocr: StringSimilarityFilterDto(matches: "receipt")))`
    sérialisé → JSON contenant `filter.ocr.matches` et pas `filter.ocr` en chaîne.
17. `xcodegen generate` (si un fichier a été ajouté) puis suite complète `-only-testing:ImmichSwiftUITests`.

## Incertitudes à lever à l'implémentation
- **Sémantique du zoom dans `ZoomableImageView`** : je n'ai lu que les déclarations (`scale`/`offset`,
  `:43-44`) et le contrat public ; l'origine exacte de `offset` (relatif au centre du conteneur ou au coin
  supérieur gauche) décide du signe dans la formule de l'étape 6. Trancher en lisant
  `Sources/Features/PhotoViewer/ZoomableImageView.swift:98-115` (`panGesture`) et `:42-94` (`body`), puis
  vérifier visuellement les boîtes à 3× avant de figer le calque.
- **Repère de l'overlay par rapport aux métadonnées EXIF** : l'OpenAPI ne précise pas si les coordonnées
  sont relatives à l'image **originale** ou à la version orientée/redressée. Si l'image affichée est déjà
  orientée par le serveur (preview), le mapping direct est bon ; sinon il faut une rotation. Trancher avec
  une photo portrait à EXIF `Orientation=6`
  (`curl -s "$IMMICH/api/assets/$ID/ocr" -H "x-api-key: $KEY" | jq .` puis comparer les boîtes au rendu du
  preview) et, si nécessaire, lire `server/src/services/ocr.service.ts` : le paquet `@immich/ocr`
  renvoie-t-il déjà des coordonnées redressées ?
- **Comportement de la route quand l'OCR est désactivé** : le contrat ne documente qu'une réponse `200`
  (aucun `4xx`), donc un tableau vide serait indistinguable de « pas de texte ». Trancher contre un serveur
  dont `GET /api/users/me/preferences` renvoie `machineLearning.ocr.enabled == false` : si la route répond
  `400`, l'écran doit afficher « indisponible » et non « aucun texte ». Si l'on veut court-circuiter en
  amont, il faut lire `getMyPreferences` (route `GET /api/users/me/preferences`, absent de `ImmichClient`).
- **Articulation `query` + `filter` sur `/search/metadata`** : `filter` est `Added v3.2.0` sans contrainte
  croisée déclarée avec `query`. Trancher en lisant `server/src/dtos/search.dto.ts` — si `filter` et `query`
  sont mutuellement exclusifs côté serveur, garder `dto.query = nil` (étape 11) et, dans le cas contraire,
  tester les deux variantes.
- **Complétude de similarité** : `StringSimilarityFilter.matches` suggère un matching par similarité
  (trigram/FTS) et non une sous-chaîne stricte ; le comportement de recherche partielle (« recei » doit-il
  trouver « receipt » ?) n'est pas documenté. Trancher en lisant la branche `ocr` de
  `server/src/repositories/search.repository.ts` et en ajustant, si besoin, la copie d'aide sous le champ de
  recherche (pas le contrat).
