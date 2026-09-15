# Task: map-settings — UI Brief

> Compagnon de `.omp/map-settings/map-settings.specs.md` (écrit le 2026-09-15, écart G14b). Ce document ne décrit
> que la **surface** : placement, hiérarchie de vues, gestes, états, tokens. Ni le contrat réseau ni la
> persistance (voir la spec).

## Design Philosophy

Deux surfaces, une seule question : **« pourquoi il me manque des photos sur la carte ? »**. La feuille de
réglages y répond en amont, le **badge du filtre actif** y répond en aval — une fois la feuille fermée, sinon
l'utilisateur voit une carte clairsemée sans explication et croit à une perte de données. Rien n'est caché,
l'état filtré est visible et réversible en un tap.

Le reste est de la retenue : la feuille est un formulaire iOS natif, la carte du lieu un simple dépliage (pas
de mode, pas d'écran d'édition, pas de navigation neuve). Verre réservé aux surfaces **flottantes au-dessus
de la carte** — le seul endroit où il est légitime (cf. la capsule du spinner de `MapSegmentView`).

## Placement dans la navigation

- **Feuille de réglages** — présentée par `MapSegmentView` (`Sources/Features/Search/MapView.swift`), jamais par
  `AuthenticatedRoot`. C'est une feuille, pas un push : `NavigationStack` interdit dans `MapSettingsSheet`
  (même piège que `LanguageSettingsView`), `.presentationDetents([.medium, .large])`. Swipe-down et « Done »
  valent tous deux application du brouillon.
- **Badge du filtre actif** (`mapFilterActiveBadge`) — dans la `ZStack` de `MapSegmentView`, en haut à droite, à gauche du bouton de
  réglages. Visible **uniquement** quand `!vm.filter.isEmpty`.
- **Aperçu plein écran du lieu** — `.sheet(item:)` porté par `PhotoViewer` (propriétaire stable), pas par
  `PhotoInfoPanel` (le panneau défile et se démonte), déclenché par le tap sur la carte « Where ». La
  mini-carte ne bouge pas : elle est déjà livrée (`PhotoInfoPanel.swift:361-378`).
- Pas de ligne dans le hub « Me » : le filtre appartient au segment carte de l'onglet Recherche (sinon deux
  sources pour un même état).

## Layout

```
MapSegmentView                                  (onglet Recherche, segment Map)
└── ZStack(alignment: .top)
    ├── ClusteredMapView                      .ignoresSafeArea()
    ├── [si isLoadingPhotos || isRenderingMarkers]  capsule spinner (centre, existant)
    └── HStack (trailing) : [badge du filtre, si !vm.filter.isEmpty] · settingsButton  (les deux → feuille)

MapSettingsSheet                              .presentationDetents([.medium, .large])
└── Form (grouped natif)
    ├── Section « Map »        Picker « Appearance » .segmented `mapSettingsThemePicker` → MapTheme.allCases
    ├── Section « Markers »    « Only show favorites » · « Include archived » · « Include partners »
    ├── Section « Date range » Picker « Show » .menu → All/1 day/7 days/30 days/1 year/3 years
    │                          (relativeDays 0/1/7/30/365/1095) ; [si plage perso] « After »/« Before »
    │                          (DatePicker(.date) + ✕) ; [si invalide] InlineErrorBadge ; Button bascule
    └── Toolbar: Button « Done »              (.confirmationAction, disabled si !isValid)

AssetLocationMapSheet (présentée par PhotoViewer) : Map(position:) + Marker, interaction ACTIVÉE
                                                  (l'inverse de MiniMapView) + bouton « Done »
```

## Composants

Réutiliser, ne pas créer :

| Besoin | Composant existant |
|---|---|
| Formulaire groupé | `Form` natif + `Section` — seul écran du dépôt où `PVInputGroup` n'a pas à être monté (toggles/pickers système apportent déjà leur cellule) |
| État « filtre actif » dans la feuille de photos | `PVStatusBadge(text:color:symbol:)` avec `Color.immichPrimary` |
| Carte du lieu | `Map(position:)` SwiftUI + `Marker` (la mini-carte `MiniMapView` reste celle du panneau) |

```swift
/// Badge du filtre actif. La VUE ne compose jamais le texte : le ViewModel projette `vm.activeFilterSummary`
/// (une seule mise en forme des presets, comme `OfflineDownloadViewModel.formattedUsage(_:)`).
private var activeFilterBadge: some View {
    Button { presentSettings = true } label: {
        Label(vm.activeFilterSummary, systemImage: "line.3.horizontal.decrease.circle.fill")
            .font(.pvCaption).lineLimit(1)
            .foregroundStyle(Color.immichPrimary)
            .padding(.horizontal, PVSpacing.s12).padding(.vertical, PVSpacing.s8)
    }
    .buttonStyle(.plain)
    .background(.regularMaterial, in: Capsule())
    .accessibilityIdentifier("mapFilterActiveBadge")
}
```

```swift
/// Ligne de borne personnalisée — le ✕ est un élément interactif distinct : l'identifiant va sur lui
/// (`mapSettingsClearFrom` / `mapSettingsClearTo`), jamais sur la ligne qui le contient.
private func boundRow(_ t: LocalizedStringKey, date: Binding<Date>, onClear: @escaping () -> Void) -> some View {
    HStack(spacing: PVSpacing.s8) {
        DatePicker(t, selection: date, in: Date(timeIntervalSince1970: 0)...Date(), displayedComponents: .date)
        Button(action: onClear) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
    }
}
```

## Interactions

| Geste | Effet |
|---|---|
| Tap sur le bouton de réglages (haut-droite de la carte) | `presentSettings = true` — la feuille s'ouvre sur le filtre courant (brouillon initialisé depuis `store.filter`) |
| Tap sur le badge du filtre actif | Ouvre la **même** feuille : seul chemin de retour pour comprendre et annuler un filtre |
| Tap « Done » / swipe-down de la feuille | `onApply(draft)` puis `onClose()` → `await vm.applyFilter(draft)` ; le swipe vaut `Done` (pas d'annulation silencieuse) |
| Bascule favorites / archived / partners | Mute le brouillon : les marqueurs sont rechargés **à la fermeture**, pas à chaque bascule (pas de rafale de requêtes) |
| Choix d'un preset relatif | `draft.relativeDays = 0/1/7/30/365/1095` et efface `from`/`to` (preset et plage personnalisée s'excluent) |
| Tap « Use custom date range » | Révèle « After » / « Before », pré-remplies avec la fenêtre du preset courant (jamais vides au premier affichage) |
| Tap « Remove custom date range » | `resetTimeRange()` : `from`, `to`, `relativeDays` remis à `nil` (= « All », l'équivalent upstream) |
| Tap ✕ d'une borne | Efface **cette** borne seulement ; l'autre reste, le preset relatif reste ignoré tant qu'une borne existe |
| Borne début > borne fin | `InlineErrorBadge` (`mapSettingsRangeError`) sous les lignes, « Done » désactivé : le filtre invalide ne part jamais au réseau et n'écrit jamais dans le cache |
| Tap sur la carte « Where » du panneau d'infos (180 pt) | `onOpenLocationMap()` → `AssetLocationMapSheet`, cadrage 0,01° autour du lieu |
| Pan/zoom dans la carte plein écran | Libre (interaction activée) ; le bouton « Done » ferme sans rien écrire ni changer le filtre |

## Liquid Glass / matériaux

- Le verre est légitime **ici et seulement ici** : le bouton de réglages et le badge flottent au-dessus d'une
  carte plein écran (même famille que la capsule du spinner existante, `.regularMaterial in Capsule()`).
  Aucun `glassEffect` n'est introduit — le dépôt n'en utilise pas, et `.regularMaterial` garantit la
  lisibilité sur tuiles claires comme sombres.
- `MapSegmentView` ne pose aucun fond : la carte est le fond. Le badge reste lisible par le matériau, jamais
  par un fond opaque qui masquerait la carte.
- `MapSettingsSheet` est un `Form` natif (fonds et séparateurs système, `separatorPV` côté contenu dépôt) :
  aucun verre. `AssetLocationMapSheet` : plein écran, aucun matériau ajouté. Seul levier de thème réel du
  dépôt : `map.overrideUserInterfaceStyle = theme == .system ? .unspecified : (theme == .dark ? .dark : .light)`
  dans `MapView.swift` (`makeUIView` / `updateUIView`) — pas un filtre de couleur posé sur la carte.

## Accessibilité

- **Identifiants** — liste figée par la carte AC (`.omp/map-settings/map-settings.AC.md`), à reprendre telle
  quelle, toujours sur l'élément interactif : `mapSettingsButton` (bouton capsule de la carte),
  `mapFilterActiveBadge` (badge du filtre actif), `mapSettingsThemePicker` (le thème est un Picker segmenté à
  3 états `MapTheme`, pas un Toggle — nom employé par la carte AC : `mapSettingsThemeToggle`),
  `mapSettingsFavoritesToggle`, `mapSettingsArchivedToggle`, `mapSettingsPartnersToggle`,
  `mapSettingsRangePicker`, `mapSettingsCustomRangeButton`, `mapSettingsFromDate`, `mapSettingsToDate`,
  `mapSettingsClearFrom`, `mapSettingsClearTo`, `mapSettingsRangeError` (`InlineErrorBadge`),
  `mapSettingsDoneButton`, `mapFilterSummary` (bandeau de `MapPhotosSheet`, dans `MapView.swift`),
  `locationMapPreviewButton`, `onOpenLocationMap`, `assetLocationMap`, `assetLocationMapDoneButton`.
- **VoiceOver** : le badge est un seul élément (`accessibilityElement(children: .combine)`) dont le label est
  parlé en clair par le VM — « Filter active: last 30 days, favorites only » — jamais deux lectures
  glyphe/texte. Les ✕ portent `accessibilityLabel("Clear start date")` / `"Clear end date"` (un ✕ muet).
- **Le badge est la seule alerte d'un filtre actif** : son absence signifie « aucun filtre » — interdit de le
  remplacer par un badge « All dates » permanent qui ne distinguerait plus rien.
- **Dynamic Type** : `Form` gère les tailles d'accessibilité ; les lignes « After »/« Before » passent en pile
  (libellé puis `DatePicker`) plutôt qu'en `HStack` figé si le texte est tronqué.
- **Cibles ≥ 44 pt** : bouton de réglages et ✕ sont de vrais boutons, pas des glyphes nus.
- Chaînes = clés anglaises du catalogue (`Resources/Localizable.xcstrings`) : `Appearance`, `System`, `Light`,
  `Dark`, `Markers`, `Only show favorites`, `Include archived`, `Include partners`, `Date range`, `Show`,
  `All`, `1 day`, `7 days`, `30 days`, `1 year`, `3 years`, `After`, `Before`, `Use custom date range`,
  `Remove custom date range`, `The start date is after the end date`, `Done`, `Clear start date`, `Clear end date`.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Ouverture/fermeture de la feuille | `presentationDetents` système, aucune animation custom | système |
| Apparition du badge du filtre après application d'un filtre | `.transition(.opacity.combined(with: .scale(scale: 0.92)))`, `PVMotion.snappy` | fondu conservé |
| Total de la feuille de photos qui change | `.contentTransition(.numericText())` sur le compteur, `Font.pvNumeric` | neutralisé par le système |
| Rechargement des marqueurs | **aucune animation** : `ClusteredMapView` diffe par id + `representedCount` — animer des milliers d'annotations fait sauter la carte | — |
| Dépliage plein écran de la carte du lieu | `.sheet` système | système |

Pas de `matchedGeometryEffect` `MiniMapView` → `AssetLocationMapSheet` : hiérarchies distinctes (UIKit → SwiftUI), le morphing promettrait une continuité que le rendu ne tiendrait pas.

## Fichiers touchés

- NEW `Sources/Features/Search/MapSettingsSheet.swift` — feuille + lignes de borne + état d'édition local.
- NEW `Sources/Features/Search/MapSettingsStore.swift`, NEW `Sources/Core/Types/MapMarkerFilter.swift` — état (spec).
- NEW `Sources/Features/PhotoViewer/AssetLocationMapSheet.swift` — carte plein écran du lieu.
- EDIT `Sources/Features/Search/MapView.swift` — bouton + badge, `.sheet`, thème, bandeau dans `MapPhotosSheet`.
- EDIT `PhotoInfoPanel.swift` (`onOpenLocationMap` + `locationMapPreviewButton`) et `PhotoViewer.swift` (`.sheet(item:)`).
- EDIT `Sources/Features/Search/MapViewModel.swift`, `Sources/DependencyContainer.swift` — `applyFilter`, projection `activeFilterSummary` (spec).

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Poser l'`accessibilityIdentifier` sur la ligne de borne ou sur la `ZStack`** : mesuré sur
   `languageRelaunchToast` (le bouton devenait introuvable) et sur les tuiles de statut — l'identifiant va
   sur le `DatePicker`, le ✕ et le badge, jamais sur leur conteneur.
2. **Envelopper `MiniMapView` dans un `Button`** pour la rendre tapable : mesuré sur `AssetThumbnailCell`
   (un `Button` enveloppant une cellule casse les taps). Ici : couche transparente
   `.contentShape(Rectangle()).onTapGesture` **limitée aux 180 pt de la carte** et identifiée
   `locationMapPreviewButton`, au-dessus de la ligne « Open in Maps » / « Adjust Location » qui garde ses
   taps. `MiniMapView` elle-même ne change pas : `AssetLocationMapSheet`, à l'inverse, porte un `Marker(`
   dans un `Map(position:)` avec `latitudeDelta: 0.01` et **aucun** `isUserInteractionEnabled = false`.
3. **Déclarer un `NavigationStack` dans `MapSettingsSheet`** : c'est une feuille (précédent
   `LanguageSettingsView`) — deux barres de navigation sinon.
4. **Présenter la feuille de réglages depuis `AuthenticatedRoot`** : `RootView.swift:227-243` y présente déjà
   `MapPhotosSheet` ; deux présentations sur le même écran se sérialisent (la carte resterait sans réglages).
   Si le runtime le confirme, remonter à `RootView` avec un drapeau dédié (à trancher à l'exécution) — pas
   empiler deux `.sheet` sur `MapSegmentView`.
5. **Afficher le compteur de `MapPhotosSheet` sans le filtre actif** : « 12 photos » à côté d'une carte
   filtrée est un mensonge par omission — le bandeau `mapFilterSummary` (dans `MapView.swift`, où vit `MapPhotosSheet`) est visible dès que
   `!vm.filter.isEmpty` (`MapPhotosSheet` reçoit `let vm` non `@Bindable` : vérifier qu'il se rafraîchit
   après `applyFilter`, sinon passer à `@Bindable`).
6. **Écrire un littéral français dans une vue** : la clé du catalogue est la chaîne anglaise.
7. **Faire porter la plage par `takenAfter`/`takenBefore` ou `/api/timeline/buckets`** : aucun des deux ne
   porte de filtre de date exploitable pour la carte (spec) — seule `/api/map/markers` avec
   `fileCreatedAfter`/`fileCreatedBefore` compte. Et la borne haute doit être une **fin de journée locale** :
   `DatePicker(.date)` rend minuit, l'écrire tel quel exclut toute la journée de fin (incertitude de fuseau
   de la spec) et fait disparaître des photos de la borne choisie.
8. **Passer un tuple `(Double, Double, String?)` à `.sheet(item:)`** : `sheet(item:)` exige un
   `Identifiable` — déclarer une petite structure de requête, sans quoi la carte plein écran ne s'ouvre jamais.
9. **Autoriser l'application d'une plage invalide** (début après fin) : le garde-fou est `InlineErrorBadge` +
   « Done » désactivé ; une requête à plage inversée écrirait un cache vide et effacerait les marqueurs d'un
   filtre valide (`MapMarkerCache` n'a qu'un fichier par variante).
10. **Changer le tint des marqueurs pour « corriger » le thème** : `ClusteredMapView` tinte marqueurs et
    clusters en `.systemIndigo` (`MapView.swift:449`, `:470`) et la lisibilité du `/N` blanc sur ces pastilles
    n'est **pas** couverte par la bascule de tuiles — la vérifier visuellement dans les deux thèmes plutôt
    que d'inventer une couleur qui divergerait du rendu MapKit.
