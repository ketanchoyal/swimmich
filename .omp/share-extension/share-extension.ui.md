# Task: share-extension — UI Brief

> Compagnon de `.omp/share-extension/share-extension.specs.md` (écrit le 2026-09-15). Ne pas dupliquer la spec :
> ce document ne décrit que la **surface** — placement, hiérarchie de vues, gestes, états, tokens.

## Design Philosophy

Ce n'est **pas un écran de l'app** : c'est une surface système, ouverte depuis Photos/Messages/Safari, qui doit
répondre en une seconde et demie à trois questions — *qu'ai-je envoyé ici ?*, *dans quel album ?*, *est-ce que ça
part ?*. L'utilisateur ne voit à cet instant ni la barre d'onglets, ni son contexte de navigation habituel : la
feuille vit dans **un processus séparé** et ne peut rien supposer de l'app (elle s'ouvre même si l'app est fermée).

La **hauteur est réduite et non négociable** — c'est le conteneur hôte qui décide, pas nous : pas de
`presentationDetents` — et **il n'y a pas de navigation profonde** : rien n'est poussé, le sélecteur d'album est un
`Picker` en ligne, jamais une seconde page.

La cohérence avec l'app passe par les **tokens du DesignSystem**, pas par du code partagé : la cible ne compile que
`Sources/ImmichSharedKit` (approche B rejetée dans la spec), elle n'importe donc ni `ImmichAppBar` ni
`Sources/Features/**`. Sur ce qui est importable — `Color.bgSecondary`, `Color.separatorPV`, `Font.pvSubhead`,
`PVSpacing`, `PVRadius` — l'extension se comporte exactement comme l'app ; pour le reste elle reproduit la
grammaire visuelle (ligne = vignette + nom + état à droite) sans l'inventer une seconde fois.

## Placement dans la navigation

- **Hors navigation.** Aucune destination de `RootView`, aucune entrée de `DependencyContainer`, aucun
  `NavigationStack` : la surface est montée par `ShareViewController` dans un
  `UIHostingController(rootView: ShareConfirmationView(viewModel:))` (racine de composition = étape 12 de la spec).
- **Jamais de `NavigationStack` dans l'extension** : un stack y produit un espace mort sous le chrome de l'hôte,
  pour un contenu qui n'a qu'un niveau.
- **Aucun retour vers l'app** : une extension `com.apple.share-services` ne peut pas appeler `UIApplication.open`.
  Le cas « session absente » ne peut donc pas « ouvrir l'app » ; il explique quoi faire (Layout §4bis).
- Racine de la cible : `ImmichShareExtension`, point d'extension `com.apple.share-services`,
  `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).ShareViewController`.

## Layout

```
ShareViewController                        (UIViewController, cible ImmichShareExtension)
└── UIHostingController
    └── ShareConfirmationView              (stateless ; reçoit le VM en @Bindable)
        └── VStack(spacing: PVSpacing.s0)
            ├── 1. En-tête compact   → VStack(alignment: .leading, spacing: PVSpacing.s2)
            │   ├── HStack : Text("Immich") .font(.pvHeadline) + Spacer() + Button("Cancel")
            │   ├── Text(vm.headerTitle)   → « Upload 3 items »          .font(.pvBody)
            │   └── Text(vm.serverLabel)   → « Millian · photos.local »  .font(.pvCaption)
            ├── Divider()                  → Color.separatorPV
            ├── 2. Fichiers reçus    → ScrollView + LazyVStack(spacing: PVSpacing.s0)
            │   └── for item in vm.items   → ShareItemRow (1 ligne, hauteur variable)
            │       ├── Leading : AssetThumbnailCell (image) | Image(systemName: "video") (vidéo)
            │       ├── Middle  : Text(item.filename) .font(.pvSubhead).lineLimit(1)
            │       │             Text(item.byteCountText) .font(.pvCaption)
            │       └── Trailing: ShareItemStatusIndicator(status: item.status)
            ├── 3. Choix d'album     → HStack(spacing: PVSpacing.s8)
            │   ├── Text("Album") .font(.pvBody)
            │   └── Picker(selection: $vm.selectedAlbumId) { Text("None") + albums }.pickerStyle(.menu)
            ├── 4. Erreur éventuelle → InlineErrorBadge(vm.errorMessage)   (si non nil)
            └── 5. Barre d'action    → HStack(spacing: PVSpacing.s8), fond Color.bgSecondary
                ├── Button("Cancel")                → PVButtonStyle → cancelRequest
                └── Button(vm.primaryActionTitle)   → pleine largeur, .disabled(!vm.canUpload)
```

**§4bis — branche « session absente »**, racine alternative quand `WidgetSessionStore().load()` est nil :
`ContentUnavailableView("Sign in to Immich", systemImage: "person.crop.circle.badge.exclamationmark",
description: Text("Open the Immich app, sign in, then share again."))` puis un `Button("Close")` en
`PVButtonStyle` qui appelle `cancelRequest`. L'utilisateur est renvoyé vers l'app **par une consigne explicite et
une sortie propre**, jamais par un appel programmatique illégal.

- **Fond** : `Color.bgPrimary` pour la surface, `Color.bgSecondary` pour l'en-tête et la barre d'action.
- **Hauteur réduite** : la liste est la seule zone extensible ; en-tête, album et barre d'action sont **fixes**. Un
  partage de 30 items ne doit jamais pousser « Upload » hors de l'écran.

## Composants

Tokens du DesignSystem et composants autorisés ; le kit partagé ne contenant aucune vue, les pièces ci-dessous sont
des `private struct` **de `ShareConfirmationView.swift`**.

| Besoin | Composant / token |
|---|---|
| Titre, compte d'items | `Text(vm.headerTitle)` en `Font.pvBody`, chaîne composée par le VM |
| Vignette / icône de média | `AssetThumbnailCell` (image) ; `Image(systemName: "video")` en `.font(.pvHeadline)` (vidéo) |
| État par ligne | `ShareItemStatusIndicator` (ci-dessous) |
| État global d'un envoi | `PVStatusBadge` (`.immichSuccess` / `.immichWarning` / `.immichError`) |
| Erreur non bloquante | `InlineErrorBadge` |
| État sans session | `ContentUnavailableView` |
| Boutons | `PVButtonStyle` — porte déjà `immichPrimary` et `PVRadius.control` |

```swift
/// Miroir exact des quatre états de `ShareItemStatus` (spec, étape 9).
private struct ShareItemStatusIndicator: View {
    let status: ShareItemStatus
    var body: some View {
        switch status {
        case .enqueued: Image(systemName: "clock").foregroundStyle(Color.textSecondaryPV)
        case .running:  ProgressView(value: status.fraction)     // déterminée : la fraction existe
            .progressViewStyle(.circular).frame(width: PVSpacing.s16, height: PVSpacing.s16)
        case .complete: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.immichSuccess)
        case .failed:   Image(systemName: "exclamationmark.triangle").foregroundStyle(Color.immichError)
        }
    }
}

L'en-tête compact (`ShareHeader`) suit la même règle : titre en `Font.pvHeadline`, compte en `Font.pvBody`, et
`serverLabel` en `Font.pvCaption` — c'est l'extension qui le dessine, l'hôte ne fournit aucun chrome. Le VM fournit
**des chaînes déjà composées** (`vm.headerTitle`, `item.byteCountText`) : la vue ne formate ni nombre, ni taille, ni
date — la spec interdit une seconde mise en forme de bytes à côté de celle de `BackupEngine`.

## Interactions

| Geste | Effet |
|---|---|
| Tap sur une ligne | `vm.toggle(item.id)` — un item décoché n'est pas envoyé et reste `enqueued` |
| Tap sur le `Picker` d'album | Menu système ; « None » ⇒ `selectedAlbumId = nil` (aucun `PUT /albums/{id}/assets`) |
| Tap « Upload n items » | `await vm.uploadAll()` ; titre → « {envoyés}/{total} », bouton `.disabled(true)` |
| Tap « Cancel » (envoi en cours ou au repos) | `cancel()` puis `extensionContext?.cancelRequest(withError:)` — les uploads en vol sont abandonnés, sans reprise (hors périmètre) |
| Fin d'envoi (tous `complete`/`failed`) | `addAssets(_:toAlbum:)` si un album est choisi ; « Done » → `completeRequest(returningItems: nil)` |
| Échec partiel (2 réussis, 1 en échec) | Chaque ligne garde son état, `PVStatusBadge` → `.immichWarning`, le bouton redevient « Upload 1 item » **pour les seuls échecs** — jamais un « réessayer tout » implicite |
| Échec total | `PVStatusBadge` `.immichError` + `InlineErrorBadge(vm.errorMessage)` (message serveur si connu) |
| Aucune session | Branche `ContentUnavailableView` — aucune action d'upload n'est offerte |
| Pull-to-refresh | **Aucun** : une feuille de partage n'a pas de geste de rafraîchissement |

L'état « en cours » est porté par le bouton (`.disabled(!vm.canUpload)`), jamais par une alerte bloquante.

## Liquid Glass / matériaux

Pas de `glassEffect`, aucun `GlassEffectContainer`, aucun `glassEffectID` dans cette cible : le verre est réservé
aux surfaces **flottantes** de l'app (précédent cité dans `sync-status.ui.md`), et l'extension ne peut de toute
façon pas importer les helpers de verre. `Color.separatorPV` et les fonds `bgPrimary`/`bgSecondary` suffisent ; du
verre sur une feuille déjà translucide casserait lisibilité et cohérence.

## Accessibilité

- **Identifiants** (sur les éléments interactifs, jamais sur un conteneur qui en contient — un identifiant de
  conteneur écrase ceux de ses descendants, piège mesuré sur `languageRelaunchToast`) :
  `shareExtensionCancelButton`, `shareExtensionDoneButton`, `shareExtensionUploadButton`,
  `shareExtensionAlbumPicker`, `shareExtensionItemRow_<index>`, `shareExtensionItemStatus_<index>`,
  `shareExtensionServerLabel`, `shareExtensionHeaderCount`, `shareExtensionErrorBadge`,
  `shareExtensionNoSessionView`, `shareExtensionNoSessionCloseButton`.
- **VoiceOver** : chaque ligne est un seul élément (`accessibilityElement(children: .combine)`), label composé par
  le VM (`"IMG_4821, 4.2 MB, uploading 35 percent"`) — jamais trois lectures vignette/nom/état. Le bouton
  principal, ancré en bas, est le dernier élément focalisable : c'est l'ordre naturel de décision.
- **Dynamic Type & cibles** : en-tête extensible sans tronquer le compte, lignes d'items à hauteur variable (aucun
  `frame(height:)` figé), bouton principal pleine largeur et lisible en tailles d'accessibilité, « Cancel » encadré
  par `PVSpacing.s16` (≥ 44 pt).
- Clés anglaises du catalogue (`String(localized:)`), réutilisées par la cible car
  `Resources/Localizable.xcstrings` y est déclaré en ressource (spec, étape 3) : `Immich`, `Cancel`, `Upload`,
  `Done`, `Album`, `None`, `Sign in to Immich`, `Open the Immich app, sign in, then share again.`

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Pourcentage d'un item | `.contentTransition(.numericText())` sur le texte de progression | neutralisé par le système |
| `running` → `complete` | `.contentTransition(.symbolEffect(.replace))` sur l'icône | remplacement instantané |
| Apparition d'`InlineErrorBadge` | `.transition(.opacity)` | fondu conservé |
| Titre « {n}/{total} » | `.contentTransition(.numericText())` | neutralisé par le système |

Aucun morphing : la feuille ne se transforme pas, elle progresse. Une animation plus longue que l'envoi d'un item
serait un défaut, pas un poli.

## Fichiers touchés

- NEW `ImmichShareExtension/ShareConfirmationView.swift` (étape 11) — l'écran, `ShareHeader`,
  `ShareItemStatusIndicator` ; `ShareItem.swift` (étape 9) ; `ShareExtensionViewModel.swift` (étape 10) ;
  `ShareViewController.swift` (étape 12) ; `Info.plist` (étape 2).
- NEW `Sources/ImmichSharedKit/SharedUploadClient.swift` (étapes 7-8), `Resources/ImmichShareExtension.entitlements`
  (étape 1), `Tests/ShareUploadClientTests.swift` + `Tests/ShareExtensionViewModelTests.swift` (étape 13).
- EDIT `project.yml` (étape 3) — cible, embarquement dans l'app, entrée dans le scheme ; `WidgetSession.swift`
  (étape 5) ; `Sources/Features/Auth/AuthViewModel.swift` (étape 6) ; `Sources/Services/MultipartBody.swift` →
  déplacé sous `Sources/ImmichSharedKit/` (étape 4).

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Déclarer un `NavigationStack` dans l'extension** : elle est montée par un `UIHostingController`, pas poussée
   par un stack ; un stack vide y produit un espace mort sous le chrome de l'hôte.
2. **Importer `ImmichAppBar` ou un composant de `Sources/Features/**`** : la cible n'embarque que
   `ImmichSharedKit` — raison même du rejet de l'approche B (`ImmichWidgets` ne dépend que du kit,
   `project.yml:111-113`). L'import échoue, ou pire, force `Sources/` entier dans une extension à mémoire serrée.
3. **Appeler `UIApplication.open` pour renvoyer vers l'app** : interdit depuis une extension ; seul
   `extensionContext.open` existe, et il n'est pas disponible pour `com.apple.share-services`. D'où la consigne +
   `cancelRequest` du cas « session absente ».
4. **Utiliser l'`URLSession` par défaut pour l'upload** : sans le délégué de confiance du kit, un Immich
   auto-hébergé à certificat auto-signé échoue à chaque requête, exactement comme dans le widget —
   `WidgetDataProvider.interactive()` existe pour ça.
5. **Afficher un `ProgressView()` indéterminé par item** : `ShareItemStatus.running` porte la fraction ; une barre
   indéterminée rend deux items en cours indiscernables.
6. **Poser un `accessibilityIdentifier` sur le `LazyVStack` des items** : il écraserait
   `shareExtensionItemRow_<index>` et `shareExtensionItemStatus_<index>` (même piège que `languageRelaunchToast`).
7. **Écrire un littéral français dans la vue** : la clé du catalogue est la chaîne anglaise
   (`String(localized: "Upload")`), jamais `"Envoyer"`.
8. **Compter sur une hauteur plein écran** : liste seule extensible, en-tête/album/action fixes — sinon « Upload »
   sort de la feuille dès le premier partage multiple.
9. **Laisser croire à une reprise après annulation** : « Cancel » abandonne les uploads en vol sans reprise ; aucun
   libellé ne doit promettre l'inverse.
