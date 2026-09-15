# Task: app-utilities — UI Brief

> Compagnon de `.omp/app-utilities/app-utilities.specs.md` ; ne décrit que la **surface**. Arbitrage repris
> de la spec : trois écrans poussés depuis une section `Advanced` neuve du hub « Me », et le dépannage
> d'asset greffé sur la feuille d'infos du viewer — jamais une entrée de réglages.

## Design Philosophy

Ces surfaces sont des **instruments de diagnostic** : elles répondent à « qu'est-ce que l'app croit
savoir ? ». D'où la règle qui gouverne le fichier : **le journal technique et les réglages ne se mélangent
pas**. Le hub « Me » porte des préférences (Backup, Notifications, Storage, General) ; la section `Advanced`
ajoutée ici porte des constats, visuellement identique aux autres — aucune couleur d'alarme.

Trois conséquences. **Un journal dense se lit en colonnes** : la ligne condense le fait (niveau, message,
`method path`, horodatage) et ne devient jamais un mur de texte — le monospace est réservé au détail, pas à
la liste. **Tout identifiant est copiable** (id, checksum, chemin, entrée de journal). **L'état vide est un
état, pas un bug** : `ContentUnavailableView`, jamais une liste vide avec un compteur à 0.

## Placement dans la navigation

| Surface | Point d'entrée | `NavigationStack` |
|---|---|---|
| App Logs | `ProfileView` → `Advanced` → ligne | Non |
| Media Stats | `ProfileView` → `Advanced` → ligne | Non |
| Download Info | `ProfileView` → `Advanced` → ligne | Non |
| Asset Troubleshoot | `PhotoInfoPanel` → carte `Troubleshoot` → feuille | **Oui, local** |

- La section `Advanced` est **neuve** et s'insère **après Administration, avant Security** : les trois lignes
  restent groupées sous un seul en-tête, c'est la séparation demandée journal / réglages.
- Les trois écrans poussés **ne déclarent aucun `NavigationStack`** (règle du dépôt pour toute vue poussée
  depuis `ProfileView:24`) ; titre via `ToolbarItem(placement: .principal)` + `.navigationBarTitleDisplayMode(.inline)`.
- Le troubleshoot part de `PhotoInfoPanel`, feuille déjà empilable (quatre `@State private var present*`,
  `:18-22`) : sa feuille embarque son propre `NavigationStack`, la page upstream exigeant l'asset
  (`AssetTroubleshootPage({required this.asset})`).

## Layout

```
ProfileView                          — porte le NavigationStack
└── Section { … } header: { Text("Advanced") }
    └── NavigationLink → AppLogView ("appLogsRow") · MediaStatsView ("mediaStatsRow") · DownloadInfoView ("downloadInfoRow")
AppLogView                           (poussée, sans NavigationStack)
└── List(vm.filteredEntries)
    ├── Picker niveaux (segmenté) + .searchable(text: $vm.searchText)
    ├── AppLogRow → NavigationLink AppLogDetailView
    │   ├── Circle() 10×10 teinté par niveau        (accessibilityHidden)
    │   └── VStack(spacing: PVSpacing.s4) : Text(entry.message).lineLimit(4)
    │       + Text("at 14:02:11.318 in HTTP") .pvCaption
    ├── toolbar: ShareLink(item: vm.exportText()) · Button("Clear", systemImage: "trash")
    └── état vide → ContentUnavailableView("No logs yet")
AppLogDetailView                     (poussée)
└── ScrollView → VStack(spacing: PVSpacing.s16) : LogTextBlock("MESSAGE", entry.message),
    ("FROM", entry.category), ("DETAILS", entry.details), ("STACK TRACE", capturedStack) — si non nil
MediaStatsView → List
    ├── Section "Local" ("mediaStatsRow") — LabeledContent ("Tracked assets", vm.trackedCount) ·
    │   ("Cached offline", vm.offlineCount) · ("Offline size", vm.formattedUsage(vm.offlineBytes)) ·
    │   ("Last server check", vm.formattedLastReconciliation())
    ├── Section "Server" — LabeledContent ("Photos", vm.photos) ("mediaStatsServerPhotos") · ("Videos", vm.videos)
    │   · ("Usage", vm.formattedUsage(vm.usage)) · ("Quota", vm.formattedQuota())
    └── ProgressView (isLoading) · InlineErrorBadge + Button("Retry")
DownloadInfoView → List ("downloadInfoRow") — header: Text("\(vm.fileCount) files · \(vm.formattedTotalSize())")
    ├── ForEach(vm.files) { VStack(spacing: PVSpacing.s4) : displayName, puis fileName · cachedAt (.pvCaption)
    │   + Spacer() + Text(vm.formattedSize(info)) .pvNumeric }
    ├── Button("Clear all", role: .destructive) ("downloadInfoPurgeButton")
    └── état vide → ContentUnavailableView("No downloaded files")
PhotoInfoPanel                       (feuille existante) → InfoCard « Troubleshoot »
└── .sheet → NavigationStack { AssetTroubleshootView(vm:assetID:) } — Label("Troubleshoot", systemImage: "ladybug")
    ├── Section "Remote asset" — LabeledContent copiables : id ("assetTroubleshootChecksum") · checksum · type ·
    │   originalFileName · originalPath · ownerId · libraryId · createdAt · updatedAt · fileCreatedAt ·
    │   fileModifiedAt · width×height · duration · isTrashed · isOffline · isEdited · visibility
    ├── Section "Local" — fileName · displayName · cachedAt · size · PVStatusBadge ("Backed up" / "Not tracked")
    └── Section "Matching assets" → LabeledContent("Server copy") : duplicateRemoteAssetID, ou "Not on the server yet"
```

## Composants

Réutiliser, ne pas créer. Un seul motif privé est justifié — la ligne de journal, qui n'existe nulle part.

```swift
/// Le fait technique tient sur une ligne ; la densité vient du monospace du détail, pas de la liste.
private struct AppLogRow: View {
    let entry: AppLogEntry
    let subtitle: String                 // déjà mis en forme par le VM
    private var tint: Color {
        switch entry.level { case .info: .immichPrimary; case .warning: .immichWarning; case .severe: .immichError }
    }
    var body: some View {
        HStack(alignment: .top, spacing: PVSpacing.s12) {
            Circle().fill(tint).frame(width: 10, height: 10).padding(.top, PVSpacing.s4).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PVSpacing.s4) {
                Text(entry.message).font(.pvBody).foregroundStyle(Color.textPrimaryPV).lineLimit(4)
                Text(subtitle).font(.pvCaption).foregroundStyle(Color.textSecondaryPV).monospacedDigit()
            }
        }
        .padding(.vertical, PVSpacing.s4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.level.rawValue) \(entry.message)")
    }
}
```

Le second motif privé, `LogTextBlock(header:value:)`, enveloppe chaque bloc du détail : en-tête en
`.pvHeadline`/`textSecondaryPV`, corps `Text(value).font(.system(.caption, design: .monospaced))` — **le seul
endroit où le monospace est légitime**, une pile d'appels se lisant en chasse fixe — puis
`.textSelection(.enabled)`, fond `Color.bgSecondary` en `RoundedRectangle(cornerRadius: PVRadius.md)`, et un
`Button("Copy", systemImage: "doc.on.doc")` en `PVButtonStyle` (`.accessibilityIdentifier("copyLogBlock")`).

| Besoin | Composant existant |
|---|---|
| Barre de titre / erreur réseau | `ImmichAppBar` (`.principal`) · `InlineErrorBadge` + `Retry` |
| État de sauvegarde | `PVStatusBadge` (`.immichSuccess` / `textSecondaryPV`) |
| Boutons / états vides | `PVButtonStyle` · `ContentUnavailableView` (les deux) |
| Valeur alignée | `LabeledContent` + `Font.pvNumeric` |

Le ViewModel fournit **des chaînes déjà mises en forme** (`formattedUsage(_:)`, `formattedTotalSize()`,
`formattedSize(_:)`, `formattedLastReconciliation()`) : la vue ne formate jamais un octet ni une date.
`OfflineDownloadViewModel.formattedUsage(_:)` et `StorageStatsViewModel.format(_:)` restent les seules mises
en forme de bytes du dépôt — aucune troisième n'est introduite.

## Interactions

| Geste | Effet |
|---|---|
| Tap `App Logs` (hub) | Pousse `AppLogView` ; `.task { vm.refresh() }` snapshot le tampon |
| Picker de niveau / `.searchable` | `vm.levelFilter` (All / Info / Warning / Severe) ; filtre `path` + `message` |
| Tap sur une ligne / `Copy` | Pousse `AppLogDetailView(entry:)` ; `UIPasteboard.general.string = value` |
| Tap `Clear` (toolbar) | `vm.clear()` — tampon en mémoire seulement, donc pas de confirmation |
| `ShareLink` | `vm.exportText()` : `date \| level \| category \| method path \| status \| durationMS \| message` |
| Tap `Media Stats` / `Download Info` (hub) | `.task { await vm.load() }` : `GET /api/server/statistics` + lectures locales / `offline.cachedAssets` |
| Pull-to-refresh (les trois écrans) | journal : `vm.refresh()` ; stats et download info : `await vm.load()` (`isLoading` en garde) |
| Tap `Clear all` | `confirmationDialog` destructif → `await vm.clearAll()` |
| Tap `Troubleshoot` | Ouvre la feuille ; `.task { await vm.load(assetID: asset.id) }` |
| Appui long sur une valeur | `.contextMenu { Button("Copy") }` |
| État vide (journal) | `ContentUnavailableView("No logs yet", systemImage: "doc.text.magnifyingglass", description: Text("Requests will appear here as you use the app."))` |
| État vide (download info) | `ContentUnavailableView("No downloaded files", systemImage: "arrow.down.doc", description: Text("Assets you keep offline will be listed here."))` |
| Aucun doublon serveur | `LabeledContent("Server copy", value: "Not on the server yet")` — un fait, pas une cellule vide |

## Liquid Glass / matériaux

**Aucun `glassEffect`.** Le dépôt réserve le verre aux surfaces **flottantes** (barres de recherche, bandeaux,
îlot Live Activity) ; `StackView` et `OfflineAssetsView` n'en portent pas, et un écran de diagnostic en verre
serait le seul de son groupe. `Color.bgPrimary` (écran), `Color.bgSecondary` (blocs du détail, tuiles) et
`Color.separatorPV` suffisent. Le seul endroit où le verre serait tentant — la feuille posée sur le viewer —
est le plus coûteux : sur une photo claire, une feuille translucide rendrait les valeurs illisibles.

## Accessibilité

- **Identifiants**, posés **sur les éléments interactifs** et jamais sur un conteneur qui en contient (posé sur un conteneur, un identifiant écrase celui de tous ses descendants — mesuré sur `languageRelaunchToast`) : `appLogsRow`, `mediaStatsRow`, `downloadInfoRow`, `appLogList`, `appLogRow_<index>`, `appLogLevelPicker`, `appLogClearButton`, `appLogShareButton`, `copyLogBlock_<section>`, `mediaStatsPhotosValue`, `mediaStatsServerPhotos`, `mediaStatsRetryButton`, `downloadInfoSize_<index>`, `downloadInfoPurgeButton`, `assetTroubleshootChecksum`.
- **VoiceOver** : la ligne de journal est **un seul élément** (`.accessibilityElement(children: .combine)`)
  avec un label produit par le VM (`"warning 404 GET /api/assets/abc"`) — sinon pastille, message et sous-titre
  se liraient en trois arrêts. La pastille est `accessibilityHidden(true)` : la couleur seule ne porte rien.
- **Cibles ≥ 44 pt** : `Clear`, `Copy` et `Clear all` en pleine largeur de section. **Dynamic Type** : aucune
  `frame(height:)` figée ; le bloc monospace grandit et devient scrollable plutôt que tronqué.
- **Reduce Motion** : aucune animation introduite ici, rien à neutraliser.
- Chaînes = **clés anglaises** (`Advanced`, `App Logs`, `Media Stats`, `Download Info`, `Troubleshoot`, `Tracked assets`, `Cached offline`, `Offline size`, `Last server check`, `Photos`, `Videos`, `Usage`, `Quota`, `Server copy`, `Not on the server yet`, `No downloaded files`, `No logs yet`, `Clear`, `Copy`, `Clear all`, `Remove all downloaded files?`, `Cancel`, `Retry`, `MESSAGE`, `DETAILS`, `FROM`, `STACK TRACE`, `Backed up`, `Not tracked`) : extraction au build, aucune écriture manuelle.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Rafraîchissement du journal | remplacement de `vm.entries` (aucune animation explicite) | — |
| Blocs du détail / erreur réseau | `.transition(.opacity)`, fondu système | fondu conservé |

Ces écrans **ne s'animent pas** : ils constatent. Aucun `matchedGeometryEffect`, aucun `glassEffectID`, aucun
`contentTransition(.numericText())` — un compteur serveur qui « roule » donnerait l'illusion d'une donnée
vivante alors qu'elle vient d'un `await` ponctuel.

## Fichiers touchés

- NEW `Sources/Core/AppLog/AppLogEntry.swift` — `AppLogLevel`, `AppLogEntry`, `AppLogSink`, `NoopAppLogSink`.
- NEW `Sources/Services/AppLogStore.swift` — tampon circulaire 500, synchrone, sous `NSLock`.
- NEW `Sources/Features/AppUtilities/{AppLog,MediaStats,DownloadInfo,AssetTroubleshoot}ViewModel.swift` et
  `{AppLog,AppLogDetail,MediaStats,DownloadInfo,AssetTroubleshoot}View.swift`.
- NEW `Tests/AppLogStoreTests.swift`, `Tests/ImmichAPIClientLogTests.swift`.
- EDIT `Sources/Services/ImmichAPIClient.swift` — paramètre `log:` + journalisation dans `dispatch` /
  `dispatchUpload` (méthode, chemin, statut, durée ; jamais query/en-têtes/corps).
- EDIT `Sources/DependencyContainer.swift` — `appLog` construit avant le client + quatre `make*ViewModel()`.
- EDIT `Sources/RootView.swift` — `@State` neufs + passage à `ProfileView` et `PhotoInfoPanel`.
- EDIT `Sources/Features/Profile/ProfileView.swift` — section `Advanced` neuve, trois lignes.
- EDIT `Sources/Features/PhotoViewer/PhotoInfoPanel.swift` — carte `Troubleshoot` + feuille à stack local.

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Journaliser `request.url?.query`, `allHTTPHeaderFields` ou `httpBody`** : la query d'un lien partagé
   porte sa clé, l'en-tête le bearer et le cookie (`sendSharedLinkRaw`, `:737-761`).
2. **Poser l'`accessibilityIdentifier` sur la `List` ou sur le `VStack` de lignes** : il écraserait celui des
   lignes et des boutons (mesuré sur `languageRelaunchToast`).
3. **Déclarer un `NavigationStack` dans `AppLogView` / `MediaStatsView` / `DownloadInfoView`** : elles sont
   poussées par `ProfileView`, qui en a déjà un. Seule la feuille du troubleshoot en embarque un.
4. **Instrumenter le protocole `ImmichClient` (≈180 méthodes) au lieu de `dispatch`/`dispatchUpload`** : ce
   sont les deux seuls chemins d'egress, et un décorateur raterait toute méthode ajoutée ensuite.
5. **Recalculer une mise en forme de bytes ou de date dans la vue** :
   `OfflineDownloadViewModel.formattedUsage(_:)` et `StorageStatsViewModel.format(_:)` sont les seules du
   dépôt ; deux implémentations divergent.
6. **Relire `os.Logger` depuis le journal système** (approche B rejetée) : OSLog n'offre ni niveau applicatif
   calqué sur `LogLevel {info, warning, severe}`, ni champ `path`/`status`/`durationMS`.
7. **Ajouter une entrée `Troubleshoot` dans `Advanced`** (la page upstream exige l'asset) · **fabriquer les
   compteurs Drift du Flutter** (iOS n'a aucune base locale) · **confondre les deux « Download Info »**
   (ici le cache déjà écrit ; la file en cours appartient à `download-panel`) · **écrire un littéral
   français dans une vue** (la clé du catalogue est la chaîne anglaise).
