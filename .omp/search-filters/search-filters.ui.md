# Task: search-filters — UI Brief

> Compagnon de `.omp/search-filters/search-filters.specs.md` (écart G14, écrit le 2026-09-15). Ne pas
> dupliquer la spec : ce document ne décrit que la **surface** — placement, hiérarchie, gestes, états,
> tokens. Aucun filtre qui ne soit déjà déclaré dans `MetadataSearchDto` n'apparaît ici.

## Design Philosophy

L'onglet Search répond à *« montre-moi ce que je cherche »* ; il ignore aujourd'hui presque tout de ce qui
est cherché. La barre de filtres lui rend cette mémoire **visible mais discrète** : un bouton dans la barre
d'outils porte le compte des contraintes actives, une ligne de chips nomme chacune d'elles, une feuille — et
une seule — les édite toutes. Trois règles gouvernent la surface :

1. **Le filtre se voit depuis la grille.** Après « Done », les chips restent sous les yeux de l'utilisateur
   tant que le filtre est actif : il ne doit jamais se demander pourquoi un résultat manque.
2. **Rien ne se devine.** Chaque champ écrit un champ réel du contrat (`rating`, `ocr`, `city`, `state`,
   `country`, `make`, `model`, `lensModel`, `type`, `isFavorite`, `takenAfter`, `takenBefore`). Pas de
   picker de personnes, de tags ni de dossier : ils doubleraient la feuille sans servir l'objectif.
3. **Les options d'affichage ne sont pas des filtres.** Tri et densité vivent dans la même feuille — comme
   `display_option_picker.dart` — mais ne comptent pas dans le badge, ni en chip, et survivent à « Reset ».

## Placement dans la navigation

- **Point d'entrée** : un `Button` dans le `ToolbarItemGroup(placement: .topBarTrailing)` de `SearchView`
  (`Sources/Features/Search/SearchView.swift:63-67`), **inséré avant** `searchModeMenu` : le filtre agit sur
  le mode courant, il le précède donc dans la lecture gauche → droite.
- **Présentation** : `.sheet(isPresented: $showFilters) { SearchFilterSheet(vm: vm) }` attachée à
  `modeContent`, **à l'intérieur** du `NavigationStack` de `SearchView.swift:29` — ancrage fixé par
  l'étape 6 de la spec, qui évite de concurrencer l'attachement de `.searchable`.
- **La feuille déclare son propre `NavigationStack`** : elle est présentée au-dessus de l'onglet Search, pas
  poussée depuis le hub « Me » — la règle « pas de stack dans une vue poussée depuis Me » ne s'y applique pas.
- **Modes** : la feuille ne s'ouvre qu'en mode `.results` (`SearchView.swift:65`) ; en Map ou Explore le
  bouton n'est pas affiché — un filtre qui ne pilote pas la surface affichée est un piège.

## Layout

```
SearchView                                     (onglet Search, porte le NavigationStack — :29)
└── NavigationStack
    ├── .searchable(text: $vm.query)            (barre système, inchangée)
    ├── modeContent                             (:65)
    │   ├── case .results → ScrollView → VStack(spacing: PVSpacing.s12)
    │   │   ├── ActiveFiltersBar                     (si vm.isFilterActive)
    │   │   │   ├── Text("Filters")                  → searchActiveFiltersBar
    │   │   │   ├── ScrollView(.horizontal)          (conteneur : pas d'identifiant)
    │   │   │   │   └── Chip × N → Button { Text + xmark.circle.fill }
    │   │   │   │        → searchFilterChip_<champ> / searchFilterChipRemove_<champ>
    │   │   │   └── Button("Clear")                  → searchActiveFiltersClear
    │   │   ├── InlineErrorBadge                     (si la dernière requête a échoué)
    │   │   ├── PVSkeletonGrid(columns: vm.density.columnCount)   (si vm.isLoading)
    │   │   ├── LazyVGrid(columns: vm.density.columnCount, spacing: PVSpacing.s2)
    │   │   │   └── AssetThumbnailCell × N           (inchangé)
    │   │   └── ContentUnavailableView("No results")  (si vide et filtres actifs)
    │   ├── case .map → MapView (3 colonnes conservées) / case .explore → ExploreContent
    ├── .toolbar → ToolbarItemGroup(.topBarTrailing)
    │   ├── Button « Filters »                       → searchFilterButton
    │   │   └── ZStack { Image("line.3.horizontal.decrease.circle")
    │   │                Circle().fill(Color.immichPrimary) + Text(count) }  (si count > 0)
    │   └── searchModeMenu
    └── .sheet(isPresented: $showFilters) → SearchFilterSheet     → searchFilterSheet
        └── NavigationStack → Form
            ├── Section "Rating"      → StarRow (bande star-ratings) + Button("Clear")
            ├── Section "OCR text"    → PVFieldSurface { TextField }       → searchFilterOCR
            ├── Section "Location"    → PVInputGroup { City | State | Country }
            ├── Section "Camera"      → PVInputGroup { Make | Model | Lens }
            ├── Section "Type & Favourites" → Picker(nil|IMAGE|VIDEO) + Toggle
            ├── Section "Dates"       → Toggle + DatePicker(.date) × 2
            ├── Section "Display"     → Picker(Sort) + Picker(Density)
            └── .toolbar → .cancellationAction Button("Reset")  → searchFilterReset
                           .confirmationAction Button("Done")   → searchFilterDone
```

- **Fond & en-tête** : `Color.bgPrimary` sur les deux surfaces ; chips en `Color.bgSecondary` + liseré
  `Color.separatorPV`, jamais de blanc littéral. `ToolbarItem(placement: .principal) { ImmichAppBar(title:
  "Filters") }`, `.navigationBarTitleDisplayMode(.inline)`.
- **La feuille est une `Form`** : onze contrôles hétérogènes s'alignent nativement en sections et le clavier
  ne recouvre pas le champ édité.
- **La grille suit la densité** : `columns` n'est plus la constante 3 de `SearchView.swift:26` mais
  `vm.density.columnCount` ; `MapView.swift:159` reste hors périmètre (feuille de carte).

## Composants

Réutiliser, ne pas créer :

| Besoin | Composant existant |
|---|---|
| Champ texte (OCR, ville/région/pays, marque/modèle/objectif) | `PVFieldSurface` dans un `PVInputGroup` — jamais un `TextField` nu en second style |
| Barre de titre de la feuille | `ImmichAppBar` en `.principal` |
| Action principale (état vide) | `PVButtonStyle` |
| Vignette de résultat | `AssetThumbnailCell` — **inchangé**, la densité ne change que le nombre de colonnes |
| Chargement / aucun résultat / erreur | `PVSkeletonGrid(columns:)`, `ContentUnavailableView`, `InlineErrorBadge` |
| Rang d'étoiles | composant de la bande `star-ratings` (AC-5060–5069) — repris tel quel, pas redessiné |
| Compteur de filtres | `ZStack { Image + Circle().fill(Color.immichPrimary) + Text }` en `Font.pvCaption` |

- `PVHeaderBadge`, `AssetMultiSelectGrid`, `UserAvatarCircle` : non utilisés (en-têtes d'une `Form` = `Text` ;
  pas de sélection multiple ni de picker de personnes dans cette fiche).
- Les sections OCR et Rating dépendent des bandes `ocr-text` (AC-5070–5079) et `star-ratings` : elles peuvent
  être masquées le temps qu'elles atterrissent, le reste de la feuille n'en dépend pas.
- Les champs texte passent par le composant stylé du DesignSystem **si son API le permet** (Incertitude de la
  spec) ; un `TextField` nu est un repli, pas une convention.

## Interactions

| Geste | Effet |
|---|---|
| Tap « Filters » (barre d'outils) | `showFilters = true` — la feuille affiche l'état courant de `vm.filter` |
| Tap une étoile de la section Rating | écrit `vm.filter.rating` (1…5) ; le « Clear » de la section le remet à `nil` |
| Saisie « OCR text » | écrit `vm.filter.ocrText` ; chaîne vide normalisée en `nil` par le binding |
| Saisie Location / Camera | écrit le champ correspondant de `vm.filter` ; l'écriture du DTO reste à `apply(to:)` |
| Tap « Done » | `await vm.applyFilters()` puis `dismiss()` — bascule en `.metadata` si on était en CLIP, annule un éventuel drill-down Explore, **sans** le debounce de 400 ms |
| Tap « Reset » | `await vm.clearFilters()` — filtre vidé, **tri et densité conservés**, feuille non refermée |
| Tap une chip, ou sa croix | retire **ce seul** filtre (`vm.filter.<champ> = nil`) puis `await vm.applyFilters()` |
| Tap « Clear » de la barre | `await vm.clearFilters()` — même effet que « Reset », sans ouvrir la feuille |
| Tap « Reset filters » de l'état vide | `await vm.clearFilters()` — retour à un état sans filtre **et** relance |
| Changement de « Sort » / « Density » | `Task { await vm.setSort(…) }` rejoue la recherche (tri **serveur**) ; `vm.setDensity(…)` écrit et persiste **sans** refetch |
| Saisie dans la recherche système | inchangé (`queryDidChange()`, debounce 400 ms) ; **les filtres restent actifs** |
| Tap une recherche récente / sauvegardée | inchangé : elle ne porte qu'une chaîne de requête ; les filtres en place restent et ne sont **pas** enregistrés |

Un filtre appliqué pendant une requête en vol est **ignoré** (`search()` est protégée par `guard !isLoading`) :
« Done » se ferme quand même et la recherche suit — aucun état désactivé, aucune alerte.

## Liquid Glass / matériaux

Pas de `glassEffect` ici. Précédent du dépôt : le verre est réservé aux surfaces **flottantes** (barres de
recherche, bandeaux, îlot Live Activity), pas aux contenus qui défilent. La barre de chips est le **premier
élément** de la `ScrollView` : elle défile avec les vignettes, ne recouvre rien, et se contente donc de `Color.bgSecondary` + liseré `Color.separatorPV`.

## Accessibilité

- **Identifiants** (sur les éléments interactifs, **jamais** sur un conteneur qui en contient) :
  `searchFilterButton`, `searchActiveFiltersBar`, `searchFilterChip_<champ>`, `searchFilterChipRemove_<champ>`,
  `searchActiveFiltersClear`, `searchFilterSheet`, `searchFilterStar1`…`searchFilterStar5`,
  `searchFilterOCR`, `searchFilterCity`, `searchFilterState`, `searchFilterCountry`, `searchFilterMake`,
  `searchFilterModel`, `searchFilterLens`, `searchFilterType`, `searchFilterFavorite`,
  `searchFilterTakenAfter`, `searchFilterTakenBefore`, `searchFilterSort`, `searchFilterDensity`,
  `searchFilterReset`, `searchFilterDone`, `searchNoResultsReset`. `<champ>` est le nom du champ DTO :
  `rating`, `ocr`, `city`, `state`, `country`, `make`, `model`, `lensModel`, `type`, `isFavorite`,
  `takenAfter`, `takenBefore`.
- **`searchActiveFiltersBar` est posé sur le `Text("Filters")` de la barre**, frère de la zone de chips —
  jamais sur le `ScrollView` horizontal, qui écraserait les identifiants des chips : dans `LanguageToast`,
  `languageRelaunchToast` posé sur le `GlassEffectContainer` faisait porter l'identifiant au `Button` du
  bandeau, devenu introuvable (`app.buttons.matching(identifier: "languageToastDismiss").count == 0`). Même
  règle pour les `PVInputGroup` de Location et Camera : l'identifiant va sur le **champ**, pas sur le groupe.
- **VoiceOver** : chaque chip est **un** élément (`accessibilityElement(children: .combine)`) dont le label est
  une phrase complète — « Rating, 4 stars », « City, Lyon », « Taken after, 1 January 2024 » — suivi de
  `.accessibilityHint("Removes this filter")`. Jamais « Rating » puis « 4 » sur deux arrêts. Le bouton de la
  barre d'outils s'annonce « Filters, 3 active » via `accessibilityValue`, pas par la seule pastille.
- **Cibles ≥ 44 pt, Dynamic Type, couleur** : chips d'au moins `PVSpacing.s32` de haut, croix couverte par
  `contentShape(Rectangle())` sur toute la chip ; libellés en `.pvSubhead` sans `lineLimit` figé, pastille en
  `.pvCaption` (pas de `frame(width:)`) ; la présence d'un filtre ne repose jamais sur la seule couleur ; aucune animation n'est nécessaire à la compréhension (**Reduce Motion** : tableau ci-dessous).
- Chaînes neuves, toutes des clés anglaises : `Filters`, `Rating`, `OCR text`, `Location`, `City`, `State`, `Country`, `Camera`, `Make`, `Model`, `Lens`, `Type`, `Favourites`, `Dates`, `Taken after`, `Taken before`,
  `Display`, `Sort`, `Density`, `Compact`, `Comfortable`, `Large`, `Reset`, `Done`, `Clear`, `No results`.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Apparition / disparition d'une chip | `.transition(.opacity.combined(with: .scale(scale: 0.9)))`, `PVMotion.standard` | fondu conservé, échelle neutralisée |
| Compteur de filtres qui change | `.contentTransition(.numericText())` sur le `Text` de la pastille | neutralisé par le système |
| Bouton « Filters » qui passe à `.fill` | `.contentTransition(.symbolEffect(.replace))` sur l'icône | remplacement instantané |
| Grille qui change de densité | `LazyVGrid` animé par `withAnimation(PVMotion.standard)` autour de `setDensity` | changement instantané |
Aucun morphing, aucun `matchedGeometryEffect`, aucun `glassEffectID` : la barre ne se transforme pas, elle énumère. La densité est le seul changement **structurel**, et la feuille garde la présentation système de `.sheet`.

## Fichiers touchés

- NEW `Sources/Features/Search/SearchFilterSheet.swift` — la feuille, sa `Form` et ses sections.
- EDIT `Sources/Features/Search/SearchView.swift` — `@State showFilters`, `columns` dérivé de `vm.density`,
  bouton + compteur dans la barre (avant `searchModeMenu`), barre de chips, état sans résultat, feuille
  attachée à `modeContent`.
- NEW `Sources/Core/Types/SearchFilter.swift` — `SearchFilter`, `SearchSortOrder`, `SearchGridDensity`
  (source des libellés de chips et des valeurs de densité affichées ici).
- NEW `Sources/Features/Search/SearchDisplayOptionsStore.swift` — persistance du tri et de la densité.
- EDIT `Sources/Features/Search/SearchViewModel.swift` — `filter`, `sort`, `density`, `activeFilterCount`,
  `isFilterActive`, `applyFilters()`, `clearFilters()`, `setSort(_:)`, `setDensity(_:)`.
- EDIT `Sources/Core/Types/SearchDTOs.swift` — les cinq champs du DTO que la feuille alimente.
- Aucune modification de `MapView.swift`, de `searchSuggestions` ni du menu des recherches récentes.

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Poser un identifiant de groupe sur un conteneur** : il se propage et **écrase** celui des chips et des
   champs, qui deviennent introuvables en XCUITest (fait mesuré sur `languageRelaunchToast`).
2. **Croire que `clearSearch()` ou `resetToIdle()` effacent les filtres** : l'étape 4 de la spec les laisse
   volontairement intacts — la seule sortie est `clearFilters()` (chips, « Clear », « Reset »).
3. **Faire passer l'application d'un filtre par `queryDidChange()`** : le debounce de 400 ms
   (`SearchViewModel.swift:115`) retarderait l'affichage ; `applyFilters()` appelle `search()` directement.
4. **Attendre de `SmartSearchDto` qu'il respecte un filtre** : il ne porte que `query`, `page`, `size`,
   `withExif` — sans la bascule en `.metadata` les filtres sont **silencieusement ignorés** : l'écran ment.
5. **Écrire un champ que la surface ne porte pas** : `order` est déprécié et n'est jamais écrit (le tri passe
   par `orderBy`, valeurs du schéma) ; une date n'est écrite que si son `Toggle` est actif.
6. **Compter le tri et la densité dans le badge, ou poser `.badge(_:)` sur le bouton** : les options
   d'affichage ne s'affichent pas en chip et survivent à « Reset » ; la pastille est un `Text` circulaire
   superposé (`.badge(_:)` n'existe que dans une `List` ou une barre d'onglets).
7. **Empiler les onze contrôles dans le `Menu` de `searchModeMenu`** : un `Menu` de `ToolbarItemGroup`
   n'accueille ni `DatePicker` ni champ de saisie — raison mesurable du rejet de l'approche B.
8. **Inventer un filtre hors schéma, ou figer la surface** : `personIds`, `tagIds`, `albumIds`,
   `originalPath`, `originalFileName`, `description` appartiennent au drill-down People, à la feature Tags ou à
   aucune vue ; et la grille doit cesser d'être la constante 3 de `SearchView.swift:26`.
9. **Écrire un littéral français dans la vue** : la clé du catalogue est la chaîne anglaise.
