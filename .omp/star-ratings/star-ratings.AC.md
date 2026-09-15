# Task: star-ratings

Status: planifié — **aucune AC ouverte** (écart G7 du registre `.omp/backlog/ImmichSwiftUI-backlog.md`). Bande
AC-5060…AC-5069 : 9 critères `new` + 1 régression bornée à la baseline de la suite complète.

## Plan (résumé)

**Objectif** : le panneau de détails du viewer écrit la note (1…5 étoiles, re-tap = retour à « non noté ») sur
le serveur et n'affiche jamais une valeur locale que le serveur a refusée ; l'onglet Recherche filtre les
résultats par note, en cumul avec les filtres EXIF existants.

**Approche retenue** : A — écriture par **PATCH `/api/assets/:id`** (`UpdateAssetDto.rating` côté serveur) via
`setAssetRating(id:rating:)` sur `ImmichClient`, avec un corps `RatingUpdateDto`/`RatingValue` dont
`encode(to:)` écrit un **`null` explicite** pour « non noté » (l'encodeur synthétisé d'un `Int?` **omet** la
clé, donc ne sait pas dé-noter, et `0`/`-1` sont invalides depuis la v3 du serveur) ; l'UI est un `PVRatingBar`
générique dans le DesignSystem ; le filtre est le **champ plat `rating`** de `MetadataSearchDto`, piloté par un
`Menu` qui force le mode Metadata.

**Pourquoi le champ plat malgré sa dépréciation (arbitrage repris tel quel)** : `rating` est
`deprecated: true` / `x-immich-state: "Deprecated"` depuis la v3.2.0 — **mais les 33 autres champs plats du
même schéma le sont aussi** (`isFavorite`, `albumIds`, `city`, `make`, `model`, `visibility`…), c'est-à-dire
exactement les cinq filtres que l'app envoie déjà. Basculer `rating` seul sur `filter: SearchFilter` ferait
coexister deux conventions dans le même corps de requête, ne réglerait pas « `eq: null` » (même trou
d'encodage, second wrapper null-preserving) et promettrait un 400 sur les serveurs antérieurs à la v3.2.0 :
la dette réelle (négociation de version + `SearchFilter`) est transversale et hors fiche. Le bucket
« Unrated » est donc hors périmètre — décision assumée, pas un oubli.

**Étapes** : (1) NEW `Sources/DesignSystem/Components/PVRatingBar.swift` ; (2) EDIT `DTOs.swift`
(`RatingUpdateDto`, `RatingValue`) ; (3) EDIT `ImmichClient.swift` (déclaration) ; (4) EDIT
`ImmichAPIClient.swift` (implémentation PATCH) ; (5) EDIT `Tests/Mocks/MockImmichClient.swift` (conformité) ;
(6) EDIT `AssetDetailViewModel.swift` (`rating`, `isSavingRating`, `setRating`) ; (7) EDIT `PhotoInfoPanel.swift`
(carte + retrait de la ligne EXIF morte) ; (8) EDIT `SearchDTOs.swift` + `SearchViewModel.swift` +
`SearchView.swift` (filtre) ; (9) EDIT des trois suites de tests ; (10) `xcodegen generate` + suite complète.

**Incertitudes** : état OpenAPI de `UpdateAssetDto.rating` (PATCH) vs `Stable` du bulk — si déprécié, basculer
sur `PUT /api/assets` en acceptant un `getAsset` après écriture ; préférence serveur `ratingsEnabled` (aucune
route de préférences n'est lue par iOS aujourd'hui — affichage inconditionnel assumé) ; lecture `-1` (asset
rejeté) affichée comme « non noté » ; acceptation serveur réelle de `{"rating": null}`.

## Critères

```
### AC-5060 [type: new]
Assertion: le corps d'écriture sait exprimer « non noté » — `RatingValue` est un enum à deux cas (valeur
entière / `unrated`) dont l'encodage passe par un `singleValueContainer` et un `encodeNil()` explicite, avec
le `decodeNil()` symétrique, et `RatingUpdateDto(rating: nil)` mappe sur `.unrated` ; le commentaire doc du
type porte la raison (v3 rejette 0 et -1, donc « non noté » ne s'écrit que par `null`).
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs.swift; grep -q "struct RatingUpdateDto" "$f" && grep -q "enum RatingValue" "$f" && grep -q "case unrated" "$f" && grep -q "singleValueContainer" "$f" && grep -q "encodeNil()" "$f" && grep -q "decodeNil()" "$f" && grep -q "init(rating: Int?)" "$f" && grep -q "func encode(to encoder: Encoder) throws" "$f" && grep -q "UpdateAssetDto" "$f" && grep -q "v3" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -nE "struct RatingUpdateDto|enum RatingValue" -r Sources` ne renvoie rien ; `grep -n rating Sources/Core/Types/DTOs.swift` ne montre que les trois `Int?` générés — aucune surcharge `encode(to:)` dans le fichier)
Post-state attendu: PASS
Note: c'est le piège central de la fiche. Un `RatingUpdateDto` réduit à `var rating: Int?` passerait tous les
greps d'appel mais **omettrait la clé** à l'encodage : le serveur recevrait `{}` et la note ne pourrait plus
jamais être retirée. D'où le `encodeNil()` et le cas de test d'AC-5068 qui vérifie la présence de la clé.
```

```
### AC-5061 [type: new]
Assertion: la méthode d'écriture traverse les deux couches — déclarée sur `ImmichClient` et réalisée par
`ImmichAPIClient` sur le **même verbe et le même chemin** que `updateAsset` (`PATCH /api/assets/:id`, via
`ImmichAPI.assets.path`), avec le corps null-preserving ; le mock de test reste conforme au protocole.
Check post-impl: sh -c 'p=Sources/Core/Protocols/ImmichClient.swift; c=Sources/Services/ImmichAPIClient.swift; m=Tests/Mocks/MockImmichClient.swift; grep -q "func setAssetRating(id: String, rating: Int?) async throws -> AssetResponseDto" "$p" && grep -qF "null" "$p" && grep -q "func setAssetRating(id: String, rating: Int?) async throws -> AssetResponseDto" "$c" && grep -qF "sendAuthed(.PATCH, path: ImmichAPI.assets.path(\"/\(id)\")" "$c" && grep -qF "AnyEncodable(RatingUpdateDto(rating: rating))" "$c" && grep -qF "ratingUpdates" "$m" && grep -qF "ratingUpdateResults" "$m" && test "$(grep -c "func setAssetRating" "$m")" -ge 1 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -n "func setAssetRating" Sources Tests` est vide — le seul chemin d'écriture de note est `updateAsset(id:dto:)`, qui ne sait pas envoyer `null`)
Post-state attendu: PASS
Note: le check vise la chaîne `AnyEncodable(RatingUpdateDto(rating: rating))` et non `RatingUpdateDto` seul :
un corps `UpdateAssetDto` réutilisé satisférait un grep trop large et rouvrirait le trou du `null`. Le chemin
est épinglé par `sendAuthed(.PATCH, path: ImmichAPI.assets.path("/\(id)")` en `-F`, pour qu'aucune constante
d'API neuve ne soit introduite.
```

```
### AC-5062 [type: new]
Assertion: le ViewModel de note expose l'état (`rating`), la garde d'aller-retour (`isSavingRating`) et les
crochets de test, sur le patron de `lastUpdateBody`/`lastUpdateAssetId` ; `setRating` écrit l'état local
**avant** l'appel réseau (optimiste) puis adopte la réponse du PATCH comme nouvelle source de `detail`.
Check post-impl: sh -c 'f=Sources/Features/AssetDetail/AssetDetailViewModel.swift; grep -q "var rating: Int?" "$f" && grep -q "private(set) var isSavingRating" "$f" && grep -q "private(set) var lastRatingSent: Int?" "$f" && grep -q "private(set) var lastRatingAssetId: String?" "$f" && grep -q "func setRating(_ value: Int?) async" "$f" && grep -qF "lastRatingSent = value" "$f" && grep -qF "client.setAssetRating(id: asset.id, rating: value)" "$f" && grep -qF "detail = response" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -nE "rating|isSavingRating" Sources/Features/AssetDetail/AssetDetailViewModel.swift` ne renvoie rien : le VM porte `toggleFavorite`/`setDateTime`/`setLocation` seulement)
Post-state attendu: PASS
Note: `detail = response` est ce qui rend la carte honnête — le PATCH rend l'`AssetResponseDto` à jour, donc
`exifInfo.rating` se rafraîchit sans `getAsset` supplémentaire (c'est l'argument qui a fait rejeter
l'approche B sur `PUT /api/assets`, qui jette le corps).
```

```
### AC-5063 [type: new]
Assertion: l'échec restaure l'état — dans `setRating`, l'écriture locale précède l'appel réseau (comparaison
de numéros de ligne), et la fin de la fonction porte un `catch` qui réécrit `rating` et pose `errorMessage` :
même contrat que `PhotoViewer.toggleFavorite` (« l'UI ne ment jamais sur l'état serveur »).
Check post-impl: sh -c 'f=Sources/Features/AssetDetail/AssetDetailViewModel.swift; grep -q "func setRating(_ value: Int?) async" "$f" && b=$(grep -nF "try await client.setAssetRating(id: asset.id, rating: value)" "$f" | cut -d: -f1 | head -1) && a=$(grep -nE "^[[:space:]]*(self\.)?rating = value" "$f" | cut -d: -f1 | head -1) && test -n "$a" && test -n "$b" && test "$a" -lt "$b" && t=$(sed -n "$((b+1)),\$p" "$f") && printf "%s\n" "$t" | grep -qE "catch" && printf "%s\n" "$t" | grep -qE "^[[:space:]]*(self\.)?rating = " && printf "%s\n" "$t" | grep -q "errorMessage = " && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun `setRating` : la fonction n'existe pas, donc `b` est vide et la chaîne s'arrête)
Post-state attendu: PASS
Note: l'ordre `a < b` encode le choix **optimiste** (et non « try puis muter ») ; la tranche
`sed -n "$((b+1)),\$p"` prouve que la réécriture de `rating` et `errorMessage` vivent **après** l'appel, donc
dans le rattrapage. Un `try await` sans `catch` ferait remonter l'erreur et la barre resterait bloquée sur une
note que le serveur n'a pas.
```

```
### AC-5064 [type: new]
Assertion: la barre d'étoiles est un composant générique du DesignSystem — cinq étoiles en `ForEach(1...5)`,
remplies/creuses selon `rating`, dimensions tactiles de 44 pt, couleurs de tokens, désactivation visuelle
pendant l'aller-retour, et les deux identifiants d'accessibilité exigés.
Check post-impl: sh -c 'f=Sources/DesignSystem/Components/PVRatingBar.swift; test -f "$f" && grep -q "struct PVRatingBar: View" "$f" && grep -q "let rating: Int?" "$f" && grep -q "var isEnabled: Bool" "$f" && grep -q "var onRate" "$f" && grep -q "var onClear" "$f" && grep -q "ForEach(1...5" "$f" && grep -qF "star.fill" "$f" && grep -qF "assetRatingBar" "$f" && grep -qF "Remove rating" "$f" && grep -qF "accessibilityLabel" "$f" && grep -qF "width: 44, height: 44" "$f" && grep -qF "PVSpacing.s4" "$f" && grep -qF "immichPrimary" "$f" && grep -qF "textSecondaryPV" "$f" && grep -qF "opacity(0.5)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/DesignSystem/Components/PVRatingBar.swift` est absent ; la note n'a aujourd'hui aucune surface d'écriture, seulement la ligne `star.fill` de `PhotoInfoPanel.swift:305`)
Post-state attendu: PASS
Note: l'identifiant est porté par le **conteneur** de la barre, et l'identifiant/label de chaque étoile est
posé sur le `Button` (jamais sur un conteneur) : un `.accessibilityIdentifier` sur un conteneur rend les cinq
étoiles indistinguables en XCUITest (piège mesuré du dépôt, mémo `3acc19d3`). Le label de l'étoile courante
devient `Remove rating`, sinon le geste « re-taper » est inatteignable en VoiceOver.
```

```
### AC-5065 [type: new]
Assertion: la carte de note vit dans le panneau de détails, rendue **avant** la carte des visages, gardée par
`if let vm`, propose son propre bouton `Clear rating` (cible VoiceOver explicite en plus du re-tap), et la
ligne EXIF morte qui affichait la note en texte a disparu du fichier.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/PhotoInfoPanel.swift; grep -q "private var ratingCard" "$f" && grep -qF "PVRatingBar(rating: vm.rating" "$f" && grep -qF "Clear rating" "$f" && grep -q "if let vm" "$f" && grep -q "InfoCard" "$f" && ! grep -q "exif.rating.map" "$f" && c=$(grep -n "var content" "$f" | cut -d: -f1 | head -1) && test -n "$c" && t=$(sed -n "$((c+1)),\$p" "$f") && a=$(printf "%s\n" "$t" | grep -n "ratingCard" | cut -d: -f1 | head -1) && b=$(printf "%s\n" "$t" | grep -n "facesCard" | cut -d: -f1 | head -1) && test -n "$a" && test -n "$b" && test "$a" -lt "$b" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -n "ratingCard\|PVRatingBar" Sources/Features/PhotoViewer/PhotoInfoPanel.swift` est vide, et `:305` porte encore `("star.fill", exif.rating.map { String($0) })` — la négation `! grep` échoue donc aujourd'hui)
Post-state attendu: PASS
Note: le retrait de la ligne EXIF est dans le même fichier que l'ajout, exprès : sans lui la note s'affiche
deux fois (le nombre dans la liste EXIF et la barre). L'ordre `ratingCard < facesCard` encode la consigne de
placement en tête de `content` — cinq cibles de 44 pt font 220 pt de large, la rangée doit rester au-dessus de
la ligne de flottaison du sheet.
```

```
### AC-5066 [type: new]
Assertion: le DTO de recherche porte le champ plat `rating` (dans `MetadataSearchDto`, donc avant
`SmartSearchDto`), accompagné du commentaire qui documente l'arbitrage de dépréciation : état `Deprecated`
depuis la v3.2.0, partagé avec les autres champs plats, remplacement `filter: SearchFilter`.
Check post-impl: sh -c 'f=Sources/Core/Types/SearchDTOs.swift; grep -q "var rating: Int?" "$f" && grep -qF "SearchFilter" "$f" && grep -qF "v3.2.0" "$f" && grep -q "eprecat" "$f" && grep -q "var isFavorite: Bool?" "$f" && a=$(grep -n "var rating: Int?" "$f" | cut -d: -f1 | head -1) && b=$(grep -n "struct SmartSearchDto" "$f" | cut -d: -f1 | head -1) && test -n "$a" && test -n "$b" && test "$a" -lt "$b" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -n rating Sources/Core/Types/SearchDTOs.swift` est vide — `MetadataSearchDto` va de `isFavorite` à `personIds` sans le champ)
Post-state attendu: PASS
Note: la comparaison `a < b` épingle l'appartenance à `MetadataSearchDto` : posé dans `SmartSearchDto`, le
champ serait silencieusement ignoré par le serveur (ce DTO n'a que `query`/`page`/`size`/`withExif`).
Le commentaire est asserté parce que la dépréciation est **l'arbitrage** de la fiche : sans lui, un relecteur
« nettoiera » le champ ou le remplacera seul par `SearchFilter`, et le corps de requête portera deux
conventions pour la même recherche.
```

```
### AC-5067 [type: new]
Assertion: le filtre est piloté de bout en bout — `ratingFilter` collant dans le ViewModel (survit aux
éditions de texte), injecté dans le DTO au dispatch, remis à `nil` par `clearSearch()`, et `setRatingFilter`
force le mode Metadata quand une valeur est posée et relance la recherche ; le menu vit dans la barre
d'outils de la branche résultats, avant `searchModeMenu`, avec l'option `Any rating`.
Check post-impl: sh -c 'a=Sources/Features/Search/SearchViewModel.swift; b=Sources/Features/Search/SearchView.swift; grep -q "var ratingFilter: Int?" "$a" && grep -q "func setRatingFilter(_ value: Int?) async" "$a" && grep -qF "dto.rating = ratingFilter" "$a" && grep -qF "searchMode = .metadata" "$a" && grep -qF "await search()" "$a" && c=$(grep -n "func clearSearch" "$a" | cut -d: -f1 | head -1) && test -n "$c" && t=$(sed -n "$((c+1)),\$p" "$a") && printf "%s\n" "$t" | grep -q "ratingFilter = nil" && grep -q "private var ratingFilterMenu" "$b" && grep -qF "Any rating" "$b" && grep -q "Picker" "$b" && grep -qF "setRatingFilter" "$b" && m=$(grep -n "ratingFilterMenu" "$b" | cut -d: -f1 | head -1) && s=$(grep -n "searchModeMenu" "$b" | cut -d: -f1 | head -1) && test -n "$m" && test -n "$s" && test "$m" -lt "$s" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -nE "rating|ratingFilter" Sources/Features/Search/SearchViewModel.swift` est vide et `Sources/Features/Search/` ne contient aucun menu de note — le DTO construit par `dispatchSearch` ne peut pas exprimer le filtre)
Post-state attendu: PASS
Note: `searchMode = .metadata` est asserté parce qu'il est **mesurable** : en mode Smart, `SmartSearchDto`
n'a aucun champ de filtre, donc le filtre serait perdu en silence. Le menu est inséré avant `searchModeMenu`
(`SearchView.swift:64-80`, sous `if vm.viewMode == .results`) : en Explore et en Map il n'y a pas de grille à
filtrer. Le champ est **collant** (arbitrage : `Any rating` et `clearSearch()` sont les seules sorties), donc
`clearSearch()` doit le remettre à `nil`, sinon un filtre survit à un effacement de recherche.
```

```
### AC-5068 [type: new]
Assertion: les trois suites existantes sont étendues sans fichier neuf — trois cas sur le ViewModel (valeur
envoyée + réponse adoptée, `nil` envoyé et état local vidé, échec rétabli), deux cas sur l'encodage (le `null`
explicite avec la clé **présente** valant `NSNull`, et la valeur `5`), quatre cas sur le filtre (champ plat
transmis, mode Metadata forcé, `Any rating` qui vide le champ, `clearSearch` qui vide le filtre).
Check post-impl: sh -c 'a=Tests/AssetDetailViewModelTests.swift; b=Tests/DTOEncodingTests.swift; c=Tests/SearchViewModelTests.swift; n=0; test -f "$a" && test -f "$b" && test -f "$c" && grep -q "func test_setRating_sendsValueAndAdoptsServerResponse" "$a" && grep -q "func test_setRating_nilSendsUnratedAndClearsLocally" "$a" && grep -q "func test_setRating_revertsOnFailure" "$a" && n=$(grep -c "func test_" "$a") && test "$n" -ge 8 && grep -q "func test_ratingUpdateDto_encodesExplicitNull" "$b" && grep -qF "NSNull" "$b" && grep -q "func test_ratingUpdateDto_encodesValue" "$b" && grep -q "func test_setRatingFilter_sendsFlatRatingField" "$c" && grep -q "func test_setRatingFilter_forcesMetadataMode" "$c" && grep -q "func test_setRatingFilter_anyClearsField" "$c" && grep -q "func test_clearSearch_clearsRatingFilter" "$c" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (les trois fichiers existent — 5, 27 et 35 cas — mais aucun des neuf noms de cas n'y figure)
Post-state attendu: PASS
Note: `NSNull` est le seul moyen de prouver que la clé `rating` **existe** dans le JSON produit : les deux cas
d'encodage échouent dès que quelqu'un « simplifie » `RatingUpdateDto` en `Int?`, ce qui est exactement la
régression muette décrite en AC-5060. Un `Tests/*.swift` neuf ne serait compilé qu'après `xcodegen generate` :
aucun fichier de test n'est donc ajouté.
```

```
### AC-5069 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests,
`-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED.
Check post-impl: sh -c 'n=0; grep -q "TEST SUCCEEDED" /tmp/immich_star_ratings_test.log 2>/dev/null && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_star_ratings_test.log | grep -oE "[0-9]+" | sort -n | tail -1) && test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log `/tmp/immich_star_ratings_test.log` absent — la suite n'a pas encore été relancée avec `PVRatingBar.swift`, qui exige `xcodegen generate` sous peine de rester hors compilation)
Post-state attendu: PASS
```
