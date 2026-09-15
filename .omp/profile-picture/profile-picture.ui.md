# Task: profile-picture — UI Brief

> Compagnon de `.omp/profile-picture/profile-picture.specs.md` (écrit le 2026-09-15). Ne pas dupliquer la
> spec : ce document ne décrit que la **surface** — placement, hiérarchie de vues, gestes, états, tokens.

## Design Philosophy

L'écran fait trois choses, dans cet ordre, et rien d'autre : **choisir → cadrer → valider**. C'est un
petit atelier, pas un second éditeur photo : deux gestes (déplacer, zoomer) sur un seul carré, une
grille de tiers empruntée à l'éditeur, et une seule action qui envoie. Tout ce qui n'est pas ce carré
(image d'origine, ratios, filtres, rotation) est hors de l'écran, parce que le serveur n'accepte qu'un
binaire et que l'avatar est rendu dans un `Circle` : seul le carré central existe visuellement.

Le second principe est la **continuité d'identité** : même avatar dans l'en-tête (120 pt), dans le
recadrage et dans la ligne du hub (40 pt) ; après envoi il change partout, sans redémarrage.

## Placement dans la navigation

- Poussée depuis **`ProfileView`** (hub « Me »), **en tête de la section `Account`** et au-dessus des
  deux `LabeledContent` Name/Email actuels (`Sources/Features/Profile/ProfileView.swift:28-34`).
  Justification : la photo de profil *est* une donnée de compte, pas un écran de bibliothèque ; l'upstream
  la place exactement là (`ProfilePictureCropRoute`, atteinte depuis la page de profil).
- `ProfilePictureView` **ne déclare aucun `NavigationStack`** : `ProfileView` en porte déjà un (l.23).
  Un second stack produit deux barres de navigation (piège déjà relevé sur `LanguageSettingsView`).
- Pas de rôle d'onglet, pas de feuille modale : écran de détail, retour natif, `dismiss()` sur annulation.
- La ligne du hub **n'est pas** un simple `Label` : elle porte l'avatar 40 pt, sans quoi elle
  promettrait une photo que l'utilisateur ne verrait nulle part avant de la publier.

## Layout

```
ProfileView (Form, section « Account », un seul NavigationStack)
└── Section « Account »
    ├── NavigationLink → ProfilePictureView            .accessibilityIdentifier("profilePictureRow")
    │   └── label: HStack(spacing: PVSpacing.s12)
    │       ├── UserAvatarCircle(user:size: 40, baseURL:token:)   → photo ou initiales
    │       └── Text("Profile Picture")                            .font(.pvBody)
    ├── LabeledContent("Name",  value: user)           (inchangés, sous la ligne)
    └── LabeledContent("Email", value: email)

ProfilePictureView                                     (poussée — AUCUN NavigationStack)
└── ScrollView
    └── VStack(spacing: PVSpacing.s24)
        ├── En-tête                                    VStack(spacing: PVSpacing.s12)
        │   ├── avatar 120 pt                          photo (AuthenticatedAsyncImage) OU initiales
        │   └── VStack(spacing: PVSpacing.s4)
        │       ├── Text("Profile Picture")            .font(.pvSubhead)
        │       └── PVStatusBadge(phase)               Saved / Uploading / Removing
        ├── État vide (aucune photo, aucun pending)    ContentUnavailableView("No profile picture", …)
        ├── Sélecteur                                  PhotosPicker(selection:, matching: .images,
        │   └── Label("Choose from Library",                        photoLibrary: .shared())
        │            systemImage: "photo.on.rectangle")
        ├── Recadrage                    (SEULEMENT si vm.pendingImage != nil)
        │   ├── GeometryReader                          VStack(spacing: PVSpacing.s8)
        │   │   ├── ZStack
        │   │   │   ├── Image(uiImage: vm.pendingImage).scaledToFit()
        │   │   │   ├── RuleOfThirdsOverlay()  sur le carré vm.cropRect
        │   │   │   └── masque assombri         Rectangle noir 0.55 hors du carré
        │   │   │       .gesture(DragGesture)  déplacement du carré, borné 0…1
        │   │   │       .gesture(MagnificationGesture)  taille du carré (zoom), borné
        │   │   └── Button("Reset")             ramène vm.cropRect au carré centré
        │   └── Aperçu avant envoi              VStack(spacing: PVSpacing.s8)
        │       ├── Circle 120 pt               rendu exact du carré qui sera envoyé
        │       └── Text("Preview")             .font(.pvCaption)
        └── Actions                                    VStack(spacing: PVSpacing.s8)
            ├── Button("Save")                  PVButtonStyle, pleine largeur
            └── Button("Remove Photo")          rôle destructif, si vm.hasPhoto seulement

Barre d'outils : ToolbarItem(placement: .principal) { ImmichAppBar(title: "Profile Picture") },
.navigationBarTitleDisplayMode(.inline). Aucun bouton « Done » dans la toolbar : les actions vivent
dans le corps, au plus près du carré qu'elles valident. Fond Color.bgPrimary ; les blocs d'actions
utilisent Color.bgSecondary.
```

- **Pendant l'envoi** (`phase == .saving`) : même corps, plus un bandeau `PVFieldSurface` contenant un
  `ProgressView()` indéterminé et `Text("Uploading photo…")` — le serveur ne renvoie aucune progression
  pour un binaire de 512×512, une barre déterminée serait un mensonge. Le formulaire entier passe en
  `.disabled(true)`, y compris le sélecteur et « Remove Photo ».
- **Attente de l'identité** (`phase == .loading`) : l'en-tête affiche le disque `avatarColor` sans
  initiales — la place est réservée, aucun saut de mise en page.

## Composants

Réutiliser, ne pas créer :

| Besoin | Composant existant |
|---|---|
| Avatars (hub 40 pt, en-tête 120 pt) | `UserAvatarCircle` — initiales aujourd'hui, photo dès l'étape 8 de la spec ; `initials(from:)` reste le repli |
| Photo authentifiée | `AuthenticatedAsyncImage(url:token:)` (`Sources/Services/AuthenticatedAsyncImage.swift:11`) |
| Grille de composition du carré | `RuleOfThirdsOverlay` (`Sources/Features/Editor/PhotoEditorView.swift:112`) — déjà utilisé par l'éditeur, `.allowsHitTesting(false)` |
| Bouton principal et bouton secondaire | `PVButtonStyle` (pleine largeur ; variante destructive pour « Remove Photo ») |
| Bandeau d'état de phase | `PVStatusBadge` (`Uploading` en `.immichWarning`, `Saved` en `.immichSuccess`) |
| Erreur non bloquante | `InlineErrorBadge` — relâché sur `vm.errorMessage`, tap → `vm.clearError()` |
| Surface des blocs d'action (bandeau d'envoi, bloc d'aperçu) | `PVFieldSurface` |
| Aucune photo du tout | `ContentUnavailableView("No profile picture", systemImage: "person.crop.circle")` |
| Barre de titre | `ImmichAppBar` dans la toolbar |

Le ViewModel fournit **l'URL déjà construite** (`vm.avatarURL`, via `ImmichAssetURL.profileImage`) et le
booléen `vm.hasPhoto` : la vue ne concatène aucun chemin et ne teste jamais `profileImagePath`.

## Interactions

| Geste | Effet |
|---|---|
| Tap sur la ligne du hub | Push de `ProfilePictureView(vm:)` — le `NavigationLink` vit dans `ProfileView` |
| Tap « Choose from Library » | `PhotosPicker` système ; au retour, `.onChange` charge la `UIImage` puis `vm.choose(_:)` |
| Photo refusée (< 128 px de petit côté) | `vm.errorMessage` renseigné, aucun recadrage affiché — l'image précédente reste en place |
| Glissement dans le carré | Déplacement : `DragGesture` → `EditPipeline.gestureRectToNormalized(_:in:)` → `vm.cropRect`, borné dans 0…1 |
| Pincement dans le carré | Zoom : `MagnificationGesture` change la **taille** du carré autour de son centre, bornes 0,25…1 en espace normalisé ; jamais de sortie du cadre image |
| Tap « Reset » | `vm.cropRect = ProfilePictureViewModel.centeredSquare(for:)` |
| Tap « Cancel » | `vm.cancelCrop()` — jette `pendingImage`, l'avatar publié reste intact |
| Tap « Save » | `await vm.save()` — rendu 512×512, envoi `POST /api/users/profile-image`, l'avatar de l'en-tête et celui du hub se mettent à jour |
| Tap « Remove Photo » | `confirmationDialog` destructif → `await vm.deletePhoto()` → retour aux initiales |
| Pull-to-refresh | `await vm.load()` — réconcilie avec `GET /api/users/me` |
| Tap sur l'`InlineErrorBadge` | `vm.clearError()` |
| État vide | `ContentUnavailableView` — pas de carré de recadrage vide empilé sous un sélecteur |

Les gestes de recadrage sont **posés sur le carré lui-même** (le `ZStack` qui le dessine), pas sur un
conteneur englobant : le reste de l'écran reste scrollable et le sélecteur cliquable. « Save » est
`.disabled(vm.pendingImage == nil || vm.phase == .saving)` — porté par le bouton, jamais par une alerte.

## Liquid Glass / matériaux

Pas de `glassEffect` sur cet écran : le verre est réservé aux surfaces **flottantes** (barres de
recherche, bandeaux, îlot Live Activity), pas aux écrans poussés du hub « Me » — `StackView`,
`OfflineAssetsView` et `LanguageSettingsView` n'en ont pas. Le masque du crop est un
`Color.black.opacity(0.55)` littéral : un crop assombrit ce qu'il exclut. Fonds `bgPrimary`/`bgSecondary`.

## Accessibilité

- **Identifiants** (sur les éléments interactifs, jamais sur un conteneur qui en contient) :
  `profilePictureRow` (ligne du hub), `profilePictureAvatar` (en-tête),
  `profilePictureChooseButton`, `profilePictureCropCanvas`, `profilePictureCropResetButton`,
  `profilePicturePreview`, `profilePictureCancelButton`, `profilePictureSaveButton`,
  `profilePictureRemoveButton`, `profilePictureUploadingIndicator`, `profilePictureErrorBadge`.
- **VoiceOver** : le carré de recadrage est un seul élément, avec un label parlant produit par le VM
  (`"Crop square, 60 percent of the image"`), pas deux lectures masque/image. L'avatar de l'en-tête
  porte `"Profile picture"` quand `hasPhoto`, `"No profile picture"` sinon.
- **Dynamic Type** : les tailles 40/120 pt sont des `frame` d'avatar, jamais des tailles de texte ; rien
  ne plafonne les polices de l'écran.
- **Cibles** ≥ 44 pt : « Save », « Remove Photo », « Choose from Library » et « Reset » sont en pleine
  largeur ; les poignées du carré sont le carré entier, jamais un liseré de 1 pt.
- **Reduce Motion** : les transitions ci-dessous se neutralisent en fondu ; les gestes de recadrage n'ont
  aucune inertie à couper.
- **Contraste** : le masque à 0.55 garde les bords de l'image lisibles sur fond clair comme sombre.
- Les chaînes sont des **clés anglaises** (`Profile Picture`, `Choose from Library`, `Preview`, `Reset`,
  `Cancel`, `Save`, `Remove Photo`, `Uploading photo…`, `No profile picture`, `Could not update profile
  picture`), jamais de littéral français.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Apparition du bloc de recadrage | `.transition(.opacity.combined(with: .scale(scale: 0.98)))`, `.easeInOut(duration: 0.2)` | fondu seul |
| Le carré suit le doigt | Aucune animation : `vm.cropRect` est écrit directement par le geste | — |
| « Reset » du carré | `withAnimation(.easeInOut(duration: 0.25))` autour de la réécriture de `cropRect` | neutre |
| Aperçu circulaire qui se met à jour | `.animation(.easeInOut(duration: 0.2), value: vm.cropRect)` sur le bloc d'aperçu | neutre |
| Bandeau d'envoi | `.transition(.opacity)` sur le `PVFieldSurface` | fondu conservé |
| Bascule photo ⇄ initiales | `.transition(.opacity)` sur le `ZStack` de l'avatar | fondu conservé |

Aucun `matchedGeometryEffect`, aucun `glassEffectID` : l'écran ne se transforme pas, il remplace une
image par une autre.

## Fichiers touchés

- NEW `Sources/Features/Profile/ProfilePictureView.swift` — l'écran : en-tête avatar, sélecteur, carré
  de recadrage, aperçu, actions.
- EDIT `Sources/Features/Profile/ProfileView.swift` — `@State var profilePicture` + la ligne
  `profilePictureRow` en tête de la section Account.
- EDIT `Sources/DesignSystem/Components/UserAvatarCircle.swift` — `baseURL`/`token` optionnels, repli
  initiales conservé.
- Voir la spec pour les fichiers non visuels : DTO, protocole `ImmichClient`, `ImmichAPIClient`,
  `ImmichAssetURL`, `ProfilePictureViewModel`, `DependencyContainer`, `RootView`, `MockImmichClient`.

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Déclarer un `NavigationStack` dans `ProfilePictureView`** : `ProfileView` en porte un
   (`ProfileView.swift:23`), le doublon affiche deux barres de navigation.
2. **Poser un `accessibilityIdentifier` sur un conteneur** (le `VStack` d'actions, le `ZStack` du carré) :
   il écrase les identifiants des boutons qu'il contient — mesuré sur `languageRelaunchToast`, où le
   bouton devenait introuvable pour XCUITest.
3. **Passer par `UIImagePickerController` ou demander l'autorisation photothèque** : `PhotosPicker`
   s'exécute hors processus et n'en a pas besoin (motif de `SharedLinkViewerView.swift:272-274`).
4. **Charger l'avatar avec `AsyncImage(url:)` et un jeton en query string** : les trois routes profil ne
   déclarent que `bearer`/`cookie`/`api_key` → 401 sur chaque avatar. `AuthenticatedAsyncImage` est le seul chargeur authentifié du dépôt.
5. **Oublier le brise-cache `?v=<profileChangedAt>`** : `ImageCache` indexe par URL ; sans `v`, une photo
   remplacée reste masquée par l'ancienne tant que le cache vit.
6. **Réécrire l'arithmétique de recadrage dans la vue** : la conversion écran → normalisé passe par
   `EditPipeline.gestureRectToNormalized(_:in:)` (`EditPipeline.swift:111`) et le carré par défaut par
   `centeredSquare(for:)`, qui reprend `PhotoEditorViewModel.setAspectRatio` (l.182-202).
7. **Laisser « Save » actif pendant `.saving`** : chaque tap relance un upload complet ; le bouton et le
   sélecteur sont désactivés tant que la phase n'est pas revenue à `.idle`.
8. **Afficher le carré de recadrage sans aperçu** : l'utilisateur ne voit pas ce que le `Circle` de
   l'avatar retiendra (recadrage circulaire du carré) — d'où le bloc `Preview` 120 pt sous le carré.
9. **Après suppression, laisser l'en-tête sur la photo** : le 204 ne renvoie rien, la vue doit retomber
   sur `UserAvatarCircle` via `hasPhoto` devenu faux, pas garder un `AuthenticatedAsyncImage` en cache.
10. **Écrire un littéral français dans la vue** : la clé du catalogue `Localizable.xcstrings` est la chaîne anglaise elle-même.
11. **Ne câbler que « Me »** : `UserAvatarCircle` a sept appelants (PhotoViewer, InvitePartnerSheet,
    AlbumDetailView, ActivityFeedSheet, AlbumShareSheet ×3) ; sans `baseURL`/`token` chez eux, la photo
    n'apparaîtrait que dans l'écran qui vient de la définir — l'utilisateur croirait l'envoi raté.
