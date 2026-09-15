# Task: folder-view

> **Audit 2026-09-15 — écart G11** (`.omp/backlog/ImmichSwiftUI-backlog.md` §2.17) : le client Flutter parcourt l'arborescence de dossiers du serveur via une page dédiée (`AutoRoute(page: FolderRoute.page, guards: [_authGuard])`,
  `mobile/lib/routing/router.dart:137`, import de la page en `:28`, du modèle en `:14`) dont tout le travail est dans `mobile/lib/pages/library/folder/folder.page.dart` (`FolderPage` / `FolderContent` /
  `FolderPath`) et `mobile/lib/services/folder.service.dart` (arbre construit côté client, assets lus par chemin) ; côté iOS, `Sources/Features/` n'a **aucun** dossier `Folders` (liste réelle : Admin, Albums,
  AssetDetail, Auth, Duplicates, Editor, Memories, Notifications, Offline, Partners, People, PhotoViewer, Profile, RoadTrip, Search, Settings, SharedLinks, Stacks, Tags, Timeline, Trash, Upload), `ImmichAPI` ne
  déclare aucun `SubPath` `/view`, et aucune déclaration de `ImmichClient` ne nomme un dossier.

**Objectif** : après cette fiche, l'utilisateur ouvre « Folders » depuis le hub « Me » (section Management) et retrouve dans l'app la structure de dossiers réelle que le serveur voit sur son disque
(bibliothèques externes : `/mnt/media/Photos/…`) : il voit les dossiers du niveau courant, descend d'un niveau en tapant un dossier, revient par la barre de navigation native, lit le chemin complet du dossier
affiché, voit la grille des assets **directement contenus** dans ce dossier et ouvre l'un d'eux en plein écran. Il peut inverser l'ordre des assets et retirer pour rafraîchir un dossier, sans que l'arbre soit
rechargé.

**Hors périmètre** :
- **Le dossier verrouillé** (`LockedFolderRoute`, `mobile/lib/presentation/pages/locked_folder.page.dart`, garde `LockedGuard`) : c'est l'écart G12, avec son PIN et son propre flux d'authentification.
  L'endpoint de cette fiche ne renvoie d'ailleurs **jamais** un asset `visibility = locked` (le filtre serveur est `visibility = Timeline`, voir les hypothèses).
- **Les assets archivés** : `ViewRepository.getAssetsByOriginalPath` filtre `visibility = Timeline` ; un asset archivé est donc invisible ici. Aucun paramètre de la route ne l'ouvre. La fiche ne contourne pas
  la limite par un second appel `search` — le comportement est celui du serveur, identique à celui du web et de Flutter.
- **La modification de l'arborescence** (déplacer, renommer, créer, supprimer un dossier) : l'OpenAPI publié ne publie aucune route de mutation sous `/view` ; les seules écritures disque passent par les
  bibliothèques d'import administrateur (écarts G12/G24, `/api/libraries`).
- **La multi-sélection et les actions en lot** sur la grille (favorite / archive / poubelle / ajout à un album) : les grilles existantes les portent par leurs propres ViewModels (`AssetMultiSelectGrid.swift`) ;
  cette vue est une vue de consultation et laisse à `AssetThumbnailCell` son menu contextuel par défaut.
- **La recherche par nom de dossier** : `GET /view/folder/unique-paths` renvoie tout l'annuaire en une réponse, sans paramètre de filtre ; un champ de recherche serait un filtre d'affichage, donc hors de la
  fiche.

**Hypothèses** (vérifiées dans le dépôt et contre `immich-app/immich@main` = `e55ac299`, le 2026-09-15) :

- **Upstream — les trois briques du modèle** :
  - `mobile/lib/models/folder/recursive_folder.model.dart` : `class RecursiveFolder extends RootFolder` et n'ajoute que `final String name` ; le parent `mobile/lib/models/folder/root_folder.model.dart` porte
    `path` et `subfolders`. Un nœud = (chemin absolu du parent, nom, enfants).
  - `mobile/lib/services/folder.service.dart` : `getFolderStructure(SortOrder order)` construit **tout l'arbre côté client** à partir de `getAllUniquePaths()` — une `Map<String, List<RecursiveFolder>>` clée par
    le chemin du parent, sentinelle `'_root_'` pour le premier niveau, entrée `'/'` ignorée, puis `attachSubfolders` récursif et tri par nom selon `order` à chaque niveau. `getFolderAssets(RootFolder, SortOrder)`
    : pour un `RecursiveFolder` il compose `fullPath = folder.path.isEmpty ? folder.name : '${folder.path}/${folder.name}'`, **retire le slash initial**, appelle `getAssetsForPath`, trie par `createdAt` selon
    `order`, et retourne `[]` sur erreur (`_log.severe`, jamais d'exception) ; pour le nœud racine il appelle `getAssetsForPath('/')`.
  - `mobile/lib/repositories/folder_api.repository.dart` : `FolderApiRepository(ViewsApi)` → `_api.getUniqueOriginalPaths()` et `_api.getAssetsByOriginalPath(path ?? '/')`, chacun enveloppé d'un try/catch qui
    rend `[]`.
- **Upstream — l'écran** (`mobile/lib/pages/library/folder/folder.page.dart`) :
  - `FolderPage` : `AppBar` au titre `currentFolder?.name ?? context.t.folders`, une seule action `IconButton(Icons.swap_vert)` qui inverse un `useState<SortOrder>(SortOrder.asc)` et **refetch tout l'arbre**
    via `fetchFolders(newOrder)`. `folder` est un paramètre de route (`RecursiveFolder?`) : `null` = niveau racine. `_findFolderInStructure` (récursif) re-résout le nœud par `(path, name)` après un refetch.
  - `FolderContent` : un `ListView` unique, dossiers d'abord puis assets, chaque ligne un `LargeLeadingTile` — dossier = `Icon(Icons.folder)` + nom + sous-titre `"$n folders"` en minuscules (`getSubtitle`),
    asset = `ClipRRect` 80×80 + `ThumbnailTile` + `asset.name` + sous-titre `"<taille> • <date>"` (`formatBytes` + `DateFormat.yMMMd`). Tap sur un dossier : `context.pushRoute(FolderRoute(folder: subfolder))` →
    **une page par niveau**. Tap sur un asset : `AssetViewerRoute` avec `TimelineService.fromAssets(folderAssets, TimelineOrigin.folder)` — le pager suit l'ordre de la liste, pas la timeline.
  - `FolderPath` : bandeau de chemin pleine largeur, `SingleChildScrollView` horizontal, texte `currentFolder.path` en `GoogleSansCode`, masqué (`SizedBox.shrink()`) quand `path.isEmpty || path == '/'`. États :
    `CircularProgressIndicator`, `Center(Text(...))` + `ImmichToast` en erreur (`failed_to_load_folder`, `failed_to_load_assets`), `Center(Text(context.t.empty_folder))` quand tout est vide.
  - La feature a sa page de documentation (`docs/docs/features/folder-view.md` + `img/folder-view-1.webp`, `img/folder-access.webp`, `img/folder-view-enable.webp`) : l'option d'administration « Folder view »
    est un réglage serveur, hors de cette fiche.
- **API — les deux routes, et la sémantique que l'OpenAPI ne dit pas** :
  - `/tmp/immich-openapi-main.json` : `GET /view/folder` → `operationId: getAssetsByOriginalPath`, tag `Views`, description « Retrieve assets that are children of a specific folder. », **un seul paramètre**
    `path` (query, `string`, `required: true`), 200 = `array` de `AssetResponseDto`. `GET /view/folder/unique-paths` → `operationId: getUniqueOriginalPaths`, « Retrieve a list of unique folder paths from asset
    original paths. », **aucun paramètre**, 200 = `array` de `string`. **`/api/folders` n'existe pas** : aucun chemin de l'OpenAPI publié ne contient `folders`.
  - `server/src/repositories/view-repository.ts` — ce que ces deux routes font réellement :
    - `getUniqueOriginalPaths(userId)` : `substring(originalPath, '^(.*/)[^/]*$')` **DISTINCT**, filtré `ownerId`, `visibility = Timeline`, `deletedAt is null`, colonnes de date non nulles, trié par
      `directoryPath`, puis `.replaceAll(/\/$/g, '')` → **chemins de dossier absolus, sans slash final** (ex. `/mnt/media/Photos/2024`). Un asset posé à la racine du disque produit la chaîne **vide** `''`.
    - `getAssetsByOriginalPath(userId, partialPath)` : normalise par `partialPath.replaceAll(/\/$/g, '')` puis filtre `originalPath LIKE '%<p>/%'` **ET** `NOT LIKE '%<p>/%/%'` → **les enfants DIRECTS, sans
      récursion**. Conséquence pratique : le chemin peut partir avec ou sans slash initial (le motif est enveloppé de `%`), et `path = "/"` comme `path = ""` se normalisent en `''` → les fichiers posés
      directement sous `/`.
    - Tri serveur : `ORDER BY regexp_replace(originalPath, '.*/(.+)', '\1') ASC` → **par nom de fichier** ; le tri par date est donc client (ce que fait `getFolderAssets` upstream). Aucune pagination, aucun
      `count`.
  - `MetadataSearchDto.originalPath` existe mais est **déprécié** dans l'OpenAPI publié (`"x-immich-state": "Deprecated"`, déprécié en `v3.2.0`) — c'est ce qui invalide l'approche C.
- **iOS — les pièces déjà en place, et celle qui manque** :
  - Transport : `protocol ImmichClient: AnyObject, Sendable` (`Sources/Core/Protocols/ImmichClient.swift:10`) regroupe déjà des GET à tableau nu — `func getAssetsByCity() async throws -> [AssetResponseDto]`
    (`:62`) — et `Sources/Core/Constants.swift:18-36` déclare les `SubPath` (`search`, `tags`, `duplicates`, `stacks`, `libraries`, `apiKeys`…) mais **aucun `/view`**.
  - Implémentation : `Sources/Services/ImmichAPIClient.swift:684` — `sendAuthed<T: Decodable>(_ method: HTTPMethod, path: String, query: [URLQueryItem] = [], body: AnyEncodable? = nil)` ; le patron d'un GET à
    query est `getTimeBuckets` (`:111-126`), celui d'un GET à tableau nu est `getAssetsByCity()` (`:187-189`). Les query items passent par `URLComponents` : un chemin de dossier contenant espaces ou `#` est
    encodé sans traitement particulier.
  - Données : `AssetResponseDto` (`Sources/Core/Types/DTOs.swift:95-129`) porte tout ce qu'il faut — `originalPath` (`:106`), `originalFileName` (`:107`), `fileCreatedAt` (`:109`), `exifInfo` optionnel
    (`:123`). La conversion vers la cellule de grille existe et est déjà utilisée par cinq écrans : `init(from dto: AssetResponseDto)` (`Sources/Core/Types/AssetReactItem.swift:173`).
  - Grille : convention unique du dépôt = `LazyVGrid` 3 colonnes `GridItem(.flexible(), spacing: PVSpacing.s2)` de `AssetThumbnailCell` — `Sources/Features/Search/SearchView.swift:26` et `:222`, idem
    `MapView.swift:197`, `PeopleView.swift:211`, `AlbumsView.swift:96`, `TimelineView.swift:366`, `DuplicatesView.swift:98`, `OfflineAssetsView.swift:172`. `AssetThumbnailCell`
    (`Sources/Features/Timeline/AssetThumbnailCell.swift:14-34`) prend `asset: AssetReactItem`, `baseURL: URL`, `token: String?`, puis des closures optionnelles.
  - Viewer : `SearchView.swift:83-88` présente `PhotoViewerItem` via un modificateur (`item:`, `baseURL:`, `token:`, `onDataChanged:`) ; `openViewer(for:)` (`:129-132`) construit `PhotoViewerItem(assets: vm.results, index: idx)`
    — l'index vient de la liste affichée, exactement la sémantique `TimelineOrigin.folder` de l'upstream.
  - Navigation : le hub « Me » est `ProfileView`, qui **porte le `NavigationStack`** (`Sources/Features/Profile/ProfileView.swift:24`) et pousse ses écrans depuis la section `Section { … } header: { Text("Management") }`
    (`:55-115`) — dont `OfflineAssetsView(vm: offline)` (`:108`), `.accessibilityIdentifier("offlineStorageRow")` (`:110`). `Sources/Features/Offline/OfflineAssetsView.swift` ne déclare aucun `NavigationStack`
    : c'est la contrainte structurelle à respecter. Précédent de push **par valeur** depuis un écran poussé : `PeopleView.swift:43` (`.navigationDestination(for: PersonResponseDto.self)`).
  - Injection : `Sources/DependencyContainer.swift` fabrique les ViewModels (`makeOfflineDownloadViewModel()` `:212`, dont le doc-comment énonce la règle « un VM partagé, pas un second ») ;
    `Sources/RootView.swift` matérialise chaque VM en `@State` (`_offline = State(initialValue: container.makeOfflineDownloadViewModel())`, `:133`), passe la liste au `ProfileView(...)` du `.sheet(isPresented: $showProfile)`
    (`:233-234`), et `.environment(container.offlineIndex)` est posé sur le **même** `body` (`:173`, corps de `:138` à `:262`) — donc les cellules de grille de ce sheet héritent de l'index hors-ligne
    (`AssetThumbnailCell.swift:22` lit `@Environment(OfflineAssetIndex.self)` en optionnel) et affichent le badge cloud sans câblage supplémentaire.
  - Outils : tokens `PVSpacing.s0…s48`, `PVRadius.none…full` (`Sources/DesignSystem/Tokens/Spacing+PhotoVault.swift:13-35`) ; couleurs `Color.bgPrimary`, `bgSecondary`, `textPrimaryPV`, `textSecondaryPV`
    (`Color+PhotoVault.swift:37-43`) et l'accent `Color.immichPrimary` — les alias `accentInfo`, `brandIndigoMuted`, `statusSuccess` sont explicitement marqués `Deprecated` dans ce fichier et ne doivent pas
    être utilisés ; composants `InlineErrorBadge.swift`, `PVButtonStyle.swift` (`Sources/DesignSystem/Components/`) ; parsing ISO `LongDateFormatter.parse(isoTimestamp:)`
    (`Sources/Core/Utilities/LongDateFormatter.swift:56`).
  - Tests : `Tests/Mocks/MockImmichClient.swift` est un type à état, une paire « réponse + erreur » par feature et un compteur — `var citiesResponse: [AssetResponseDto]?` / `var citiesError: Error?`
    (`:109-110`), `func getAssetsByCity()` (`:443-447`) qui fait `bump()`, jette `globalError ?? citiesError`, puis rend `citiesResponse ?? []`.
- **Ce qui rend la fiche nécessaire** : aucun des cinq écrans de grille existants ne lit un dossier (timeline, `search/metadata`, album), et `ImmichAPI` ne connaît pas `/view`. Un utilisateur dont la
  photothèque est une bibliothèque externe n'a donc aucun moyen de retrouver un fichier par son arborescence, alors que le serveur l'expose en deux routes qui n'exigent aucun droit particulier.

**Approche retenue** : A — deux méthodes neuves sur `ImmichClient` (`getFolderAssets(path:)`, `getUniqueFolderPaths()`) derrière un `SubPath` neuf `ImmichAPI.view`, un `FolderViewModel` unique qui construit
l'arbre une fois et **cache les assets par chemin** (`assetsByPath: [String: [AssetReactItem]]`), et une `FolderView` stateless poussée par valeur depuis la section Management de `ProfileView` — un niveau par
push, `navigationDestination(for: FolderNode.self)`.
- **B (rejetée)** : un seul écran qui déplie l'arbre entier (`OutlineGroup`/`DisclosureGroup` alimenté par `getUniqueFolderPaths()`) et n'appelle le serveur qu'au tap sur le nœud courant → rejetée sur deux
  faits du dépôt. (1) L'arbre entier est matérialisé avant le premier affichage (un nœud par dossier distinct renvoyé par `unique-paths`, comme `getFolderStructure` le fait déjà), et le cas normal d'une
  bibliothèque externe est un chemin profond (`/mnt/media/PhotosLibrary.photoslibrary/originals/0`) : la `List` porterait des dizaines de milliers de lignes, contre une poignée de dossiers dans l'approche A.
  (2) L'upstream a explicitement choisi l'inverse (`context.pushRoute(FolderRoute(folder: subfolder))`, une page par niveau) et le `NavigationStack` de `ProfileView` (`:24`) fournit gratuitement le retour
  niveau par niveau ; rien ne justifie de payer ce remplacement.
- **C (rejetée)** : abandonner `/view/folder` et lire les assets d'un dossier par `POST /api/search/metadata` avec `originalPath`, pour bénéficier de la pagination → rejetée pour trois raisons mesurables. (1)
  `MetadataSearchDto.originalPath` est **déprécié** dans l'OpenAPI publié (état `Deprecated` depuis `v3.2.0`). (2) La sémantique « enfants directs » (`LIKE '%<p>/%' AND NOT LIKE '%<p>/%/%'`) n'est pas
  exprimable par ce filtre, qui vise le chemin **de l'asset** : on afficherait les descendants récursifs. (3) `/view/folder` ne pagine pas — la pagination serait un coût (compteur de pages, curseur `nextPage`,
  bouton « charger plus », états de fusion) payé pour un besoin inexistant.

## Étapes

1. **Le chemin d'API** — EDIT `Sources/Core/Constants.swift` : ajouter dans `enum ImmichAPI`, à côté de `static let search = SubPath(root: "/search")` (l. `22`), `static let view = SubPath(root: "/view") // gap G11 (folder view)`.
   Les deux routes du contrat deviennent `ImmichAPI.view.path("/folder")` et `ImmichAPI.view.path("/folder/unique-paths")`.
2. **Le contrat de transport** — EDIT `Sources/Core/Protocols/ImmichClient.swift` : après `func getAssetsByCity() async throws -> [AssetResponseDto]` (l. `62`), ajouter deux signatures documentées par la
   sémantique serveur relevée plus haut : `/// GET /api/view/folder?path= — direct children of the folder only, no recursion. The path may carry or omit its leading slash; trailing slashes are ignored by the server. Archived assets are excluded (the server filters on visibility = timeline).`
   puis `func getFolderAssets(path: String) async throws -> [AssetResponseDto]`, et `/// GET /api/view/folder/unique-paths — every distinct directory holding a timeline asset: absolute, without a trailing slash, "" for assets sitting at the filesystem root.`
   puis `func getUniqueFolderPaths() async throws -> [String]`.
3. **L'implémentation HTTP** — EDIT `Sources/Services/ImmichAPIClient.swift` : après `getAssetsByCity()` (l. `187-189`), `func getFolderAssets(path: String) async throws -> [AssetResponseDto] { try await sendAuthed(.GET, path: ImmichAPI.view.path("/folder"), query: [URLQueryItem(name: "path", value: path)]) }`
   et `func getUniqueFolderPaths() async throws -> [String] { try await sendAuthed(.GET, path: ImmichAPI.view.path("/folder/unique-paths")) }`. Le paramètre passe par `[URLQueryItem]` comme `getTimeBuckets`
   (`:111-126`).
4. **Le doublon de test** — EDIT `Tests/Mocks/MockImmichClient.swift` : ajouter, sur le modèle de la paire `citiesResponse`/`citiesError` (`:109-110`), `var folderPathsResponse: [String]?`, `var folderPathsError: Error?`,
   `var folderAssetsResponse: [AssetResponseDto]?`, `var folderAssetsError: Error?` et `private(set) var requestedFolderPaths: [String] = []`. Les deux méthodes font `bump()`, jettent `globalError ?? <…>Error`,
   et `getFolderAssets` **enregistre `path` dans `requestedFolderPaths`** avant de rendre `folderAssetsResponse ?? []` : c'est le seul moyen de prouver le chemin réellement envoyé au serveur.
5. **L'arbre et le ViewModel** — NEW `Sources/Features/Folders/FolderViewModel.swift` : `import Foundation`, `import Observation`.
   - `struct FolderNode: Hashable, Identifiable` avec `let path: String` (chemin absolu du dossier, `""` pour le niveau supérieur), `let name: String`, `let children: [FolderNode]`, `var id: String { path }`,
     `var hasChildren: Bool`. Le type vit dans ce fichier, comme `ExplorePlace` vit dans `SearchViewModel.swift`.
   - `enum FolderSortOrder: String { case ascending, descending }`.
   - `@MainActor @Observable final class FolderViewModel` avec `private let client: any ImmichClient`, `init(client: any ImmichClient)`, et l'état : `private(set) var root: FolderNode?`, `private(set) var hasRootLevelAssets = false`,
     `private(set) var assetsByPath: [String: [AssetReactItem]]`, `private(set) var loadingPaths: Set<String>`, `private(set) var errorByPath: [String: String]`, `private(set) var isBuildingTree = false`,
     `private(set) var treeError: String?`, `private(set) var folderOrder: FolderSortOrder = .ascending`, `private(set) var assetOrder: FolderSortOrder = .descending`.
   - `static func buildTree(from paths: [String]) -> (root: FolderNode, hasRootLevelAssets: Bool)` : pur, sans réseau, donc testable directement — signale la chaîne vide comme `hasRootLevelAssets` au lieu d'en
     faire un nœud, découpe chaque chemin sur `"/"` en segments non vides, crée un nœud par segment intermédiaire (`childPath = parentPath.isEmpty ? "/\(name)" : "\(parentPath)/\(name)"`), et trie chaque niveau
     par `localizedStandardCompare`. Même algorithme que `FolderService.getFolderStructure`, sans la sentinelle `'_root_'` (la récursion rend la clé synthétique inutile).
   - `func loadTree() async` : sort immédiat si `root != nil` (l'arborescence ne bouge qu'après un import côté serveur, et l'écran se rafraîchit par dossier) ; `isBuildingTree = true`, `let paths = try await client.getUniqueFolderPaths()`,
     applique `buildTree(from:)`, puis `treeError = nil`, `isBuildingTree = false` ; sur `catch` : `treeError = error.localizedDescription` (convention du dépôt : `SearchViewModel.swift:207`,
     `TagsViewModel.swift:25`).
   - `func loadAssets(for path: String, force: Bool = false) async` : retour immédiat si `assetsByPath[path] != nil && !force` — c'est le cache par chemin du store web (`assets[path] ??= …`,
     `folders.svelte.ts`) et celui des providers par dossier de Flutter ; `loadingPaths.insert(path)`, `let dtos = try await client.getFolderAssets(path:)`, tri par `LongDateFormatter.parse(isoTimestamp: $0.fileCreatedAt)`
     selon `assetOrder` (le serveur trie par nom de fichier, l'ordre par date est client — comme `getFolderAssets` upstream), mappe en `AssetReactItem(from:)`, écrit `assetsByPath[path]`,
     `loadingPaths.remove(path)`, `errorByPath[path] = nil` ; sur `catch`, `errorByPath[path] = error.localizedDescription` et `loadingPaths.remove(path)`.
   - Lecture pour la vue : `func children(of node: FolderNode?) -> [FolderNode]` (niveau courant, trié selon `folderOrder`), `func sortedAssets(for path: String) -> [AssetReactItem]`, `func isLoadingAssets(_ path: String) -> Bool`,
     `func errorMessage(_ path: String) -> String?`.
   - Actions : `func toggleAssetOrder()` (inverse `assetOrder` et re-trie **en mémoire** chaque entrée de `assetsByPath` — l'endpoint ne paginant pas, un refetch ne peut rien apporter de neuf), `func refresh(path: String) async`
     (`await loadAssets(for: path, force: true)`), `func retryTree() async` (`root = nil`, `hasRootLevelAssets = false`, puis `loadTree()`).
   - Le chemin envoyé au serveur est `node.path` **tel quel**, slash initial conservé : la normalisation serveur ne retire que les slashes **finaux** et le motif est enveloppé de `%` — inutile de reproduire le
     `fullPath.substring(1)` de `FolderService`.
6. **L'écran, un niveau** — NEW `Sources/Features/Folders/FolderView.swift` : `import SwiftUI`.
   - `struct FolderView: View` avec `@Bindable var vm: FolderViewModel`, `let node: FolderNode?` (`nil` = niveau supérieur), `@Environment(AuthViewModel.self) private var auth`, `@State private var viewerItem: PhotoViewerItem?`,
     et `private let columns = Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s2), count: 3)` (identique à `SearchView.swift:26`).
   - Corps : `ScrollView { LazyVStack(alignment: .leading, spacing: PVSpacing.s16) { pathBar; folderRows; assetGrid }.padding(.horizontal, PVSpacing.s16) }` sur `.background(Color.bgPrimary)`, avec
     `.navigationTitle(node?.name ?? String(localized: "Folders"))`, `.navigationBarTitleDisplayMode(.inline)`, `.toolbar { sortButton }`, `.task(id: node?.path ?? "/") { await load() }`, `.refreshable { await vm.refresh(path: currentPath) }`,
     `.navigationDestination(for: FolderNode.self) { FolderView(vm: vm, node: $0) }`, et le modificateur `PhotoViewerItem` de `SearchView.swift:83-88` (`baseURL: auth.baseURL ?? URL(string: "https://example.com")!`,
     `token: auth.accessToken`, `onDataChanged:` → `Task { await vm.refresh(path: currentPath) }`). **Aucun `NavigationStack`** : `ProfileView` en porte un (`:24`), exactement comme `OfflineAssetsView`.
   - `private var currentPath: String { node?.path ?? (vm.hasRootLevelAssets ? "/" : "") }` et `private func load() async` : `await vm.loadTree()` puis, si `currentPath` n'est pas vide, `await vm.loadAssets(for: currentPath)`.
     Le niveau supérieur n'appelle le serveur que si l'arbre a signalé des assets posés à la racine du disque (`hasRootLevelAssets`), ce que `getUniqueOriginalPaths` exprime par la chaîne vide.
   - `pathBar` : `EmptyView` quand `node == nil` ou `node!.path.isEmpty` ; sinon `ScrollView(.horizontal, showsIndicators: false) { Text(node!.path).font(.system(.footnote, design: .monospaced)).foregroundStyle(Color.textSecondaryPV) }`
     — le `FolderPath` de l'upstream, avec la police monospace du système au lieu de `GoogleSansCode`.
   - `folderRows` : `ForEach(vm.children(of: node)) { child in NavigationLink(value: child) { HStack(spacing: PVSpacing.s12) { Image(systemName: "folder").font(.system(size: 28)) .foregroundStyle(Color.immichPrimary); VStack(alignment: .leading, spacing: PVSpacing.s2) { Text(child.name).font(.headline).lineLimit(1); if child.hasChildren { Text(child.children.count == 1 ? String(localized: "1 folder") : String(localized: "\(child.children.count) folders")).font(.subheadline).foregroundStyle(Color.textSecondaryPV) } } } } .accessibilityIdentifier("folderRow_\(child.path)") }`
     — le `LargeLeadingTile` de l'upstream en SwiftUI natif, sous-titre `"N folders"` compris.
   - `assetGrid` : `LazyVGrid(columns: columns, spacing: PVSpacing.s2) { ForEach(vm.sortedAssets(for: currentPath)) { item in AssetThumbnailCell(asset: item, baseURL: auth.baseURL ?? URL(string: "https://example.com")!, token: auth.accessToken, onTap: { openViewer(for: item) }) } }`,
     et `openViewer(for:)` qui reprend `SearchView.swift:129-132` en indexant dans `vm.sortedAssets(for: currentPath)` pour que le pager suive l'ordre affiché.
   - États, dans cet ordre : `vm.isBuildingTree && vm.root == nil` → `ProgressView()` ; sinon `vm.treeError` → `InlineErrorBadge` + bouton `Retry` (`vm.retryTree()`) ; sinon `vm.isLoadingAssets(currentPath) && vm.sortedAssets(for: currentPath).isEmpty`
     → `ProgressView()` ; sinon `vm.errorMessage(currentPath)` → `InlineErrorBadge` + bouton `Retry` (`vm.refresh(path: currentPath)`) ; sinon enfants vides **et** assets vides → `Text("Empty folder")`
     (l'`empty_folder` de l'upstream). Identifiants : `foldersEmptyState`, `foldersRetryButton`.
   - `sortButton` : bouton de toolbar, image `arrow.up.arrow.down`, `.accessibilityIdentifier("folderSortButton")`, `.accessibilityLabel` valant `"Sort: Newest first"` ou `"Sort: Oldest first"` selon
     `vm.assetOrder`, action `vm.toggleAssetOrder()`.
7. **L'injection** — EDIT `Sources/DependencyContainer.swift` : après `makeOfflineDownloadViewModel()` (l. `212-219`), ajouter `/// Folder view (gap G11). Read-only: the tree and the per-folder asset cache live in the VM and nothing is persisted, so no store is shared here.`
   puis `func makeFolderViewModel() -> FolderViewModel { FolderViewModel(client: client as any ImmichClient) }` — même forme que `makeDuplicatesViewModel()` (`:203`).
8. **Le câblage racine** — EDIT `Sources/RootView.swift` : déclarer `@State private var folders: FolderViewModel` dans `AuthenticatedRoot` à côté de `@State private var offline: OfflineDownloadViewModel`,
   l'initialiser dans `init(container:)` par `_folders = State(initialValue: container.makeFolderViewModel())`, et l'ajouter à l'appel `ProfileView(...)` du `.sheet(isPresented: $showProfile)` (`:233-234`) sous
   la forme `folders: folders`.
9. **Le point d'entrée** — EDIT `Sources/Features/Profile/ProfileView.swift` : ajouter `@State var folders: FolderViewModel` aux propriétés stockées (après `@State var offline: OfflineDownloadViewModel`), puis
   dans la section `Management`, **immédiatement après** la ligne `Offline Storage` (`:108-111`), une ligne `NavigationLink { FolderView(vm: folders, node: nil) } label: { Label("Folders", systemImage: "folder") }`
   portant `.accessibilityIdentifier("foldersRow")`. L'ancrage après `Offline Storage` est délibéré : les deux lignes parlent de la même photothèque vue de deux côtés — la première liste ce que l'appareil garde
   en cache, la seconde ce que le serveur voit sur son disque ; les séparer de deux dizaines de lignes éloignerait la seule paire navigable par arborescence.
10. **Les tests du ViewModel** — NEW `Tests/FolderViewModelTests.swift` : `import XCTest`, `@testable import ImmichSwiftUI`, une suite `final class FolderViewModelTests: XCTestCase`, un `MockImmichClient` par
    test. Cas, tous `@MainActor` : `test_buildTree_groupsPathsByLevel` (deux chemins partageant un parent → un nœud parent, deux enfants, noms = derniers segments) ; `test_buildTree_flagsRootLevelAssets` (une
    entrée vide → `hasRootLevelAssets == true`, aucun nœud fantôme) ; `test_buildTree_sortsSiblingsByName` ; `test_loadAssets_sendsTheFolderPathAsIs` (assertion sur `requestedFolderPaths == ["/mnt/media/Photos"]`
    — c'est le contrat de fil, le seul fait qui décide si le serveur renvoie le bon niveau) ; `test_loadAssets_cachesPerPath` (deux appels, un seul bump de `requestCount`) ; `test_refresh_forcesARefetch`
    (`force: true` → deux bumps) ; `test_toggleAssetOrder_reordersInMemoryWithoutRefetching` (ordre inversé, `requestCount` inchangé) ; `test_assetsError_isScopedToItsPath` (erreur sur un chemin →
    `errorMessage(path)` non nil, et un second chemin chargé sans erreur reste lisible) ; `test_loadTree_surfacesError` (`folderPathsError` → `treeError` non nil et `root` nil).
11. **Le catalogue de chaînes** — aucune écriture manuelle dans `Resources/Localizable.xcstrings` : la clé est la chaîne anglaise et l'extraction est faite par Xcode au build (décision i18n du dépôt). Les clés
    neuves des étapes 6 et 9 sont : `Folders`, `1 folder`, `%lld folders`, `Empty folder`, `Retry`, `Sort: Newest first`, `Sort: Oldest first`.
12. `xcodegen generate` (deux fichiers source et un fichier de test sont ajoutés : sans régénération du projet ils ne sont pas compilés), puis la suite complète `-only-testing:ImmichSwiftUITests`.

## Incertitudes à lever à l'implémentation

- **L'appel serveur pour les assets posés à la racine du disque.** `getUniqueOriginalPaths` renvoie `''` dans ce cas et `getAssetsByOriginalPath('')` se normalise en `LIKE '%/%' AND NOT LIKE '%/%/%'`. La fiche
  n'appelle donc le serveur au niveau supérieur que si l'arbre a signalé un tel dossier. Trancher avec un serveur réel : `curl -s -H "x-api-key: $KEY" "$IMMICH/api/view/folder?path=" | jq length` — si le compte
  est toujours 0 sur une bibliothèque externe (cas normal, les fichiers sont sous `/mnt/…`), la garde devient inutile mais reste inoffensive.
- **Le tri appliqué aux noms de dossiers.** L'upstream applique **le même** `SortOrder` aux deux listes (`fetchFolders(order)` et `getFolderAssets(order)`, `folder.page.dart`), donc `desc` y donne des dossiers
  Z→A. La fiche les sépare : noms A→Z (`localizedStandardCompare`, comme Files.app et comme aucun écran du dépôt ne fait l'inverse), assets récents d'abord (convention de toutes les grilles du dépôt). Si la
  parité littérale est préférée, un second état `folderOrder` piloté par le même bouton suffit — arbitrage de revue, qu'aucune commande ne tranche.
- **Le libellé et la position de la ligne du hub.** `Folders` reprend `context.t.folders` de l'upstream et la route `/folders` du web ; si le catalogue a déjà une clé proche, la réutiliser plutôt que d'en créer
  une. Vérifier par : `python3 -c "import json;d=json.load(open('Resources/Localizable.xcstrings'));print([k for k in d['strings'] if 'older' in k])"`.
- **Les icônes.** `folder` pour la ligne du hub et les nœuds dossiers est le seul choix cohérent avec le `Icons.folder` de l'upstream ; `arrow.up.arrow.down` traduit le `Icons.swap_vert` upstream. Aucune
  collision avec les icônes de la section Management (`trash`, `icloud.and.arrow.up`, `bell.badge`, `rectangle.on.rectangle.angled`, `person.2`, `tag`, `square.stack.3d.down.right`, `person.badge.plus`,
  `arrow.down.circle`). Vérifier par revue de la maquette.
- **Le volume d'un dossier très peuplé.** `/view/folder` ne pagine pas : un dossier de plusieurs milliers d'assets revient en une réponse. `LazyVGrid` ne construit que les cellules visibles, donc l'affichage
  tient, mais le décodage de la réponse entière ne se découpe pas. Mesurer : `curl -s -H "x-api-key: $KEY" "$IMMICH/api/view/folder?path=/mnt/media/Photos/2024" | jq length` — si le compte dépasse quelques
  milliers, la seule issue sans changer de route est un plafond d'affichage avec un bouton « show more » local, à décider en revue et non dans cette fiche.
