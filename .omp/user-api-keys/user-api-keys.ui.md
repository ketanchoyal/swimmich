# Task: user-api-keys — UI Brief

> Compagnon de `.omp/user-api-keys/user-api-keys.specs.md` (écart G20, écrit le 2026-09-15). Ne pas dupliquer la
> spec : ce document ne décrit que la **surface** — placement, hiérarchie de vues, gestes, états, tokens.

## Design Philosophy

L'écran dit une chose que l'app ne disait pas : **« ces clés sont les miennes, pas celles du serveur »**. La
console d'administration les montrait au même endroit que les comptes et les tâches ; ici, aucun objet
d'administration n'apparaît — pas un utilisateur, pas une bibliothèque, pas un job. La hiérarchie est celle d'une
liste de propriété : une ligne par clé, ses permissions lisibles en un coup d'œil, et deux gestes seulement.

Le second principe commande la mise en scène du secret : **un secret se lit une fois, dans l'unique alerte que
l'app consacre à un secret**. Après la fermeture, la valeur n'est plus nulle part ; le bouton `Copy` existe pour que
l'utilisateur n'ait pas à la reconstituer à la main.

## Placement dans la navigation

- Poussée depuis **`ProfileView`** (hub « Me »), **section `Management`**, en dernière ligne, **après Offline
  Storage** (`Sources/Features/Profile/ProfileView.swift:107-112`) et donc juste avant le `} header: { Text(
  "Management") }` de `:113`. Libellé `API Keys`, icône `key.horizontal`, identifiant `apiKeysRow`.
- **Pourquoi Management et non la section `Security`** (celle du `Toggle` Face ID, `:134-146`) : cette section ne
  porte qu'un garde d'accès local au téléphone (`appLockToggle`), et son footer dit ce qu'elle protège (« someone
  holding your unlocked phone »). Une clé API est un objet serveur, comme Trash ou Offline Storage ; la ranger sous
  `Security` mélangerait un verrou d'appareil et des identifiants de machine. La ligne reste en **dehors** du bloc
  `if auth.isAdmin` (`:117-125`) — c'est tout l'objet de G20.
- `UserApiKeysView` **ne déclare aucun `NavigationStack`** : `ProfileView` en porte déjà un (`:131`). Un second
  stack produit deux barres de navigation (piège relevé à la livraison de `LanguageSettingsView`, et attendu par le
  doc-comment de `OfflineAssetsView`).
- `APIKeyCreateView`, elle, **doit** déclarer un `NavigationStack` : c'est une feuille, elle n'hérite d'aucune barre
  et ses boutons `Create` / `Cancel` n'auraient pas de place.

## Layout

```
ProfileView (hub « Me »)
└── NavigationStack → Form
    ├── Section header: Text("Management")
    │   ├── … Trash, Backup, Notifications, Duplicates, People, Tags, Stacks, Partners
    │   ├── NavigationLink « Offline Storage »  arrow.down.circle   (offlineStorageRow)
    │   └── NavigationLink « API Keys »         key.horizontal      (apiKeysRow)   ← inséré ici
    ├── Section header: Text("Administration")   if auth.isAdmin — ne porte PLUS de clés API
    └── Section header: Text("Security") → Toggle « Require Face ID » (appLockToggle)

UserApiKeysView                            (poussée depuis ProfileView — AUCUN NavigationStack)
└── List
    ├── Section header: Text("Current session")            (rendue SEULEMENT si vm.myKey != nil)
    │   └── Row (apiKeysCurrentRow) : nom de la clé courante
    │       └── sous-titre : vm.permissionsSummary(myKey)   — aucune action de balayage : la ligne INFORME
    ├── Section header: Text("Your keys")
    │   ├── ForEach(vm.keys) → Row
    │   │   ├── title  : key.name                    (.font(.pvBody), Color.textPrimaryPV)
    │   │   ├── value  : vm.formattedCreatedAt(key)  (.font(.pvCaption), Color.textSecondaryPV)
    │   │   ├── detail : vm.permissionsSummary(key)  (.font(.pvCaption), Color.textTertiaryPV)
    │   │   ├── .swipeActions(edge: .trailing) → Button(role: .destructive) « Delete »  trash
    │   │   └── .swipeActions(edge: .leading)  → Button « Rotate »  arrow.triangle.2.circlepath
    │   └── si vm.keys.isEmpty && !vm.isLoading :
    │       ContentUnavailableView("No API keys yet", systemImage: "key.horizontal", description: …)
    ├── si vm.errorMessage != nil → InlineErrorBadge(vm.errorMessage)
    └── .overlay si vm.isLoading && vm.keys.isEmpty → ProgressView()  (premier chargement seulement)
    .navigationTitle("API Keys") .navigationBarTitleDisplayMode(.inline)
    .toolbar { ToolbarItem(.topBarTrailing) → Button « Create » plus  (apiKeysCreateButton) }
    .task { await vm.load(); await vm.loadMyKey() }   .refreshable { await vm.load() }

APIKeyCreateView                           (feuille, .sheet(isPresented: $showCreate))
└── NavigationStack                       (INTERNE — obligatoire pour une feuille)
    └── Form
        ├── Section → TextField("Name", text: $name)                (apiKeyNameField)
        ├── Section → Toggle("Full access", isOn: $fullAccess)      (apiKeyFullAccessToggle)
        └── si !fullAccess: une Section par catégorie de APIKeyPermission.grouped
            ├── Button « Select all » / « Deselect all » de la catégorie  (apiKeyCategoryToggle_<catégorie>)
            └── ForEach(items) → Toggle(permission)                       (apiKeyPermissionToggle_<permission>)
        └── .toolbar → Button "Cancel" (role: .cancel) · Button "Create" (apiKeyCreateConfirmButton)
```

- **Barre** : titre inline `API Keys`, bouton `Create` en `.topBarTrailing` — seul contrôle de la barre ; rotation et
  révocation vivent sur les lignes, là où l'objet est désigné. Fond : `Color.bgPrimary` via la `List` système.

## Composants

Réutiliser, ne pas créer :

| Besoin | Composant existant |
|---|---|
| En-tête de section | `Section { … } header: { Text("…") }` dans la `List` |
| Alerte du secret affiché une fois | `.alert("API Key Secret", …)` repris **textuellement** de `AdminView.swift:59-67` (`Button("Copy")` → `UIPasteboard.general.string`, `Button("OK", role: .cancel) { vm.dismissSecret() }`) |
| Erreur non bloquante | `InlineErrorBadge` (jamais une alerte modale pour un échec de chargement) |
| État vide | `ContentUnavailableView("No API keys yet", systemImage: "key.horizontal", …)` |
| Ligne du hub | `NavigationLink { … } label: { Label("API Keys", systemImage: "key.horizontal") }` |
| Bouton d'action de la feuille | `Button("Create")` / `Button("Cancel")` en barre ; `PVButtonStyle` si un bouton plein largeur est ajouté, `PVInputGroup` si le champ du nom doit s'aligner sur le reste du dépôt |

Le ViewModel fournit **des chaînes déjà mises en forme** : `vm.formattedCreatedAt(key)` et
`vm.permissionsSummary(key)`. La vue n'inspecte jamais `key.permissions` — groupement et résumé (`"Full access"`
quand `all` est présent) vivent dans `APIKeyPermission`, données pures.

## Interactions

| Geste | Effet |
|---|---|
| Tap ligne « API Keys » (hub) | Pousse `UserApiKeysView(vm: apiKeys)` — hors du bloc `if auth.isAdmin` |
| Pull-to-refresh | `await vm.load()` (recharge la liste ; ne recharge pas la ligne « Current session ») |
| Tap « Create » | `showCreate = true` → feuille `APIKeyCreateView` |
| Tap « Full access » dans la feuille | Bascule entre `["all"]` et la sélection par catégorie (les cases restent en mémoire si on revient) |
| Tap « Select all » d'une catégorie | Coche/décoche les items de cette catégorie ; l'état de la ligne reflète l'ensemble, pas un compteur partiel |
| Tap « Create » dans la feuille | `onCreate(name, fullAccess ? ["all"] : Array(selected))` ; la feuille **ne se ferme que si le retour est `true`** (nom vide → refus local) |
| Tap « Cancel » dans la feuille | `@Environment(\.dismiss)` — aucune requête |
| Balayage gauche sur une ligne de clé | Révèle « Delete » (`role: .destructive`) → pose `vm.deletionTarget` |
| Balayage droite sur une ligne de clé | Révèle « Rotate » → pose `vm.rotationTarget` |
| Confirmation « Rotate key? » | `await vm.rotate(key)` : invalide l'ancien secret immédiatement, remplit `pendingSecret`, recharge la liste |
| Confirmation « Delete key? » | `await vm.delete(key)` : `deleteAPIKey(id:)` (204 accepté tel quel), recharge la liste |
| Fermeture de l'alerte du secret | `vm.dismissSecret()` remet `pendingSecret` à `nil` — la valeur n'est plus relisible |
| Tap « Copy » | `UIPasteboard.general.string = vm.pendingSecret` — **sans fermer** l'alerte : l'utilisateur garde la valeur sous les yeux jusqu'à ce qu'il la déclare lue |
| Ligne « Current session » | Aucun geste : elle informe, elle ne se révoque pas d'ici (voir ci-dessous) |

**Le cas de la clé unique.** `GET /api-keys` renvoie la liste des clés **du porteur du jeton** ; `GET /api-keys/me`
renvoie **au singulier** la clé qui porte la requête, et peut échouer pour un appelant authentifié par session. La
surface est donc **une liste**, jamais un formulaire à clé unique — mais si le compte n'a qu'une clé, elle apparaît
**deux fois** : ligne d'information (« Current session », non balayable) et ligne propriétaire dans « Your keys »
(balayable, donc rotative et révocable) — dédoublonner retirerait le seul endroit d'où la faire tourner. Si
`loadMyKey()` échoue, la section « Current session » disparaît : pas de ligne vide, pas d'erreur.

## Liquid Glass / matériaux

Pas de `glassEffect` sur ces deux écrans. Précédent du dépôt : le verre est réservé aux surfaces **flottantes**
(barres de recherche, bandeaux, îlot Live Activity) — `StackView`, `OfflineAssetsView` et `AdminView` n'en utilisent
pas. Ici la `List` système, `Color.separatorPV` et le fond `bgPrimary` suffisent ; la feuille de création n'ajoute
aucun matériau non plus : c'est un `Form` standard.

## Accessibilité

- **Identifiants** (sur les éléments interactifs, jamais sur un conteneur qui en contient) : `apiKeysRow`,
  `apiKeysCreateButton`, `apiKeysCurrentRow`, `apiKeyNameField`, `apiKeyFullAccessToggle`,
  `apiKeyCategoryToggle_<catégorie>`, `apiKeyPermissionToggle_<permission>`, `apiKeyCreateConfirmButton`,
  `apiKeyCopySecretButton`, `apiKeyRotateConfirmButton`, `apiKeyDeleteConfirmButton`.
- **VoiceOver** : l'alerte porte le titre `API Key Secret` et son message est le secret lui-même, lu caractère par
  caractère (comportement voulu : l'utilisateur doit pouvoir le recopier à la voix). Les lignes de clé combinent nom,
  date et permissions en un seul élément (`accessibilityElement(children: .combine)`).
- **Dynamic Type** : aucun `frame(height:)` figé ; la ligne de date+permissions se replie sur plusieurs lignes aux
  tailles d'accessibilité (le sous-titre passe sous le titre).
- **Cibles** ≥ 44 pt : la rotation et la révocation sont exposées par `.swipeActions`, atteignables au rotor VoiceOver
  (« Actions ») — ne pas ajouter un second chemin qui rouvrirait le secret par un tap long.
- **Reduce Motion** : rien à neutraliser (voir Animations).
- Toutes les chaînes sont des **clés anglaises** : `API Keys`, `Current session`, `Your keys`, `No API keys yet`,
  `Create`, `Cancel`, `Delete`, `Rotate`, `Full access`, `Name`, `Rotate key?`, `Delete key?`, `The current secret
  stops working immediately. The new secret is shown once.`, `Apps using this key will stop working.`, `Unknown`.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Ligne de clé supprimée / ajoutée | animation système de la `List` (le `ForEach` sur `vm.keys` la produit seule) | système |
| Apparition de l'alerte du secret | présentation système de `.alert` | système |
| Feuille de création | présentation système de `.sheet` | système |

Aucune animation n'est écrite à la main : pas de `matchedGeometryEffect`, pas de `contentTransition`, pas de
`glassEffectID`. Le seul moment qui bouge est le retrait de la ligne après révocation, et il est produit par la
`List`.

## Fichiers touchés

- NEW `Sources/Features/UserApiKeys/UserApiKeysView.swift` — la `List`, l'alerte du secret, les deux
  `confirmationDialog` (étapes 8 à 10 de la spec).
- NEW `Sources/Features/UserApiKeys/APIKeyCreateView.swift` — la feuille et son `NavigationStack` interne.
- NEW `Sources/Features/UserApiKeys/UserApiKeysViewModel.swift` — état et actions (aucune vue).
- NEW `Sources/Core/Types/APIKeyPermission.swift` — 146 permissions, groupement par préfixe, `summary(for:)`.
- NEW `Tests/UserApiKeysViewModelTests.swift` — 8 cas nommés (voir spec).
- EDIT `Sources/Features/Profile/ProfileView.swift` — `@State var apiKeys` + ligne `apiKeysRow` dans Management.
- EDIT `Sources/RootView.swift` — `@State private var apiKeys` dans `AuthenticatedRoot` + passage à `ProfileView`.
- EDIT `Sources/DependencyContainer.swift` — `makeUserApiKeysViewModel()`.
- EDIT `Sources/Features/Admin/AdminView.swift` et `AdminViewModel.swift` — **retrait** de `apiKeysSection`, de
  l'alerte « API Key Secret » et des actions clés : la surface a déménagé, elle n'est pas dupliquée.

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Garder les clés API dans `AdminView` « pour ne pas casser l'existant »** : la section est inatteignable pour un
   non-administrateur (`ProfileView.swift:117` garde tout le bloc par `if auth.isAdmin`) et elle affichait en réalité
   les clés de l'admin lui-même — deux propriétaires du même état, c'est le bug qui suit.
2. **Réutiliser `AdminViewModel`** : son `load()` émet users + jobs + libraries en plus des clés
   (`AdminViewModel.swift:36-42`) et il expose `createUser`/`deleteUser`/`updateLibrary` à une surface non-admin.
3. **Déclarer un `NavigationStack` dans `UserApiKeysView`** : elle est poussée par `ProfileView`, qui en a un — deux
   barres de navigation. Le `NavigationStack` est en revanche obligatoire dans `APIKeyCreateView`.
4. **Poser un `accessibilityIdentifier` sur un conteneur** (le `Form` de la feuille, un `Section`) : il se propage à
   tous les descendants et écrase l'identifiant du `TextField` et des `Toggle`s (mesuré sur
   `languageRelaunchToast`, où le bouton devenait introuvable par son propre identifiant).
5. **Rendre le secret relisible** (« Show again », second écran, valeur gardée dans `keys`) : le serveur ne le
   renvoie qu'à la création et à la rotation — une surface qui promet de le remontrer ment.
6. **Deux alertes de secret distinctes** pour la création et la rotation : `pendingSecret` est unique dans le VM, et
   l'alerte unique est le point le plus sensible de l'écran — la répliquer, c'est garantir que l'une des deux
   divergera du texte (avertissement, fermeture, copie).
7. **Écrire un libellé qui dit « Secret » pour une clé existante** : le secret n'existe qu'au retour de `POST
   /api-keys` et de `POST /api-keys/{id}/rotate`. Partout ailleurs on parle d'une clé, avec un nom et des
   permissions.
8. **Inventer l'édition d'une clé** : `PUT /api-keys/{id}` est marqué déprécié et hors périmètre ; renommer se fait
   en révoquant puis recréant, et l'UI ne doit pas suggérer un formulaire d'édition qui n'existe pas.
9. **Faire croire qu'une clé API est une session** : révoquer une clé ne ferme aucune session, et gérer les
   sessions/appareils est l'écart G19 (fiche `device-sessions`). L'écran ne parle ni de « sign out device » ni de
   « session list ».
10. **Recalculer une mise en forme de date dans la vue** : `vm.formattedCreatedAt(_:)` s'appuie sur le formateur
    ISO-8601 du dépôt (`Sources/Core/Utilities/LongDateFormatter.swift`) et retombe sur `Unknown` ; deux
    implémentations de date finissent toujours par diverger.
