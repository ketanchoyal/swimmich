# Task: search-filters

Status: planifié — **aucune AC ouverte** (écart G14 du registre `.omp/backlog/ImmichSwiftUI-backlog.md` §2.17 — le
client Flutter porte `mobile/lib/widgets/search/search_filter/{star_rating_picker,display_option_picker,
media_type_picker,people_picker,location_picker,camera_picker}.dart`, l'onglet Search d'iOS n'a aucun état de
filtre).

## Plan (résumé)

**Objectif** : une feuille « Filters » ouverte depuis la barre de l'onglet Search contraint la recherche par
note (1–5 étoiles), texte détecté (OCR), lieu (ville/région/pays), appareil (marque/modèle/objectif), type de
média, favoris et plage de dates de prise de vue ; deux options d'affichage persistantes (ordre de tri, densité
de la grille) vivent dans la même feuille ; le nombre de filtres actifs est visible sur le bouton de la barre et
un effacement global est à un geste.

**Approche retenue** : A — un état de filtre **valeur** `SearchFilter` porté par `SearchViewModel`, projeté
dans le DTO par une méthode unique (`apply(to:)`) réutilisant `ExploreField.apply(_:to:)`, plus une feuille
`SearchFilterSheet` sans logique et un `SearchDisplayOptionsStore` (UserDefaults) pour le tri et la densité. Les
approches B (tout dans le `Menu` de `topBarTrailing` — un `Menu` n'accueille ni `DatePicker` ni champ de saisie)
et C (n'envoyer que le nœud `filter` non déprécié — objet imbriqué absent du DTO, matrice de compatibilité
serveur) sont rejetées dans la spec.

**Étapes** : (1) NEW `Sources/Core/Types/SearchFilter.swift` ; (2) EDIT `Sources/Core/Types/SearchDTOs.swift`
(cinq champs + doc-comments de dépréciation) ; (3) NEW `Sources/Features/Search/SearchDisplayOptionsStore.swift` ;
(4) EDIT `Sources/Features/Search/SearchViewModel.swift` ; (5) NEW `Sources/Features/Search/SearchFilterSheet.swift` ;
(6) EDIT `Sources/Features/Search/SearchView.swift` ; (7) NEW `Tests/SearchFilterTests.swift` ;
(8) `xcodegen generate` + suite complète `-only-testing:ImmichSwiftUITests` (log `/tmp/immich_searchfilters_test.log`).

**Incertitudes** (à lever à l'implémentation, cf. spec § Incertitudes) : raw values de `orderBy` (schéma
`SearchOrder`) ; segment « Unrated » (`rating: null` inexprimable, `encodeIfPresent` omet la clé) ; symbole exact
de l'étoile à reprendre de la bande `star-ratings` (AC-5060–5069) ; composant de champ du DesignSystem ;
`compact` à 5 ou 4 colonnes selon les contraintes d'`AssetThumbnailCell` ; rendu du compteur sur un `Button` de
toolbar (pas de `.badge(_:)` hors `List`) ; pas de stub de recherche dans `UITests/` (preuve bornée aux tests du
ViewModel et au rendu de la feuille).

**Hors périmètre** : picker de personnes, picker de tags, migration vers le nœud `filter`, persistance d'un
filtre dans les recherches sauvegardées, modes Map/Explore, recherche par dossier/nom de fichier/description.

## Critères

```
### AC-5130 [type: new]
Assertion: `SearchFilter` porte exactement les champs du DTO de recherche — `rating`, `ocrText` (projeté sur
`MetadataSearchDto.ocr`), `city`, `state`, `country`, `make`, `model`, `lensModel`, `type`, `isFavorite`,
`takenAfter`, `takenBefore` — avec `isEmpty`, `activeCount`, `none` et une écriture unique `apply(to:)` déléguée
à `ExploreField` pour les six champs EXIF (un seul endroit sait écrire `city`/`country`/`make`/`model`/`state`/
`lensModel`).
Check post-impl: sh -c 'f=Sources/Core/Types/SearchFilter.swift; test -f "$f" && grep -qE "struct SearchFilter: Equatable" "$f" && grep -qE "var rating: Int\?" "$f" && grep -qE "var ocrText: String\?" "$f" && grep -qE "var city: String\?" "$f" && grep -qE "var state: String\?" "$f" && grep -qE "var country: String\?" "$f" && grep -qE "var make: String\?" "$f" && grep -qE "var model: String\?" "$f" && grep -qE "var lensModel: String\?" "$f" && grep -qE "var type: String\?" "$f" && grep -qE "var isFavorite: Bool\?" "$f" && grep -qE "var takenAfter: Date\?" "$f" && grep -qE "var takenBefore: Date\?" "$f" && grep -qE "var isEmpty: Bool" "$f" && grep -qE "var activeCount: Int" "$f" && grep -qE "static let none" "$f" && grep -qE "func apply\(to dto: inout MetadataSearchDto\)" "$f" && grep -qE "ExploreField" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — `ls Sources/Core/Types/SearchFilter.swift` est vide, vérifié le 2026-09-15)
Post-state attendu: PASS
```

```
### AC-5131 [type: new - aucun filtre proposé à l'écran absent du contrat serveur]
Assertion: les champs ajoutés à `MetadataSearchDto` (`rating`, `takenAfter`, `takenBefore`,
`orderBy`) sont déclarés, chacun existe dans les propriétés publiées de `MetadataSearchDto`
(`components.schemas.MetadataSearchDto.properties` : `rating` integer nullable « Filter by rating [1-5], or null
for unrated », `takenAfter`/`takenBefore` string date-time, `orderBy` → `#/components/schemas/SearchOrder`), la
feuille ne propose QUE des noms de champs du DTO — pas un champ inventé, pas
`originalPath`/`originalFileName`/`description`/`tagIds`/`personIds`, hors périmètre — et `rating` porte un
doc-comment disant la dépréciation du contrat plat et le remplacement `filter`.
Note (arbitrage du 2026-09-15) : `ocr` a été retiré de cette liste parce que la carte `ocr-text` (AC-5077)
**interdit** la déclaration du scalaire plat dans `SearchDTOs.swift`, et que le critère texte passe par
`filter.ocr.matches` — sous un serveur antérieur à v3.2.0 il n'est pas exprimable du tout, la feuille de
filtres le dit alors à l'utilisateur. Les deux cartes se contredisaient sur ce point ; la matrice AC l'a
montré (AC-5077 rouge après la fusion de `search-filters`).
Check post-impl: sh -c 's=/tmp/immich-openapi-main.json; d=Sources/Core/Types/SearchDTOs.swift; sh=Sources/Features/Search/SearchFilterSheet.swift; ok=0; if test -f "$sh"; then ok=1; for k in rating takenAfter takenBefore orderBy city state country make model lensModel type isFavorite; do grep -qE "var $k:" "$d" || ok=0; done; if command -v jq >/dev/null 2>&1 && test -f "$s"; then keys=$(jq -r ".components.schemas.MetadataSearchDto.properties|keys_unsorted[]" "$s" | tr "\n" " "); for k in rating takenAfter takenBefore orderBy city state country make model lensModel type isFavorite; do case " $keys " in *" $k "*) ;; *) ok=0;; esac; done; fi; for k in ocrText rating city state country make model lensModel type isFavorite takenAfter takenBefore; do grep -qE "filter\.$k" "$sh" || grep -qF "\.$k" "$sh" || ok=0; done; grep -qiE "deprecated" "$d" || ok=0; fi; test "$ok" = 1 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun de `rating`/`ocr`/`takenAfter`/`takenBefore`/`orderBy` n'apparaît dans `Sources/Core/Types/SearchDTOs.swift` — `grep -nE "rating|ocr|orderBy" Sources/Core/Types/SearchDTOs.swift` ne renvoie rien, vérifié le 2026-09-15)
Post-state attendu: PASS
Note: le contrôle cite nommément les champs du schéma et les confronte aux propriétés publiées ; la partie schéma est gardée par `command -v jq` + `test -f` (l'artefact `/tmp/immich-openapi-main.json` peut ne pas survivre à la session), les boucles DTO et feuille, elles, discriminent toujours. `order` (déprécié, `never written` par la fiche) reste déclaré : il n'est pas retiré, seulement jamais alimenté.
```

```
### AC-5132 [type: new]
Assertion: `SearchViewModel` porte l'état de filtre (`filter`, `activeFilterCount`, `isFilterActive`),
`applyFilters()` bascule `searchMode` en `.metadata` quand le mode est CLIP (`SmartSearchDto` n'a aucun champ de
filtre), annule `pendingExploreFilter` (le filtre explicite l'emporte sur le drill-down) et appelle `search()`
sans passer par le debounce de `queryChanged()` (400 ms), `clearFilters()` remet le filtre à zéro par le même
chemin ; le store d'affichage entre par l'`init` avec une valeur par défaut (la signature publique des appelants
existants ne casse pas).
Check post-impl: sh -c 'f=Sources/Features/Search/SearchViewModel.swift; grep -qE "var filter = SearchFilter\(\)" "$f" && grep -qE "var activeFilterCount" "$f" && grep -qE "var isFilterActive" "$f" && grep -qE "func applyFilters\(\) async" "$f" && grep -qE "func clearFilters\(\) async" "$f" && grep -qE "searchMode = \.metadata" "$f" && grep -qE "pendingExploreFilter = nil" "$f" && grep -qE "filter = SearchFilter\(\)" "$f" && grep -qE "display: SearchDisplayOptionsStore" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -nE "rating|ocr|orderBy|density|filter\.apply" Sources/Features/Search/SearchViewModel.swift` ne renvoie rien : aucun état de filtre n'existe, vérifié le 2026-09-15)
Post-state attendu: PASS
Note: `resetToIdle()` et `clearSearch()` ne touchent PAS `filter` (vider le champ de recherche n'efface pas les filtres) — couvert par `test_clearSearch_doesNotClearFilters` en AC-5138, un grep ne sachant pas lire un corps de méthode.
```

```
### AC-5133 [type: new - ce que le serveur reçoit réellement]
Assertion: `dispatchSearch(page:)` reste le seul point de construction du DTO et y écrit le filtre
(`filter.apply(to: &dto)`), l'ordre (`dto.orderBy = sort.serverValue` — jamais `order`) et les deux dates
`takenAfter`/`takenBefore` converties en chaînes ISO-8601 ; le test lit le corps capturé par le mock
(`MockImmichClient.lastMetadataSearchDto`, déjà alimenté ligne 421) et vérifie ce que le serveur reçoit, pas le
câblage interne.
Check post-impl: sh -c 'v=Sources/Features/Search/SearchViewModel.swift; t=Tests/SearchFilterTests.swift; test -f "$t" && grep -qE "filter\.apply\(to: &dto\)" "$v" && grep -qE "dto\.orderBy = sort\.serverValue" "$v" && grep -qE "dto\.takenAfter = " "$v" && grep -qE "dto\.takenBefore = " "$v" && grep -qE "string\(from: " "$v" && grep -qE "lastMetadataSearchDto" "$t" && grep -qE "test_orderBy_isWrittenAndOrderIsNeverSet" "$t" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Tests/SearchFilterTests.swift` absent, et `grep -nE "takenAfter|orderBy|filter\.apply" Sources/Features/Search/SearchViewModel.swift` ne renvoie rien, vérifié le 2026-09-15)
Post-state attendu: PASS
Note: `ISO8601DateFormatter` n'est PAS un critère discriminant — il apparaît déjà deux fois dans `SearchViewModel.swift:419,422` (le `parseDate` du drill-down Explore, côté lecture). Le critère est l'écriture (`dto.takenAfter = `) plus `string(from: )` (formatage), absents aujourd'hui.
```

```
### AC-5134 [type: new - les chips et leurs identifiants]
Assertion: `SearchView` affiche au-dessus de la grille une barre de chips des filtres actifs, seulement quand
`vm.isFilterActive` (identifiant `searchActiveFiltersBar` porté par le libellé `Text("Filters")` de la barre — jamais par le conteneur
scrollable des chips, qui écraserait leurs identifiants en XCUITest (fait mesuré sur `languageRelaunchToast`) —,
un chip par contrainte portant l'identifiant
`searchFilterChip_<champ>` où `<champ>` est le nom du champ DTO (`searchFilterChip_rating`, `_ocr`, `_city`,
`_state`, `_country`, `_make`, `_model`, `_lensModel`, `_type`, `_isFavorite`, `_takenAfter`, `_takenBefore`),
chacun muni d'un bouton de retrait `searchFilterChipRemove_<champ>` qui n'efface QUE cette contrainte, et un
`Clear` global d'identifiant `searchActiveFiltersClear` qui appelle `await vm.clearFilters()`.
Check post-impl: sh -c 'f=Sources/Features/Search/SearchView.swift; grep -qE "searchActiveFiltersBar" "$f" && grep -qE "searchActiveFiltersClear" "$f" && grep -qE "searchFilterChip_" "$f" && grep -qE "searchFilterChipRemove_" "$f" && grep -qE "vm\.isFilterActive" "$f" && grep -qE "await vm\.clearFilters\(\)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -n "searchActiveFiltersBar\|searchFilterChip" Sources/Features/Search/SearchView.swift` ne renvoie rien, vérifié le 2026-09-15)
Post-state attendu: PASS
Note: identifiant posé sur l'élément interactif (le `Button` du chip), jamais sur le conteneur `HStack` — un identifiant de conteneur rend le chip intappable en XCUITest (piège mesuré de la carte stacks-ui). Les deux préfixes sont cherchés littéralement : une composition `"searchFilterChip_\(chip.field)"` les contient bien.
```

```
### AC-5135 [type: new - la feuille de filtres]
Assertion: `SearchFilterSheet` est une vue `Form` sans logique (aucun client réseau : toute écriture passe par
`vm.filter.*` ou `vm.setSort/setDensity/applyFilters/clearFilters`) qui déclare son PROPRE `NavigationStack`
— elle est présentée en feuille au-dessus de l'onglet Search (dont le `NavigationStack` est à
`SearchView.swift:29`), pas poussée depuis le hub « Me » — et expose les identifiants `searchFilterSheet`,
`searchFilterStar1`…`searchFilterStar5`, `searchFilterOCR`, `searchFilterCity`, `searchFilterState`,
`searchFilterCountry`, `searchFilterMake`, `searchFilterModel`, `searchFilterLens`,
`searchFilterType`, `searchFilterFavorite`, `searchFilterTakenAfter`, `searchFilterTakenBefore`,
`searchFilterSort`, `searchFilterDensity`, `searchFilterReset`, `searchFilterDone`.
Check post-impl: sh -c 'f=Sources/Features/Search/SearchFilterSheet.swift; ok=0; if test -f "$f"; then ok=1; grep -qE "struct SearchFilterSheet: View" "$f" || ok=0; grep -qE "@Bindable var vm: SearchViewModel" "$f" || ok=0; grep -qF "@Environment(\.dismiss)" "$f" || ok=0; grep -qE "NavigationStack \{" "$f" || ok=0; grep -qE "Form \{" "$f" || ok=0; grep -qE "ImmichClient|URLRequest|URLSession" "$f" && ok=0; for k in Sheet OCR City State Country Make Model Lens Type Favorite TakenAfter TakenBefore Sort Density Reset Done; do grep -qE "searchFilter$k" "$f" || ok=0; done; for i in 1 2 3 4 5; do grep -qE "searchFilterStar$i" "$f" || ok=0; done; grep -qE "await vm\.applyFilters\(\)" "$f" || ok=0; fi; test "$ok" = 1 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — aucun dossier de composant de filtre sous `Sources/Features/Search`, vérifié le 2026-09-15)
Post-state attendu: PASS
Note: `NavigationStack` est ICI présent et voulu (feuille) — l'inverse de la règle des vues poussées depuis « Me ». Le check vise la déclaration `NavigationStack {`, et la boucle d'identifiants vise des chaînes littérales : pas de placeholder du type `searchFilter<Field>`. Les rangs d'étoiles s'appuient sur la bande `star-ratings` (AC-5060–5069) ; si elle livre un composant à identifiant propre, l'enveloppe de la feuille porte quand même `searchFilterStar<n>`.
```

```
### AC-5136 [type: new - effacement individuel et global]
Assertion: chaque champ de la feuille s'efface individuellement — la chaîne vide d'un `TextField` est
normalisée en `nil` par le binding (`… .isEmpty ? nil : …`) pour `ocrText` et les six champs EXIF, et la note a
son bouton `Clear` (`vm.filter.rating = nil`) : le DTO ne reçoit alors plus la clé (Codable synthétisé,
`encodeIfPresent`) ; le `Reset` de la feuille et le `Clear` de la barre de chips passent tous deux par
`await vm.clearFilters()`, qui remet `filter` à `SearchFilter()` SANS toucher aux options d'affichage
(`sort`, `density`).
Check post-impl: sh -c 'f=Sources/Features/Search/SearchFilterSheet.swift; ok=0; if test -f "$f"; then ok=1; grep -qE "isEmpty \? nil" "$f" || ok=0; grep -qE "vm\.filter\.rating = nil" "$f" || ok=0; grep -qE "searchFilterReset" "$f" || ok=0; grep -qE "await vm\.clearFilters\(\)" "$f" || ok=0; fi; test "$ok" = 1 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent, vérifié le 2026-09-15)
Post-state attendu: PASS
Note: le non-effacement des options d'affichage par `clearFilters()` est prouvé par le test (AC-5138) : `grep` ne lit pas un corps de méthode, et `sort`/`density` sont écrites ailleurs dans la même classe.
```

```
### AC-5137 [type: new - les options d'affichage]
Assertion: `SearchDisplayOptionsStore` calqué sur `RecentSearchesStore` (`UserDefaults` injecté, clés privées,
`load`/`save`) persiste `searchSortOrder` (`SearchSortOrder`, raw value = valeur `orderBy` du contrat) et
`searchGridDensity` (`SearchGridDensity` : `compact`/`comfortable`/`large` → `columnCount` 5/3/2), avec repli
`.newestTaken` et `.comfortable` sur clé absente ou illisible ; le ViewModel expose `sort`/`density` et
`setDensity` ne refetch pas (la grille se remet en page seule) tandis que `setSort` rejoue la recherche (le tri
est serveur) ; `SearchView` dérive ses colonnes de `vm.density.columnCount`.
Check post-impl: sh -c 'st=Sources/Features/Search/SearchDisplayOptionsStore.swift; v=Sources/Features/Search/SearchViewModel.swift; sf=Sources/Core/Types/SearchFilter.swift; view=Sources/Features/Search/SearchView.swift; ok=0; if test -f "$st" && test -f "$sf"; then ok=1; grep -qE "struct SearchDisplayOptionsStore" "$st" || ok=0; grep -qE "private let defaults: UserDefaults" "$st" || ok=0; grep -qE "searchSortOrder" "$st" || ok=0; grep -qE "searchGridDensity" "$st" || ok=0; grep -qE "func loadSort" "$st" || ok=0; grep -qE "func saveSort" "$st" || ok=0; grep -qE "func loadDensity" "$st" || ok=0; grep -qE "func saveDensity" "$st" || ok=0; grep -qE "\.newestTaken" "$st" || ok=0; grep -qE "\.comfortable" "$st" || ok=0; grep -qE "enum SearchSortOrder" "$sf" || ok=0; grep -qE "enum SearchGridDensity" "$sf" || ok=0; grep -qE "var columnCount: Int" "$sf" || ok=0; grep -qE "func setSort" "$v" || ok=0; grep -qE "func setDensity" "$v" || ok=0; grep -qE "var sort: SearchSortOrder" "$v" || ok=0; grep -qE "var density: SearchGridDensity" "$v" || ok=0; grep -qE "vm\.density\.columnCount" "$view" || ok=0; fi; test "$ok" = 1 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`SearchDisplayOptionsStore.swift` absent et `Sources/Features/Search/SearchView.swift:26` fige encore `private let columns = Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s2), count: 3)`, vérifié le 2026-09-15)
Post-state attendu: PASS
Note: tout grep de « density » est scopé au fichier — `Sources/Features/Search/MapViewModel.swift:161` contient déjà le mot (commentaire « Annotation-grid density »), un grep de dossier passerait au vert sans une ligne de cette fiche.
```

```
### AC-5138 [type: new]
Assertion: `Tests/SearchFilterTests.swift` (convention `<Type>Tests.swift` du dossier, `MockImmichClient`,
`UserDefaults(suiteName:)` jetable, cas `@MainActor`) expose ≥ 9 cas couvrant l'écriture sélective du filtre, le
comptage, la borne de note, la bascule CLIP → Metadata, l'ordre, les deux effacements, l'aller-retour des
options d'affichage, la densité et la sérialisation des dates.
Check post-impl: sh -c 'f=Tests/SearchFilterTests.swift; ok=0; if test -f "$f"; then ok=1; n=$(grep -cE "func test_" "$f"); test "$n" -ge 9 || ok=0; for t in test_filterApply_writesOnlyNonNilFields test_activeCount_countsEachConstraintOnce test_rating_outOfRange_isIgnoredByApply test_ocrText_switchesFromSmartToMetadata test_orderBy_isWrittenAndOrderIsNeverSet test_clearFilters_resetsFilterButKeepsQuery test_clearSearch_doesNotClearFilters test_displayOptions_roundTripThroughUserDefaults test_density_columnCount_matchesDensity test_dispatch_writesDateRangeAsISO8601; do grep -qE "$t" "$f" || ok=0; done; fi; test "$ok" = 1 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent, vérifié le 2026-09-15)
Post-state attendu: PASS
Note: un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate` — sans régénération la suite passe « verte » par omission.
```

```
### AC-5139 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests,
`-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED, dans le log de la fiche.
Check post-impl: sh -c 'l=/tmp/immich_searchfilters_test.log; n=0; grep -qE "TEST SUCCEEDED" "$l" 2>/dev/null && n=$(grep -oE "Executed [0-9]+ tests" "$l" | grep -oE "[0-9]+" | sort -n | tail -1); test "${n:-0}" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent — `n` reste à 0, donc `test 0 -ge 886` échoue, rc=0)
Post-state attendu: PASS
Note: `n=0` est posé AVANT la lecture du log : sans ça un log absent donne `n` vide et `test "" -ge 886` crache « integer expression expected » au lieu d'un FAIL propre.
```
