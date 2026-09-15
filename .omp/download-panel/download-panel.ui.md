# Task: download-panel — UI Brief

> Compagnon de `.omp/download-panel/download-panel.specs.md` (2026-09-15). Ce document ne décrit que la
> **surface** — placement, hiérarchie de vues, gestes, états, tokens — et ne duplique pas la spec.

## Design Philosophy

Deux surfaces, une seule intention : **« je veux le fichier »**. Le **panneau flottant**
(`DownloadProgressPanel`) répond sans quitter l'écran courant à *où en est ce que j'ai demandé, est-ce fini ?*
Il tient en une ligne et **zéro état propre** : il projette le `DownloadQueueViewModel`. L'**écran
d'information** (`DownloadInfoView`) est le constat détaillé : une ligne par fichier — nom serveur, taille,
barre, échec, actions.

La différence avec l'**épinglage hors ligne**, déjà livré, est structurelle et doit rester lisible :

| | Épinglage hors ligne (existant) | File de téléchargement (cette fiche) |
|---|---|---|
| Intention | « garde-la disponible sans réseau » | « donne-moi le fichier » |
| Marqueur | badge de cellule piloté par `OfflineAssetIndex` | barre de progression + panneau flottant |
| Nom | `<assetId>.<ext>`, délibérément pas celui du serveur | `IMG_0421.HEIC`, le nom du serveur |
| Durée de vie | `maxCacheSize` peut l'évincer | jamais évincé par un budget de cache |
| Libellé | « Download for Offline » | « Download to Files » |

Aucune des deux surfaces ne parle de l'autre : le panneau ignore `maxCacheSize`, aucun téléchargement utilisateur n'allume le badge hors ligne.

## Placement dans la navigation

- **Panneau** : `overlay(alignment: .bottom)` dans `AuthenticatedRoot` (`Sources/RootView.swift`), déclaré **avant** les `.sheet` existantes (`:221`, `:224`, `:233`) : au-dessus des onglets, sous toute présentation, et **visible d'un onglet à l'autre** — c'est tout l'objet de la fiche. Précédent dans ce fichier : le doc-comment de tête (`:5`, « overlays a LockView ») et `private struct LockView` (`:273`) font de la vue racine l'endroit où l'app surimprime un état global.
- **Écran d'information** : feuille (`showDownloadInfo`) ouverte au tap sur le panneau, sur le patron exact des trois `@State` voisines (`showCreateAlbum` `:112`, `showCreateSharedLink` `:113`, `showProfile` `:114`).
- **Pas de rôle d'onglet, pas de poussée depuis `ProfileView`** : la file n'est pas un réglage, elle est transitoire ; une fois vide et l'écran fermé, il ne reste rien.
- **Entrées** : la ligne « Download to Files » du `SaveSection` du viewer (`PhotoViewer.swift:1160`, sous « Download original » `:1179-1181`) et l'action de masse du détenteur de `selectedIds` du timeline.

## Layout

```
RootView — AuthenticatedRoot
└── TabView (5 onglets)
    ├── .overlay(alignment: .bottom)                  ← précédent LockView (:5, :273)
    │   └── if downloads.isPanelVisible
    │       └── DownloadProgressPanel(vm:onOpenInfo:)  ← zéro état, projette le VM
    │           └── Button(action: onOpenInfo)          ← LE panneau entier est un seul Button
    │               └── HStack(spacing: PVSpacing.s8)
    │                   ├── Image("arrow.down.circle")  ├── Text("3 of 12")
    │                   ├── ProgressView(value: vm.aggregateProgress)   (absente si nil)
    │                   └── Image("chevron.up")
    └── .sheet(isPresented: $showDownloadInfo)
        └── NavigationStack                             ← fournit la pile (jamais DownloadInfoView)
            └── DownloadInfoView(vm: downloads)
                ├── ImmichAppBar(title: "Downloads") + "Clear completed" | "Done"
                └── ScrollView → VStack(spacing: PVSpacing.s16)
                    ├── résumé: Text("3 of 12").pvNumeric
                    │   ├── Text(vm.formattedAggregateSize).pvSubhead
                    │   └── ProgressView(value: vm.aggregateProgress)     (absente si nil)
                    ├── Section "Downloading" → downloadRow(item)   (.running)
                    ├── Section "Queued"      → downloadRow(item)   (.queued)
                    ├── Section "Failed"      → downloadRow + InlineErrorBadge(item.errorMessage)
                    ├── Section "Completed"   → downloadRow(item)
                    └── downloadRow(item)      ← @ViewBuilder privé, sans état
                        ├── Image(item.isArchive ? "doc.zipper" : "photo")
                        ├── Text(item.fileName)              ← nom serveur : IMG_0421.HEIC
                        ├── PVStatusBadge("Available offline")   ← si déjà dans le cache
                        ├── Text(item.formattedSize).pvCaption
                        ├── ProgressView(value: item.progress)   (absente si nil)
                        └── Button "Cancel" (.running/.queued) | Button "Retry" (.failed)
```

- **Fond** : `Color.bgPrimary` pour la feuille, `Color.bgSecondary` pour les lignes, `Color.separatorPV`
  entre elles. Aucun blanc littéral.
- **Le panneau ne réserve aucune place** : un `overlay` ne décale pas la grille. Si une bannière d'upload apparaît un jour en bas de `AuthenticatedRoot`, les deux se rangent dans un même `VStack` (aujourd'hui aucun `ProgressBanner` n'existe dans `Sources/`).

## Composants

| Besoin | Composant existant |
|---|---|
| Barre de titre du panneau | `ImmichAppBar` (`ToolbarItem(placement: .principal)`) |
| État d'une ligne | `PVStatusBadge` — jamais un `Text` coloré à la main |
| Échec d'une ligne | `InlineErrorBadge` (raison courte : « Connection canceled », « Server returned 500 ») |
| Boutons de ligne | `PVButtonStyle` (`.bordered` pour Cancel/Retry ; aucune action n'est primitive ici) |
| Surfaces | `Color.bgSecondary` + `PVRadius.md` ; le verre est réservé au panneau (voir plus bas) |
| File vide | `ContentUnavailableView("No downloads yet", systemImage: "arrow.down.circle", description: Text("Download a photo to see it here."))` |

```swift
/// Panneau — un SEUL Button enveloppe la ligne : aucun bouton imbriqué.
struct DownloadProgressPanel: View {
    @Bindable var vm: DownloadQueueViewModel
    let onOpenInfo: () -> Void

    var body: some View {
        Button(action: onOpenInfo) {
            HStack(spacing: PVSpacing.s8) {
                Image(systemName: "arrow.down.circle").font(.pvHeadline)
                Text("\(vm.completedCount) of \(vm.totalCount)")
                    .font(.pvSubhead).contentTransition(.numericText())
                if let fraction = vm.aggregateProgress {
                    ProgressView(value: fraction).frame(width: 72)
                }
                Image(systemName: "chevron.up").font(.pvCaption)
            }
            .foregroundStyle(Color.textPrimaryPV)
            .padding(PVSpacing.s12)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        }
        .accessibilityIdentifier("downloadPanel")
        .accessibilityLabel(vm.panelAccessibilityLabel)   // « 3 of 12 downloads in progress »
    }
}
```

- **Progression agrégée** : `vm.aggregateProgress` est `nil` tant qu'aucune entrée ne connaît son `expectedBytes` (le serveur n'envoie pas toujours de `Content-Length`). Dans ce cas on **retire la barre** au lieu d'un `ProgressView()` indéterminé : le compteur « n of N » reste vrai, lui.
- **Nom du fichier** : vient du serveur via `AssetFileTransfer.baseName(originalName:datePrefix:)`, exposé prêt par le VM (`item.fileName`) ; la vue ne reconstruit ni basename ni extension.
- **Tailles** : `item.formattedSize` et `vm.formattedAggregateSize` sont produits par le VM (`ByteCountFormatter.countStyle: .file`), dans la ligne de `OfflineDownloadViewModel.formattedUsage(_:)` ; la vue ne formate jamais un nombre.

## Interactions

| Geste | Effet |
|---|---|
| Tap sur le panneau (capsule entière) | `showDownloadInfo = true` → `NavigationStack { DownloadInfoView(vm:) }` |
| Tap « Done » | `dismiss()` ferme l'écran ; **la file continue** — c'est le point de la fiche |
| Tap « Cancel » sur une ligne `.running` | `vm.cancel(assetId:)` → `.cancelled`, sans `errorMessage` (annuler n'est pas échouer) |
| Tap « Cancel » sur une ligne `.queued` | même appel : l'entrée n'est jamais lancée |
| Tap « Retry » sur une ligne `.failed` | `vm.retry(assetId:)` → repasse `.queued` puis `.running`, `errorMessage` remis à `nil` |
| Tap « Clear completed » | `vm.clearCompleted()` — retire **uniquement** les `.completed` ; désactivé si `completedCount == 0` |
| Tap « Download to Files » (viewer) | `downloads.enqueue(asset:baseURL:token:)` depuis `SaveSection`, sans fermer la feuille du viewer |
| Tap « Download » (sélection) | `downloads.enqueue(assets: items.filter { selectedIds.contains($0.id) }, baseURL:token:)`, puis fermeture du mode sélection |
| Ligne déjà couverte par le cache hors ligne | **Aucun traitement spécial** : l'action reste offerte et produit un fichier nommé par le serveur, à la destination utilisateur. La ligne porte en plus `PVStatusBadge("Available offline")`, lu sur `OfflineAssetIndex`, pour que l'utilisateur voie qu'il demande un doublon. Ce cache n'est ni lu en écriture, ni élagué par cette surface. |
| Asset déjà dans la file | L'id d'entrée **est** l'`assetId` : une seconde demande remonte la même ligne au lieu d'en créer une deuxième |
| Pull-to-refresh | Rien : l'écran projette un état vivant, il n'y a pas de source à recharger |
| File vide | `ContentUnavailableView` — pas de sections vides empilées |

Un bouton se désactive par `.disabled(...)` porté par le bouton, jamais par une alerte. Une entrée `.failed`
n'arrête pas la file : les lignes suivantes continuent de progresser.

## Liquid Glass / matériaux

- `DownloadProgressPanel` : `.background(.ultraThinMaterial, in: Capsule())` + ombre — c'est une surface
  **flottante** au-dessus du contenu, exactement le cas d'usage réservé par le dépôt (barres de recherche,
  bandeaux, îlot Live Activity). La `Capsule` la fait lire comme un objet posé, pas comme un élément d'écran.
- `DownloadInfoView` : **aucun matériau**, aucun `glassEffect`. Précédent : les écrans de contenu
  (`StackView`, `OfflineAssetsView`, `SyncStatusView`) n'en utilisent pas ; en ajouter ici rendrait cet écran
  plus « primaire » que les écrans de réglages.
- Le panneau ne masque jamais `LockView` : l'overlay est déclaré sous les sheets existantes, `LockView` reste
  l'overlay le plus haut.

## Accessibilité

- **Identifiants**, sur les éléments **interactifs** et jamais sur un conteneur : `downloadPanel` (le `Button`
  unique ; le résumé interne n'en porte aucun, sinon il masquerait le bouton), `downloadInfoCancel_<assetId>`
  et `downloadInfoRetry_<assetId>` (suffixés par asset : plusieurs lignes coexistent, un identifiant nu serait
  ambigu dès la deuxième), `downloadInfoClearCompleted`, `downloadInfoDone`, `downloadToFilesButton`,
  `downloadSelectionButton`.
- **Pas d'identifiant sur la ligne** : `downloadInfoRow_<assetId>` est remplacé par
  `accessibilityElement(children: .combine)` + label produit par le VM (« IMG_0421.HEIC, 3.4 MB, downloading,
  42 percent »). Un identifiant sur la ligne engloberait Cancel/Retry et les rendrait inatteignables.
- **VoiceOver** : le panneau est un seul élément dont le label est `vm.panelAccessibilityLabel`, pas la concaténation des `Text` internes ; chaque ligne est un élément combiné, jamais deux lectures libellé/valeur.
- **Cibles ≥ 44 pt** : le panneau fait au moins 44 pt de haut (`PVSpacing.s12` vertical + `.pvSubhead`) ; Cancel/Retry sont en `.bordered` pleine hauteur ; les deux actions de barre d'outils ont la cible système.
- **Dynamic Type** : aucune `frame(height:)` figée ; le `ProgressView` de ligne est en `.frame(maxWidth: .infinity)` pour se rétrécir quand le nom grandit, et le nom passe à la ligne (`.lineLimit(2)`) au lieu d'être tronqué au milieu.
- **Reduce Motion** : apparition en fondu (`opacity`) et non en ressort ; `contentTransition` neutralisé par le système ; aucune animation rejouée à la main.
- **Chaînes, clés anglaises** : `Downloads`, `Downloading`, `Queued`, `Completed`, `Failed`, `Cancel`, `Retry`, `Clear completed`, `Done`, `Download to Files`, `Available offline`, `No downloads yet`, `%lld of %lld`. Aucun littéral français ; l'extraction du catalogue est faite par Xcode.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Apparition / disparition du panneau | `.transition(.opacity.combined(with: .move(edge: .bottom)))`, `PVMotion.standard` | fondu conservé, déplacement retiré |
| Compteurs « n of N » et tailles | `.contentTransition(.numericText())` sur les `Text` du VM | neutralisé par le système |
| Barre agrégée qui avance | `ProgressView(value:)`, aucune animation manuelle | mise à jour sans interpolation |
| Ligne changeant de statut | `.contentTransition(.symbolEffect(.replace))` sur l'icône | remplacement instantané |
| Ligne retirée par « Clear completed » | `withAnimation(PVMotion.standard) { vm.clearCompleted() }` | suppression sans animation |

Aucun morphing, aucun `matchedGeometryEffect`, aucun `glassEffectID` : le panneau ne se transforme pas, il se met à jour — la capsule garde sa forme et change de contenu, ce qui est exactement l'effet voulu.

## Fichiers touchés

- NEW `Sources/Features/DownloadPanel/DownloadItem.swift` — types de la file (`DownloadStatus`, `DownloadItem`).
- NEW `Sources/Features/DownloadPanel/DownloadQueueViewModel.swift` — la file process-wide.
- NEW `Sources/Features/DownloadPanel/DownloadProgressPanel.swift` — le panneau flottant.
- NEW `Sources/Features/DownloadPanel/DownloadInfoView.swift` — l'écran d'information et son `downloadRow`.
- NEW `Tests/DownloadQueueViewModelTests.swift` — 8 cas (spec, étape 12).
- EDIT `Sources/RootView.swift` — `@State downloads`, `@State showDownloadInfo`, l'`overlay` et la `sheet`.
- EDIT `Sources/DependencyContainer.swift` — `makeDownloadQueueViewModel()`.
- EDIT `Sources/Core/Protocols/ImmichClient.swift` + `Sources/Services/ImmichAPIClient.swift` — requêtes.
- EDIT `Sources/Features/PhotoViewer/PhotoViewer.swift` — `let downloads` + ligne « Download to Files ».
- EDIT le détenteur de `selectedIds` du timeline — action de masse « Download ».

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Déclarer un `NavigationStack` dans `DownloadInfoView`** : la pile vient de la `sheet` de `RootView` ; un second stack produit deux barres de navigation (piège relevé à la livraison de `LanguageSettingsView`).
2. **Emboîter un bouton dans un bouton** : envelopper le panneau dans un `Button` contenant déjà des `Button` le rend inerte (piège mesuré : `AssetThumbnailCell` dans un `Button`). Un seul `Button`, zéro bouton enfant.
3. **Faire alimenter le badge hors ligne par la file** : passer par `OfflineAssetIndex` allumerait l'indicateur « hors ligne » de la timeline pour des fichiers jamais épinglés (3ᵉ motif de rejet de l'approche B).
4. **Réutiliser la destination du cache** (`Application Support/OfflineAssets/<assetId>.<ext>`) : fichier introuvable pour l'utilisateur, et évincé par `setMaxCacheSize(_:)` ou `clearAll()`.
5. **Créer un `DownloadQueueViewModel` par présentation du viewer** : il mourrait à la fermeture de la feuille — exactement le défaut que la fiche corrige (`SaveToLibraryViewModel`, `PhotoViewer.swift:945`).
6. **Passer par `SaveToLibraryViewModel.downloadOriginal()`** : ce chemin charge l'original en mémoire et écrit dans Photos ; il ne produit aucun fichier et ne connaît qu'un asset, jamais une sélection.
7. **Poser un `accessibilityIdentifier` sur un conteneur** : sur la capsule, il masque le bouton ; sur une ligne, il masque Cancel/Retry (mesuré sur `languageRelaunchToast`).
8. **Formater un nombre ou une date dans la vue** : une seule mise en forme d'octets existe (`OfflineDownloadViewModel.formattedUsage(_:)`) ; le VM expose `formattedSize` et `formattedAggregateSize`.
9. **Afficher un `ProgressView()` indéterminé pour le total** : si `aggregateProgress` est `nil`, on retire la barre et on garde « n of N », qui reste exact.
10. **Libeller l'action « Download for Offline »** : ce libellé appartient à `downloadForOfflineButton` (`PhotoViewer.swift:1257`), qui écrit dans le cache. Ici : « Download to Files ».
11. **Écrire un littéral français dans une vue** : la clé du catalogue est la chaîne anglaise.
12. **Empiler un second `overlay(alignment: .bottom)`** : le panneau occupe déjà le bas de la vue racine ; une future bannière d'upload se range dans le même `VStack`.
