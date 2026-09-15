# Task: recently-taken

> **Audit 2026-09-15 — écart G13** (`.omp/backlog/ImmichSwiftUI-backlog.md` §2.17, P4 découverte) : le client officiel expose deux routes de consultation rapide —
> `mobile/lib/routing/router.dart` (`e55ac299`) déclare `AutoRoute(page: RecentlyTakenRoute.page, guards: [_authGuard, _duplicateGuard])` et `AutoRoute(page: RecentlyAddedRoute.page, guards: [_authGuard, _duplicateGuard])`,
> portées par deux pages de 32 lignes qui ne contiennent aucune logique (`mobile/lib/presentation/pages/recently_taken.page.dart:11-30`, `recently_added.page.dart:11-30` : un `Timeline` avec un titre différent, alimenté par `timelineFactoryProvider.remoteAssets(user.id)` / `.recentlyAdded(user.id)`).
> Côté iOS, `grep -n "Recently" Sources/` ne renvoie que le commentaire de `Sources/Features/Trash/TrashView.swift:3` ; ni `Sources/Features/Recent/` ni `Sources/Features/RecentlyTaken/` n'existent, et le seul ordre de tri disponible sur une grille d'assets est celui de la timeline.

**Objectif** : après cette fiche, l'utilisateur ouvre depuis le hub « Me » un écran **Recently Taken** qui liste les photos par date de prise de vue décroissante,
et un écran **Recently Added** qui liste les photos par date d'ajout au serveur décroissante — les deux en grille paginée par jour, sans mode sélection,
avec l'état vide, l'erreur, le rechargement par pull et le chargement progressif en fin de grille. Les deux écrans ne font que consulter : aucun bouton de barre d'outils n'y agit sur les assets.

**Hors périmètre** :
- **Le tri de la timeline principale** : `TimelineView` garde `takenAt` par défaut ; aucun réglage n'est ajouté à l'onglet Photos.
- **Les autres `TimelineOrigin` de l'upstream** (`favorite`, `archived`, `video`, `place`, `person`, `locked`) : seuls `remoteAssets` et `recentlyAdded` donnent les deux routes de cette fiche.
  Favoris, archive, vidéos et dossier verrouillé ont leurs propres écarts (G6, G12, …).
- **Le mode sélection et les actions en masse** sur ces écrans : l'upstream les offre parce que son widget `Timeline` est le même objet que la timeline principale ; ici les écrans sont en lecture seule, l'édition passe par l'onglet Photos.
- **La déduplication entre « ajoutés » et la timeline** : `orderBy=createdAt` ne change que l'ordre et les clés de buckets, jamais le contenu renvoyé.
- **Une entrée depuis l'onglet Photos** : tranché à l'étape 10, non retenue.

**Hypothèses** (vérifiées dans le dépôt et contre `immich-app/immich@main`, le 2026-09-15) :

- **Upstream — ce que « récemment ajouté » veut dire exactement** :
  - `mobile/lib/domain/services/timeline.service.dart:60-70` : `TimelineService recentlyAdded(String userId) => TimelineService(_timelineRepository.recentlyAdded(userId, groupBy));` — le service n'est qu'un câblage, l'ordre est décidé plus bas.
  - `mobile/lib/infrastructure/repositories/timeline.repository.dart:310-319` : `TimelineQuery recentlyAdded(String userId, GroupAssetsBy groupBy)` filtre `row.uploadedAt.isNotNull() & row.deletedAt.isNull() & (row.visibility.equalsValue(timeline) | row.visibility.equalsValue(archive))`, avec `origin: TimelineOrigin.recentlyAdded, sortBy: SortAssetsBy.uploaded`.
  - `timeline.repository.dart:701-705` et `:714` : l'implémentation réelle est `OrderingTerm.desc(sortBy == SortAssetsBy.uploaded ? _db.remoteAssetEntity.uploadedAt : _db.remoteAssetEntity.createdAt)`.
    **« Récemment ajoutés » = tri décroissant sur la date de mise en ligne**, et le Flutter l'obtient de sa **réplique Drift locale** (`mergedAssetDrift` / `remoteAssetEntity`), pas d'une route serveur.
  - Conséquence directe : iOS n'ayant pas de réplique, l'équivalent serveur est le champ `createdAt` d'un asset — la date d'insertion de la ligne côté serveur, c'est-à-dire la mise en ligne.
- **OpenAPI publié (`/tmp/immich-openapi-main.json`, `main`)** :
  - `GET /timeline/buckets` accepte **`orderBy` → `AssetOrderBy`** et **`order` → `AssetOrder`**, à côté de `isFavorite`, `isTrashed`, `key`, `personId`, `slug`, `tagId`, `userId`, `visibility`, `withStacked`, `withPartners` ;
    `components.schemas.AssetOrderBy.enum == ["takenAt", "createdAt"]` (description : *Asset sorting property*).
  - `POST /search/metadata` prend un `orderBy` de type `SearchOrder { field: SearchOrderField (défaut fileCreatedAt), direction: AssetOrder (défaut desc) }` et
    `components.schemas.SearchOrderField.enum == ["fileCreatedAt", "localDateTime", "fileSizeInBytes", "rating"]` — **aucun champ de date de mise en ligne**.
    Ses `order`, `page`, `size` (défaut 250) et `takenAfter`/`createdAfter`/… sont marqués `deprecated` au profit de `cursor`. Sa réponse est `SearchResponseDto { assets, albums }`.
  - Conclusion mesurable : **seule la route buckets peut produire « récemment ajoutés »** ; `search/metadata` en est structurellement incapable.
- **iOS — le contrat de transport à étendre** :
  - `Sources/Core/Constants.swift:85-88` : `enum AssetOrderBy: String, Codable, Sendable { case takenAt; case createdAt }` — **déjà défini, jamais référencé ailleurs dans `Sources/` ni `Tests/`** (un grep de `AssetOrderBy` ne renvoie que sa déclaration).
  - `Sources/Core/Protocols/ImmichClient.swift:30-37` : `func getTimeBuckets(isFavorite:isTrashed:personId:withPartners:visibility:withStacked:) async throws -> [TimeBucketsResponseDto]` — **ni `orderBy` ni `order`**.
  - `Sources/Services/ImmichAPIClient.swift:111-127` : construit la liste de `URLQueryItem` puis `sendAuthed(.GET, path: ImmichAPI.timeline.path("/buckets"), query: query)`. `Sources/Core/Constants.swift:22` porte `static let timeline = SubPath(root: "/timeline")`.
  - Conformateurs et appelants à suivre dans la même passe : `Tests/Mocks/MockImmichClient.swift:323`, `Sources/Features/Timeline/TimelineViewModel.swift:161,178,204`, `Sources/Features/Trash/TrashViewModel.swift:38,54`.
    `Sources/ImmichSharedKit/WidgetDataProvider.swift:268-272` appelle `/api/timeline/buckets` en direct, hors protocole : non concerné.
  - Réponse : `Sources/Core/Types/DTOs.swift:61-63` — `TimeBucketsResponseDto { let timeBucket: String; let count: Int }` ; la clé est une date ISO, donc la section de jour est déjà disponible sans requête supplémentaire.
- **iOS — la surface de navigation** :
  - `Sources/RootView.swift:139-142` : l'onglet Photos rend `TimelineView(vm: timeline, stacks: stacks, scrollTargetID:, scrollTargetDay:)`.
  - `Sources/Features/Timeline/TimelineView.swift:69` : `TimelineView` porte **son propre `NavigationStack`** ; `:219` : `.toolbar(vm.selectionMode ? .visible : .hidden, for: .navigationBar)` — la barre est **cachée hors mode sélection**.
    Son overlay top-leading (`:110-118`) contient l'avatar qui présente la feuille « Me » via `OpenProfileKey` (`Sources/RootView.swift:302-306`), et `:222` monte `.navigationDestination(item: $openedStackID)`, qui exige un `StacksViewModel`.
  - `Sources/Features/Profile/ProfileView.swift:24` : le hub « Me » est un `NavigationStack { … }` ; son doc-comment (`:3-6`) dit qu'il recueille les features ayant perdu leur onglet.
    Les lignes vivent dans une `Section` à en-tête « Management » (`:55-115`), avec le précédent exact d'une vue poussée sans `NavigationStack` : `NavigationLink { OfflineAssetsView(vm: offline) } label: { Label("Offline Storage", systemImage: "arrow.down.circle") }` (`:107-111`).
  - `Sources/DependencyContainer.swift:92-94` : `func makeTimelineViewModel() -> TimelineViewModel { TimelineViewModel(client: client as any ImmichClient) }` — le patron de fabrique à imiter.
  - `Sources/Features/Timeline/AssetMultiSelectGrid.swift:1-30` : la grille réutilisable hors timeline est une grille de **sélection** (`selectedIds`, `excluding`, `selectionHint`, `onToggle`, paginée par `POST /api/search/metadata`) — inadaptée à une consultation pure ;
    l'unité réellement réutilisable est la cellule `AssetThumbnailCell` (`Sources/Features/Timeline/AssetThumbnailCell.swift`).
- **Ce qui rend la fiche nécessaire** : aucune vue de `Sources/` ne peut demander une grille ordonnée autrement que par date de prise de vue — `ImmichClient.getTimeBuckets` n'expose pas l'axe de tri,
  et l'unique appel de recherche ordonnée (`SearchViewModel`) ne peut pas viser la date d'ajout.

**Approche retenue** : A — étendre `getTimeBuckets` d'un paramètre `orderBy: AssetOrderBy?` (l'enum existe déjà, non branché), puis **un seul** `RecentAssetsViewModel` paramétré par `RecentAssetsMode` (`.taken` / `.added`) et **une seule** `RecentAssetsView`, poussés deux fois depuis le hub « Me ».
- **B (rejetée)** : pousser deux `TimelineView` supplémentaires alimentées par un `TimelineViewModel(client:orderBy:)` → rejetée sur trois faits mesurables de `TimelineView.swift` :
  (1) `:219` masque la barre de navigation hors mode sélection, donc le bouton Retour du `NavigationLink` disparaît dès l'arrivée sur l'écran ;
  (2) l'overlay `:110-118` rend l'avatar de profil qui présente la feuille « Me » (`OpenProfileKey`) — la feuille serait présentée depuis elle-même ;
  (3) `:222` exige un `StacksViewModel`, soit une troisième instance de ce ViewModel. L'upstream échappe au problème parce que son `Timeline` est **le** widget partagé, pas une page.
- **C (rejetée)** : bâtir les deux écrans sur `POST /api/search/metadata` (le chemin déjà câblé par `SearchViewModel` et `AssetMultiSelectGrid`) → rejetée par le contrat :
  `SearchOrderField.enum` vaut `["fileCreatedAt", "localDateTime", "fileSizeInBytes", "rating"]`, **aucune date d'ajout n'est triable**, et `order`/`page` sont `deprecated` au profit d'un `cursor` que `MetadataSearchDto` (`Sources/Core/Types/SearchDTOs.swift`) ne modélise même pas. L'écran « Recently Added » serait impossible.

## Étapes

1. **Le paramètre de tri dans le protocole** — EDIT `Sources/Core/Protocols/ImmichClient.swift` : ajouter `orderBy: AssetOrderBy?` à la signature de `getTimeBuckets` (`:30-37`), avant `withStacked`,
   et étendre le doc-comment : « `orderBy: .createdAt` demande `GET /api/timeline/buckets?orderBy=createdAt` — les buckets sont alors les jours de **mise en ligne**. `nil` laisse le défaut serveur (`takenAt`). ».
   Une exigence de protocole ne peut pas porter de valeur par défaut : **tous** les conformateurs et appelants sont mis à jour dans la même passe (étapes 2 à 4).
2. **Le transport** — EDIT `Sources/Services/ImmichAPIClient.swift` : dans `getTimeBuckets` (`:111-127`), ajouter `if let orderBy { query.append(URLQueryItem(name: "orderBy", value: orderBy.rawValue)) }` à côté de `withStacked`.
   `AssetOrderBy.rawValue` vaut déjà `takenAt` / `createdAt`, soit exactement l'`enum` de `components.schemas.AssetOrderBy` : aucune table de conversion.
3. **Le mock de test** — EDIT `Tests/Mocks/MockImmichClient.swift` : aligner la signature (`:323`) et mémoriser la valeur reçue dans une propriété lisible par les tests (`private(set) var lastTimeBucketsOrderBy: AssetOrderBy?`), sur le modèle des autres captures du mock.
   C'est ce qui permet d'asserter la requête sans serveur.
4. **Les appelants existants** — EDIT `Sources/Features/Timeline/TimelineViewModel.swift` (`:161`, `:178`, `:204`) et EDIT `Sources/Features/Trash/TrashViewModel.swift` (`:38`, `:54`) : passer `orderBy: nil`.
   Aucun changement de comportement — ces deux écrans restent sur l'ordre serveur par défaut.
5. **Le mode** — NEW `Sources/Features/Recent/RecentAssetsMode.swift` : `import Foundation`. `enum RecentAssetsMode: String, Sendable, CaseIterable { case taken, added }` avec
   `var orderBy: AssetOrderBy { self == .taken ? .takenAt : .createdAt }`, `var title: LocalizedStringKey { self == .taken ? "Recently Taken" : "Recently Added" }` et `var emptyMessage: LocalizedStringKey`.
   Les deux pages upstream ne diffèrent que par ces deux valeurs (`recently_taken.page.dart:24-29` vs `recently_added.page.dart:24-29`) : un enum les représente exactement, sans dupliquer une vue.
6. **Le ViewModel** — NEW `Sources/Features/Recent/RecentAssetsViewModel.swift` : `import Foundation`, `import Observation`. `@MainActor @Observable final class RecentAssetsViewModel` avec
   `let mode: RecentAssetsMode`, `private let client: any ImmichClient`, `init(client: any ImmichClient, mode: RecentAssetsMode)`, et l'état publié
   `private(set) var dayGroups: [RecentDayGroup] = []`, `private(set) var isLoading = false`, `private(set) var isLoadingMore = false`, `private(set) var errorMessage: String?`, `private(set) var hasMore = true`
   (faux quand le dernier bucket demandé ne renvoie rien), plus le privé `private var buckets: [TimeBucketsResponseDto] = []`, `private var bucketIndex = 0`, `private var loadedIds: Set<String> = []`.
   - `func load() async` : `isLoading = true`, puis `buckets = try await client.getTimeBuckets(isFavorite: nil, isTrashed: nil, personId: nil, withPartners: nil, visibility: nil, withStacked: true, orderBy: mode.orderBy)`.
     `withStacked: true` parce que le badge « +N » de `AssetThumbnailCell` suppose des buckets sans les secondaires (`Sources/Features/Timeline/AssetThumbnailCell.swift:148-151`).
     Puis `bucketIndex = 0`, `loadedIds = []`, `dayGroups = []`, et `await loadNextBucket()`. Le `catch` renseigne `errorMessage`, que l'écran rejoue par un bouton « Refresh ».
   - `private func loadNextBucket() async` : lit `client.getTimeBucket(timeBucket: buckets[bucketIndex].timeBucket, personId: nil, withPartners: nil, visibility: nil, withStacked: true)`,
     applique `AssetReactItem.zip(...)`, filtre les ids déjà présents (`loadedIds`) et **insère en fin** — contrairement à `TimelineViewModel.loadOlder()` (`:233-237`) qui préfixe : ici on descend toujours vers le plus ancien.
   - `func loadMore() async` : garde `hasMore`, incrémente `bucketIndex`, appelle `loadNextBucket()`.
     `struct RecentDayGroup: Identifiable, Equatable { let id: String; let title: String; let items: [AssetReactItem] }` est construit depuis `buckets[i].timeBucket` (déjà une date ISO) et `DateHeaderFormatter`, le formateur de jour de la timeline (`Sources/Features/Timeline/TimelineView.swift:11`).
   - `func refresh() async { await load() }`. Aucun état partagé, aucune instance unique : deux instances (une par mode) ne se marchent pas dessus, ce qui rend inutile la contrainte « un VM de processus » de `DependencyContainer`.
7. **L'écran** — NEW `Sources/Features/Recent/RecentAssetsView.swift` : `import SwiftUI`. `struct RecentAssetsView: View` prenant `@State var vm: RecentAssetsViewModel`. Corps :
   `ScrollView { LazyVStack(spacing: PVSpacing.s24, pinnedViews: [.sectionHeaders]) { ForEach(vm.dayGroups) { group in Section { grid(group.items) } header: { dayHeader(group.title) } } } }` avec `.padding(.horizontal, 4)` (convention de grille de la timeline),
   plus un `ProgressView()` en pied déclenchant `await vm.loadMore()` par `.onAppear` quand `vm.hasMore`, un `ContentUnavailableView` pour l'état vide (`vm.mode.emptyMessage`) et un pour l'erreur (message + bouton « Refresh »).
   - `grid(_:)` : `private let columns = Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s2), count: 3)` et `AssetThumbnailCell(asset:baseURL:token:)` — la cellule de la timeline, aucune cellule neuve.
     **Pas de sélection, pas de badge de sélection, pas de `NavigationLink`** : ces écrans sont des galeries consultatives.
   - `.navigationTitle(vm.mode.title)`, `.navigationBarTitleDisplayMode(.inline)`, `.task { await vm.load() }`, `.refreshable { await vm.refresh() }`, `.background(Color.bgPrimary)`.
     **Aucun `NavigationStack`** : la vue est poussée depuis `ProfileView`, qui en porte un (`Sources/Features/Profile/ProfileView.swift:24`) — même contrat que `OfflineAssetsView`.
   - Identifiants : `recentGrid` sur le `ScrollView`, `recentEmptyState` sur l'état vide, `recentError` sur le bloc d'erreur — posés sur les éléments concernés, jamais sur un conteneur qui en contient
     (piège mesuré : un identifiant de conteneur écrase celui de ses descendants).
8. **La fabrique** — EDIT `Sources/DependencyContainer.swift` : ajouter, à côté de `makeTimelineViewModel()` (`:92-94`), `func makeRecentAssetsViewModel(mode: RecentAssetsMode) -> RecentAssetsViewModel { RecentAssetsViewModel(client: client as any ImmichClient, mode: mode) }`.
   Le mode est un paramètre explicite, comme `makeAlbumDetailViewModel(albumId:)` (`:112-114`).
9. **Le câblage racine** — EDIT `Sources/RootView.swift` : déclarer dans `AuthenticatedRoot` `@State private var recentTaken: RecentAssetsViewModel` et `@State private var recentAdded: RecentAssetsViewModel`,
   les initialiser dans `init(container:)` par `_recentTaken = State(initialValue: container.makeRecentAssetsViewModel(mode: .taken))` et `_recentAdded = State(initialValue: container.makeRecentAssetsViewModel(mode: .added))`,
   puis les passer à l'appel `ProfileView(...)` du `.sheet(isPresented: $showProfile)` — l'endroit qui liste déjà `trash:`, `stacks:`, `offline:`.
10. **Le point d'entrée** — EDIT `Sources/Features/Profile/ProfileView.swift` : ajouter `@State var recentTaken: RecentAssetsViewModel` et `@State var recentAdded: RecentAssetsViewModel` aux propriétés stockées (après `@State var offline`),
    puis insérer **avant** la `Section` à en-tête « Management » (`:55`) une nouvelle `Section { … } header: { Text("Recently") }` contenant
    `NavigationLink { RecentAssetsView(vm: recentTaken) } label: { Label("Recently Taken", systemImage: "clock.arrow.circlepath") }` avec `.accessibilityIdentifier("recentTakenRow")`, puis
    `NavigationLink { RecentAssetsView(vm: recentAdded) } label: { Label("Recently Added", systemImage: "arrow.up.circle") }` avec `.accessibilityIdentifier("recentAddedRow")`.
    Choix justifié : ces deux écrans consultent la photothèque comme l'onglet Photos, mais `TimelineView` masque sa barre de navigation hors sélection (`TimelineView.swift:219`) et présente la feuille « Me » depuis son propre overlay (`:110-118`) ;
    une entrée depuis l'onglet Photos demanderait donc de toucher la vue la plus réglée du dépôt pour un gain nul, alors que le hub « Me » est déjà le point d'entrée des surfaces poussées de ce type (`OfflineAssetsView`, `:107-111`). L'en-tête « Recently » garde ces liens hors de Management, qui porte des réglages.
11. **Les tests du ViewModel** — NEW `Tests/RecentAssetsViewModelTests.swift` : `import XCTest`, `@testable import ImmichSwiftUI`. Suite `final class RecentAssetsViewModelTests: XCTestCase`, `@MainActor`, fabriquant un `MockImmichClient` alimenté en buckets et en buckets d'assets.
    Cas nommés : `test_takenMode_requestsBucketsOrderedByTakenAt` (assertion sur `lastTimeBucketsOrderBy == .takenAt`), `test_addedMode_requestsBucketsOrderedByCreatedAt`, `test_load_groupsItemsByBucketDay`,
    `test_loadMore_appendsOlderBucketsAtTheEnd` (l'ordre des items ne s'inverse pas, contrairement à la timeline), `test_loadMore_dedupesAssetsAlreadyLoaded`, `test_loadMore_stopsAtTheLastBucket` (`hasMore == false`, aucun appel supplémentaire),
    `test_load_failure_surfacesMessageAndKeepsEmptyGrid`, `test_refresh_replacesTheGrid`. Aucun test ne pinne un libellé d'interface.
12. **Le catalogue de chaînes** — aucune écriture manuelle dans `Resources/Localizable.xcstrings` : la clé est la chaîne anglaise et l'extraction Xcode la crée au build.
    Chaînes neuves des étapes 5, 7 et 10 : `Recently Taken`, `Recently Added`, `Recently`, `Photos you take will appear here.`, `Photos you add to the server will appear here.`, `Refresh`.
13. `xcodegen generate` (trois fichiers source et un fichier de test sont ajoutés : sans régénération ils ne sont pas compilés), puis la suite complète `-only-testing:ImmichSwiftUITests` — la signature `getTimeBuckets` change, donc tout le module recompile d'un bloc.

## Incertitudes à lever à l'implémentation

- **La propriété de date d'un `AssetReactItem`.** Le groupement par jour s'appuie sur la clé du bucket (`TimeBucketsResponseDto.timeBucket`), mais si la cellule ou l'en-tête a besoin de la date de l'asset lui-même, il faut le bon nom de champ.
  Vérifier par : `grep -n "let fileCreatedAt\|let localDateTime\|let uploadedAt" Sources/Core/Types/AssetReactItem.swift`.
- **L'interactivité de la tuile.** `TimelineView` ouvre le viewer par un tap sur la cellule ; reproduire ce tap depuis un écran poussé par le hub n'engage aucune ressource nouvelle (`.photoViewer(item:)` est un modificateur de vue).
  Si cette ouverture se heurte au présentateur de la feuille « Me » (SwiftUI sérialise les présentations d'un même présentateur — `Sources/RootView.swift:74-78`), l'écran reste consultatif et le plein écran se fait depuis l'onglet Photos.
  Vérifier par : un run manuel sur simulateur — aucune commande ne tranche un comportement de présentation SwiftUI.
- **Le libellé des en-têtes de jour.** `DateHeaderFormatter` produit les chaînes relatives de la timeline (`Today`, `Yesterday`) : vérifier qu'elles restent lisibles pour des jours de **mise en ligne**, où « Today » signifie « ajouté aujourd'hui », pas « pris aujourd'hui ».
  Vérifier par : `grep -n "func \|static let" Sources/Core/Utilities/DateHeaderFormatter.swift`, puis un coup d'œil aux deux écrans côte à côte.
- **Le sort du paramètre `order`.** L'OpenAPI expose aussi `order` → `AssetOrder` (`asc`/`desc`). Il n'est pas nécessaire ici (le défaut serveur `AssetOrderBy` est `takenAt` et `SearchOrder.direction` défaut `desc`),
  mais si un bucket vide montre un ordre inattendu, la correction est d'envoyer `order: .desc` explicitement, pas de trier côté client. Vérifier par : relecture du paramètre `order` de `/timeline/buckets` dans `/tmp/immich-openapi-main.json`.
- **Le nom du dossier de feature.** `Sources/Features/Recent/` est proposé parce que l'enum couvre les deux modes ; un dossier par route upstream (`RecentlyTaken/`, `RecentlyAdded/`) ne changerait aucune signature — seule l'étape 13 est concernée.
  Vérifier par : `grep -rn "Features/" project.yml` pour la convention de déclaration des sources.
