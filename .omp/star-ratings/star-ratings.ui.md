# Task: star-ratings — UI Brief

> Compagnon de `.omp/star-ratings/star-ratings.specs.md` (écrit le 2026-09-15). Ne pas dupliquer la spec :
> ce document ne décrit que la **surface** — placement, hiérarchie de vues, gestes, états, tokens.

## Design Philosophy

Une seule question, cinq cibles : **« combien d'étoiles, et comment la retirer ? »**. La note n'est pas un réglage mais un geste immédiat : la barre est posée au sommet du panneau de détails, en tête de lecture, pour qu'un tap suffise — aucun sous-écran, aucune feuille, aucune confirmation (noter n'est pas destructeur). Le vocabulaire est celui du panneau existant (`InfoCard`, `Label` + `pvCaption.weight(.semibold)`, fonds `bgSecondary`) : la carte de note doit être indiscernable d'une carte `tagsCard`/`stackCard` posée à côté d'elle.

**Point le plus fragile de toute la fiche : « non noté » n'est pas « 0 étoile ».** Le serveur depuis v3 n'accepte que trois états — `1…5`, `-1` (rejeté, hors périmètre UI) et `null` ; `0` est **invalide**, et l'encodeur synthétisé d'un `Int?` nil *omet* la clé au lieu d'envoyer `null`. C'est pourquoi la dénotation passe par `RatingUpdateDto`, et pourquoi l'UI ne doit jamais présenter la barre vide comme un zéro. Concrètement : **cinq étoiles creuses = non noté**, **une étoile pleine + quatre creuses = note 1**. Ces deux états ne se ressemblent pas, et la barre n'affiche jamais le nombre.

## Placement dans la navigation

- **Carte du panneau de détails**, pas un écran : `PhotoInfoPanel` est présenté en `.sheet` par `PhotoViewer` (`Sources/Features/PhotoViewer/PhotoViewer.swift:269-281`) avec `.presentationDetents([.fraction(0.7), .large])` et `.presentationDragIndicator(.visible)`.
- La carte est le **premier enfant du `ScrollView` de `content`** (`PhotoInfoPanel.swift:100-116`), avant `facesCard` (`:103`). Raison : au detent court le premier écran montre ~3 cartes en moyenne, et 5 cibles de 44 pt font 220 pt de large — la rangée doit tomber au-dessus de la ligne de flottaison de `.fraction(0.7)`.
- Aucun `NavigationStack`, aucune feuille, aucun onglet neuf : la carte hérite du sheet existant et de son bouton de fermeture (`onClose`).
- Le filtre de note, lui, vit dans la barre d'outils de `SearchView` (branche `vm.viewMode == .results`, `SearchView.swift:63-80`), **avant** `searchModeMenu`, et n'existe que là : en Explore et en Map il n'y a pas de grille à filtrer (même traitement que `searchModeMenu`).
- Le filtre est **mono-valeur** (« Any rating » + 1…5) : décision de la spec (approche A, §Étapes 10), pas un multi-choix. Le bucket « Unrated » reste hors périmètre parce qu'un `Int?` nil ne s'exprime pas dans `MetadataSearchDto.rating`.

## Layout

```
PhotoViewer
└── .sheet(isPresented: $showInfo)                       detents [.fraction(0.7), .large]
    └── PhotoInfoPanel                                   VStack(spacing: PVSpacing.s0)
        ├── header                                       (existant : date longue, bouton fermer)
        └── content                                      guard: vm?.detail?.exifInfo != nil
            └── ScrollView
                ├── ratingCard                ← NEW, premier enfant
                │   └── InfoCard                                 (PhotoInfoPanel.swift:439)
                │       └── VStack(alignment: .leading, spacing: PVSpacing.s8)
                │           ├── Label("Rating", systemImage: "star.fill")
                │           │       .font(.pvCaption.weight(.semibold))   (motif tagsCard)
                │           ├── PVRatingBar(rating: vm.rating,
                │           │               isEnabled: !vm.isSavingRating,
                │           │               onRate: { await vm.setRating($0) },
                │           │               onClear: { await vm.setRating(nil) })
                │           │   └── HStack(spacing: PVSpacing.s4)
                │           │       └── ForEach(1...5, id: \.self) → Button
                │           │             └── Image(systemName: value <= (rating ?? 0)
                │           │                                   ? "star.fill" : "star")
                │           │                   .font(.system(size: 28))
                │           │                   .frame(width: 44, height: 44)   ← cible tactile
                │           ├── Button("Clear rating")        ← si vm.rating != nil
                │           │       .buttonStyle(PVSubtleButtonStyle())
                │           └── InlineErrorBadge(message:)    ← si vm.errorMessage != nil
                ├── facesCard(faces: vm?.faces ?? [])            (existant)
                ├── tagsCard(tags: detail.tags)                  (existant)
                ├── stackCard(stack: detail.stack)               (existant)
                └── ExifInfoPanel(…)                            (existant)
                    └── fileItems  ← la ligne ("star.fill", exif.rating…) est RETIRÉE (:305)

SearchView — branche vm.viewMode == .results
└── .toolbar → ToolbarItemGroup(placement: .topBarTrailing)
    ├── ratingFilterMenu                  ← NEW, avant searchModeMenu
    │   └── Menu
    │       └── Picker("Rating", selection: <Binding<Int?>>)
    │           ├── Label("Any rating", systemImage: "star").tag(Int?.none)
    │           └── ForEach(1...5, id: \.self)
    │                 Label("%lld star", systemImage: "star.fill").tag(Int?.some(value))
    └── searchModeMenu (existant)
```

- **Une seule source par état** : la note n'est plus affichée qu'à un endroit. La ligne `("star.fill", exif.rating.map { String($0) })` de `fileItems` (`PhotoInfoPanel.swift:305`) est retirée : elle rendait un « 3 » nu avec un glyphe d'étoile, donc indistinguable d'un « 1 » dans la même grille, et muette sur l'état non noté (`compactMap` la faisait disparaître — une absence de donnée, pas un choix). Le nombre n'est rendu nulle part.
- **Rien à rendre avant la donnée** : `content` ne s'affiche que si `vm?.detail?.exifInfo` existe — la barre lit donc toujours une note déjà chargée. Aucun état « note inconnue », aucun `ProgressView` propre à la carte.
- **`-1` (rejeté)** : la barre le rend comme non noté (aucune étoile pleine), parce que la grammaire 5 étoiles n'a pas d'état « rejeté » et que l'UI n'écrit jamais `-1`. Aucun libellé ne dit « Rejected ». Re-noter un asset rejeté l'écrase donc — assumé et documenté ici (spec §Hors périmètre, §Incertitudes).
- **`rating` est local d'abord** : le tap écrit `vm.rating` immédiatement, puis le `PATCH /api/assets/:id` renvoie l'`AssetResponseDto` à jour, adopté dans `vm.detail` — la barre ne se resynchronise pas par un second `getAsset`.
- **Label du menu de filtre** : `Image(systemName: vm.ratingFilter == nil ? "star" : "star.fill")`, teinté `Color.immichPrimary` quand un filtre est actif (il doit rester visible menu fermé), `.accessibilityLabel("Rating filter: …")`. Un `Picker` lié à un `Int?` exige un `Binding` explicite avec `.tag(Int?.none)` — sans lui, `nil` et `0` se confondent dans la sélection.

## Composants

| Besoin | Composant |
|---|---|
| Barre d'étoiles | **NEW** `PVRatingBar` (`Sources/DesignSystem/Components/PVRatingBar.swift`) — entrées `rating: Int?`, `isEnabled`, `onRate: (Int) -> Void`, `onClear: () -> Void` |
| Carte de la note | `InfoCard` (privé à `PhotoInfoPanel.swift:439`) — même contenant que `tagsCard`/`stackCard` |
| En-tête de carte | `Label("Rating", systemImage: "star.fill")` en `.font(.pvCaption.weight(.semibold))` (motif `tagsCard`, `:177`) |
| Bouton de dénotation | `PVSubtleButtonStyle` — jamais un bouton texte nu |
| Échec d'écriture | `InlineErrorBadge(message: vm.errorMessage)` (`Sources/DesignSystem/Components/InlineErrorBadge.swift:11`) |
| Menu de filtre | `Menu` + `Picker` — motif `searchModeMenu` (`SearchView.swift:138-151`) |
| Résultat vide après filtre | `ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text("Try a different search term."))`, déjà rendu par `SearchView.resultsContent` (`:180-190`) — aucune chaîne neuve |

Pas de nouveau composant côté recherche : le filtre est un état du `SearchViewModel`, pas une vue.

## Interactions

| Geste | Effet |
|---|---|
| Tap sur l'étoile *n* (n ≠ note courante) | `onRate(n)` → `Task { await vm.setRating(n) }` : état local écrit tout de suite, PATCH `{"rating": n}` part, haptique `.selection` |
| Tap sur l'étoile **déjà courante** | `onClear()` → `vm.setRating(nil)` → PATCH `{"rating": null}` (parité `rating_bar.widget.dart`, où re-taper renvoie `0`) |
| Tap « Clear rating » | Idem `setRating(nil)` : porte VoiceOver explicite du même geste, puisque « re-taper » n'est pas énonçable |
| Tap pendant un aller-retour | Ignoré : `isSavingRating` garde la porte (choix assumé : pas de file d'attente de requêtes) |
| **Échec réseau / hors ligne** | `catch` : `vm.rating` est **restauré à la valeur d'avant le tap** (contrat de `PhotoViewer.toggleFavorite`, `PhotoViewer.swift:717-729`) et `errorMessage` est posé → `InlineErrorBadge` sous la barre. Rien n'est mis en file d'attente hors ligne (aucun ledger, aucune outbox de note), le sheet ne se ferme pas, la barre redevient active |
| Hors ligne, détail **déjà** chargé | La barre reste manipulable : le tap est optimiste, le PATCH échoue, l'état revient — l'utilisateur voit le retour arrière plutôt qu'un bouton mort |
| Sélection du `Picker` de filtre | `Task { await vm.setRatingFilter(v) }` : force `searchMode = .metadata` quand `v != nil` (`SmartSearchDto` n'a aucun champ de filtre), puis relance `search()` |
| « Any rating » | `setRatingFilter(nil)` → `dto.rating` retiré, mode conservé |
| Édition du texte de recherche | Le filtre **survit** (sticky) ; seuls « Any rating » et `clearSearch()` le retirent |

Les états désactivés sont portés par les contrôles (`.disabled(...)`, `.opacity(0.5)` sur la barre pendant l'aller-retour), jamais par une alerte : un tap refusé ne produit aucune modale.

## Liquid Glass / matériaux

Pas de `glassEffect` sur la carte : le panneau **est déjà** une feuille native, dont le fond et le chrome sont le verre du système — ajouter du verre à l'intérieur doublerait le matériau. Précédent du dépôt : le verre est réservé aux surfaces **flottantes** (barres de recherche, bandeaux, îlot Live Activity), pas aux cartes de contenu d'un sheet — `tagsCard`, `stackCard` et `ExifInfoPanel` n'en utilisent aucun. La carte garde le fond `Color.bgSecondary` d'`InfoCard` et les séparateurs `Color.separatorPV`. Le `Menu` de filtre, lui, hérite du verre de la barre d'outils système : rien à poser explicitement.

## Accessibilité

- **Identifiants** — sur les éléments **interactifs** uniquement, jamais sur l'`InfoCard` ni sur le `HStack` de la barre (un identifiant de conteneur écrase ceux de ses enfants ; mesuré sur `languageRelaunchToast`) : `assetRatingStar_1`, `assetRatingStar_2`, `assetRatingStar_3`, `assetRatingStar_4`, `assetRatingStar_5`, `assetRatingClearButton`, `searchRatingFilterMenu`.
- **VoiceOver** — chaque étoile est un `Button` à part entière, `.accessibilityLabel(Text("Rate \(value) stars"))`, remplacé par `Text("Remove rating")` sur l'étoile **courante** : sans cela le geste « re-taper pour retirer » est inatteignable au lecteur d'écran. L'état non noté s'énonce par les libellés (« Rate 1 star… »), jamais par un zéro. La carte n'est **pas** fusionnée en un seul élément (`accessibilityElement(children: .combine)` interdirait de viser une étoile).
- **Cibles ≥ 44 pt** — chaque `Button` porte `.frame(width: 44, height: 44)` autour d'un glyphe de 28 pt (équivalent des `itemSize: 40` upstream). « Clear rating » est en `PVSubtleButtonStyle` (`minHeight: 44`).
- **Dynamic Type** — le glyphe garde 28 pt (un SF Symbol dans un `Image` ne suit pas la taille de texte) ; aucun `.frame(height:)` figé sur la carte, aucune troncature de libellé. Le signal textuel de l'état (« Clear rating ») est un élément de la pile, pas une icône : il reste lisible aux tailles d'accessibilité.
- **Reduce Motion** — voir la table ci-dessous : rien à neutraliser à la main, `PVMotion.adaptive` est le seul chemin d'animation de l'apparition.
- **Retour haptique** — le dépôt le permet : `.sensoryFeedback(.selection, trigger: vm.rating)` sur la barre, même forme non optionnelle que les sites existants (`PhotoViewer.swift:948-950`, `TrashView.swift:44-45`, `SlideshowView.swift:276`). Aucun réglage global de haptique n'existe dans le dépôt : rien à gater aujourd'hui.
- **Chaînes** — clés anglaises, extraction au build, aucune écriture dans le `.xcstrings` : `Rating`, `Clear rating`, `Any rating`, `%lld star`, `Rate %lld stars`, `Remove rating`. Aucun littéral français.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Remplissage / dé-remplissage d'une étoile | `.contentTransition(.symbolEffect(.replace))` sur l'`Image` | remplacement instantané (système) |
| Apparition de la carte au premier chargement | `.transition(.opacity)` animé par `PVMotion.adaptive(PVMotion.standard, reduceMotion:)` | fondu conservé, ressort retiré |
| Entrée en aller-retour (`isSavingRating`) | `.animation(PVMotion.snappy, value: vm.isSavingRating)` sur l'opacité de la barre | neutralisé |
| Menu de filtre | animation système du `Menu` | système |

Aucun `matchedGeometryEffect`, aucun `glassEffectID`, aucun morphing : la barre ne se transforme pas, sa valeur change. `contentTransition(.numericText())` est réservé aux compteurs — il n'y a pas de chiffre ici.

## Fichiers touchés

- NEW `Sources/DesignSystem/Components/PVRatingBar.swift` — 5 `Button` de 44 pt, remplissage indexé, re-tap = clear, haptique. Seul atome neuf.
- EDIT `Sources/Core/Types/DTOs.swift` — `RatingUpdateDto` / `RatingValue` (le `null` explicite de dénotation).
- EDIT `Sources/Core/Protocols/ImmichClient.swift` — `setAssetRating(id:rating:)`.
- EDIT `Sources/Services/ImmichAPIClient.swift` — `PATCH /api/assets/:id` avec `AnyEncodable(RatingUpdateDto(...))`.
- EDIT `Sources/Features/AssetDetail/AssetDetailViewModel.swift` — `rating`, `isSavingRating`, `setRating(_:)` optimiste + revert.
- EDIT `Sources/Features/PhotoViewer/PhotoInfoPanel.swift` — `ratingCard` en tête de `content`, **et** retrait de la ligne `star.fill` de `fileItems` (`:305`).
- EDIT `Sources/Core/Types/SearchDTOs.swift` — `MetadataSearchDto.rating: Int?`.
- EDIT `Sources/Features/Search/SearchViewModel.swift` — `ratingFilter`, `setRatingFilter(_:)`, câblage dans `dispatchSearch(page:)` et `clearSearch()`.
- EDIT `Sources/Features/Search/SearchView.swift` — `ratingFilterMenu` avant `searchModeMenu`.
- EDIT `Tests/Mocks/MockImmichClient.swift` — conformité `setAssetRating` + capture des appels.
- EDIT `Tests/AssetDetailViewModelTests.swift`, `Tests/DTOEncodingTests.swift`, `Tests/SearchViewModelTests.swift` — cas de la spec.
- Commande `xcodegen generate` (un fichier source neuf), puis suite `-only-testing:ImmichSwiftUITests`.

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Poser `accessibilityIdentifier("assetRatingBar")` sur le `HStack`** : un identifiant de conteneur écrase ceux de ses enfants (leçon `languageRelaunchToast`), les cinq étoiles deviendraient invisibles aux tests et à VoiceOver. Les identifiants vont sur les `Button`.
2. **Envoyer `0` pour dénoter** : `0` est invalide depuis la v3 du schéma serveur, et l'encodeur synthétisé d'un `Int?` nil **omet** la clé — dénoter exige `RatingUpdateDto` avec un `encodeNil()` du `singleValueContainer`. Le libellé « 0 star » n'existe donc ni dans la barre ni dans le menu.
3. **Laisser la ligne `star.fill` dans `fileItems`** (`PhotoInfoPanel.swift:305`) : la note s'afficherait deux fois, une fois en nombre nu dans la carte File, une fois en étoiles — et la première est muette sur l'état non noté.
4. **Faire porter le filtre par le mode Smart** : `SmartSearchDto` n'a que `query`/`page`/`size`/`withExif`, le filtre serait perdu en silence ; `setRatingFilter(_:)` force `.metadata`.
5. **Lier le `Picker` directement à `vm.ratingFilter` sans `Binding` explicite ni `.tag(Int?.none)`** : `nil` et `0` se confondent dans la sélection, et une sentinelle `0` réintroduirait un état que le serveur n'accepte plus.
6. **Câbler `onDataChanged` depuis la carte de note** : chaque tap relancerait la recherche complète de l'onglet (`SearchView.swift:96-100`). Les grilles déjà chargées gardent leur contenu — assumé.
7. **Afficher un état in-flight plein écran** (`ProgressView()` ou overlay) pendant le PATCH : l'aller-retour est court et la barre le porte déjà (`.disabled` + `.opacity(0.5)`) ; un overlay ferait clignoter le sheet.
8. **Ajouter un `NavigationStack`, une feuille ou une confirmation dans la carte** : elle vit dans le sheet existant de `PhotoViewer`, et noter n'est pas destructeur.
9. **Inventer une surface « Rejected »** (icône, libellé, couleur) pour `rating == -1` : aucune maquette upstream, et l'UI n'écrit jamais `-1`.
10. **Écrire un littéral français ou une chaîne non clé dans la vue** : la clé du catalogue **est** la chaîne anglaise (`sourceLanguage = en`), l'extraction se fait au build.
