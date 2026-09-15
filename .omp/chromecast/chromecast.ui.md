# Task: chromecast — UI Brief

> Compagnon de `.omp/chromecast/chromecast.specs.md` (écrit 2026-09-15, écart G9). Ne pas dupliquer la spec : ce document ne décrit
> que la **surface** — placement, hiérarchie de vues, gestes, états, tokens. Approche retenue : **C — AirPlay** (`AVRoutePickerView` +
> `AVRouteDetector` + `routeChangeNotification`). **Aucune surface Google Cast n'est dessinée ici** (pas de `Podfile`, pas de receiver
> app ID, pas de `POST /api/sessions`) ; la couture `CastService` est seulement dimensionnée pour l'accueillir plus tard.

## Design Philosophy

Une seule question, posée depuis le lecteur plein écran : **« puis-je envoyer ce que je regarde vers un écran, et y est-il déjà ? »**
La diffusion est un **état secondaire** du viewer, pas un mode : une **pastille discrète** dans la coiffe (même famille visuelle que
le diaporama et les détails) et une **feuille de taille moyenne** sans réglage, qui ne contient que l'état de la route et le contrôle
système.

Règle de vérité qui gouverne tout le reste : **l'app ne prétend jamais savoir ce qu'elle ne sait pas**. `AVRoutePickerView` n'expose
aucune liste d'appareils et `AVRouteDetector` ne rend que deux booléens — la feuille n'énumère donc rien, ne simule aucune
progression, et quand la photo ne peut pas partir elle le dit en une phrase au lieu de laisser un bouton actif qui ne ferait rien.

## Placement dans la navigation

- La pastille vit dans **`topBar(_:)` de `PhotoViewer`** (`Sources/Features/PhotoViewer/PhotoViewer.swift:363`), **entre le bouton
  diaporama (`:400`) et le bouton détails (`:413`)** — la coiffe est le seul endroit qui ne dépende pas du type d'asset affiché.
- **Aucun rôle d'onglet, aucune vue poussée** : `CastSheet` est une **feuille du viewer** (`.sheet(isPresented:)` attaché au corps de
  `PhotoViewer`), présentée sur l'asset courant (`localAssets[safe: selectedIndex]`, l'accès sûr déjà employé par `pager` `:331-360`).
- `CastSheet` **ne déclare aucun `NavigationStack`** : une feuille n'est pas poussée depuis le hub « Me », un stack y produirait une
  barre de navigation sans destination (piège relevé à la livraison de `LanguageSettingsView`).
- La grille n'a **pas** d'entrée de cast (« appui long → Cast » est hors périmètre) et la pastille est **masquée quand `isTrash` est vrai**.

## Layout

```
PhotoViewer (viewer plein écran)
└── topBar (3 boutons verre + le nouveau)
    ├── retour
    ├── diaporama                    :400
    ├── pastille de diffusion        ← NOUVEAU  « viewerCastButton »
    │     Image(systemName: isConnected ? "airplayvideo.circle.fill" : "airplayvideo")
    │     Color.immichPrimary si connectée · .disabled(!castService.isAvailable) · .hidden si isTrash
    └── détails                      :413

CastSheet (présenté sur l'asset courant)              .presentationDetents([.medium])
└── VStack(spacing: PVSpacing.s16)                    .background(Color.bgPrimary)
    ├── En-tête    : Text("Cast to a screen") — .font(.pvHeadline), Color.textPrimaryPV
    ├── Ligne d'état  « castStatusRow »               VStack(spacing: PVSpacing.s4)
    │   ├── Label(routeName, systemImage: "airplayvideo")  si connecté   (Color.immichPrimary)
    │   └── Text("No external screen connected")           sinon         (Color.textSecondaryPV)
    ├── Contrôle système   « castRoutePicker »
    │   RoutePickerView().frame(width: 44, height: 44)      (.disabled(!vm.isAvailable))
    ├── Tuile honnête « castImageHint »   (seulement si !vm.canCast(asset))
    │   Label("AirPlay cannot send a still photo. Use Screen Mirroring from Control Center.", systemImage: "info.circle")
    └── Bouton primaire : Button("Done") { dismiss() }
```

- **Rien d'autre dans la feuille** : pas de liste, pas de compteur, pas de bouton « Stop casting » (artefact Cast-only du client
  Flutter, `cast_dialog.dart`). Le sélecteur n'a **pas de taille intrinsèque utile** : l'appelant le contraint à 44×44.
- `CastSheet` prend `let asset: AssetReactItem` et `let service: any CastService` ; son `CastViewModel` est construit dans
  `init(asset:service:)` via `_vm = State(initialValue:)`, jamais dans `body`. La feuille ne porte que l'**asset courant du pager**,
  pas la pile : changer de photo ferme la feuille (comportement d'un `.sheet` lié à un état du viewer).

## Composants

Réutiliser, ne pas créer :

| Besoin | Composant existant |
|---|---|
| Titre de la feuille, en-tête de groupe | `Text` en `.pvHeadline` + `PVHeaderBadge` (jamais un glyphe héros) |
| État de la route (connecté / non connecté) | `PVStatusBadge` dans la ligne d'état (`.immichPrimary` / texte secondaire) |
| Erreur non bloquante (échec d'ouverture de la feuille) | `InlineErrorBadge` — pas d'`alert` pour une diffusion |
| Bouton `Done` | `PVButtonStyle` (même grammaire que `AssetTagsSheet.swift:44-52`) |
| Fond / séparateurs | `Color.bgPrimary` (feuille), `Color.bgSecondary` (tuile), `Color.separatorPV` |
| Pont UIKit | `RoutePickerView: UIViewRepresentable` — même famille que `VideoPlayerLayerContainer.swift` |

`ImmichAppBar`, `PVInputGroup`, `PVFieldSurface`, `PVGridCell`, `PVSkeletonGrid`, `UserAvatarCircle` et `ContentUnavailableView` **ne
sont pas employés** : pas d'écran du hub, pas de saisie, pas de grille, pas de liste vide à habiller (voir « Erreurs à ne pas faire »).

## Interactions

| Geste | Effet |
|---|---|
| Tap sur `viewerCastButton` (vidéo) | Présente `CastSheet` sur l'asset courant ; `vm.onAppear()` rafraîchit l'état de la route |
| Tap sur `viewerCastButton` (photo) | Même feuille, mais `vm.canCast(asset) == false` → la tuile `castImageHint` est visible |
| Tap sur `castRoutePicker` | Ouvre le **sélecteur de route du système** (Apple TV / TV AirPlay 2 / boîtiers AirPlay) et route le flux |
| Tap « iPhone » dans le sélecteur système | **Sortie de la diffusion** : la route revient au téléphone, `isConnected` repasse à faux, la pastille redevient `airplayvideo` |
| Tap sur `Done` ou glissement vers le bas | `dismiss()` + `vm.onDisappear()` |
| Play / pause / seek pendant la diffusion | Restent **locaux**, dans les contrôles du viewer : l'AirPlay n'offre aucun canal de retour |
| Rotation, pinch-zoom, pager | Inchangés — la diffusion ne capture aucun geste, la pastille est un bouton comme les autres |
| Photo affichée pendant une diffusion vidéo | La photo s'affiche **sur le téléphone** ; l'écran continue de recevoir la vidéo (la route est une propriété de la session, pas du pager) |

Aucune action destructive, donc aucune `confirmationDialog` : arrêter une diffusion n'est pas destructeur, et l'y soumettre ferait
deux gestes là où le système en demande un.

## Liquid Glass / matériaux

- La pastille de la coiffe utilise **le verre déjà employé par les trois boutons voisins** (`PhotoViewer.swift:363-437`) : mêmes
  formes, même taille, même position — aucune recette de verre nouvelle, **aucun nouveau composant DesignSystem**.
- La feuille, elle, **n'utilise pas `glassEffect`** : le verre du dépôt est réservé aux surfaces **flottantes** au-dessus d'une image
  (coiffe, barre de recherche, bandeaux). Une feuille modale a déjà son fond système ; `Color.bgPrimary` suffit et évite d'empiler
  deux translucidités derrière un `presentationDetents([.medium])`.
- **Pas de `glassEffectID`/`GlassEffectContainer`** reliant la pastille à la feuille : il n'y a pas de morphing entre un bouton de
  barre et une feuille modale présentée par le système.

## Accessibilité

- **Identifiants** — seuls les quatre que la spec pinne, posés **sur les éléments interactifs** : `viewerCastButton` (bouton de la
  coiffe), `castStatusRow` (ligne d'état), `castRoutePicker` (contrôle système), `castImageHint` (tuile photo). Ne pas en inventer
  d'autres : ces quatre-là sont la surface vérifiable par les checks AC. **Jamais d'`accessibilityIdentifier` sur un conteneur** qui
  en contient : mesuré sur `languageRelaunchToast`, où l'identifiant posé sur le `GlassEffectContainer` écrasait celui de ses enfants
  et rendait le bouton introuvable par son propre identifiant.
- **Libellés vocaux** : `.accessibilityLabel(castService.isConnected ? "Casting" : "Cast")` sur la pastille — l'état est **audible**,
  pas seulement visuel. Le `AVRoutePickerView` est un contrôle UIKit : lui donner un `.accessibilityLabel` sur le
  `UIViewRepresentable`, sinon VoiceOver annonce un élément sans nom. **VoiceOver** : `castStatusRow` est **un seul** élément
  (`accessibilityElement(children: .combine)`) — nom de route et icône ne se lisent pas en deux fois.
- **Cibles ≥ 44 pt** : pastille de la coiffe et sélecteur système (44×44). **Dynamic Type** : `Text` partout, `VStack` sans hauteur
  figée ; la tuile `castImageHint` passe sur trois lignes aux tailles d'accessibilité. **Reduce Motion** : rien à neutraliser.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Pastille : écran connecté ⇄ déconnecté | `.contentTransition(.symbolEffect(.replace))` sur `Image(systemName:)` | remplacement instantané |
| Teinte de la pastille, apparition de `castImageHint` | `.foregroundStyle(...)` par `PVMotion.standard` / `.transition(.opacity)` | fondu conservé |
| Présentation de la feuille / du sélecteur système | système — l'app n'anime rien | système |

**Aucun indicateur de progression pendant la découverte** : `AVRouteDetector` ne publie aucune progression, un `ProgressView()`
indéterminé tournerait sans jamais pouvoir s'arrêter (le spinner `isDeviceConnecting` de `cast_dialog.dart` = chemin Cast).

## Fichiers touchés

- NEW `Sources/Core/Protocols/CastService.swift` — la couture (`isAvailable`, `isConnected`, `connectedRouteName`, `supportsStillImages`).
- NEW `Sources/Services/AirPlayCastService.swift` — `AVRouteDetector` + `AVAudioSession.routeChangeNotification`.
- NEW `Sources/Features/Cast/CastViewModel.swift` (projections seules, plus `canCast(_:)`) et NEW `RoutePickerView.swift`
  (`UIViewRepresentable`, `prioritizesVideoDevices = true`), NEW `CastSheet.swift` (la feuille décrite ci-dessus).
- EDIT `Sources/Services/AVVideoPlaybackEngine.swift` — `allowsExternalPlayback` / `usesExternalPlaybackWhileExternalScreenIsActive` ;
  EDIT `Sources/DependencyContainer.swift` — `castService` + `makeCastViewModel(asset:)`.
- EDIT `Sources/Features/PhotoViewer/PhotoViewer.swift` — pastille, feuille, paramètre défaut-valué (les 7 appelants de `photoViewer(` inchangés).
- NEW `Tests/Mocks/MockCastService.swift`, NEW `Tests/CastViewModelTests.swift`.
- **Aucune** écriture dans `Resources/Localizable.xcstrings` : les six clés de l'étape 10 de la spec (clés = chaînes anglaises) sont extraites par Xcode.

## Vidéo / photo : les deux surfaces, en clair

| | Vidéo | Photo |
|---|---|---|
| Pastille | Visible et active si `isAvailable` | Visible et active (la feuille s'ouvre quand même) |
| `canCast(asset)` | `true` | `false` — AirPlay ne transporte pas d'image fixe |
| Ce qui part | **Le flux vidéo lui-même**, routé par le système ; le téléphone **reste le client HTTP** (le `Bearer` de `AVVideoPlaybackEngine.swift:37` continue de fonctionner, rien à ajouter au serveur) | **Rien.** Seul chemin : le **miroir d'écran du Centre de contrôle**, hors du contrôle de l'app |
| Affichage local | La vidéo **quitte** l'écran du téléphone (transfert, pas de duplication) ; timeline et contrôles restent locaux | La photo reste affichée sur le téléphone |
| Message | Aucun | `castImageHint` : « AirPlay cannot send a still photo. Use Screen Mirroring from Control Center. » |

« Transfert » et non « miroir » : l'AirPlay vidéo remet le flux à la route, il ne duplique pas l'écran — le téléphone n'affiche donc
plus l'image pendant la diffusion, alors que ses contrôles pilotent toujours la lecture. La spec assume que **cette fiche ne ferme pas
G9 pour la photo**, et le tableau de parité reste ouvert.

## Découverte réseau et permissions, sans jargon

- **C'est iOS qui cherche, pas l'app.** `AVRoutePickerView` ouvre le sélecteur de route du système, qui trouve lui-même les Apple TV,
  TV AirPlay 2 et boîtiers AirPlay du Wi-Fi local, et affiche sa propre mention « Recherche… » tant qu'il n'a rien trouvé. L'app
  n'énumère aucun appareil : **l'état « aucun appareil trouvé » appartient au sélecteur système**, pas à la feuille.
- **Aucune permission pour l'AirPlay.** iOS publie les routes audio/vidéo via `AVAudioSession` et ne réclame à l'app ni consentement
  réseau local ni clé `Info.plist`. Les clés des Incertitudes de la spec (`NSBonjourServices` `_googlecast._tcp`,
  `NSLocalNetworkUsageDescription`, entitlement `multicast`) appartiennent **exclusivement à l'option B**. Et **ne jamais éditer
  `Resources/Info.plist`**, généré par xcodegen depuis `info.properties` (`project.yml:33-60`).
- **Ce que l'app sait vraiment** : deux booléens. `isAvailable` (`routeDetected || multipleRoutesDetected`) = « un écran est
  joignable » → sélecteur actif. `isConnected` (port `.airPlay` dans `currentRoute.outputs`) = « la sortie est l'écran » → la ligne
  d'état affiche son nom. Pas de troisième état : il n'y a pas de troisième information.
- **Échec = message, jamais de silence.** Si le flux ne part pas (route qui tombe, écran qui refuse), ni spinner perpétuel ni bouton
  inerte : la pastille repasse à l'état déconnecté dès `routeChangeNotification`, la ligne d'état revient à « No external screen
  connected », et un échec d'ouverture de la feuille s'affiche en `InlineErrorBadge`. Rien n'est avalé.
- **Rien ne dépend d'internet** : même Wi-Fi local suffit ; c'est le routeur qui compte, pas la connexion au serveur Immich.

## Arrière-plan, et ce qui change

- **La diffusion survit au passage en arrière-plan** : la route appartient au système et le `AVPlayer` continue. L'app ne coupe
  **jamais** le cast sur `scenePhase != .active` ; il n'existe aucun chemin de code pour le faire, en ajouter un serait le bug.
- **L'observation est au niveau du processus** : `castService.startObserving()` est appelé **une fois dans l'`init` du
  `DependencyContainer`** (une seule observation pour tout le processus, comme `upload`). La feuille ne doit **pas** en être la seule
  propriétaire : sinon la fermer ou passer en arrière-plan figerait la pastille dans un état faux. `vm.onAppear()`/`vm.onDisappear()`
  sont des points de rafraîchissement idempotents, pas un cycle de vie exclusif.
- **Au retour au premier plan**, la pastille est relue à la source : `AirPlayCastService` est `@Observable` et `PhotoViewer` lit
  `castService.isConnected` dans `body` (spec, étape 8). **Aucune copie `@State` de `isConnected`**, qui ne se rafraîchirait pas.
- **La feuille se ferme** au passage en arrière-plan (comportement système) ; l'état de diffusion reste lisible sur la pastille au
  retour, sans réouverture.
- **Routeur audio** (écouteurs, casque Bluetooth) : `routeChangeNotification` est aussi émis pour eux. La pastille ne doit **pas**
  clignoter — elle ne lit que les sorties de type `.airPlay`, jamais « une route a changé ».

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **`accessibilityIdentifier` sur le conteneur de la feuille** : il écraserait ceux de ses enfants (mesuré sur `languageRelaunchToast`).
2. **Lire `AVAudioSession`/`AVRouteDetector` dans le corps de `PhotoViewer`** : état non testable dans le seul composant du dépôt qui,
   à part `client`, n'a aucune dépendance injectée (rejet de l'approche A).
3. **`ProgressView()` pour la découverte ou la connexion** : aucun signal de progression n'existe en AirPlay (spinner `cast_dialog.dart` = chemin Cast).
4. **Dessiner notre propre liste d'appareils** (donc un état vide à la `ContentUnavailableView`) : `AVRoutePickerView` n'expose aucune
   liste, `AVRouteDetector` ne rend que des booléens — toute liste affichée serait inventée.
5. **Bouton « Stop casting »** : artefact Cast-only ; en AirPlay la sortie se fait dans le sélecteur système (« iPhone »).
6. **Envoyer des commandes distantes** (play/pause/seek) : hors périmètre, les contrôles restent locaux.
7. **`NavigationStack` dans `CastSheet`** (double barre) ou **copie `@State` de `isConnected`** (pastille figée) : deux pièges d'état.
9. **Littéral français ou chaîne neuve dans la vue** : la liste de l'étape 10 de la spec est **fermée** (`Cast`, `Casting`,
   `No external screen connected`, `Cast to a screen`, `AirPlay cannot send a still photo. …`, `Done`).
10. **Ajouter les clés Bonjour / l'entitlement multicast** « pour que la découverte marche » : inutiles en AirPlay, réservés à l'option B.
11. **Pastille visible dans la corbeille** : `isTrash` vrai → pas d'action de sortie.
12. **Laisser croire qu'une photo peut partir** : c'est l'écart G9 que la spec refuse de masquer — `castImageHint` est obligatoire.
