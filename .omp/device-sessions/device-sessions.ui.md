# Task: device-sessions — UI Brief

> Compagnon de `.omp/device-sessions/device-sessions.specs.md` (écrit le 2026-09-15, écart G19). Ne pas
> dupliquer la spec : ce document ne décrit que la **surface** — placement, hiérarchie de vues, gestes,
> états, tokens. Le producteur des chaînes est le ViewModel, pas la vue.

## Design Philosophy

Un écran de **contrôle**, pas de consultation. L'utilisateur vient y répondre à une question de sécurité :
« qui est connecté à mon compte, et comment j'en retire un ? ». Trois règles dictent la surface :

1. **La session courante n'est jamais une ligne comme les autres.** Elle ouvre la liste, porte le badge
   « This device », et n'offre **aucune** affordance de révocation (ni poubelle, ni swipe, ni menu). On ne
   se déconnecte pas soi-même par accident — le web masque la poubelle par `{#if !session.current}`.
2. **Deux destructions, deux confirmations, deux textes.** « Log out » (un appareil) et « Log out other
   devices » (N) ne partagent ni titre, ni corps, ni bouton : le second dit explicitement que **cet
   appareil reste connecté**.
3. **L'écran expose des appareils, donc rien de superflu.** Pas d'identifiant de session, pas de champ
   `isPendingSyncReset` (il appartient à la fiche sync), aucun `textSelection(.enabled)`, aucun
   `ShareLink`, aucun menu « Copy » : rien n'entre au presse-papiers depuis cet écran.

## Placement dans la navigation

- Poussée depuis **`ProfileView`** (hub « Me »), section `Security`, **immédiatement après** le
  `Toggle("Require Face ID")` (`Sources/Features/Profile/ProfileView.swift:132-137`) et avant le `footer`
  de la section : la session est un objet de sécurité, pas un réglage de bibliothèque, et le web range
  `DeviceCard` sous les réglages de sécurité du compte.
- La ligne du hub est un `NavigationLink` étiqueté `Label("Connected Devices", systemImage:
  "laptopcomputer.and.iphone")`, identifiant `deviceSessionsRow`.
- `DeviceSessionsView` **ne déclare aucun `NavigationStack`** : `ProfileView` en porte déjà un
  (`:25-26`) — un second stack produirait deux barres de navigation (piège de `LanguageSettingsView`).
- Écran de détail avec retour natif : pas de rôle d'onglet, pas de feuille pour la liste. Seul le
  déverrouillage PIN ouvre une **alerte** (pas une feuille) — un champ unique de six chiffres.

## Layout

```
DeviceSessionsView                          (poussée depuis ProfileView, aucun NavigationStack)
└── List (.insetGrouped, fond Color.bgPrimary)
    ├── Section « This device »             — header: Text("This device")
    │   └── DeviceSessionRow(vm.currentSession)
    │       ├── Image(systemName: vm.deviceSymbol(for:))    .font(.pvHeadline)
    │       ├── VStack(alignment: .leading, spacing: PVSpacing.s2)
    │       │   ├── HStack { Text(trimmedDescription)   .font(.pvSubhead)
    │       │   │           PVStatusBadge("This device", .immichSuccess, "checkmark") }
    │       │   ├── Text(vm.lastSeenText(for:))         .font(.pvCaption) .textSecondaryPV
    │       │   └── Text(vm.lastSeenAbsoluteText(for:)) .font(.pvCaption) .textTertiaryPV
    │       └── (aucun bouton, aucun swipeAction)
    ├── Section « Other devices »           — header: Text("Other devices")
    │   └── ForEach(vm.otherSessions) { DeviceSessionRow($0)
    │       ├── Image(systemName: vm.deviceSymbol(for:)) + VStack(description / last seen)
    │       ├── PVStatusBadge("Expired", .immichWarning, "clock.badge.exclamationmark")   // si isExpired
    │       └── Button(role: .destructive) { vm.requestRevoke(session) }
    │             .accessibilityIdentifier("deviceSessionRevokeButton_\(id)")
    │             .swipeActions(edge: .trailing, allowsFullSwipe: false)
    │   }
    ├── Section (erreur, seulement si vm.errorMessage != nil)
    │   └── InlineErrorBadge(vm.errorMessage)   .accessibilityIdentifier("deviceSessionsErrorBadge")
    └── (état vide) ContentUnavailableView("No connected devices", systemImage: "laptopcomputer.and.iphone",
                                            description: Text("Sign in from another device to see it here."))
```

- **Barre d'outils** (aucun titre central : la ligne du hub et le retour suffisent) :
  `ToolbarItemGroup(placement: .topBarTrailing)` → un bouton cadenas
  `Image(systemName: vm.isElevated ? "lock.open" : "lock")` (`deviceSessionsLockButton`), qui appelle
  `vm.lockCurrentSession()` si `isElevated`, sinon ouvre l'alerte de déverrouillage ; et un `Menu` « More »
  à **une seule** entrée, `Button("Log out other devices", role: .destructive)`
  (`deviceSessionsRevokeAllButton`, `.disabled(vm.otherSessions.isEmpty)`) — dans un menu, jamais à côté du
  cadenas : une action qui efface N sessions ne partage pas la rangée d'un contrôle d'état.
- `.navigationTitle("Connected Devices")`, `.navigationBarTitleDisplayMode(.inline)`.
- `.task { await vm.load() }` au premier affichage, `.refreshable { await vm.load() }` pour recharger.
- **Chargement** (`vm.isLoading && vm.sessions.isEmpty`) : deux sections de trois lignes de gabarit
  `.redacted(reason: .placeholder)` — pas `PVSkeletonGrid`, un shimmer **de grille** (D4).
- **Expiration** : `expiresAt` est optionnel (absent de `required`, sans `duration` le serveur renvoie
  `null`). Une session dont `expiresAt` est dans le passé reste listée et révocable, avec le badge
  « Expired » ; aucune ligne « Expires … » vide n'est rendue quand `expiresAt` est `nil`.
- **Version de l'app** : `appVersion` est `nullable` — la ligne de description ne compose que les
  segments non nuls (`"iOS • iPhone (v1.135.0)"`, jamais `"iOS • iPhone (v)"`).

## Composants

Réutiliser, ne pas créer (aucun nouveau composant `DesignSystem` pour cette fiche) :

| Besoin | Composant existant | Note |
|---|---|---|
| Titre de barre | `ImmichAppBar(title:)` en `ToolbarItem(placement: .principal)` | optionnel ici, l'écran est poussé |
| État d'une ligne (`This device`, `Expired`) | `PVStatusBadge(text:color:symbol:)` | `.immichSuccess` / `.immichWarning` |
| Erreur non bloquante | `InlineErrorBadge` | en tête de liste, la liste reste utilisable |
| Liste vide | `ContentUnavailableView` | jamais un `List` vide muet |
| Ligne d'appareil | `LabeledContent` / `Label` + `VStack` | structure `DeviceCard.svelte` |
| Révocation d'une ligne | `.swipeActions(edge: .trailing, allowsFullSwipe: false)` | geste, pas un bouton pleine largeur |

`DeviceSessionRow` est un `private struct` local à `DeviceSessionsView.swift` : il ne monte pas dans le
DesignSystem. Le ViewModel fournit **toutes** les chaînes déjà mises en forme (`deviceDescription(for:)`,
`lastSeenText(for:)`, `lastSeenAbsoluteText(for:)`, `deviceSymbol(for:)`, `isExpired(_:)`).

## Interactions

| Geste | Effet |
|---|---|
| Tap sur la ligne du hub (`deviceSessionsRow`) | Pousse `DeviceSessionsView` ; `GET /sessions` part au `.task`, pas à l'ouverture de l'onglet « Me » |
| Swipe trailing sur une ligne « Other devices » | Révèle « Log out » (destructif, `allowsFullSwipe: false`) → arme la confirmation |
| Tap « Log out » d'une ligne | `confirmationDialog` titré **« Log out iPhone? »** (nom de l'appareil), corps « This device will have to sign in again. », bouton « Log out » destructif → `await vm.revoke(session)` |
| Confirmation de ligne annulée | Rien n'est appelé ; `vm.pendingRevocation = nil` |
| Tap « Log out other devices » | `confirmationDialog` titré **« Log out N other devices? »**, corps « Your current device stays signed in. », bouton « Log out N devices » destructif → `await vm.revokeAllOthers()` |
| Tap sur la ligne « This device » | Rien : pas de navigation, pas de sélection, pas de menu |
| Tap bouton cadenas, `isElevated == true` | `await vm.lockCurrentSession()` — l'icône repasse à `lock`, l'accès élevé retombe |
| Tap bouton cadenas, `isElevated == false` | `alert("Unlock", isPresented: $showUnlock)` : `TextField("PIN", text: $pin)` `.keyboardType(.numberPad)`, identifiant `deviceSessionsUnlockField`, bouton « Unlock » (`deviceSessionsUnlockConfirm`) désactivé tant que `pin.count != 6` → `await vm.unlock(pinCode: pin)` |
| PIN refusé par le serveur | `vm.errorMessage` renseigné, `isElevated` reste `false`, l'alerte se referme ; le champ est vidé |
| Pull-to-refresh | `await vm.load()` |
| Échec réseau | `InlineErrorBadge` en tête de liste ; les lignes déjà chargées restent affichées et révocables |

Les deux confirmations sont **distinctes** : titre (nom d'appareil vs nombre), corps, et bouton différent —
et seule la seconde affirme que la session courante survit. Une confirmation unique réutilisée pour les
deux gestes ferait perdre exactement l'information qui compte.

## Liquid Glass / matériaux

Pas de `glassEffect` sur cet écran : le verre est réservé aux surfaces **flottantes** (barres de recherche,
bandeaux, îlot Live Activity), et les écrans de contenu poussés (`StackView`, `OfflineAssetsView`,
`SyncStatusView`) n'en utilisent pas. Fonds `Color.bgPrimary`, lignes de `List` en `Color.bgSecondary`
(jamais de blanc littéral), séparateurs `Color.separatorPV`. Les badges sont des aplats opaques
(`PVStatusBadge`), pas des surfaces translucides : un badge de sécurité reste lisible sur tout fond.

## Accessibilité

- **Identifiants** (sur les éléments interactifs, jamais sur un conteneur qui en contient) :
  `deviceSessionsRow` (ligne du hub), `deviceSessionsList`, `deviceSessionRow_<id>`,
  `deviceSessionRevokeButton_<id>`, `deviceSessionsLockButton`, `deviceSessionsRevokeAllButton`,
  `deviceSessionsUnlockField`, `deviceSessionsUnlockConfirm`, `deviceSessionsErrorBadge`,
  `deviceSessionsEmptyView`. Le `List` porte `deviceSessionsList` mais **pas** les lignes : un identifiant
  posé sur le conteneur écraserait ceux des enfants (mesuré sur `languageRelaunchToast`).
- **VoiceOver** : chaque ligne est un seul élément (`accessibilityElement(children: .combine)`) et son
  label vient du VM — « iPhone, iOS 26.0, version 1.135.0, last seen 2 hours ago, this device ». Le badge
  « This device » **n'est pas** un élément séparé : il est fondu dans la phrase. Le bouton de révocation
  swipé porte un label explicite (« Log out iPhone »), pour que le geste ne soit pas le seul chemin vers
  l'action.
- **Sensibilité / confidentialité** : la liste porte `.privacySensitive()` (noms d'appareils masqués dans
  l'instantané de l'app switcher) ; pas de `textSelection(.enabled)`, aucun `ShareLink`, aucun `Menu`
  « Copy », aucun `contextMenu` sur les lignes — rien ne sort par le presse-papiers.
- **Cibles ≥ 44 pt** : la ligne entière est tapable (hauteur naturelle du `List`, jamais de
  `.frame(height:)` figé) ; le bouton cadenas est un `Button` de barre d'outils (44 pt système).
- **Dynamic Type** : `VStack` de textes, aucun `lineLimit(1)` sur la description d'appareil (un nom long
  se replie au lieu d'être tronqué) ; le `PVStatusBadge` suit la taille de police.
- **Reduce Motion** : aucune animation propre n'est introduite (voir ci-dessous) ; rien à neutraliser.
- **Chaînes** (clés anglaises, `sourceLanguage = en`) : `Connected Devices`, `This device`,
  `Other devices`, `Expired`, `Log out`, `Log out other devices`, `Log out iPhone?` / `Log out %@?`,
  `This device will have to sign in again.`, `Log out %lld other devices?`,
  `Your current device stays signed in.`, `Log out %lld devices`, `Last seen`, `Lock session`, `Unlock`,
  `PIN`, `Unknown`, `No connected devices`, `Sign in from another device to see it here.`

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Icône du cadenas qui bascule | `.contentTransition(.symbolEffect(.replace))` | remplacement instantané |
| Disparition d'une ligne révoquée | animation système de `List` sur `vm.sessions` | système |
| Apparition du badge « Expired » | `.transition(.opacity)` | fondu conservé |
| Ouverture de l'alerte PIN | système | système |

Aucun morphing, aucun `matchedGeometryEffect`, aucun `glassEffectID` : l'écran ne se transforme pas, il
constate — la révocation n'anime pas la ligne « pour faire joli ».

## Fichiers touchés

- NEW `Sources/Features/Security/DeviceSessionsView.swift` — l'écran, son `DeviceSessionRow` privé, les
  deux `confirmationDialog` et l'alerte PIN.
- NEW `Sources/Features/Security/DeviceSessionsViewModel.swift` — état, projections, présentation,
  `pendingRevocation`.
- NEW `Sources/Core/Types/DTOs+Session.swift` — `SessionResponseDto`, `SessionUnlockDto`.
- NEW `Tests/DeviceSessionsViewModelTests.swift` — 8 cas nommés (spec, étape 10).
- EDIT `Sources/Features/Profile/ProfileView.swift` — `@State var deviceSessions` + ligne
  `deviceSessionsRow` dans la section `Security`.
- EDIT `Sources/RootView.swift` — `@State private var deviceSessions` + passage à `ProfileView`.
- EDIT `Sources/DependencyContainer.swift` — `makeDeviceSessionsViewModel()`.
- EDIT `Sources/Core/Protocols/ImmichClient.swift` (cinq méthodes), `Sources/Core/Constants.swift`
  (trois chemins), `Sources/Services/ImmichAPIClient.swift` (cinq appels HTTP) — spec, étapes 4-6.

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Déclarer un `NavigationStack` dans `DeviceSessionsView`** : elle est poussée par `ProfileView`, qui
   en porte un (`:25-26`) — second stack, second barre de navigation.
2. **Poser un `accessibilityIdentifier` sur le conteneur du `List` au lieu des lignes** : les identifiants
   des lignes deviennent introuvables (mesuré sur `languageRelaunchToast`).
3. **Charger `GET /sessions` depuis le `Form` de `ProfileView`** : ce `Form` a déjà un
   `.task { await storage.load() }` (`:154`) ; y ajouter les sessions ferait payer un aller-retour réseau
   à chaque ouverture de l'onglet « Me » (approche B, rejetée).
4. **Réutiliser `AppLockViewModel` comme verrou de session** : câblé sur
   `@AppStorage(AppLockViewModel.enabledKey)` et Face ID, sans identifiant de session ni corps
   `SessionUnlockDto`, il ne peut appeler ni `/auth/session/lock` ni `/auth/session/unlock` (approche C).
5. **Offrir la révocation sur la session courante** : `revoke(_:)` garde déjà `guard !session.current`,
   mais la surface ne doit même pas **montrer** le geste — ni poubelle, ni `.swipeActions`, ni
   `contextMenu` sur la section « This device ».
6. **Utiliser la même confirmation pour les deux destructions** : le libellé global doit dire que
   l'appareil courant reste connecté, sinon l'utilisateur croit se déconnecter lui-même.
7. **Afficher l'`id` de session, `isPendingSyncReset`, ou rendre le texte sélectionnable** : rien de
   superflu à l'écran, rien de copiable inutilement.
8. **Écrire un littéral français dans la vue** : la clé du catalogue est la chaîne anglaise.
9. **Afficher une section « Expires » vide** quand `expiresAt` est `null` (champ optionnel : une session
   créée sans `duration` n'a pas d'expiration).
