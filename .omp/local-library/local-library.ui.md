# Task: local-library — UI Brief

> Compagnon de `.omp/local-library/local-library.specs.md` (écart G3, 2026-09-15). Ce document ne décrit que
> la **surface** — placement, hiérarchie, gestes, états, tokens ; le contrat serveur (`bulk-upload-check`,
> `/assets/statistics`) et les étapes d'implémentation restent dans la spec.

## Design Philosophy

L'écran répond à une question que l'app ne sait pas encore poser : **« qu'est-ce que MON appareil contient,
et qu'est-ce qui manque au serveur ? »**. Ce n'est ni la timeline (le serveur) ni l'écran Backup (*un run*) :
c'est le **relevé de la photothèque locale**, mis en regard du relevé distant. Trois convictions :

1. **Deux colonnes, un verdict.** « This device » et « Your server » côte à côte ; l'écart entre les deux
   chiffres **est** l'information.
2. **Aucun verdict n'est inventé.** Un asset ne porte « on server » / « not on server » **qu'après** la
   vérification demandée (`POST /api/assets/bulk-upload-check`). Avant, la cellule est neutre : l'absence de
   réponse ne vaut jamais « sauvegardé ».
3. **L'envoi est explicite et borné.** Une sélection, un compteur, un envoi — pas de run, pas de file, pas
   de Live Activity, pas de reprise. Le moteur de sauvegarde garde son écran.

## Placement dans la navigation

- Poussé depuis **`ProfileView`** (hub « Me »), section `Management`, **immédiatement après « Offline
  Storage »** (`ProfileView.swift:107-112`) : les deux lignes lisent l'**appareil**, pas le serveur, et le hub
  « Me » est déjà le reliquat des surfaces qui ne méritent pas un onglet.
- `LocalLibraryView` **ne déclare aucun `NavigationStack`** : `ProfileView` en porte déjà un (`:24`) — un second
  stack produirait deux barres de navigation (piège relevé sur `LanguageSettingsView`).
- **Pas d'onglet, pas de segment dans Photos** : l'onglet Photos reste l'onglet *serveur*. `TimelineView` ne
  peut pas héberger cette surface — sa grille (`AssetMultiSelectGrid`) est typée sur `[AssetReactItem]` issu de
  `POST /api/search/metadata`, et `fetchAssets()` rend un `[PHAsset]` complet **sans curseur**.
- **Cohabitation avec Backup** : aucune barre de progression de run ici — pas de `segmentBar`, pas de lignes
  failed/deferred, pas de « Run now ». Seule progression : la sélection envoyée (spec §4, `uploadProgress`).

## Layout

```
LocalLibraryView                                  (poussée par ProfileView, aucun NavigationStack)
└── ScrollView                                    .background(Color.bgPrimary)
    └── VStack(spacing: PVSpacing.s16)            .padding(PVSpacing.s16)
        ├── summaryCard                           VStack(spacing: PVSpacing.s8)
        │   ├── HStack(spacing: PVSpacing.s8)     2 × SummaryColumn, largeur égale
        │   │     "This device"  Label("iphone"), .pvNumeric(total), .pvCaption "N photos · M videos"
        │   │     "Your server"  total distant, "—" tant que remoteSummary == nil
        │   └── InlineErrorBadge                  si vm.errorMessage != nil (stats distantes KO)
        ├── albumsSection                         VStack(spacing: PVSpacing.s4)
        │   ├── Text("Albums") en-tête            .pvHeadline ; id "localAlbumRow"
        │   ├── AlbumRow "All photos"             sélectionné quand selectedAlbumID == nil
        │   └── AlbumRow(album, isSmart)          "sparkles" si isSmart sinon "rectangle.stack" + count
        └── gridSection
            ├── Text("On this device") en-tête    id "localAssetGrid" ← feuille, jamais le LazyVGrid
            ├── PVSkeletonGrid(rows: 3, columnCount: 3)   si vm.phase == .enumerating
            ├── ContentUnavailableView                    si permissions refusées ou photothèque vide
            └── LocalAssetGrid                            LazyVGrid 3 colonnes, spacing PVSpacing.s2

.safeAreaInset(edge: .bottom) ─ SelectionBar (seulement si vm.hasSelection) :
   "\(vm.selectionCount) selected" .pvHeadline │ "\(vm.localOnlyCount) not on server" .immichWarning
   "\(vm.savedCount) on server" .immichSuccess │ ProgressView(value:) "\(done) / \(total)" si .uploading
   Button "Check" (PVSubtleButtonStyle)        Button "Upload" (PVPrimaryButtonStyle)
```

- **Barre d'outils** : `ToolbarItem(placement: .principal) { ImmichAppBar(title: "On this device") }` +
  `.navigationBarTitleDisplayMode(.inline)`, comme les autres écrans poussés du hub.
- **Rafraîchissement** : `.task { await vm.loadAlbums(); await vm.loadAssets(albumID: nil); await vm.loadRemoteSummary() }`
  puis `.refreshable { … }` — les stats distantes chargent en tâche de fond, jamais bloquantes.
- **Quatre états de grille** : permissions refusées → `ContentUnavailableView("Photo library access is off",
  systemImage: "lock")` + action « Allow access » (`requestAuthorization`), ou « Open Settings » si le statut
  est `denied`/`restricted` (iOS ne repose plus la question) ; photothèque vide → `ContentUnavailableView(
  "Nothing here yet", …)` ; **assets évincés d'iCloud** → cellule conservée avec le placeholder `icloud.slash`
  et sa légende, jamais une grille silencieusement trouée ; volume local → jamais calculé à l'ouverture
  (compter les octets oblige à lire chaque ressource), seulement sur demande et mis en forme par le VM.

## Composants

Réutiliser, ne pas créer (aucun ajout au DesignSystem) :

| Besoin | Composant existant |
|---|---|
| Barre de titre | `ImmichAppBar` (`title: LocalizedStringKey`, jamais une `String` — sinon pas d'extraction) |
| Action principale / secondaire | `PVPrimaryButtonStyle` / `PVSubtleButtonStyle` (famille `PVButtonStyle`) |
| Gabarit de cellule | `PVGridCell` (coin `PVRadius.md`, fond `Color.bgSecondary`) |
| Squelette, badge, erreur | `PVSkeletonGrid(rows:columnCount:)`, `PVStatusBadge(text:color:symbol:)`, `InlineErrorBadge(message:retry:)` |

```swift
/// Déclarée dans LocalAssetCell.swift (NEW) — pas dans le DesignSystem.
struct LocalAssetCell: View {
    let asset: PHAsset
    let isSelected: Bool
    let isLocalOnly: Bool?          // nil == verdict PAS demandé → aucun badge
    let onTap: () -> Void
    let loadThumbnail: (PHAsset) async -> UIImage?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                if let image = image { Image(uiImage: image).resizable().scaledToFill()
                    .aspectRatio(1, contentMode: .fill).clipped() }        // vignette locale
                else { Image(systemName: "icloud.slash") }                 // asset évincé d'iCloud
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.pvHeadline).padding(PVSpacing.s4)
                    .foregroundStyle(isSelected ? Color.immichPrimary : Color.textSecondaryPV)
            }
            .clipShape(RoundedRectangle(cornerRadius: PVRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("localAssetCell_\(asset.localIdentifier)")
        .accessibilityLabel(verdictLabel)   // verdict porté par la cellule, jamais par un parent
    }
}
```

`LocalAssetGrid` reprend **exactement** les colonnes et l'espacement d'`AssetMultiSelectGrid`
(`AssetMultiSelectGrid.swift:89`) — les deux grilles de sélection de l'app doivent se lire pareil ; aucune
pagination, aucun `onAppear` par cellule.

## Interactions

| Geste | Effet |
|---|---|
| Tap sur une cellule | `vm.toggle(asset.localIdentifier)` — la sélection ne déclenche **aucun** réseau |
| Tap sur une ligne d'album | `vm.clearSelection()` puis `vm.loadAssets(albumID:)` ; « All photos » ⇒ `albumID == nil` (un verdict ne suit pas le changement d'album) |
| Tap « Check » | `await vm.checkSelection()` — checksums puis **un seul** `bulkUploadCheck` par lot de `checkChunkSize` ; `reject` → `savedIDs`, sinon → `localOnlyIDs` |
| Tap « Upload » | `await vm.uploadSelection()` — n'envoie **que** `localOnlyIDs`, un asset à la fois, `uploadProgress` mis à jour à chaque asset |
| Pull-to-refresh | `await vm.loadAssets(albumID: selectedAlbumID)` + `await vm.loadRemoteSummary()` |
| Tap « Allow access » | `await vm.requestAccess()` → `photoLibrary.requestAuthorization(_:)`, puis rechargement ; libellé « Open Settings » quand le statut est `denied`/`restricted` |
| Sélection vide | La `SelectionBar` est **absente** — pas de barre à 0, `.safeAreaInset` ne réserve rien |

Pendant `.checking` et `.uploading`, les deux boutons sont `.disabled(...)` et portent le `ProgressView` :
l'état occupé est porté par le bouton, jamais par une alerte. « Upload » ne réenvoie jamais un asset
`reject` — c'est l'information achetée par la vérification.

## Liquid Glass / matériaux

Pas de `glassEffect` ici : dans ce dépôt le verre est réservé aux surfaces **flottantes** (barre de recherche,
bandeaux, îlot Live Activity) ; `StackView`, `OfflineAssetsView` et `BackupSettingsView` n'en utilisent pas.
La `SelectionBar` est ancrée par `.safeAreaInset(edge: .bottom)` sur `Color.bgSecondary` avec un filet
`Color.separatorPV` — pas de matériau translucide, pour que les vignettes ne transparaissent pas sous les
compteurs. Le reste vit sur `Color.bgPrimary`, cartes et cellules sur `Color.bgSecondary`.

## Accessibilité

- **Identifiants** — sur les éléments **interactifs ou feuilles**, jamais sur un conteneur : `localLibraryRow`
  (ligne du hub), `localAlbumRow` (en-tête de section), `localAlbumRow-<album.name>` (chaque ligne, pour lever
  l'ambiguïté d'un identifiant unique sur N lignes), `localLibrarySummary`, `localOnlyValue`, `savedValue`,
  `checkSelectionButton`, `uploadSelectionButton`, `localAssetGrid`, `localAssetCell_<localIdentifier>`.
- **Piège de conteneur (mesuré)** : un `accessibilityIdentifier` posé sur un conteneur se propage à tous ses
  descendants et **écrase** le leur (constaté sur `languageRelaunchToast`, où le bouton devenait introuvable).
  `localAssetGrid` est donc posé sur le `Text` d'en-tête de la section grille, **jamais** sur le `LazyVGrid`.
- **VoiceOver** : chaque cellule est un seul élément (`.accessibilityElement(children: .combine)`) au label
  composite : `"Photo, selected, not on the server"`, `"Video, on the server"`, `"Photo"` — verdict absent ⇒
  **aucune** mention de sauvegarde, jamais « on the server » par défaut.
- **Dynamic Type** : 3 colonnes fixes, aucun `frame(height:)` figé, aucune taille littérale — uniquement les
  tokens (`pvNumeric` pour les compteurs, `pvCaption` pour les légendes, `pvHeadline` pour les sections) ;
  cibles ≥ 44 pt (cellules à la largeur d'une colonne, deux boutons de barre basse à la moitié de la largeur).
- **Reduce Motion** : `.contentTransition(.numericText())` est neutralisé par le système ; aucune transition de
  grille, aucun `matchedGeometryEffect`.
- **Chaînes = clés anglaises** : `On this device`, `This device`, `Your server`, `Albums`, `All photos`,
  `selected`, `not on server`, `on server`, `Check`, `Upload`, `Nothing here yet`, `Not downloaded from
  iCloud`, `Allow access`, `Open Settings`, `Photo library access is off`. Aucun littéral français.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Compteurs du résumé qui changent | `.contentTransition(.numericText())` | neutralisé par le système |
| Apparition de la `SelectionBar` | `.transition(.opacity)`, `PVMotion.standard` | fondu conservé |
| Sélection d'une cellule | remplacement `circle` ⇄ `checkmark.circle.fill`, sans scale bounce | système |
| Grille → squelette | `.transition(.opacity)` sur `PVSkeletonGrid` | fondu conservé |
| Progression d'envoi | `ProgressView(value:)` déterminé, mis à jour par asset | inchangé |

Aucun morphing ni `glassEffectID` : l'écran se met à jour, il ne se transforme pas.

## Fichiers touchés

- NEW `Sources/Features/LocalLibrary/LocalLibraryView.swift` (+ `SelectionBar`, `SummaryColumn`, `AlbumRow` privés).
- NEW `Sources/Features/LocalLibrary/LocalAssetCell.swift` — la cellule, son verdict et son placeholder iCloud.
- NEW `Sources/Features/LocalLibrary/LocalAssetGrid.swift` — grille 3 colonnes, alignée sur `AssetMultiSelectGrid`.
- NEW `Sources/Features/LocalLibrary/LocalLibraryViewModel.swift` — état, énumération, vérification, envoi (spec §3-4).
- NEW `Tests/LocalLibraryViewModelTests.swift` — 8 cas nommés (spec §11).
- EDIT `Sources/Core/Protocols/PhotoLibraryService.swift` — `loadThumbnail(for:targetSize:scale:) async -> UIImage?` + `import UIKit`.
- EDIT `Sources/Services/PhotoLibraryServiceImpl.swift` — vignette : `PHImageManager` unique, `isNetworkAccessAllowed = false`.
- EDIT `Sources/DependencyContainer.swift` — `makeLocalLibraryViewModel()` près de `makeOfflineDownloadViewModel()`.
- EDIT `Sources/RootView.swift` — `@State private var localLibrary` + passage à `ProfileView` ; `ProfileView.swift` — `@State var localLibrary` + ligne `localLibraryRow` après « Offline Storage ».

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Recréer une barre de progression de backup ici.** `BackupSettingsView` porte déjà ~270 lignes de
   progression vivante (`progressSection`, `segmentBar`, `completionSummary`) et son sujet est *un run* : cet
   écran ne connaît ni run, ni file, ni deferral.
2. **Poser un identifiant d'accessibilité sur le `LazyVGrid`** : il écraserait les `localAssetCell_…` de toutes
   les cellules (piège du conteneur, mesuré sur `languageRelaunchToast`). **Déclarer un `NavigationStack` dans
   `LocalLibraryView`** : elle est poussée par `ProfileView`, qui en a un.
3. **Réutiliser `AssetMultiSelectGrid`** : typée sur `[AssetReactItem]` (`POST /api/search/metadata`), elle ne
   peut pas rendre des `PHAsset` — la grille locale est une seconde grille, avec les mêmes colonnes.
4. **Afficher un badge « sauvegardé » avant la vérification** : `isLocalOnly == nil` n'affiche rien ; confondre
   « pas de verdict » et « sur le serveur » est exactement le bug que `bulk-upload-check` évite.
5. **Déclencher un téléchargement iCloud depuis la grille, ou appeler `fetchAssets()` depuis la vue** :
   `loadThumbnail` utilise `isNetworkAccessAllowed = false`, et l'énumération est le travail du ViewModel
   (`phase == .enumerating` affiche le squelette) ; `fetchAssets()` rend la photothèque entière.
6. **Promettre une mutation PhotoKit** (supprimer, créer un album, renommer) : `PhotoLibraryService` ne sait
   que lire et `saveImage`/`saveVideo` — aucun bouton ne doit offrir ce qu'il ne peut pas tenir.
