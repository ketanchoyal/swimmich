# Task: album-sync — UI Brief

> Compagnon de `.omp/album-sync/album-sync.specs.md` (écrit le 2026-09-15). Ne pas dupliquer la spec :
> ce document ne décrit que la **surface** — placement, hiérarchie de vues, états, gestes, tokens.

## Design Philosophy

La feature n'a **pas d'écran à elle** : elle s'installe dans deux surfaces existantes — l'écran **Backup**
(`BackupSettingsView`, `Sources/Features/Upload/UploadViewModel.swift:444+`) et le générique `AlbumPickerView`.
Règle unique : **ne rien ajouter qui ressemble à un second système**. Le miroir se déclare comme les deux
autres listes d'albums (même `NavigationLink`, même `LabeledContent`, même compteur `albumCount(_:_:)`), et le
rattrapage comme le « Check server now » voisin (une `Section` : bouton, statut, footer explicatif).

Second principe : la **vérité**. Le miroir est *one-way*, ne supprime jamais rien, et la structure de l'album
serveur est **figée à la création** — la spec exclut explicitement l'autre sens (serveur→appareil, retrait
d'asset, renommage, propagation d'une suppression). La copie le dit en clair une fois, dans le footer.

## Placement dans la navigation

- Troisième `NavigationLink` de la `Section` **Albums** (`albumSection`, `UploadViewModel.swift:589-630`),
  **sous** « Albums to back up » / « Albums to skip » et **avant** le footer : la même question (« quels
  albums ? ») se lit d'un bloc.
- Nouvelle `Section` **Album mirror** dans le `Form`, **après** `albumSection` et **avant** `progressSection` :
  le réglage d'abord, le résultat ensuite. Modèle : `serverCheckSection` (`:493-525`), l'action de maintenance
  non destructive déjà en place.
- **Aucun `NavigationStack`** dans la section : `BackupSettingsView` enveloppe déjà son `Form` dans le sien
  (`UploadViewModel.swift:450`) et le picker est poussé par le `NavigationLink` — un stack de plus produirait
  deux barres (piège relevé sur `LanguageSettingsView`).
- Le `NavigationLink` pousse `AlbumPickerView(title:albums:selection:)` **inchangé** ; c'est le call site qui
  filtre les smart albums (voir Composants).

## Layout

```
BackupSettingsView                            (poussée depuis ProfileView, hub « Me »)
└── NavigationStack
    └── Form
        ├── Section { Server, User }
        ├── backupSection
        ├── albumSection                      ← MODIFIÉE
        │   ├── Picker « Back up »            (scope : all / selected / excluded)
        │   ├── NavigationLink → AlbumPickerView(« Albums to back up »)
        │   ├── NavigationLink → AlbumPickerView(« Albums to skip »)
        │   ├── NavigationLink → AlbumPickerView(« Albums to mirror »)   ← NEUF
        │   │   label: LabeledContent("Mirror into albums", value: albumCount(…, "mirrored"))
        │   └── footer  (albumSectionFooter + phrase one-way)
        ├── reorganizeSection                 ← NEUVE  (modèle : serverCheckSection)
        │   ├── LabeledContent « In albums »  → vm.albumSyncSummary   (si outcome != nil)
        │   ├── DisclosureGroup « N mirrored » (si vm.mirrorStatuses non vide)
        │   │   └── MirrorAlbumRow ×N → PVStatusBadge : Created | Merged | Mirroring | Failed
        │   ├── ProgressView(value: vm.reorganizeFraction) → currentValueLabel « 320 / 1 204 »
        │   └── Button « Reorganize into album »  .bordered, identifier backupReorganizeButton
        ├── progressSection → trackingSection → serverCheckSection → resetTrackingSection
        └── (fin du Form)

AlbumPickerView                               (inchangée, partagée par les trois liens)
└── List { lignes d'albums }  +  bouton de validation
```

- **Barre d'outils** : inchangée — `ToolbarItem(placement: .principal) { ImmichAppBar(title: "Backup") }`,
  `.navigationBarTitleDisplayMode(.inline)` (`UploadViewModel.swift:468-473`).
- **États d'un album miroir**, projection du seul état déjà produit par la spec (`resolveAlbums`, `stage`,
  `flush`), aucune donnée neuve : `Mirroring` = des assets sont dans le buffer du service ; `Merged` = album
  serveur retrouvé (mapping persisté ou fusion par nom) et ajouts réussis ; `Created` = album serveur créé
  pendant la résolution de ce run ; `Failed` = le compteur `failed` d'`AlbumSyncOutcome` a progressé pour lui.
- **États vides** : `vm.mirrorStatuses` vide → le `DisclosureGroup` n'est pas dessiné du tout (jamais une
  ligne « 0 mirrored ») ; `vm.albumSyncOutcome == nil` → aucun `LabeledContent` « In albums ».

## Composants

| Besoin | Composant existant |
|---|---|
| Lien vers le picker | `NavigationLink` + `LabeledContent` (motif des deux liens d'albums, `:603-621`) |
| Compteur d'albums | helper privé `albumCount(_:_:)` (`:629`) — « None » ou « N mirrored » |
| Statut par album lié | `PVStatusBadge(text:color:symbol:)` (`Sources/DesignSystem/Components/PVStatusBadge.swift:8-11`) |
| Erreur bloquante du rattrapage | `InlineErrorBadge(message:retry:)` (`Components/InlineErrorBadge.swift:11-13`) |
| En-tête d'écran | `ImmichAppBar` (déjà posé par l'écran, rien à refaire) |
| Barre de progression | `ProgressView(value:)` déterminé, même grammaire que `progressSection` |

```swift
// 1) Troisième lien, dans `albumSection`. Filtre smart albums fait ici, au call site : la
//    résolution les ignore (`BackupAlbum.SmartID`), la case serait un réglage sans effet.
NavigationLink {
    AlbumPickerView(title: "Albums to mirror",
                    albums: vm.albums.filter { !$0.isSmart },
                    selection: $vm.settings.syncedAlbumIDs)
} label: {
    LabeledContent("Mirror into albums", value: albumCount(vm.settings.syncedAlbumIDs, "mirrored"))
}

// 2) Ligne de statut — état déjà calculé par le VM, jamais recalculé dans la vue.
private struct MirrorAlbumRow: View {
    let name: String
    let status: MirrorStatus            // label + color + symbol fournis par le ViewModel
    var body: some View {
        HStack(spacing: PVSpacing.s8) {
            Text(name).font(.pvBody).foregroundStyle(Color.textPrimaryPV).lineLimit(1)
            Spacer(minLength: PVSpacing.s8)
            PVStatusBadge(text: status.label, color: status.color, symbol: status.symbol)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("backupMirrorAlbum_\(status.deviceAlbumID)")
    }
}

// 3) La section de rattrapage — modèle `serverCheckSection`.
@ViewBuilder
private var reorganizeSection: some View {
    Section {
        if let summary = vm.albumSyncSummary {
            LabeledContent("In albums", value: summary)   // « 412 added · 38 already there · 2 failed »
        }
        if vm.isReorganizing {
            ProgressView(value: vm.reorganizeFraction) {
                Text("Reorganizing")
            } currentValueLabel: {
                Text(vm.reorganizeProgressText).font(.pvCaption)   // « 320 / 1 204 »
                    .foregroundStyle(Color.textSecondaryPV)
            }
        }
        Button { Task { await vm.reorganizeIntoAlbums() } } label: {
            Label("Reorganize into album", systemImage: "rectangle.stack.badge.plus")
        }
        .disabled(!vm.canReorganize || vm.running || vm.isReorganizing)
        .accessibilityIdentifier("backupReorganizeButton")
    } header: { Text("Album mirror") } footer: { Text(albumMirrorFooter) }
}
```

`albumMirrorFooter` reprend `albumSectionFooter` et le complète — **une seule promesse, en clair** : « chaque
photo d'un album appareil rejoint l'album serveur de même nom. L'album est créé au premier backup puis
réutilisé tel quel : déplacer une photo dans Photos ne la déplace pas sur le serveur, et rien n'est jamais
supprimé ni renommé ici. »

## Interactions

| Geste | Effet |
|---|---|
| Tap « Mirror into albums » | Pousse `AlbumPickerView(title: "Albums to mirror", …)` — sélection écrite dans `vm.settings.syncedAlbumIDs` (persistée, clé `photoBackupSyncedAlbums`) |
| Cocher/décocher un album | Écrit l'ensemble ; décocher n'efface **rien** sur le serveur, le run suivant cesse simplement d'y ranger les nouvelles photos |
| Tap « Reorganize into album » | `await vm.reorganizeIntoAlbums()` — `entriesForReconciliation()` → `bulk-upload-check` → `PUT /albums/{id}/assets` ; aucune ré-upload |
| Rattrapage pendant un run | Impossible : bouton `.disabled(vm.running \|\| vm.isReorganizing)` — deux écrivains sur le même buffer |
| Dépliage « N mirrored » | `DisclosureGroup` (animation système) : un statut par album lié |
| Échec de résolution au run | Le backup continue — `albumMap` vide pour ce run (`?? [:]`, étape 7) ; aucun bandeau n'interrompt la sauvegarde |
| Erreur du rattrapage | `.alert` sur `vm.albumSyncError`, un seul bouton `OK` qui remet l'erreur à `nil` |
| `canReorganize == false` | Bouton grisé, jamais d'alerte : aucun album miroir, ou ledger vide (`trackedAssetCount == 0`) |

## Liquid Glass / matériaux

Pas de `glassEffect`, pas de `GlassEffectContainer`, pas de `scrollEdgeEffectStyle`. Le miroir vit dans un
`Form`, sur les fonds `Color.bgPrimary` / `bgSecondary` et les séparateurs `Color.separatorPV` : c'est le
vocabulaire des trois autres sections d'albums du même écran. Le verre reste réservé aux surfaces flottantes
(barres de recherche, bandeaux) — rien à faire dans une `Section` de réglages.

## Accessibilité

- **Identifiants** (sur les éléments interactifs, jamais sur un conteneur) : `backupReorganizeButton` (même style que le voisin `reconcileNowButton`, `:517`), `backupMirrorAlbumsRow` sur le lien du picker, `backupMirrorAlbum_<deviceAlbumID>` sur chaque ligne de statut (ligne fusionnée en un seul élément). Rien sur la `Section` ni sur le `DisclosureGroup`.
- **VoiceOver** : `MirrorAlbumRow` est un élément unique (`accessibilityElement(children: .combine)`) ; l'état se lit en une phrase — « Vacances, merged » — jamais « Vacances » puis « Merged » séparément. La progression annonce le couple déjà écrit par le VM (« 320 / 1204 »).
- **Cibles ≥ 44 pt** : le bouton occupe la ligne entière d'une `Section` de `Form` ; les albums sont des lignes de `List`. **Dynamic Type** : nom d'album en `.pvBody`, `lineLimit(1)` + `Spacer(minLength:)` pour que le badge ne soit jamais poussé hors de la ligne.
- **Chaînes** : toutes des **clés anglaises** — `Albums to mirror`, `Mirror into albums`, `Reorganize into album`, `In albums`, `Album mirror`, `Reorganizing`, `Created`, `Merged`, `Mirroring`, `Failed`, `None`, `mirrored` — jamais un littéral français dans la vue.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Compteurs (« In albums », « N mirrored ») | `.contentTransition(.numericText())` sur la valeur | neutralisé par le système |
| Badge `Mirroring` → `Merged` | `.contentTransition(.symbolEffect(.replace))` sur le symbole du badge | remplacement instantané |
| Apparition de la barre de rattrapage | `.transition(.opacity)`, `PVMotion.standard` | fondu conservé |
| Dépliage de la liste des albums | `DisclosureGroup` (système) | système |

Aucun `matchedGeometryEffect`, aucun `glassEffectID` : rien ne se transforme d'un écran à l'autre.

## Fichiers touchés

- EDIT `Sources/Features/Upload/UploadViewModel.swift` — **la surface entière** : troisième lien dans `albumSection` (`:589-630`), `reorganizeSection` dans le `Form` (`:452`), `MirrorAlbumRow` privé, `reorganizeIntoAlbums()`, `albumSyncSummary`, `albumSyncError`, `isReorganizing`, `reorganizeFraction`, `reorganizeProgressText`, `mirrorStatuses`, `canReorganize`, footer complété.
- EDIT `Sources/Services/BackupEngine.swift` — `albumSyncOutcome` publié, `reorganizeAlbums(entries:)`, `stage` après chaque upload, `flush` après `ledger.save()` : l'état que la vue lit.
- EDIT `Sources/Core/Protocols/BackupAssetSource.swift` + `Sources/Services/PhotoLibraryServiceImpl.swift` — `albumMembership(deviceAlbumIDs:)` (un fetch par album).
- NEW `Sources/Core/Protocols/AlbumSyncServicing.swift`, `Sources/Services/AlbumSyncService.swift`, `Sources/Services/AlbumSyncStore.swift` — le service et le mapping par utilisateur.
- EDIT `Sources/DependencyContainer.swift` — `albumSyncStore` + `makeAlbumSyncService()` (un seul service par processus, comme `container.upload`).
- EDIT `Tests/Mocks/MockBackupAssetSource.swift` + mock client, NEW `Tests/AlbumSyncServiceTests.swift`.
- `AlbumPickerView` : **inchangée** — le filtre smart albums est appliqué au call site.

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Déclarer un `NavigationStack` dans la nouvelle section** : `BackupSettingsView` en porte déjà un autour de son `Form` — double barre (relevé à la livraison de `LanguageSettingsView`).
2. **Poser un `accessibilityIdentifier` sur la `Section` ou le `DisclosureGroup`** : il écrase les identifiants des enfants — mesuré sur `languageRelaunchToast`, où le bouton devenait introuvable.
3. **Laisser croire à une synchronisation bidirectionnelle** : aucun libellé ne dit « sync », et le chemin du miroir n'appelle jamais `removeAssetsFromAlbum` (hors périmètre de la spec).
4. **Promettre que déplacer une photo dans Photos la déplace sur le serveur** : la structure serveur est figée à la création — c'est dans le footer, pas laissé à l'interprétation.
5. **Afficher un `ProgressView()` indéterminé** pendant le rattrapage : `reorganizeFraction` existe (entrées traitées / entrées lues du ledger), la barre doit être déterminée — même règle que le run.
6. **Proposer les smart albums dans le picker de miroir** : la résolution les ignore ; ils restent sélectionnables pour le *scope* de backup.
7. **Recalculer un compteur dans la vue** : `albumSyncSummary` et `reorganizeProgressText` sortent déjà mis en forme du VM, la vue ne concatène rien.
8. **Écrire un littéral français dans la vue** : la clé du catalogue `Localizable.xcstrings` est la chaîne anglaise, l'extraction est faite par Xcode au build.
9. **Bloquer le backup quand le miroir échoue** : une résolution ratée laisse `albumMap` vide pour le run et l'upload continue.
10. **Créer un second `AlbumSyncService`** : deux services auraient deux buffers et le second perdrait la moitié des assets du run.
