# Task: ocr-text — UI Brief

> Compagnon de `.omp/ocr-text/ocr-text.specs.md` (2026-09-15). Ne pas dupliquer la spec : ce document
> ne décrit que la **surface** — placement, hiérarchie de vues, gestes, états, tokens.

## Design Philosophy

L'OCR n'est **pas un écran**, c'est une **couche de lecture posée sur la photo**. Le viewer reste un
viewer : plein écran, chrome qui s'efface au tap. La bascule ajoute une seule chose — le texte déjà
reconnu par le serveur, replacé là où il a été vu. Aucun panneau, aucune feuille : le mode texte doit
rester allumé pendant qu'on zoome, qu'on balaye, qu'on change de photo.

Deux principes tiennent le reste du document : **l'overlay n'est jamais un acteur tactile** (ni pinch, ni
double-tap, ni swipe — il *suit* l'image), et **le chrome dit l'état, l'image ne dit rien** (les trois
états d'OCR sont des capsules du chrome, jamais un recouvrement de la photo).

## Placement dans la navigation

- **Aucune navigation nouvelle.** `PhotoViewer` est présenté par `.fullScreenCover(item:)`
  (`PhotoViewer.swift:36-50`), pas poussé : un `NavigationStack` y donnerait deux barres de navigation.
- Bascule du viewer : bouton de `topBar(_:)` (`PhotoViewer.swift:367`), **entre Slideshow et Info** —
  même groupe, même poids visuel, aucun menu.
- Bascule de Recherche : bouton du **chrome partagé** de `SearchView`, à côté de `searchModeMenu`
  (`SearchView.swift:138-153`).
- `showOcr` vit dans `PhotoViewer` (`@State`, près de `showInfo`/`infoVM`, `:138-139`) et **survit au
  changement de page** : chaque page recharge ses boîtes, l'overlay ne se rallume pas page par page.

## Layout

```
PhotoViewer (.fullScreenCover(item: PhotoViewerPresentation))      — AUCUN NavigationStack
└── ZStack(alignment: .top)
    ├── pager (TabView .page) — inchangé
    │   └── ZoomableImageView(asset:token:showOcr:ocrBoxes:…)      — seul détenteur de scale/offset
    │       └── GeometryReader { proxy in                          ← ajouté par la feature
    │           ├── AuthenticatedAsyncImage(.fit)
    │           │       .frame(proxy.size).scaleEffect(scale).offset(offset)
    │           │       .gesture(MagnifyGesture) / DragGesture / 2× tap   — inchangés
    │           └── .overlay { if showOcr { OcrOverlayView(…) } }
    │                 ├── Canvas → quadrilatères 1,5 pt + étiquettes (police FIXE)
    │                 └── .accessibilityRepresentation { liste des text }  ← VoiceOver
    │                     .allowsHitTesting(false)                 — jamais de geste ici
    ├── topBar(_:)  HStack : [Back] …… [Slideshow] [OCR] [Info]
    └── capsule d'état OCR (sous le topBar) : « Analyzing… » / « No text found » /
        « Detected text unavailable »                              — jamais sur l'image
```

`imageRect` = image aspect-fit **avant** zoom : `AVMakeRect(aspectRatio:insideRect:)` avec `asset.ratio`
(`ZoomableImageView.swift:23`), recalculé à chaque rotation par le `GeometryReader` ; une seule capsule
flottante au-dessus de la photo (opaque, ~28 pt), effacée dès que `boxes` est non vide.

## Composants

| Besoin | Composant existant |
|---|---|
| Barre du haut du viewer | `ImmichAppBar` (déjà dans `topBar(_:)`) — on y ajoute un bouton |
| Bascule (viewer et recherche) | bouton icône du chrome, état actif teinté `Color.immichPrimary` |
| Capsule d'état | motif local du chrome : `Color.bgPrimary` + `PVRadius.full` |
| Erreur non bloquante | `InlineErrorBadge` si la capsule doit porter un texte long |

```swift
/// Sources/Features/PhotoViewer/OcrOverlayView.swift — contrat (spec étape 6).
struct OcrOverlayView: View {
    let boxes: [AssetOcrResponseDto]   // quad = 4 coins normalisés 0-1, PAS une bbox
    let imageRect: CGRect              // aspect-fit dans le viewport, AVANT zoom
    let scale: CGFloat, let offset: CGSize, let viewportSize: CGSize

    var body: some View {
        Canvas { context, _ in
            for box in boxes {
                let quad = box.quad.path(in: imageRect, scale: scale, offset: offset, viewport: viewportSize)
                context.stroke(quad, with: .color(.immichPrimary), lineWidth: 1.5)  // largeur constante
                context.fill(quad, with: .color(.immichPrimary.opacity(0.18)))
                if box.isConfident { context.draw(label(box.text), at: anchor(box), anchor: .bottomLeading) }
            }
        }
        .allowsHitTesting(false)              // ← protège le pinch, le pan et le double-tap
        .accessibilityRepresentation { OcrTextBoxList(boxes: boxes.filter(\.isConfident)) }
    }
}
```

Une **seule** formule de mapping, documentée dans le fichier : `p = (imageRect.minX + nx *
imageRect.width, imageRect.minY + ny * imageRect.height)` puis `p' = viewportCenter + (p -
viewportCenter) * scale + offset` — cohérent avec `.scaleEffect(scale)` (ancre `.center`) suivi de
`.offset(offset)` (`ZoomableImageView.swift:53-55`). C'est elle qui fait coller les boîtes à 4×.

Bouton de bascule, dans `topBar(_:)` : `Button { showOcr.toggle() } label: { Image(systemName:
"text.viewfinder") }` — `.accessibilityLabel("Detected text")`, `.accessibilityValue(showOcr ? "on" :
"off")`, `.accessibilityIdentifier("viewerOcrToggle")` (sur le bouton, **jamais** sur la `HStack`) et
`.disabled(currentAsset?.isImage != true)` : une vidéo n'a pas d'OCR.

## Interactions

| Geste | Effet |
|---|---|
| Tap `viewerOcrToggle` | `showOcr.toggle()` ; à l'allumage `Task { await ocrVM.load() }` — idempotent par `assetId` (`didLoad`) |
| Pinch / pan, overlay affiché | **inchangés** : la photo zoome et se déplace, les boîtes suivent via `scale`/`offset` |
| Double-tap, overlay affiché | zoome à 3× (geste du `ZoomableImageView`) ; l'overlay suit, il ne consomme pas le tap |
| Tap simple, overlay affiché | masque/affiche le chrome **et** l'overlay (comportement existant du viewer) |
| Swipe de page | la page suivante charge son OCR ; overlay vide, capsule « Analyzing… » |
| Rotation de l'appareil | `GeometryReader` recalcule `viewportSize`/`imageRect` ; rien d'autre à écrire |
| Page vidéo avec `showOcr == true` | bouton désactivé (`.disabled`), overlay vide |
| Tap `searchOcrFilterToggle` | `vm.ocrFilterEnabled.toggle()` puis `vm.queryDidChange()` — relance la frappe débouncée |
| Tap sur une boîte | **rien** : pas de sélection, pas de copie (hors périmètre de la spec) |

**Pourquoi l'overlay ne prend aucun geste.** `ZoomableImageView` attache `MagnifyGesture`, le
`DragGesture` (high-priority quand zoomé) et les deux `onTapGesture` **au contenu image**, et lit
`scale`/`offset` depuis son `@State private` (`:43-44`). Un overlay hit-testable les avalerait dès qu'il
aurait une `contentShape` ou un enfant interactif : pinch perdu, double-tap perdu, pan saccadé — et le
viewer a déjà un `onTapGesture` simple pour le chrome, donc un conflit de hit-test se traduit par un
chrome qui ne revient plus. D'où `.allowsHitTesting(false)` sur toute la couche.

**Pourquoi pas de « copier le texte ».** La spec l'exclut (§ Hors périmètre) : l'overlay est une couche
de lecture, pas un document — le repli accessible donne le texte à VoiceOver sans sélection.

## Liquid Glass / matériaux

- **Aucun `glassEffect` dans l'overlay.** Une boîte doit se lire sur une photo claire *et* sombre ; le
  verre, qui échantillonne ce qu'il y a dessous, donne l'inverse (contraste variable). Précédent du
  dépôt : le verre est réservé aux surfaces flottantes du chrome, jamais à un calque de contenu.
- **Contraste, la seule règle qui compte ici** :
  - **Tracé** : `Color.immichPrimary`, **1,5 pt à largeur constante** (jamais multipliée par `scale`),
    plus un voile `opacity(0.18)` — visible sur un ciel blanc comme sur une nuit noire.
  - **Étiquette** : capsule **opaque** `Color.bgPrimary`, `Font.pvCaption` en `Color.textPrimaryPV`,
    `PVRadius.sm`, bord `Color.separatorPV` : le contraste suit le thème, pas la photo.
  - **Interdits** : texte blanc à même la photo, `Color.black.opacity(…)` ou blanc littéral,
    `.blendMode` / `.plusLighter` (imprévisible sur des JPEG bruités).
- La capsule d'état reprend `Color.bgPrimary` opaque + `PVRadius.full`.

## Accessibilité

- **Identifiants** (sur les éléments interactifs ou les feuilles, jamais sur un conteneur qui en
  contient) : `viewerOcrToggle`, `viewerOcrStatusText`, `viewerOcrLoadingIndicator`,
  `viewerOcrText_<index>`, `searchOcrFilterToggle`.
- **La représentation est obligatoire** : l'overlay est `allowsHitTesting(false)` et un `Canvas` n'expose
  aucun élément ; sans `.accessibilityRepresentation`, `viewerOcrText_<index>` serait introuvable en
  XCUITest. Elle expose `boxes.filter(\.isConfident)` dans l'ordre du ViewModel (`textScore` décroissant
  puis `topLeft.y`), hors hiérarchie visuelle (`.opacity(0)` interdit : il retirerait l'accessibilité).
- **VoiceOver** : le bouton annonce « Detected text » puis « on »/« off » (`accessibilityValue`) ; les
  boîtes sont lues **dans l'ordre du texte**, jamais dans l'ordre du tableau serveur. Un texte non
  confiant est tracé mais ni étiqueté ni annoncé.
- **Cibles ≥ 44 pt et Dynamic Type** : padding du chrome existant pour les deux bascules ; étiquettes en
  `Font.pvCaption`, capsule en `.pvSubhead`, `.lineLimit(2)` avec troncature, aucun `frame(width:)` figé.
- **Reduce Motion** : fondu d'apparition sauté si `accessibilityReduceMotion` ; rien d'autre ne bouge.
- **Langue** : chaînes = **clés anglaises** (`Detected text`, `Search by detected text`, `Detected text
  unavailable`, `Analyzing…`, `No text found`) traduites dans `Resources/Localizable.xcstrings`.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Allumage / extinction de l'overlay | `.opacity` avec `PVMotion.standard` | `withAnimation` sauté |
| Chargement en cours | `ProgressView()` indéterminé de 16 pt dans la capsule | texte seul |
| Arrivée des boîtes | aucune animation par boîte : bloc unique (opacité de la couche) | idem |
| Zoom / pan de la photo | existant (`PVMotion.snappy`) — l'overlay suit passivement | système |

Le `ProgressView()` indéterminé est **assumé** : l'interdit mesuré sur « Sync Status » visait une
progression dont la fraction est connue (le run de backup) ; la route OCR n'en expose aucune.

## Fichiers touchés

- NEW `Sources/Features/PhotoViewer/OcrOverlayView.swift` — `Canvas`, mapping, représentation VoiceOver
  (spec étape 6) ; NEW `OcrOverlayViewModel.swift` — `boxes`/`isLoading`/`didLoad`/`errorMessage` (5).
- NEW `Sources/Core/Types/AssetOcrDTOs.swift` — `AssetOcrResponseDto` (13 champs), `quad`, `isConfident`
  (spec étape 1) ; NEW `SearchFilterDTOs.swift` — `SearchFilterDto` / `StringSimilarityFilterDto` (9).
- EDIT `Sources/Features/PhotoViewer/ZoomableImageView.swift` — `ocrBoxes`/`showOcr`, `GeometryReader`,
  `.overlay`, capsule d'état (7) ; EDIT `PhotoViewer.swift` — `showOcr`, `ocrVM`, `refreshOcr()`, bouton
  `viewerOcrToggle` dans `topBar(_:)` (8).
- EDIT `Sources/Features/Search/SearchView.swift` — `searchOcrFilterToggle` près de `searchModeMenu`, +
  `ocrFilterEnabled` (`SearchViewModel`) et `filter` (`MetadataSearchDto`) (10-12) ; EDIT
  `Resources/Localizable.xcstrings` — 5 clés anglaises + `fr` (13).
- EDIT `ImmichClient.swift`, `ImmichAPIClient.swift`, `MockImmichClient.swift`,
  `OcrOverlayViewModelTests.swift`, `SearchViewModelTests.swift`, `DTOEncodingTests.swift` (2-4, 14-16).

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Poser l'overlay en frère du pager dans `PhotoViewer`** (ou remonter le zoom au parent) :
   `scale`/`offset` sont `@State private` dans `ZoomableImageView` (`:43-44`) ; un calque frère ne peut
   pas les lire, donc dès 1,01× les boîtes restent figées pendant que la photo bouge — c'est le fait qui
   a écarté l'approche B du haut de la spec.
2. **Dessiner un `CGRect` / `Path(rect:)` ou mettre l'overlay *dans* le `.scaleEffect(scale)`** :
   `x1..x4`/`y1..y4` sont quatre **coins** normalisés (boîte inclinable), et l'overlay interne verrait
   ses étiquettes grossir à 3× et ses traits s'épaissir à 4×.
3. **Rendre l'overlay hit-testable** (`contentShape`, `onTapGesture`, enfant `Button`) : le pinch, le
   double-tap et le pan sont attachés au contenu image, un calque au-dessus les avale.
4. **Poser `accessibilityIdentifier("viewerOcrToggle")` sur la `HStack` du `topBar`** : un identifiant de
   conteneur se propage et **écrase** ceux de ses descendants (mesuré sur `languageRelaunchToast`, où le
   bouton devenait introuvable par son propre identifiant).
5. **Utiliser le champ scalaire `ocr` de `MetadataSearchDto`** : déprécié `v3.2.0` au même cycle que la
   feature ; le remplaçant est `filter.ocr.matches` (`StringSimilarityFilter`).
6. **Afficher une alerte bloquante** quand `GET /api/assets/{id}/ocr` échoue : l'erreur vit dans une
   capsule du chrome (« Detected text unavailable »), la photo reste consultable. Et **ne jamais
   confondre « aucun texte » et « OCR indisponible »** : tableau vide → « No text found » ; échec ou OCR
   désactivé côté serveur → « Detected text unavailable ».
7. **Utiliser `ContentUnavailableView` pour « aucun texte »** : le viewer est plein écran, on ne remplace
   pas la photo par un état vide. **Filtrer les boîtes côté client** est l'autre erreur : `isConfident`
   est un seuil d'affichage de l'étiquette, pas un filtre de données.
8. **Ajouter une sélection ou un bouton « Copy »** (hors périmètre) ; **déclarer un `NavigationStack`**
   dans le viewer, qui est un `.fullScreenCover(item:)` ; **écrire un littéral français** dans la vue.
