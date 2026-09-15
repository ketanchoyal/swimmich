# Task: map-settings

> **Audit 2026-09-15 — écart G14b** :
> le client Flutter a une feuille de réglages de carte (thème, favoris seuls, archives, partenaires, plage de dates relative ou personnalisée) ;
> l'app iOS n'en a aucune et code en dur `getMapMarkers(isFavorite: nil, isArchived: nil)` en deux endroits.
> Preuve upstream : `mobile/lib/presentation/widgets/map/map_settings_sheet.dart@e55ac299` (`switchFavoriteOnly`, `switchIncludeArchived`, `switchWithPartners`, `setRelativeTime(0)`, `setCustomTimeRange(const TimeRange())`, boutons `use_custom_date_range`/`remove_custom_date_range`),
> `mobile/lib/widgets/map/map_settings/map_settings_time_dropdown.dart` (entrées 0 / 1 / 7 / 30 / 1 an / 3 ans en jours)
> et `map_custom_time_range.dart` (deux sélecteurs `date_after`/`date_before`, `firstDate: DateTime(1970)`).
> État iOS vérifié : `Sources/Core/Protocols/ImmichClient.swift:67` n'expose que `isFavorite`/`isArchived`,
> `Sources/Services/ImmichAPIClient.swift:197-201` ne sérialise que ces deux-là,
> `Sources/Features/Search/MapViewModel.swift:218` et `:240` les passent à `nil`.

**Objectif** :
depuis le segment carte de l'onglet Recherche, l'utilisateur ouvre une feuille de réglages et choisit
(a) le thème de la carte (système / clair / sombre),
(b) favoris seuls, archives incluses, partenaires inclus,
(c) une plage de dates — preset relatif (tout / jour / 7 / 30 / 1 an / 3 ans) ou plage personnalisée « après »/« avant » avec bornes effaçables.
Les marqueurs, la feuille de photos et leurs compteurs se recalculent aussitôt, et le choix survit à un relancement de l'app.
Depuis le viewer, la carte du lieu d'un asset (déjà affichée) devient dépliable en plein écran pour explorer autour du lieu.

**Hors périmètre** :
l'aperçu carte du lieu dans le panneau d'infos est **déjà livré** (`Sources/Features/PhotoViewer/PhotoInfoPanel.swift:361-378` monte `MiniMapView`, défini `:548`) — seule son ouverture en plein écran est traitée ici.
Rien sur « Open in Maps » (`:389-397`), « Adjust Location » (`AdjustLocationSheet`, `:398-406`), le clustering/la culling de `ClusteredMapView`, le format des marqueurs (`MapMarkerResponseDto`),
ni les filtres de recherche (`SearchFilter`) — le filtre de carte est un état indépendant du segment Search.

**Hypothèses** (vérifiées dans le dépôt et contre `immich-app/immich@main`, le 2026-09-15) :
- `ImmichClient.getMapMarkers(isFavorite: Bool?, isArchived: Bool?) async throws -> [MapMarkerResponseDto]` — `Sources/Core/Protocols/ImmichClient.swift:67` ;
  implémentation `Sources/Services/ImmichAPIClient.swift:197-205` (query `isFavorite`, `isArchived`).
- `MapViewModel` (`Sources/Features/Search/MapViewModel.swift`) : `markers` / `visibleAnnotations` / `visiblePhotos` recalculés par `filterVisible(_:)`,
  cache disque `MapMarkerCache` (`private let cache`, `:73`), `refreshTTL` (`:155-163`), `reload()` (`:290-297`) qui fait `cache.clear()` puis `loadMarkers()`,
  `persist(_:)` (`:266-271`) et `applyMarkers(_:persist:)` (`:276-287`).
- `MapMarkerCache` (`Sources/Features/Search/MapMarkerCache.swift`) : un seul fichier `Caches/MapMarkers/markers.json` (`:24-31`),
  `load()` (`:34`), `age()` (`:36-40`), `save(_:)` (`:51-58`), `clear()` (`:60-62`) — aucune dimension de filtre dans le chemin de fichier.
- Route `GET /api/map/markers` dans `/tmp/immich-openapi-main.json` : paramètres `fileCreatedAfter` (string, `date-time`), `fileCreatedBefore` (string, `date-time`),
  `isArchived`, `isFavorite`, `withPartners`, `withSharedAlbums`.
  **C'est `fileCreatedAfter`/`fileCreatedBefore` qui portent la plage temporelle** — pas `takenAfter`/`takenBefore`.
- `GET /api/timeline/buckets` n'a **aucun** paramètre de date (relevé : `albumId`, `bbox`, `isFavorite`, `isTrashed`, `key`, `order`, `orderBy`, `personId`, `slug`, `tagId`, `userId`, `visibility`, `withCoordinates`, `withPartners`, `withStacked`)
  → il ne peut pas porter la plage personnalisée.
- `MetadataSearchDto` porte bien `takenAfter`/`takenBefore` (plus `createdAfter`, déprécié) mais il rend des assets, pas des marqueurs, et n'a aucun filtre lat/lon
  → il ne remplace pas `/api/map/markers`.
- Aucun symbole `MapSettings*` n'existe dans `Sources/` (grep) : ni store, ni vue, ni bouton d'accès.
- La feuille de photos de la carte est présentée par `AuthenticatedRoot` (`Sources/RootView.swift:227-243`, `presentationBackgroundInteraction(.enabled)`) ;
  `MapSegmentView` est monté par `SearchView` (`Sources/Features/Search/SearchView.swift:18`, `:123-125`) et reçoit le VM partagé construit par `DependencyContainer.makeMapViewModel()` (`Sources/DependencyContainer.swift:104-106`).
- Persistance de réglages : précédent maison = `BackupSettingsStore` (UserDefaults suite, `Sources/Features/Upload/UploadViewModel.swift:8-56`) et `AppLanguageStore` (`Sources/Features/Settings/AppLanguageStore.swift:25-36`).
- `MiniMapView` est volontairement non interactif (`isUserInteractionEnabled = false`, `Sources/Features/PhotoViewer/PhotoInfoPanel.swift:565`).

**Approche retenue** : A — un value type `MapMarkerFilter` (Equatable/Sendable, `Codable`) qui produit à la fois les `URLQueryItem` de `/api/map/markers` et une clé de variante de cache ;
le protocole `ImmichClient` prend ce filtre au lieu de deux `Bool?`, et un `MapSettingsStore` persistant (UserDefaults) alimente le `MapViewModel` qui recharge à chaque changement.
- **B (rejetée)** : garder la signature et empiler des paramètres optionnels (`withPartners:`, `createdAfter:`, `createdBefore:`)
  → 5 paramètres dont 3 `nil` par défaut aux **deux** sites d'appel (`MapViewModel.swift:218`, `:240`) ; rien ne détecte « le filtre a changé » (aucun `Equatable` à comparer)
  et la clé de cache devrait redupliquer la liste des paramètres, donc toute évolution future du filtre se ferait en deux endroits désynchronisables.
- **C (rejetée)** : ne rien changer côté réseau et filtrer côté client dans `filterVisible(_:)`
  → le serveur expose déjà `fileCreatedAfter`/`fileCreatedBefore`/`isFavorite`/`isArchived`/`withPartners` ; filtrer localement obligerait à télécharger et cacher la totalité du catalogue
  (10k+ marqueurs, ce que `MapMarkerCache` + `refreshTTL` existent pour amortir), à rescanner tous les marqueurs à chaque changement de région,
  et laisserait `MapPhotosSheet` afficher un total de région faux tant que le filtre local n'aurait pas été réappliqué.

## Étapes

1. **Filtre typé** — NEW `Sources/Core/Types/MapMarkerFilter.swift` :
   `struct MapMarkerFilter: Equatable, Sendable, Codable` avec `var onlyFavorites = false`, `var includeArchived = false`, `var withPartners = false`, `var relativeDays: Int? = nil`, `var from: Date?`, `var to: Date?` ;
   `static let all = MapMarkerFilter()`, `var isEmpty: Bool` (== `.all`) ;
   `func queryItems(now: Date = Date()) -> [URLQueryItem]` qui n'émet `isFavorite=true`/`isArchived=true`/`withPartners=true` que si vrai,
   `fileCreatedAfter` = `now - relativeDays * 86_400` (ISO 8601, même formateur que `ImmichAPIClient`), puis `fileCreatedAfter`/`fileCreatedBefore` de la plage personnalisée
   (`from`/`to` priment sur `relativeDays` : si l'un des deux est non nul, le preset relatif est ignoré) ;
   `var cacheVariant: String?` = `nil` quand `isEmpty`, sinon une clé stable **sans horodatage** (`"f1-a0-p1-r30"`, `"f0-a0-p0-c<epochFrom>-<epochTo>"`) —
   c'est ce qui permet de réutiliser le cache d'un preset pendant la fenêtre `refreshTTL`.

2. **Protocole** — EDIT `Sources/Core/Protocols/ImmichClient.swift:67` :
   remplacer `func getMapMarkers(isFavorite: Bool?, isArchived: Bool?) async throws -> [MapMarkerResponseDto]` par `func getMapMarkers(filter: MapMarkerFilter) async throws -> [MapMarkerResponseDto]`.

3. **Client** — EDIT `Sources/Services/ImmichAPIClient.swift:197-205` :
   `getMapMarkers(filter:)` construit `query = filter.queryItems()` et le passe au même helper de requête que les autres `GET` du fichier ; supprimer les deux `if let` sur `isFavorite`/`isArchived`.

4. **Cache indexé par filtre** — EDIT `Sources/Features/Search/MapMarkerCache.swift:22-32` :
   ajouter `variant: String? = nil` à l'initialiseur ; `fileURL` reste `markers.json` quand `variant == nil` (le cache existant reste donc valide, **aucune migration**)
   et devient `markers-<variant>.json` sinon. `load`/`age`/`save`/`clear` inchangés.

5. **Store de réglages** — NEW `Sources/Features/Search/MapSettingsStore.swift` :
   `@Observable @MainActor final class MapSettingsStore`, `init(defaults: UserDefaults = .standard)` avec `defaultsKeyFilter = "mapMarkerFilter"` et `defaultsKeyTheme = "mapTheme"`,
   `private(set) var filter: MapMarkerFilter`, `private(set) var theme: MapTheme` (`enum MapTheme: String, Codable, CaseIterable { case system, light, dark }`),
   `func setFilter(_:)` / `func setTheme(_:)` (encodage JSON via `JSONEncoder.immich` + `defaults.set`),
   et `func resetTimeRange()` qui remet `relativeDays`/`from`/`to` à `nil` (le « Remove custom date range » d'upstream, qui remet aussi le preset relatif à 0).

6. **ViewModel** — EDIT `Sources/Features/Search/MapViewModel.swift` :
   ajouter `let settings: MapSettingsStore` à l'init (`init(client:cache:settings:)`, `cache` par défaut reconstruit par variante), `var filter: MapMarkerFilter { settings.filter }` ;
   `func applyFilter(_ new: MapMarkerFilter) async` qui court-circuite si `new == settings.filter` (d'où l'`Equatable`), sinon `regionTask?.cancel()`, `settings.setFilter(new)`, `markers = []`, `loaded = false`, `errorMessage = nil`, `await loadMarkers()` ;
   remplacer les deux appels `client.getMapMarkers(isFavorite: nil, isArchived: nil)` (`:218` et `:240`) par `client.getMapMarkers(filter: filter)` et lire/écrire le cache via `MapMarkerCache(directory: nil, variant: filter.cacheVariant)` ;
   `persist` conserve son garde-fou « ne jamais écraser un cache par une réponse vide ».

7. **Injection** — EDIT `Sources/DependencyContainer.swift:104-106` :
   `MapSettingsStore` en propriété du conteneur (un seul store, partagé), `makeMapViewModel()` devient `MapViewModel(client: client as any ImmichClient, settings: mapSettings)` ;
   `Sources/RootView.swift:121` reste inchangé (il appelle déjà `makeMapViewModel()`).

8. **Feuille de réglages** — NEW `Sources/Features/Search/MapSettingsSheet.swift` :
   `struct MapSettingsSheet: View` avec `@Bindable var store: MapSettingsStore`, `let onApply: (MapMarkerFilter) -> Void`, `let onClose: () -> Void` — **pas de `NavigationStack`** (c'est une feuille, comme `AdjustLocationSheet`).
   Contenu aligné sur upstream : Toggle thème système ⇄ clair/sombre (`MapTheme`), Toggle « Only show favorites », Toggle « Include archived », Toggle « Include partners »,
   puis soit un `Picker` de preset (All / 1 day / 7 days / 30 days / 1 year / 3 years → `relativeDays` 0/1/7/30/365/1095),
   soit deux lignes « After »/« Before » avec `DatePicker(displayedComponents: .date)`, `firstDate: Date(timeIntervalSince1970: 0)` (= `DateTime(1970)` upstream) et `lastDate: Date()`,
   chacune avec un bouton croix d'effacement, plus le bouton de bascule « Use custom date range » / « Remove custom date range ».
   État d'édition local (`@State private var draft: MapMarkerFilter`) puis `onApply(draft)` à la fermeture ; chaînes d'UI via le catalogue `Resources/Localizable.xcstrings`.

9. **Accès depuis la carte** — EDIT `Sources/Features/Search/MapView.swift` (`MapSegmentView`) :
   ajouter un bouton capsule verre (même famille visuelle que la capsule du spinner, tokens `PVSpacing`) en haut à droite de la `ZStack`,
   `@State private var presentSettings = false` + `.sheet(isPresented: $presentSettings) { MapSettingsSheet(store: vm.settings, onApply: { filter in Task { await vm.applyFilter(filter) } }, onClose: { presentSettings = false }) }`
   avec `.presentationDetents([.medium, .large])`.

10. **Thème** — EDIT `Sources/Features/Search/MapView.swift` :
    `ClusteredMapView` (`:315`) reçoit `let interfaceStyle: UIUserInterfaceStyle?` et le pose en `makeUIView`/`updateUIView` (`map.overrideUserInterfaceStyle = interfaceStyle ?? .unspecified`) —
    `MapSegmentView` le dérive de `vm.settings.theme` (`.system → nil`, `.light → .light`, `.dark → .dark`), seul mécanisme qui change réellement les tuiles MKMapView.

11. **Aperçu plein écran depuis le viewer** — EDIT `Sources/Features/PhotoViewer/PhotoInfoPanel.swift:359-381` :
    rendre la carte de la carte « Where » tapable (`Button` transparent au-dessus de `MiniMapView`, ou `.onTapGesture`) quand `lat`/`lon` existent,
    en appelant un nouveau `var onOpenLocationMap: (() -> Void)?` (même patron que `onOpenInMaps`, `:15-16`, et `onAdjustLocation`, `:275`).

12. **Feuille plein écran du lieu** — NEW `Sources/Features/PhotoViewer/AssetLocationMapSheet.swift` :
    `struct AssetLocationMapSheet: View { let latitude: Double; let longitude: Double; let placeName: String? }` —
    `Map(position:)` SwiftUI avec un `Marker` (interaction **activée** cette fois, à l'inverse de `MiniMapView:565`),
    cadrage initial `MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)` (même échelle que `MiniMapView:568-570`), bouton fermer.

13. **Câblage viewer** — EDIT `Sources/Features/PhotoViewer/PhotoViewer.swift` :
    `@State private var locationMap: (Double, Double, String?)?`, passer `onOpenLocationMap = { locationMap = (lat, lon, placeLabel) }` au `PhotoInfoPanel`,
    monter `AssetLocationMapSheet` en `.sheet(item:)` sur `PhotoViewer` (propriétaire stable), pas sur le panneau.

14. **Lisibilité du filtre dans la feuille de photos** — EDIT `Sources/Features/Search/MapView.swift` :
    `MapPhotosSheet` affiche le filtre actif (bandeau plage de dates + « favorites only ») pour que son compteur de région soit interprétable ;
    aucune requête supplémentaire, tout est déjà dans `vm.filter`.

15. `xcodegen generate` (si un fichier a été ajouté) puis suite complète `-only-testing:ImmichSwiftUITests`.

## Incertitudes à lever à l'implémentation

- **`withPartners` réellement appliqué côté serveur** (marqueurs de partenaires filtrés par album partagé ? `withSharedAlbums` requis en complément ?)
  → `curl -s "$IMMICH/api/map/markers?withPartners=true" -H "x-api-key: $KEY" | jq length` puis même appel sans le paramètre, sur une instance avec un partenaire, en comparant aussi `fileCreatedAfter` seul.
- **Sémantique exacte de `fileCreatedAfter`** (date de fichier EXIF vs date d'upload) pour un preset « 1 year »
  → `curl -s "$IMMICH/api/map/markers?fileCreatedAfter=$(date -u -v-1y +%Y-%m-%dT%H:%M:%S.000Z)" -H "x-api-key: $KEY" | jq length` contre `POST /api/search/metadata` avec `takenAfter` équivalent ; si les deux divergent, garder `fileCreatedAfter` (seul paramètre de la route carte) et le documenter dans la feuille.
- **Fuseau des bornes** : les paramètres sont des `date-time`, pas des dates → comparer un asset pris à 23:30 heure locale le jour de la borne avec `curl -s "$IMMICH/api/map/markers?fileCreatedBefore=<jour borne>T00:00:00.000Z"` et ajuster l'arrondi des `DatePicker` (début/fin de journée locale).
- **Effet réel de `overrideUserInterfaceStyle` sur des tuiles déjà chargées** (MapKit peut garder le rendu en cache)
  → basculer clair → sombre dans le simulateur et vérifier visuellement ; si les tuiles ne changent pas, forcer un rechargement (`map.mapType = map.mapType`) ou recréer la vue via `.id(theme)`.
- **Coexistence de deux feuilles sur le même écran** (`MapSettingsSheet` depuis `MapSegmentView` vs `MapPhotosSheet` présentée par `AuthenticatedRoot`, `RootView.swift:227-243`)
  → vérifier au runtime ; si SwiftUI sérialise les présentations, remonter la feuille au présentateur stable (`RootView`) avec un `map.isSettingsSheetPresented` à côté de `isPhotoSheetPresented` (`MapViewModel.swift:83`).
- **`MapPhotosSheet` voit-elle le filtre ?** la vue reçoit `let vm: MapViewModel` (non `@Bindable`) → vérifier que le bandeau se rafraîchit après `applyFilter(_:)`, sinon passer la vue à `@Bindable var vm: MapViewModel`.
- **Compatibilité du cache existant** : `Caches/MapMarkers/markers.json` n'a pas de champ de filtre → confirmer qu'un fichier écrit par la version précédente est bien servi comme le filtre `.all` (lancer l'app avant/après la mise à jour et lire `[MapVM] cache hit: N markers`).
