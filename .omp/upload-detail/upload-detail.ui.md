# Task: upload-detail — UI Brief

> Compagnon de `.omp/upload-detail/upload-detail.specs.md` (2026-09-15). Ce document ne décrit que la
> **surface** — placement, hiérarchie de vues, gestes, états, tokens — et ne duplique pas la spec.

## Design Philosophy

L'écran répond, **après coup**, à la question que la barre de progression efface en disparaissant :
« qu'a fait le run, asset par asset ? ». Trois listes, dans cet ordre : ce qui **attend** (iCloud,
Wi-Fi), ce qui est **passé** (nombre + volume), ce qui a **échoué** (nom, raison, taille, bouton Retry).
C'est un **compte rendu**, pas un pupitre : la seule action neuve est le retry ciblé, parce que « Retry
failed » relance aujourd'hui un scan complet de la photothèque (`UploadViewModel.swift:882` →
`runBackup(manual: true)`, spec §Hypothèses). Le vocabulaire reste celui du dépôt — tokens
`PVSpacing`/`PVRadius`/`Font.pv*`, fond `Color.bgPrimary`, cartes `Color.bgSecondary` — et la miniature
est `BackupThumbnailView` (`UploadViewModel.swift:976`), déjà réutilisable (placeholder iCloud-only).

### La frontière avec la barre de progression vivante de l'écran Backup

**`BackupSettingsView` raconte le run en cours ; `UploadDetailView` raconte ce que le run a laissé.** Les
deux lisent le **même** objet — l'`UploadViewModel` unique du process (`DependencyContainer.swift:36`,
« One VM, one run, one island ») — donc la frontière est un partage d'information, jamais une seconde
source :

| Information | Écran Backup (barre vivante) | Upload details |
|---|---|---|
| Progression **globale** | `ProgressView(value: progressFraction)` + « X of Y » | Reprise **compacte** en en-tête, même fraction, même moteur — pour que l'écran ne soit pas orphelin |
| Ligne de progression texte | `statusMessage`, propriétaire | **Jamais affichée telle quelle** : convertie en état **par asset** (`currentState`) |
| Pourcentage iCloud **par asset** | Inexistant (`statusMessage` ne porte pas de fraction) | Carte « Downloading from iCloud » : `vm.currentICloudFraction` |
| Listes par asset (retenus, échecs) | Inexistant | Sections Waiting / Failed |
| Contrôle d'exécution | Run now / Stop / reprise | **Stop seulement**, sur le même `upload.cancelBackup()` |
| Retry | « Retry failed » = rescan complet | `retryAsset(id:)` / `retryAllFailed()` = run restreint (`only:`) |

Conséquence : l'écran n'affiche **jamais deux fois la même phrase** — il ne recycle pas `statusMessage` et n'ajoute pas une seconde barre globale en gros ; il projette `currentAssetID` en état d'asset.

## Placement dans la navigation

- **Poussée depuis `BackupSettingsView`** (`Sources/Features/Upload/UploadViewModel.swift:444`) : sa
  `backupSection` (`:547`) gagne `NavigationLink { UploadDetailView(vm: detail) }` avec
  `Label("Upload details", systemImage: "list.bullet.rectangle")` et, si `vm.failedAssetCount > 0`, le
  compte. Remplace le bouton « N couldn't be backed up » (`:860-871`) qui présentait `BackupFailuresSheet`
  (`:1028`) — feuille en lecture seule recevant une **copie** du tableau (`:474-475`), donc incapable de
  suivre les assets en vol.
- `BackupSettingsView` est poussée par `ProfileView` (`ProfileView.swift:62-68`), qui porte déjà le
  `NavigationStack` (`:24`) : **aucun `NavigationStack` ici**. Pas d'onglet, pas de feuille.
- Barre : `ToolbarItem(placement: .principal) { ImmichAppBar(title: "Upload details") }` + `.navigationBarTitleDisplayMode(.inline)`, comme `SyncStatusView`.

## Layout

```
UploadDetailView(vm: UploadDetailViewModel)          (poussée depuis BackupSettingsView)
└── ScrollView
    └── VStack(spacing: PVSpacing.s16)               .padding(PVSpacing.s16)   fond Color.bgPrimary
        ├── RunHeader                                → VStack(spacing: PVSpacing.s8)
        │   ├── ProgressView(value: vm.progressFraction)      (déterminée ; cachée si !vm.isRunning)
        │   ├── HStack(spacing: PVSpacing.s12) : BackupThumbnailView(localIdentifier: vm.currentAssetID)
        │   │   + VStack(.leading, spacing: PVSpacing.s4) : Text(vm.currentStateLabel)   .pvBody
        │   │       Text(vm.currentFileName) .pvCaption .textSecondaryPV ; Text("X of Y") .pvNumeric
        │   └── Button « Stop » / « Cancelling… »             (PVButtonStyle, pleine largeur)
        ├── Section « Downloading from iCloud »  (si vm.currentICloudFraction != nil)
        │   └── Card teintée immichPrimary : Label(icloud.and.arrow.down) + ProgressView(value:) + « N% »
        ├── Section « Waiting »                  (si !vm.deferrals.isEmpty)
        │   └── ForEach(vm.deferrals) → DeferralRow : BackupThumbnailView(deferral.id) ; Text(deferral.name)
        │         .pvBody ; Label(icloud.and.arrow.down | wifi.slash) .pvCaption
        │         Text(formattedBytes(deferral.fileSize)) .pvNumeric
        │         Text("Retried automatically on the next run") .pvCaption
        ├── Section « Uploaded »                 (si vm.uploadedCount > 0)
        │   └── Card : LabeledContent("Uploaded") → "N" .pvNumeric
        │              LabeledContent(size) → formattedBytes(vm.uploadedBytes)
        ├── Section « Failed »                   (si !vm.failures.isEmpty)
        │   ├── header : Text("Failed") + Button « Retry all »
        │   └── ForEach(vm.failures) → FailureRow : BackupThumbnailView(failure.assetID) ; Text(failure.name)
        │         .pvBody ; Text(failure.reason) .pvCaption .immichError
        │         Text(formattedBytes(failure.fileSize)) .pvNumeric ; Button « Retry » (PVButtonStyle)
        └── État vide   (si vm.isEmpty : rien en vol, aucune retenue, aucun échec, rien d'envoyé)
            └── ContentUnavailableView("Nothing to upload", systemImage: "checkmark.circle",
                                       description: Text("The last backup left nothing to do."))
```

- **Pas de `LazyVStack`** (listes bornées par le run) ; **une carte par ligne** en `Color.bgSecondary`
  (`RoundedRectangle(cornerRadius: PVRadius.md, style: .continuous)`), `Color.separatorPV` seulement entre
  deux lignes d'une même section.
- **« Uploaded » est un résumé, pas une liste** : le moteur ne garde que des compteurs pour les réussites
  (`uploadedCount`, `uploadedBytes`, spec §étape 9), là où l'upstream conserve `uploadItems` pour tout le
  run.
- **Formatage** : la vue ne formate jamais un nombre — `UploadDetailViewModel.formattedBytes(_:)` (spec
  §étape 9) via `ByteCountFormatter.string(fromByteCount:countStyle: .file)`, et
  `String(localized: "Unknown size")` quand `fileSize` est `nil` (asset iCloud-only pas encore exporté).

## Composants

Réutiliser, ne pas créer :

| Besoin | Composant existant |
|---|---|
| Miniature par asset | `BackupThumbnailView(localIdentifier:)` — placeholder iCloud-only inclus, aucun chargeur `PHAsset` neuf |
| Boutons d'action | `PVButtonStyle` (`.bordered` pour Retry, `.borderedProminent` pour Stop) |
| État d'une ligne / raison d'échec | `PVStatusBadge` (`immichWarning` retenue, `immichSuccess` envoyé, `immichError` échec) et `InlineErrorBadge` |
| En-tête d'écran / état vide | `ImmichAppBar`, `ContentUnavailableView` |
| Chiffres (tailles, « X of Y ») | `Font.pvNumeric` + `.contentTransition(.numericText())` |

```swift
/// Contrat local à l'écran (déclaré dans UploadDetailView.swift).
private struct UploadAssetRow: View {
    let thumbnailID: String?      // localIdentifier Photos, nil toléré
    let name: String              // nom de fichier
    let detail: String            // raison d'échec, ou état
    let detailColor: Color        // .immichError | .textSecondaryPV
    let size: String              // déjà mis en forme par le VM (formattedBytes)
    @ViewBuilder let trailingAction: () -> some View   // Button Retry, absent sur les retenues

    // body : HStack(spacing: PVSpacing.s12) { BackupThumbnailView(localIdentifier: thumbnailID)
    //   VStack(alignment: .leading, spacing: PVSpacing.s4) { Text(name).font(.pvBody).lineLimit(1)
    //     Text(detail).font(.pvCaption).foregroundStyle(detailColor).lineLimit(2)
    //     Text(size).font(.pvNumeric).foregroundStyle(Color.textSecondaryPV) }
    //   Spacer(minLength: PVSpacing.s8) ; trailingAction() }
    //   .padding(PVSpacing.s12)
    //   .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: PVRadius.md, style: .continuous))
}
```

## Interactions

| Geste | Effet |
|---|---|
| Tap « Retry » sur une ligne d'échec | `await vm.retry(id: failure.assetID)` → `upload.retryAsset(id:)` → `engine.run(settings:manual:only: [id])`, sans réénumérer la photothèque |
| Tap « Retry all » | `await vm.retryAllFailed()` → **un seul** run restreint avec `failures.map(\.assetID)` |
| Tap « Stop » | `vm.cancel()` → `upload.cancelBackup()` ; libellé « Cancelling… » dès `vm.isCancelling` |
| Tap sur le corps d'une ligne d'échec | Rien, sauf l'entrée « already on server » (avertissement de Live Photo, l'asset est sur le serveur) qui ouvre le détail d'asset existant |
| Tap sur une ligne de retenue | Rien : une retenue n'est pas une erreur, elle se résout au run suivant |
| Pull-to-refresh | Rien — pas de `.refreshable` : les listes sont des projections du moteur en mémoire, il n'y a rien à recharger |
| Retry pendant un run | Impossible : `.disabled(vm.isRunning)` ; le moteur a sa garde `!running`, l'écran ne la contourne pas |

Retenter un asset **déjà retenu** est autorisé et sans doublon : la liste `deferrals` remplace l'entrée de même `id` (spec §étape 2).

## Liquid Glass / matériaux

Pas de `glassEffect` : le verre est réservé aux surfaces **flottantes** (barres, bandeaux, îlot Live
Activity) ; `SyncStatusView`, `StackView` et `OfflineAssetsView` n'en utilisent pas. `Color.bgSecondary`
et `Color.separatorPV` suffisent à distinguer les sections ; la carte « Downloading from iCloud » est
**teintée** (`Color.immichPrimary` à faible opacité), pas vitrée — seul accent de couleur de l'écran.

## Accessibilité

- **Identifiants** (sur les éléments interactifs, jamais sur un conteneur qui en contient) :
  `uploadDetailRow` (ligne de `BackupSettingsView`), `uploadDetailCancelButton`, `uploadDetailRetryAllButton`,
  `uploadDetailRetryButton_<localIdentifier>`, `uploadDetailProgress`, `uploadDetailCurrentName`,
  `uploadDetailICloudCard`, `uploadDetailUploadedValue`, `uploadDetailUploadedBytesValue`,
  `uploadDetailFailureRow_<localIdentifier>`, `uploadDetailDeferralRow_<localIdentifier>` — clé de ligne =
  `localIdentifier` Photos, pas un index.
- **VoiceOver** : chaque ligne est un élément unique (`accessibilityElement(children: .combine)`) au label
  parlant produit par le VM (« IMG_0421, export failed, 12 megabytes »), jamais miniature, nom, raison et
  taille lus séparément.
- **Dynamic Type** : aucune `frame(height:)` figée, `lineLimit(2)` sur la raison et la mention des retenues ;
  cibles ≥ 44 pt (boutons « Retry » et « Stop » pleine largeur dans leur carte).
- **Reduce Motion** : seuls `.numericText()` et un `.transition(.opacity)` sont utilisés, tous deux
  neutralisés par le système.
- **Clés anglaises** : `Upload details`, `Downloading from iCloud`, `Waiting`, `Uploaded`, `Failed`,
  `Retry`, `Retry all`, `Stop`, `Cancelling…`, `Unknown size`, `Retried automatically on the next run`,
  `Nothing to upload`, `already on server`.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Compteurs (« X of Y », tailles) | `.contentTransition(.numericText())` | neutralisé par le système |
| Barre globale / fraction iCloud | `ProgressView(value:)`, jamais indéterminée | barre conservée |
| Apparition d'une ligne pendant le run | `.transition(.opacity)`, `PVMotion.standard` | fondu conservé |
| Bascule Stop ⇄ Cancelling… | `.contentTransition(.symbolEffect(.replace))` sur l'icône | remplacement instantané |

Aucun morphing, aucun `matchedGeometryEffect`, aucun `glassEffectID`, aucun squelette : l'upstream fige
trois emplacements (`_maxSlots = 3`, `_buildPlaceholderCard`), mais l'engine iOS n'expose qu'**un** asset
courant (`currentFileName`/`currentAssetID`) — une seule carte en vol, pas de placeholder.

## Fichiers touchés

- NEW `Sources/Features/UploadDetail/UploadDetailView.swift` — l'écran et `UploadAssetRow`.
- NEW `Sources/Features/UploadDetail/UploadDetailViewModel.swift` — projections calculées (voir la spec).
- NEW `Tests/UploadDetailViewModelTests.swift` — 8 cas nommés.
- EDIT `Sources/Features/Upload/UploadViewModel.swift` — `retryAsset(id:)`, `retryAllFailed()`,
  `failedAssetCount`, recâblage de `completionSummary` (`:882`), suppression de `BackupFailuresSheet`
  (`:1028`) et `showFailuresSheet` (`:210`), paramètre `detail` sur `BackupSettingsView` (`:444`).
- EDIT `Sources/DependencyContainer.swift` — `makeUploadDetailViewModel(upload:)`.
- EDIT `Sources/RootView.swift` — `@State private var uploadDetail` (`:97`) + passage à `ProfileView`.
- EDIT `Sources/Features/Profile/ProfileView.swift` — `@State var uploadDetail` (`:13`) + passage à
  `BackupSettingsView` (`:62-68`).

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Construire un second `BackupEngine`** : `DependencyContainer.swift:28-35` décrit la conséquence — deux gardes `!running` indépendantes (double téléchargement iCloud) et un `engine.onProgressUpdate` unique que le premier run à finir coupe sous l'autre. Ici on **compose** `container.upload`.
2. **Recycler `statusMessage` en sous-titre** : la même phrase s'afficherait sur les deux écrans ; elle reste la propriété de `BackupSettingsView`, on projette `currentState`.
3. **Déclarer un `NavigationStack`** : la vue est poussée par `BackupSettingsView`, elle-même poussée par `ProfileView`, qui en porte un (`ProfileView.swift:24`) — deux barres de navigation sinon.
4. **Poser un identifiant sur le conteneur de lignes** : il écraserait ceux des boutons `Retry` par ligne (mesuré sur `languageRelaunchToast`).
5. **Afficher un pourcentage d'upload par asset** : `ImmichClient.uploadAsset` (`ImmichClient.swift:264-276`) n'expose aucun callback de progression — seul un `ProgressView()` indéterminé est honnête. Le pourcentage n'existe que pour la descente iCloud.
6. **Afficher un débit réseau** : aucun équivalent de `networkSpeedAsString` côté iOS (`grep -rn "networkSpeed" Sources/` ne renvoie rien).
7. **Relancer les échecs par `runBackup(manual: true)`** : cela réénumère toute la photothèque (`BackupEngine.swift:235`) ; le retry passe par `only:`.
8. **Recalculer une mise en forme de taille dans la vue** : une seule implémentation de bytes existe (`OfflineDownloadViewModel.formattedUsage(_:)`) ; ici `formattedBytes(_:)`.
9. **Écrire un littéral français dans la vue** : la clé du catalogue est la chaîne anglaise.
10. **Garder `BackupFailuresSheet` en plus de la page** : deux vocabulaires pour la même information (même `name`, même `reason`) ; la page est un sur-ensemble strict — feuille supprimée, le bouton « N couldn't be backed up » devient la navigation.
11. **Rendre toutes les lignes d'échec tapables** : seule l'entrée « already on server » (avertissement de Live Photo, `BackupEngine.swift:597`) a un écran de destination.
12. **Promettre une liste par asset pour les réussites** : le moteur ne garde que `uploadedCount` et `uploadedBytes` ; « Uploaded » reste un résumé.
