# Task: map-settings

Status: planifié — **aucune AC ouverte** (écart G14b, audit 2026-09-15 de `.omp/map-settings/map-settings.specs.md`).

## Plan (résumé)

**Objectif** : depuis le segment carte de l'onglet Recherche, une feuille de réglages règle le thème
(système / clair / sombre), les marqueurs (favoris seuls, archives incluses, partenaires inclus) et une plage
de dates (preset relatif ou plage personnalisée après/avant, effaçable) ; les marqueurs et la feuille de
photos se recalculent aussitôt et le choix survit au relancement. Le cache disque cesse d'être partagé entre
filtres. Depuis le viewer, l'aperçu carte du lieu devient dépliable en plein écran.

**Approche retenue** : A — un value type `MapMarkerFilter` (`Equatable/Sendable/Codable`) qui produit à la fois
les `URLQueryItem` de `GET /api/map/markers` **et** une clé de variante de cache ; `ImmichClient.getMapMarkers`
prend ce filtre au lieu de deux `Bool?` ; un `MapSettingsStore` persistant (UserDefaults, précédent
`AppLanguageStore`/`BackupSettingsStore`) alimente le `MapViewModel` qui recharge à chaque changement.

- **B (rejetée)** — empiler des paramètres optionnels sur la signature actuelle : 5 paramètres dont 3 `nil` par
  défaut aux **deux** sites d'appel (`MapViewModel.swift:218`, `:240`), aucune détection « le filtre a changé »
  (pas d'`Equatable`), et la clé de cache redupliquerait la liste des paramètres.
- **C (rejetée)** — filtrer côté client dans `filterVisible(_:)` : le serveur expose déjà
  `fileCreatedAfter`/`fileCreatedBefore`/`isFavorite`/`isArchived`/`withPartners` ; filtrer localement oblige à
  télécharger et cacher tout le catalogue (ce que `MapMarkerCache` + `refreshTTL` amortissent), à rescanner à
  chaque changement de région, et laisserait `MapPhotosSheet` afficher un total de région faux.

**Étapes** : (1) NEW `Sources/Core/Types/MapMarkerFilter.swift` ; (2) EDIT `Sources/Core/Protocols/ImmichClient.swift:67` ;
(3) EDIT `Sources/Services/ImmichAPIClient.swift:197-205` ; (4) EDIT `Sources/Features/Search/MapMarkerCache.swift:22-32` ;
(5) NEW `Sources/Features/Search/MapSettingsStore.swift` ; (6) EDIT `Sources/Features/Search/MapViewModel.swift` ;
(7) EDIT `Sources/DependencyContainer.swift:104-106` ; (8) NEW `Sources/Features/Search/MapSettingsSheet.swift` ;
(9) EDIT `Sources/Features/Search/MapView.swift` (bouton + feuille + thème + bandeau de filtre) ;
(10) EDIT `Sources/Features/PhotoViewer/PhotoInfoPanel.swift:359-381` ; (11) NEW `Sources/Features/PhotoViewer/AssetLocationMapSheet.swift` ;
(12) EDIT `Sources/Features/PhotoViewer/PhotoViewer.swift` ; (13) NEW `Tests/MapMarkerFilterTests.swift` +
`Tests/MapSettingsStoreTests.swift` + cas `applyFilter` dans `Tests/MapViewModelTests.swift` ;
(14) `xcodegen generate` puis suite `-only-testing:ImmichSwiftUITests`.

**Incertitudes** : `withPartners` réellement appliqué serveur (à comparer avec/sans le paramètre) ; sémantique
`fileCreatedAfter` (date de fichier vs upload) ; fuseau des bornes (`date-time`, pas `date`) ; effet réel de
`overrideUserInterfaceStyle` sur des tuiles déjà chargées ; coexistence de deux feuilles (`MapSettingsSheet`
depuis `MapSegmentView` vs `MapPhotosSheet` présentée par `AuthenticatedRoot`, `RootView.swift:227-243`).

## Critères

```
### AC-5140 [type: new]
Assertion: un value type `MapMarkerFilter` porte l'intégralité du filtre et sérialise exactement les paramètres de la route carte (`fileCreatedAfter`/`fileCreatedBefore` en date-time, `isFavorite`, `isArchived`, `withPartners`) ; la plage personnalisée prime sur le preset relatif et la variante de cache est stable sans horodatage.
Check post-impl: sh -c 'f=Sources/Core/Types/MapMarkerFilter.swift; test -f "$f" && grep -qE "struct MapMarkerFilter" "$f" && grep -qE "Equatable, Sendable, Codable" "$f" && grep -qE "var onlyFavorites" "$f" && grep -qE "var includeArchived" "$f" && grep -qE "var withPartners" "$f" && grep -qE "var relativeDays: Int" "$f" && grep -qE "var from: Date" "$f" && grep -qE "var to: Date" "$f" && grep -qE "static let all" "$f" && grep -qE "var isEmpty" "$f" && grep -qE "func queryItems" "$f" && grep -qE "fileCreatedAfter" "$f" && grep -qE "fileCreatedBefore" "$f" && grep -qE "var cacheVariant" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun `MapMarkerFilter` — `grep -rn "MapMarkerFilter" Sources/` renvoie 0 occurrence, le type n'existe pas)
Post-state attendu: PASS
Note: les deux noms `fileCreatedAfter`/`fileCreatedBefore` sont ceux de `/api/map/markers` dans l'OpenAPI — pas `takenAfter`/`takenBefore` (ceux-là rendent des assets).
```

```
### AC-5141 [type: new]
Assertion: la plage temporelle est portée EXCLUSIVEMENT par la route carte : `ImmichClient.getMapMarkers` prend le filtre (les `Bool?` disparaissent), le client sérialise `filter.queryItems()`, et le chemin timeline (`getTimeBuckets`) reste sans aucun paramètre de date.
Check post-impl: sh -c 'p=Sources/Core/Protocols/ImmichClient.swift; c=Sources/Services/ImmichAPIClient.swift; grep -qE "func getMapMarkers\(filter: MapMarkerFilter\)" "$p" && grep -qE "func getMapMarkers\(filter: MapMarkerFilter\)" "$c" && grep -qE "filter.queryItems\(\)" "$c" && ! grep -qE "getMapMarkers\(isFavorite:" "$p" && ! grep -qE "getMapMarkers\(isFavorite:" "$c" && grep -qE "func getTimeBuckets\(" "$c" && ! (grep -A 14 "func getTimeBuckets(" "$c" | grep -qE "After|Before") && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`ImmichClient.swift:67` = `getMapMarkers(isFavorite: Bool?, isArchived: Bool?)` ; `ImmichAPIClient.swift:197-200` ne sérialise que `isFavorite`/`isArchived` — aucune occurrence du type de filtre)
Post-state attendu: PASS
Note: `getTimeBuckets` (déclaration `Sources/Services/ImmichAPIClient.swift:111`) n'a aucun paramètre de date — la plage ne peut donc pas y transiter ; le check vise la déclaration et sa fenêtre de 14 lignes, pas un commentaire.
```

```
### AC-5142 [type: new]
Assertion: le cache disque des marqueurs prend une dimension de variante : `markers.json` reste le chemin du filtre vide (compatibilité, aucune migration du fichier existant) et devient `markers-<variante>.json` sinon.
Check post-impl: sh -c 'f=Sources/Features/Search/MapMarkerCache.swift; grep -qE "variant: String" "$f" && grep -qE "markers-" "$f" && grep -qE "markers.json" "$f" && grep -qE "func load\(\)" "$f" && grep -qE "func age\(\)" "$f" && grep -qE "func save\(" "$f" && grep -qE "func clear\(\)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Features/Search/MapMarkerCache.swift:25` = `init(directory: URL? = nil)`, `:30` = `base.appendingPathComponent("markers.json")` ; le mot `variant` n'apparaît nulle part dans le fichier)
Post-state attendu: PASS
Note: `load`/`age`/`save`/`clear` restent inchangés — un cache écrit par la version précédente doit continuer d'être servi comme filtre `.all`.
```

```
### AC-5143 [type: new]
Assertion: `MapViewModel` détient le store, expose `filter` et `applyFilter(_:)` (court-circuit si le filtre est identique, remise à zéro de l'état puis rechargement), interroge la route avec le filtre aux DEUX sites et construit son cache avec la variante ; le composition root fabrique le VM avec un store unique.
Check post-impl: sh -c 'v=Sources/Features/Search/MapViewModel.swift; d=Sources/DependencyContainer.swift; n=$(grep -cE "getMapMarkers\(" "$v"); grep -qE "settings: MapSettingsStore" "$v" && grep -qE "var filter: MapMarkerFilter" "$v" && grep -qE "func applyFilter" "$v" && grep -qE "getMapMarkers\(filter: filter\)" "$v" && ! grep -qE "isFavorite: nil" "$v" && test "${n:-0}" -eq 2 && grep -qE "cacheVariant" "$v" && grep -qE "MapSettingsStore" "$d" && grep -qE "MapViewModel\(client:.*settings:" "$d" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Features/Search/MapViewModel.swift:218` et `:240` appellent `client.getMapMarkers(isFavorite: nil, isArchived: nil)` ; `Sources/DependencyContainer.swift:105` = `MapViewModel(client: client as any ImmichClient)`)
Post-state attendu: PASS
Note: le garde-fou « ne jamais écraser un cache par une réponse vide » de `persist(_:)` (`MapViewModel.swift:266-271`) doit survivre à la réécriture.
```

```
### AC-5144 [type: new]
Assertion: un `MapSettingsStore` `@Observable` persiste filtre et thème dans UserDefaults (clés `mapMarkerFilter` / `mapTheme`), expose `MapTheme` (system/light/dark) et sait effacer la seule plage de dates (« Remove custom date range » d'upstream, qui remet aussi le preset relatif à 0).
Check post-impl: sh -c 'f=Sources/Features/Search/MapSettingsStore.swift; test -f "$f" && grep -qE "@Observable" "$f" && grep -qE "class MapSettingsStore" "$f" && grep -qE "defaultsKeyFilter = \"mapMarkerFilter\"" "$f" && grep -qE "defaultsKeyTheme = \"mapTheme\"" "$f" && grep -qE "enum MapTheme: String, Codable, CaseIterable" "$f" && grep -qE "case system" "$f" && grep -qE "case light" "$f" && grep -qE "case dark" "$f" && grep -qE "func setFilter" "$f" && grep -qE "func setTheme" "$f" && grep -qE "func resetTimeRange" "$f" && grep -qE "defaults.set" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — `grep -rn "MapSettings" Sources/` renvoie 0 occurrence : ni store, ni vue, ni bouton d'accès)
Post-state attendu: PASS
Note: le `init` prend `defaults: UserDefaults = .standard` pour que les tests utilisent une suite dédiée.
```

```
### AC-5145 [type: new]
Assertion: la feuille de réglages est une feuille (aucun `NavigationStack`), édite un brouillon local puis applique à la fermeture, et porte les identifiants sur les contrôles interactifs ; le bouton d'ouverture et le thème (contrôle + application à `MKMapView`) vivent sur la carte.
Check post-impl: sh -c 's=Sources/Features/Search/MapSettingsSheet.swift; v=Sources/Features/Search/MapView.swift; test -f "$s" && grep -qE "struct MapSettingsSheet: View" "$s" && ! grep -qE "NavigationStack \{" "$s" && grep -qE "mapSettingsThemePicker" "$s" && grep -qE "mapSettingsFavoritesToggle" "$s" && grep -qE "mapSettingsArchivedToggle" "$s" && grep -qE "mapSettingsPartnersToggle" "$s" && grep -qE "mapSettingsRangePicker" "$s" && grep -qE "1095" "$s" && grep -qE "365" "$s" && grep -qE "firstDate" "$s" && grep -qE "draft" "$s" && grep -qE "InlineErrorBadge" "$s" && grep -qE "mapSettingsRangeError" "$s" && grep -qE "onApply" "$s" && grep -qE "presentSettings" "$v" && grep -qE "MapSettingsSheet\(" "$v" && grep -qE "presentationDetents" "$v" && grep -qE "accessibilityIdentifier\(\"mapSettingsButton\"\)" "$v" && grep -qE "overrideUserInterfaceStyle" "$v" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent ; `grep -c accessibilityIdentifier Sources/Features/Search/MapView.swift` = 0)
Post-state attendu: PASS
Note: presets 0/1/7/30/365/1095 jours (`relativeDays`) et `DatePicker` borné à `Date(timeIntervalSince1970: 0)` ; une plage début > fin affiche `mapSettingsRangeError` (`InlineErrorBadge`) et laisse « Done » désactivé, aucun appel réseau n'est émis dans cet état ; le thème est un `Picker` à trois cas (`MapTheme` system/light/dark, identifiant `mapSettingsThemePicker`) appliqué par `map.overrideUserInterfaceStyle = interfaceStyle ?? .unspecified` sur `ClusteredMapView` (`MapView.swift:315`) ; identifiants sur les `Picker`/`Toggle`/`Button`, jamais sur un conteneur (il absorbe alors l'identifiant de ses enfants).
```

```
### AC-5146 [type: new]
Assertion: le filtre actif est lisible sans ouvrir la feuille : badge sur le bouton de réglages de la carte et bandeau de résumé dans la feuille de photos, tous deux dérivés de `vm.filter` et rafraîchis après `applyFilter(_:)`.
Check post-impl: sh -c 'v=Sources/Features/Search/MapView.swift; n=$(grep -cE "filter\.(onlyFavorites|includeArchived|withPartners|relativeDays|from|to|isEmpty)" "$v"); grep -qE "mapFilterActiveBadge" "$v" && grep -qE "mapFilterSummary" "$v" && test "${n:-0}" -ge 2 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`MapView.swift` ne contient ni badge ni bandeau : 0 occurrence de `.filter.` et 0 identifiant d'accessibilité)
Post-state attendu: PASS
Note: aucune requête supplémentaire — tout vient de `vm.filter` ; si `MapPhotosSheet` (déclarée `let vm: MapViewModel`, `MapView.swift:148`) ne se rafraîchit pas, la passer à `@Bindable`.
```

```
### AC-5147 [type: new]
Assertion: les tests unitaires couvrent les trois surfaces : sérialisation/variante du filtre, persistance du store sur une suite UserDefaults dédiée, et le comportement d'`applyFilter` dans le ViewModel.
Check post-impl: sh -c 'a=Tests/MapMarkerFilterTests.swift; b=Tests/MapSettingsStoreTests.swift; c=Tests/MapViewModelTests.swift; n=$(grep -cE "func test_" "$a" 2>/dev/null); m=$(grep -cE "func test_" "$b" 2>/dev/null); k=$(grep -cE "func test_.*(applyFilter|[Ff]ilter)" "$c"); test -f "$a" && test -f "$b" && test "${n:-0}" -ge 4 && grep -qE "fileCreatedAfter" "$a" && grep -qE "cacheVariant" "$a" && test "${m:-0}" -ge 3 && grep -qE "UserDefaults\(suiteName:" "$b" && test "${k:-0}" -ge 3 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Tests/MapMarkerFilterTests.swift` et `Tests/MapSettingsStoreTests.swift` absents ; `Tests/MapViewModelTests.swift` n'a aucun cas `applyFilter` — 21 `func test_` mesurés, aucun sur le filtre)
Post-state attendu: PASS
Note: un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate` — sans régénération la suite passe « verte » par omission.
```

```
### AC-5148 [type: new]
Assertion: l'aperçu carte du lieu, déjà monté dans le panneau d'infos, devient dépliable en plein écran : zone tapable identifiée dans `PhotoInfoPanel`, nouvelle feuille `AssetLocationMapSheet` avec interaction activée (à l'inverse de `MiniMapView`) et même échelle de cadrage, montée par `PhotoViewer` qui reste le propriétaire de la présentation.
Check post-impl: sh -c 'p=Sources/Features/PhotoViewer/PhotoInfoPanel.swift; v=Sources/Features/PhotoViewer/PhotoViewer.swift; s=Sources/Features/PhotoViewer/AssetLocationMapSheet.swift; grep -qE "onOpenLocationMap" "$p" && grep -qE "locationMapPreviewButton" "$p" && grep -qE "onOpenLocationMap" "$v" && grep -qE "AssetLocationMapSheet" "$v" && test -f "$s" && grep -qE "struct AssetLocationMapSheet: View" "$s" && grep -qE "latitudeDelta: 0.01" "$s" && grep -qE "Marker\(" "$s" && ! grep -qE "isUserInteractionEnabled = false" "$s" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Features/PhotoViewer/PhotoInfoPanel.swift:373` monte `MiniMapView` sans ouverture tapable — `:16` et `:274-275` n'exposent que `onOpenInMaps`/`onAdjustLocation` ; `AssetLocationMapSheet.swift` absent)
Post-state attendu: PASS
Note: `MiniMapView` reste non interactif (`PhotoInfoPanel.swift:565`) — c'est la feuille plein écran qui porte l'interaction.
```

```
### AC-5149 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED.
Check post-impl: sh -c 'l=/tmp/immich_mapsettings_test.log; n=$(grep -oE "Executed [0-9]+ tests" "$l" 2>/dev/null | grep -oE "[0-9]+" | sort -n | tail -1); grep -qE "TEST SUCCEEDED" "$l" 2>/dev/null && test "${n:-0}" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent)
Post-state attendu: PASS
```
