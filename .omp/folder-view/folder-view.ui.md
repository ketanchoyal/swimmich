# Task: folder-view — UI Brief

> Compagnon de `.omp/folder-view/folder-view.specs.md` (écrit le 2026-09-15). Ce document ne décrit que la
> **surface** : placement, hiérarchie de vues, gestes, états, tokens. La sémantique serveur (enfants
> directs, filtre `visibility = Timeline`) y est rappelée là où elle change une décision d'affichage, pas
> redémontrée.

## Design Philosophy

L'écran répond à **« où est ce fichier sur le disque du serveur ? »** — une question que ni la timeline ni
la recherche ne savent traiter quand la photothèque est une bibliothèque externe. Trois partis pris :

- **Le chemin est l'identité de l'écran.** Un dossier s'annonce par son nom en titre, et par son chemin
  absolu juste en dessous : seule information qui distingue `/mnt/media/Photos/2024` de `/mnt/backup/Photos/2024`.
- **Un niveau à la fois.** Le serveur ne renvoie que les **enfants directs** ; l'UI liste les sous-dossiers,
  elle ne les déplie pas — liste plate par niveau, jamais d'`OutlineGroup`.
- **Consultation, pas gestion.** Aucun bouton ne déplace, renomme ou crée un dossier (aucune route de
  mutation sous `/view`). La grille est celle de la timeline, avec ses gestes habituels, rien de plus.

Le vocabulaire visuel reste celui du dépôt : tokens du DesignSystem, monospace système pour les chemins,
verre absent (écran de contenu poussé, comme `OfflineAssetsView`).

## Placement dans la navigation

- Poussée depuis **`ProfileView`** (hub « Me »), section `Management`, **immédiatement après la ligne
  `Offline Storage`** (`Sources/Features/Profile/ProfileView.swift:108-111`). Justification : les deux
  lignes parlent de la même photothèque vue de deux côtés — la première liste ce que l'appareil garde en
  cache, la seconde ce que le serveur voit sur son disque.
- `FolderView` **ne déclare aucun `NavigationStack`** : `ProfileView` en porte un (`:24`), exactement comme
  `OfflineAssetsView`. Un second stack produirait deux barres de navigation superposées.
- **Un niveau = un push.** `NavigationLink(value: child)` + `.navigationDestination(for: FolderNode.self)`
  déclaré dans `FolderView` : la vue se re-pousse elle-même, le retour natif est gratuit et le titre du
  dossier parent apparaît pendant le geste. Précédent de push par valeur depuis un écran poussé :
  `PeopleView.swift:43`.
- Pas de rôle d'onglet, pas de feuille. La ligne du hub porte `.accessibilityIdentifier("foldersRow")`.
- **Hors périmètre** : le dossier verrouillé (écart G12) a sa propre route et son propre flux de PIN.

## Layout

```
FolderView(vm:node:)                        (poussée par ProfileView, un push par niveau)
└── ScrollView
    └── LazyVStack(alignment: .leading, spacing: PVSpacing.s16)
        ├── pathBar                          → ScrollView(.horizontal) + Text(node.path) monospace
        │                                     (absent au niveau supérieur : node == nil)
        ├── folderRows                       → ForEach(vm.children(of: node))
        │   └── NavigationLink(value: child) → HStack(spacing: PVSpacing.s12)
        │           ├── Image(systemName: "folder")         .font(.pvTitleXL/.immichPrimary)
        │           ├── Text(child.name)                    .font(.pvHeadline)
        │           └── Text("N folders")                   .font(.pvSubhead)
        └── assetGrid                        → LazyVGrid(3 colonnes, spacing: PVSpacing.s2)
            └── ForEach(vm.sortedAssets(for: currentPath))
                └── AssetThumbnailCell(asset:baseURL:token:onTap:)

États (dans cet ordre, exclusifs) :
    isBuildingTree && root == nil   → ProgressView()          (premier chargement de l'arbre)
    treeError != nil                → InlineErrorBadge + « Retry »
    isLoadingAssets && vide         → ProgressView()
    errorMessage(currentPath)       → InlineErrorBadge + « Retry »
    aucun dossier ET aucun asset    → ContentUnavailableView("Empty folder", …)
```

- **Titre** : `.navigationTitle(node?.name ?? String(localized: "Folders"))` +
  `.navigationBarTitleDisplayMode(.inline)` — le nom du dossier courant, jamais son chemin (le chemin vit
  dans le bandeau, où il ne casse pas la barre). Un seul `ToolbarItem(placement: .topBarTrailing)` :
  le bouton de tri (`arrow.up.arrow.down`, `.accessibilityIdentifier("folderSortButton")`).
- **Fond** : `Color.bgPrimary`, contenu en `.padding(.horizontal, PVSpacing.s16)`.
- **Bandeau de chemin** : `node == nil` ou `node.path.isEmpty` → `EmptyView` ; sinon défilement horizontal,
  `Text(node.path)` en `.font(.system(.footnote, design: .monospaced))`, `.foregroundStyle(Color.textSecondaryPV)`,
  `.lineLimit(1)`, `.accessibilityIdentifier("folderPathBar")` — le `FolderPath` de l'upstream, dont la
  `GoogleSansCode` devient la monospace système.
- **Rafraîchissement** : `.task(id: node?.path ?? "/") { await load() }` (le niveau se charge à l'arrivée,
  y compris au retour arrière) et `.refreshable { await vm.refresh(path: currentPath) }` — le
  pull-to-refresh ne rafraîchit **que le dossier courant**, l'arbre n'est pas reconstruit.

## Composants

Réutiliser, ne pas créer :

| Besoin | Composant existant |
|---|---|
| Tuile d'asset de la grille | `AssetThumbnailCell` (`Sources/Features/Timeline/AssetThumbnailCell.swift`) — porte déjà son menu contextuel par défaut et le badge cloud |
| Ligne de dossier | motif local `HStack` dans la vue (l'upstream a un `LargeLeadingTile` ; le dépôt n'a pas d'équivalent, et la ligne est trop simple pour en mériter un) |
| Erreur non bloquante | `InlineErrorBadge` |
| État vide | `ContentUnavailableView("Empty folder", systemImage: "folder", description: Text("This folder holds no sub-folder and no asset."))` |
| Chargement en attente | `ProgressView()` centré (`PVSkeletonGrid` est réservé aux grilles de premier écran) |

```swift
/// Contrat local à l'écran — la ligne de dossier (déclarée dans FolderView.swift).
private struct FolderRow: View {
    let node: FolderNode

    var body: some View {
        HStack(spacing: PVSpacing.s12) {
            Image(systemName: "folder")
                .font(.pvTitleXL)
                .foregroundStyle(Color.immichPrimary)
            VStack(alignment: .leading, spacing: PVSpacing.s2) {
                Text(node.name).font(.pvHeadline).foregroundStyle(Color.textPrimaryPV).lineLimit(1)
                // Enfants DÉJÀ connus de l'arbre : unique-paths renvoie l'annuaire complet,
                // le compte ne se remplit jamais après coup.
                if node.hasChildren {
                    Text(node.children.count == 1 ? String(localized: "1 folder")
                                                  : String(localized: "\(node.children.count) folders"))
                        .font(.pvSubhead)
                        .foregroundStyle(Color.textSecondaryPV)
                }
            }
        }
        .frame(minHeight: 44)                  // cible tactile
        .contentShape(Rectangle())
    }
}
```

## Interactions

| Geste | Effet |
|---|---|
| Tap sur une ligne de dossier | `NavigationLink(value: child)` → **push** du niveau suivant (`FolderView(vm: vm, node: child)`) ; le même `vm` sert les deux niveaux, le cache par chemin évite un refetch au retour |
| Tap sur une tuile d'asset | `openViewer(for:)` → `PhotoViewerItem(assets: vm.sortedAssets(for: currentPath), index: idx)` : le pager suit **l'ordre affiché**, pas la timeline (`TimelineOrigin.folder` de l'upstream) |
| Tap sur le bouton de retour | Pop natif du `NavigationStack` de `ProfileView` ; le niveau parent réaffiche son cache, sans appel réseau |
| Tap sur `folderSortButton` | `vm.toggleAssetOrder()` — inverse l'ordre des assets **en mémoire**, sans refetch (`/view/folder` ne pagine pas, un aller-retour ne peut rien apporter de neuf) |
| Pull-to-refresh | `await vm.refresh(path: currentPath)` — force le refetch **du seul dossier courant** |
| Swipe-back (bord gauche) | Pop natif ; interrompu, l'écran n'a rien à annuler (aucune écriture) |
| Tap sur `Retry` | `await vm.retryTree()` si l'erreur porte sur l'arbre (`root` remis à `nil` puis `loadTree()`), sinon `await vm.refresh(path: currentPath)` |
| Menu contextuel long-press sur une tuile | Menu par défaut d'`AssetThumbnailCell` : **rien de neuf n'est câblé ici** (multi-sélection et actions en lot = `AssetMultiSelectGrid`, hors périmètre) |

## Liquid Glass / matériaux

Pas de `glassEffect` ici : le dépôt réserve le verre aux surfaces **flottantes** (barres de recherche,
bandeaux, îlot Live Activity), jamais aux écrans de contenu poussés — `OfflineAssetsView` et `StackView`
n'en utilisent pas. `Color.separatorPV` et `Color.bgSecondary` suffisent à détacher les lignes de dossier.

## Accessibilité

- **Identifiants** (sur les éléments interactifs, **jamais** sur un conteneur qui en contient — un
  identifiant de conteneur écrase ceux de ses descendants, piège mesuré sur `languageRelaunchToast`) :
  `foldersRow` (hub), `folderPathBar`, `folderRow_<path>`, `folderAsset_<assetId>`, `folderSortButton`,
  `foldersRetryButton`, `foldersEmptyState`.
- **VoiceOver** : la ligne de dossier est un seul élément (`accessibilityElement(children: .combine)`),
  label produit par la vue (`"2024, 12 folders"`) ; la tuile conserve les labels d'`AssetThumbnailCell`,
  **badge cloud compris** (« On this device » / « Not downloaded »).
- **Dynamic Type** : `minHeight: 44` seulement, aucun `frame(height:)` figé. Le chemin monospace tronque
  (`.lineLimit(1)`) sans repousser la mise en page, mais reste **lu intégralement** par VoiceOver.
- **Cibles** ≥ 44 pt : lignes pleine largeur via `.contentShape(Rectangle())`, bouton de tri en toolbar.
  **Contraste** : chemin en `Color.textSecondaryPV` sur `bgPrimary` — jamais `textTertiaryPV`.
- **Chaînes** = clés anglaises (`String(localized:)`), jamais un littéral français : `Folders`,
  `1 folder`, `%lld folders`, `Empty folder`, `Retry`, `Sort: Newest first`, `Sort: Oldest first`.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Push vers un sous-dossier | animation système de `NavigationStack` (aucune ajoutée) | remplacée par un fondu |
| Apparition de la grille après chargement | `.transition(.opacity)` | fondu conservé |
| Bascule d'ordre des assets | réordonnancement de `LazyVGrid`, sans `matchedGeometryEffect` (les tuiles se replacent, elles ne volent pas) | identique |
| Icône du bouton de tri | `.contentTransition(.symbolEffect(.replace))` | remplacement instantané |

Aucun morphing, aucun `glassEffectID` : l'écran ne se transforme pas, il descend d'un niveau.

## Fichiers touchés

- NEW `Sources/Features/Folders/FolderView.swift` — l'écran, `FolderRow` privé, barre de chemin, grille,
  cinq états.
- NEW `Sources/Features/Folders/FolderViewModel.swift` — `FolderNode`, `FolderSortOrder`, arbre + cache par
  chemin. NEW `Tests/FolderViewModelTests.swift` — 9 cas, dont `test_loadAssets_sendsTheFolderPathAsIs`.
- EDIT `Sources/Core/Constants.swift` (`ImmichAPI.view`), `Sources/Core/Protocols/ImmichClient.swift`
  (`getFolderAssets(path:)`, `getUniqueFolderPaths()`), `Sources/Services/ImmichAPIClient.swift` (les deux
  GET), `Tests/Mocks/MockImmichClient.swift` (`folderPathsResponse/Error`, `folderAssetsResponse/Error`,
  `requestedFolderPaths`).
- EDIT `Sources/DependencyContainer.swift` (`makeFolderViewModel()`), `Sources/RootView.swift`
  (`@State private var folders` + passage à `ProfileView`), `Sources/Features/Profile/ProfileView.swift`
  (`@State var folders` + ligne `foldersRow` dans Management).

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Déclarer un `NavigationStack` dans `FolderView`** : `ProfileView` en porte un (`:24`) — piège qui a
   produit deux barres de navigation sur `LanguageSettingsView`.
2. **Faire croire à une récursion.** Le filtre serveur est `LIKE '%<path>/%' AND NOT LIKE '%<path>/%/%'` :
   seuls les enfants **directs** reviennent. Empiler les descendants, ou compter autrement qu'à partir de
   la réponse du dossier, promettrait un niveau que la route ne rend pas.
3. **Laisser croire que les assets archivés ou verrouillés sont perdus.** Le filtre est `visibility = Timeline`
   et **aucun paramètre ne l'ouvre**. L'état vide doit donc dire « Empty folder » et non « No assets » :
   le dossier peut contenir des fichiers que le serveur ne montre pas. Nommer archive ou dossier verrouillé
   ici serait une promesse non tenable (Trash, écran Locked Folder / G12).
4. **Poser un `accessibilityIdentifier` sur le `LazyVGrid` ou le `LazyVStack`** : il écraserait les
   `folderRow_<path>` et `folderAsset_<id>` de ses descendants (piège `languageRelaunchToast`).
5. **Envoyer `node.path` amputé de son slash initial** par symétrie avec `FolderService.getFolderAssets`
   (`fullPath.substring(1)`) : la normalisation serveur ne retire que les slashes **finaux** et le motif
   est enveloppé de `%`. Le chemin part **tel quel**.
6. **Refetcher inutilement** : `.refreshable` et `Retry` ne touchent que le dossier courant (`loadTree()`
   sort si `root != nil`), et `toggleAssetOrder()` réordonne **en mémoire** — `/view/folder` ne pagine pas
   et le serveur trie par nom de fichier, donc l'ordre par date est client et un aller-retour n'apporte rien.
7. **Appeler le niveau supérieur avec un chemin vide sans nécessité** : `""` et `"/"` se normalisent en
   `''`, donc demandent les fichiers posés à la racine du **disque**. Seulement si `hasRootLevelAssets`.
8. **Traiter la réponse comme paginée** : aucun `count`, aucun curseur — pas de « Load more », pas de
   spinner de fin de liste.
9. **Recalculer une mise en forme de date ou de bytes dans la vue** : la grille reçoit des `AssetReactItem`
   déjà converties, l'écran n'affiche ni taille ni date (elles appartiennent au viewer).
