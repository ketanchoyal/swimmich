# Task: recently-taken — UI Brief

> Compagnon de `.omp/recently-taken/recently-taken.specs.md` (2026-09-15). Ce document ne décrit que la **surface** : placement, hiérarchie de vues, gestes, états, tokens. Une seule vue, deux modes — `RecentAssetsMode.taken` (« Recently Taken ») et `.added` (« Recently Added »).

## Design Philosophy

L'écran répond à une question de consultation : **« qu'est-ce qui est arrivé récemment dans ma photothèque ? »**, selon deux axes que l'utilisateur ne doit jamais confondre — la **date de prise de vue** (`taken`) et la **date de mise en ligne sur le serveur** (`added`). Toute la surface est donc bâtie sur une seule paire d'informations par mode : un **titre** et une **icône**, portés par `RecentAssetsMode` et nulle part ailleurs. La vue ne teste jamais `mode == .taken` ; elle lit `vm.mode.title`, `vm.mode.systemImage` et `vm.mode.emptyMessage`. C'est ce qui rend impossible la divergence entre les deux écrans.

Second principe : la **lecture seule**. La spec est explicite — « les écrans sont en lecture seule, l'édition passe par l'onglet Photos ». La grille est donc une **galerie** : aucun mode sélection, aucun badge de sélection, aucune action en masse, aucun `NavigationLink`. C'est la différence structurelle assumée avec `TimelineView` : l'upstream peut offrir la sélection sur ces routes parce que son widget `Timeline` est *le* widget partagé, pas une page ; ici, dupliquer la sélection imposerait de dupliquer ses actions (favori, archive, corbeille), qui appartiennent à l'onglet Photos. Le geste long — l'entrée du mode sélection dans la timeline — est donc **inerte** ici.

Troisième principe : le défilement va **toujours vers le bas**. L'écran démarre sur le jour le plus récent et empile les jours plus anciens ; la timeline fait l'inverse (`loadOlder()` préfixe). Une seule direction, une seule sentinelle de chargement, en pied de grille.

## Placement dans la navigation

- **Section neuve** du hub « Me » (`Sources/Features/Profile/ProfileView.swift`), insérée **avant** la `Section` à en-tête « Management » (`:55-115`) : `Section { … } header: { Text("Recently") }` contenant deux `NavigationLink` — `Label("Recently Taken", systemImage: "clock.arrow.circlepath")` et `Label("Recently Added", systemImage: "arrow.up.circle")`. L'en-tête « Recently » est distinct de « Management », qui porte des réglages et non de la consultation.
- **Précédent exact copié** : `NavigationLink { OfflineAssetsView(vm: offline) } label: { Label("Offline Storage", systemImage: "arrow.down.circle") }` (`ProfileView.swift:107-111`) — vue poussée depuis le hub, sans stack.
- **`RecentAssetsView` ne déclare aucun `NavigationStack`** : `ProfileView.swift:24` en porte déjà un ; un second stack empile deux barres de navigation (piège déjà payé sur `LanguageSettingsView`).
- **Pourquoi pas depuis l'onglet Photos** (étape 10 de la spec, non retenue) et **pourquoi la vue ne réutilise pas `TimelineView`** — trois faits mesurables de `Sources/Features/Timeline/TimelineView.swift` :
  1. `:219` — `.toolbar(vm.selectionMode ? .visible : .hidden, for: .navigationBar)` : la barre est **cachée hors mode sélection**, donc le bouton Retour du `NavigationLink` disparaîtrait dès l'arrivée sur l'écran ;
  2. `:110-118` — l'overlay top-trailing rend `ProfileAvatarButton`, qui présente la feuille « Me » via `OpenProfileKey` (`RootView.swift:302-306`) : la feuille se présenterait depuis elle-même ;
  3. `:222` — `.navigationDestination(item: $openedStackID)` exige un `StacksViewModel`, soit une **troisième** instance de ce ViewModel pour des écrans qui n'ouvrent aucune pile.
- **Chrome** : `.navigationTitle(vm.mode.title)` + `.navigationBarTitleDisplayMode(.inline)`, et aucun `ToolbarItem(placement: .principal) { ImmichAppBar(…) }` (motif de `TrashView.swift:227-229`, qui suppose un titre vidé : ici il doublerait le titre, et `ImmichAppBar` rend le logo de l'app, pas l'icône du mode). Pas de bouton de fermeture : détail poussé, retour par le geste système.

## Layout

```
RecentAssetsView(vm: RecentAssetsViewModel)        poussée par ProfileView, aucun NavigationStack
├── .navigationTitle(vm.mode.title)                « Recently Taken » | « Recently Added »
├── .navigationBarTitleDisplayMode(.inline)
├── .task { await vm.load() }   .refreshable { await vm.refresh() }
├── .background(Color.bgPrimary)
└── content                                        un seul état à la fois
    ├── if vm.isLoading && vm.dayGroups.isEmpty
    │   └── PVSkeletonGrid(rows: 4, columnCount: 3)        3 = les colonnes réelles de la grille
    ├── else if let message = vm.errorMessage, vm.dayGroups.isEmpty
    │   └── VStack(spacing: PVSpacing.s16)
    │       ├── Label(vm.mode.title, systemImage: vm.mode.systemImage)   .font(.pvSubhead)
    │       ├── Text(message)  .font(.pvBody) .foregroundStyle(Color.textSecondaryPV)
    │       │                  [id: recentError]        sur le texte, jamais sur ce VStack
    │       └── Button("Refresh") { Task { await vm.refresh() } }        .buttonStyle(PVButtonStyle())
    │             [id: recentErrorRetry]
    ├── else if vm.dayGroups.isEmpty
    │   └── ContentUnavailableView  [id: recentEmptyState]
    │       ├── Label(vm.mode.title, systemImage: vm.mode.systemImage)
    │       └── Text(vm.mode.emptyMessage)  « Photos you take / add … will appear here. »
    └── else
        └── ScrollView  [id: recentGrid]
            └── LazyVStack(spacing: PVSpacing.s24, pinnedViews: [.sectionHeaders])
                ├── ForEach(vm.dayGroups) { group in Section(content:, header: dayHeader) }
                │     LazyVGrid(columns: 3 × GridItem(.flexible(), spacing: PVSpacing.s2), spacing: s2)
                │     ForEach(group.items) { item in
                │         AssetThumbnailCell(asset: item, baseURL: …, token: …,
                │                             selectionMode: false, contextMenuEnabled: false) }
                └── if vm.hasMore { ProgressView() [id: recentLoadMore]
                                    .onAppear { await vm.loadMore() } }
            .padding(.horizontal, PVSpacing.s4)     4 pt : la convention de grille de la timeline
```

- **Groupement par jour** : la section vient de `buckets[i].timeBucket`, une date ISO déjà renvoyée par `GET /api/timeline/buckets` — aucune requête supplémentaire, aucun groupement client. `RecentDayGroup.title` est **déjà mis en forme par le ViewModel** (`DateHeaderFormatter`, `Sources/Features/Timeline/DateHeaderFormatter.swift`) ; la vue n'appelle jamais un formateur de date (règle `sync-status` : une seule mise en forme, côté VM).
- **En-tête de jour sur une ligne**, contrairement à l'overlay à deux lignes de `TimelineView:93-96` : cet overlay est un flottant « Photos » posé sur les photos ; ici on veut une bande épinglée, lisible sur `bgPrimary`.
- **Pagination infinie** : la sentinelle est le `ProgressView()` en fin de `LazyVStack` ; `loadMore()` garde `vm.hasMore`, qui passe à `false` quand le dernier bucket demandé ne renvoie rien. Aucun bouton « charger plus ».
- **Cibles 44 pt** : les lignes du hub sont pleine largeur, le bouton « Refresh » est pleine largeur, une tuile fait un tiers de largeur.

## Composants

Réutiliser ; rien à créer hors le motif `dayHeader` (les deux en-têtes de la timeline sont inutilisables ici : l'un est un flottant à deux lignes avec ombre, l'autre un en-tête de `List`).

| Besoin | Composant existant |
|---|---|
| Tuile d'asset | `AssetThumbnailCell(asset:baseURL:token:)` (`AssetThumbnailCell.swift:14-35`), `selectionMode: false` |
| État vide / erreur / premier chargement | `ContentUnavailableView`, `PVSkeletonGrid(rows:columnCount:)` (comme `TimelineView:337-351`) |
| Reprise après erreur | `Button("Refresh")` + `PVButtonStyle()` |
| Fond, séparateurs | `Color.bgPrimary` / `Color.bgSecondary` / `Color.separatorPV` — aucun blanc littéral |
| Groupe de jours | `LazyVGrid` + `Section` — le motif de la timeline, sans son zoom (`TimelineGridZoom`) |

Le mode porte la totalité du vocabulaire visuel. **Un seul ajout à l'enum** (`systemImage`) : l'icône apparaît en trois endroits (ligne du hub, état vide, état d'erreur), et une divergence entre ces trois endroits est exactement le bug que l'enum doit rendre impossible.

```swift
// Sources/Features/Recent/RecentAssetsMode.swift — la vue ne teste jamais le mode
var systemImage: String {
    switch self {
    case .taken: "clock.arrow.circlepath"    // l'icône de la ligne du hub
    case .added: "arrow.up.circle"
    }
}

private let columns = Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s2), count: 3)

private func dayHeader(_ title: String) -> some View {
    Text(title)                             // déjà mise en forme par DateHeaderFormatter, dans le VM
        .font(.pvHeadline)
        .foregroundStyle(Color.textPrimaryPV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, PVSpacing.s8)
        .background(Color.bgPrimary)        // opaque : un header épinglé laisse passer la grille dessous
        .accessibilityAddTraits(.isHeader)
}
```

## Interactions

| Geste | Effet |
|---|---|
| Tap sur une tuile | **Rien.** `onTap` garde sa valeur par défaut `{}` : le plein écran appartient à l'onglet Photos (le présentateur de la feuille « Me » sérialise les présentations — Incertitudes de la spec) |
| Appui long sur une tuile | **Rien.** Pas de mode sélection : `selectionMode: false` neutralise la bascule, et le menu contextuel est désactivé (Erreurs §2) |
| Pull-to-refresh | `.refreshable { await vm.refresh() }` — recharge les buckets puis le premier jour |
| Arrivée sur la sentinelle de pied | `await vm.loadMore()` — charge le jour suivant, seulement si `vm.hasMore` |
| Arrivée sur l'écran | `.task { await vm.load() }`, sans garde : deux instances (une par mode) ne partagent rien |
| Tap « Refresh » (erreur) | `await vm.refresh()` — seul chemin de reprise ; l'erreur n'est jamais un overlay bloquant |
| Retour | Rien à libérer : aucun état partagé, aucune tâche d'arrière-plan |

## Liquid Glass / matériaux

**Aucun `glassEffect` sur cet écran.** Précédent du dépôt : le verre est réservé aux surfaces **flottantes** (bandeaux, pilules de la timeline, îlot Live Activity), jamais aux écrans de contenu poussés — `OfflineAssetsView` et `StackView`, les deux autres surfaces poussées depuis le hub « Me », n'en utilisent pas. Ici tout est grille de bout en bout : fond `bgPrimary`, en-têtes de jour opaques, séparateurs `Color.separatorPV`. Du verre sous une grille de photos ajouterait du coût de composition pour un écran qui n'a rien à faire flotter.

## Accessibilité

- **Identifiants** (ceux de la spec, posés sur l'élément porteur, jamais sur un conteneur qui en contient) : `recentTakenRow` / `recentAddedRow` (les `NavigationLink` du hub), `recentGrid` (le `ScrollView`), `recentEmptyState` (le `ContentUnavailableView`), `recentError` (le `Text`), `recentErrorRetry` (le bouton), `recentLoadMore` (la sentinelle). Règle mesurée ici : un identifiant de conteneur **écrase** celui de ses descendants (`languageRelaunchToast` rendait `languageToastDismiss` introuvable) — d'où `recentError` sur le texte et non sur le `VStack` qui porte le bouton, et **aucun identifiant de tuile** : sous `recentGrid`, il n'existe aucun identifiant descendant à masquer.
- **VoiceOver** : `.isHeader` sur chaque en-tête de jour — c'est le seul moyen de parcourir une grille de plusieurs centaines de tuiles. Les tuiles restent des éléments combinés par `AssetThumbnailCell` : ni label ni trait ajoutés ici. Le mode est lu par la barre de navigation ; la ligne du hub lit « Recently Taken » / « Recently Added ».
- **Dynamic Type** : 3 colonnes fixes, aucune hauteur figée, en-têtes en `.pvHeadline` (`.padding(.vertical, PVSpacing.s8)`, pas de `frame(height:)`).
- **Reduce Motion** : rien à neutraliser, l'écran n'introduit aucune animation.
- **Libellés — clés anglaises, jamais de littéral français** : `Recently`, `Recently Taken`, `Recently Added`, `Refresh`, `Photos you take will appear here.`, `Photos you add to the server will appear here.`.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Premier jour affiché | Aucune : le `LazyVStack` remplace le `PVSkeletonGrid` d'un coup | neutre par construction |
| Insertion d'un jour plus ancien | Aucune : le jour s'ajoute **sous** la sentinelle, hors du viewport | neutre par construction |
| Sentinelle de chargement | Aucune : `ProgressView()` système | système |

Aucun `matchedGeometryEffect`, aucun `glassEffectID`, aucun morphing : l'écran ne se transforme pas, il **s'empile**. Une animation d'insertion serait invisible (hors écran) ou coûteuse (une animation par tuile sur plusieurs centaines d'éléments) — le dépôt a déjà tranché ce compromis sur la timeline.

## Fichiers touchés

- NEW `Sources/Features/Recent/RecentAssetsMode.swift` — l'enum `taken`/`added` : `orderBy`, `title`, `emptyMessage`, `systemImage`.
- NEW `Sources/Features/Recent/RecentAssetsViewModel.swift` (spec, étapes 5-6) et NEW `Sources/Features/Recent/RecentAssetsView.swift` — l'écran, `dayHeader`, la grille, les trois états.
- NEW `Tests/RecentAssetsViewModelTests.swift` — 8 cas nommés (spec étape 11) ; **aucun libellé d'interface épinglé**.
- EDIT `Sources/Features/Timeline/AssetThumbnailCell.swift` — paramètre **additif** `var contextMenuEnabled: Bool = true` (`:91`), pour que cette grille soit réellement en lecture seule sans toucher les six appelants existants.
- EDIT `Sources/Core/Protocols/ImmichClient.swift`, `Sources/Services/ImmichAPIClient.swift`, `Tests/Mocks/MockImmichClient.swift`, `Sources/Features/Timeline/TimelineViewModel.swift`, `Sources/Features/Trash/TrashViewModel.swift` — le paramètre `orderBy` (spec étapes 1-4).
- EDIT `Sources/DependencyContainer.swift` (`makeRecentAssetsViewModel(mode:)`), EDIT `Sources/RootView.swift` (`@State recentTaken` / `recentAdded` passés à `ProfileView`), EDIT `Sources/Features/Profile/ProfileView.swift` (les deux `@State` + la `Section` « Recently »).
- Aucune écriture dans `Resources/Localizable.xcstrings` : la clé est la chaîne anglaise, l'extraction la crée.

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Déclarer un `NavigationStack` dans `RecentAssetsView`** : `ProfileView.swift:24` en porte déjà un ; un second stack empile deux barres de navigation (piège déjà payé sur `LanguageSettingsView`).
2. **Instancier `AssetThumbnailCell` sans désactiver son menu contextuel** : `AssetThumbnailCell.swift:88-91` n'attache le menu que si `selectionMode == false` et `sharedLink == nil` — exactement notre cas — et ses entrées appellent `onToggleFavorite()` / `onDelete()`, dont les valeurs par défaut sont des closures **vides** (`:27-28`). L'écran offrirait un menu « Favorite / Delete » **mort**, en contradiction avec la lecture seule de la spec.
3. **Porter un identifiant d'accessibilité sur un conteneur qui en contient** : mesuré sur `languageRelaunchToast`, où l'identifiant du `GlassEffectContainer` écrasait celui du bouton (`app.buttons.matching(identifier: "languageToastDismiss").count == 0` alors que le bouton était bien à l'écran).
4. **Tester `mode == .taken` dans la vue** : tout libellé et toute icône vivent dans `RecentAssetsMode` — deux branches dans la vue, c'est deux écrans à maintenir là où l'enum en promet un seul.
5. **Préfixer les jours plus anciens au lieu de les ajouter en fin** : la timeline le fait (`loadOlder()`, `TimelineViewModel:233-237`) parce qu'elle remonte le temps ; ici on descend, sinon l'ordre s'inverse en scrollant.
6. **Écrire un littéral français dans la vue** : la clé du catalogue est la chaîne anglaise, et `ImmichAppBar(title:)` prend une `LocalizedStringKey` — un littéral passé à un paramètre `String` n'est jamais extrait ni traduit.
7. **Construire l'en-tête de jour dans la vue** : la date est déjà mise en forme par le ViewModel (`DateHeaderFormatter`) ; une seconde mise en forme divergerait des libellés de la timeline (« Today » / « Yesterday ») dès qu'une locale change.
8. **Réutiliser `AssetMultiSelectGrid`** : c'est une grille de **sélection** (`selectedIds`, `excluding`, `selectionHint`, `onToggle`, paginée par `POST /api/search/metadata`) — elle apporte le mode sélection que ces écrans excluent, et sa pagination ne sait pas viser `createdAt`.
9. **Ajouter un `ToolbarItem(placement: .principal) { ImmichAppBar(…) }`** : le motif de `TrashView.swift:227-229` suppose un `navigationTitle` vidé ; ici il doublerait le titre posé par `.navigationTitle(vm.mode.title)`.
