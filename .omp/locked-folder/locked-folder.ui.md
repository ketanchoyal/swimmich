# Task: locked-folder — UI Brief

> Compagnon de `.omp/locked-folder/locked-folder.specs.md` (écrit le 2026-09-15). Ne pas dupliquer la spec :
> ce document ne décrit que la **surface** — placement, hiérarchie de vues, gestes, états, tokens.

## Design Philosophy

Le dossier verrouillé est une **pièce à porte**, pas un filtre. On franchit la porte (PIN à 6 chiffres, ou
Face ID qui **rejoue** le PIN mémorisé côté Keychain), ou l'on est dedans et l'on agit. La porte est donc un
écran **plein**, mince, sans distraction — un champ, un bouton, une erreur — jamais une feuille greffée sur une
grille. Une fois dedans, l'écran est la grille de la timeline avec un bandeau d'état : rien à réapprendre.
La distinction avec l'**App Lock global** doit se lire d'un coup d'œil : l'App Lock est un `Toggle` de la
section `Security` qui garde **l'app entière** (overlay posé par `RootView`) ; le dossier verrouillé est une
**ligne poussée**, avec sa propre pastille d'état et son propre PIN **serveur** : l'un est un réglage, l'autre
est un lieu.

## Placement dans la navigation

- **Entrée** : `ProfileView` (hub « Me »), section `Security` (l.131-141), ligne `lockedFolderRow` placée
  **avant** le `Toggle("Require Face ID", …)` de l'App Lock — motif repris de l'upstream
  (`mobile/lib/presentation/pages/locked_folder.page.dart`, atteint depuis les réglages).
- **Sortie** : `LockedFolderView` **ne déclare aucun `NavigationStack`** — `ProfileView` en porte déjà un ; la
  vue est poussée dans la pile de la sheet « Me », exactement comme `TrashView`.
- **Aucun onglet, aucune feuille, aucune entrée depuis la timeline** : la timeline ne fait qu'**envoyer** vers le
  dossier ; et ce n'est pas un filtre de la timeline (pas de cas ajouté au menu All / Favorites / Archived /
  Shared with you).
- Les trois portes (`needsSetup`, `locked`, `unlocked`) vivent dans la **même** vue, en `switch` sur `vm.gate` :
  pas trois destinations, pour qu'aucun retour arrière ne contourne la saisie.

## Layout

```
LockedFolderView                                      (poussée par ProfileView)
└── Group
    ├── gate == .needsSetup
    │   └── VStack(spacing: PVSpacing.s16) : Text « Create a PIN » → Font.pvTitle
    │       ├── PVInputGroup → PVFieldSurface × 2 : SecureField « 6 digits », « Confirm PIN » (numberPad)
    │       ├── Toggle « Unlock with Face ID »         (seulement si biométrie disponible)
    │       └── Button « Create a PIN »                → lockedFolderCreatePINButton
    ├── gate == .locked
    │   └── VStack(spacing: PVSpacing.s24)             (centré, Color.bgPrimary)
    │       ├── Image(systemName: "lock")              → Font.pvTitleXL, Color.textSecondaryPV
    │       ├── PVFieldSurface → SecureField « 6 digits »          → lockedFolderPINField
    │       ├── InlineErrorBadge                       (si vm.errorMessage != nil)
    │       ├── Button « Unlock »                      → lockedFolderUnlockButton
    │       └── Button « Unlock with Face ID »         → lockedFolderBiometricButton
    │           (masqué dès que vm.failedAttempts ≥ 5)
    └── gate == .unlocked
        └── ScrollView
            ├── bandeau d'état (non scrollant)         → lockedFolderStatusBadge + lockNowButton
            ├── LazyVGrid(3 colonnes, spacing: PVSpacing.s2) → lockedFolderCell_<assetId>
            │   └── si vm.items vide : ContentUnavailableView « Nothing in your locked folder »
            └── PVSkeletonGrid en pied tant que vm.isLoadingMore
        toolbar (placement: .principal) : ImmichAppBar(title: "Locked Folder")
            └── restoreFromLockedFolderButton « Move back to timeline » (désactivé si sélection vide)
```

- **Rafraîchissement** : `.refreshable { await vm.loadFirstPage() }`, `.task { await vm.refreshGate() }` ;
  **fond** `Color.bgPrimary`, saisie via `PVFieldSurface` (`Color.bgSecondary`) ; **défilement infini** par
  `onAppear` de la dernière cellule → `vm.loadMore()`.

## Composants
Réutiliser, ne pas créer :

| Besoin | Composant existant |
|---|---|
| Champ PIN | `PVInputGroup` + `PVFieldSurface` (le `SecureField` reste natif : `numberPad`) |
| Statut verrouillé / déverrouillé | `PVStatusBadge` (`.immichWarning` verrouillé, `.immichSuccess` déverrouillé) |
| Erreur de saisie | `InlineErrorBadge` (jamais une `alert`) ; icône secondaire en `.font(.pvHeadline)` |
| Cellule, en-tête, attente, vide | `AssetThumbnailCell`, `ImmichAppBar`, `PVSkeletonGrid`, `ContentUnavailableView` |

```swift
private struct LockedFolderPINView: View {           // composant local à LockedFolderView.swift
    @Bindable var vm: LockedFolderViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: PVSpacing.s24) {
            Image(systemName: "lock").font(.pvTitleXL).foregroundStyle(Color.textSecondaryPV)
            Text("Locked Folder").font(.pvHeadline).foregroundStyle(Color.textPrimaryPV)
            PVInputGroup {
                PVFieldSurface {
                    SecureField("6 digits", text: $vm.pinEntry).keyboardType(.numberPad)
                        .font(.pvNumeric).focused($focused).accessibilityIdentifier("lockedFolderPINField")
                }
            }
            if let message = vm.errorMessage {
                InlineErrorBadge(message)         // « Wrong PIN » / « Too many attempts »
                    .accessibilityIdentifier("lockedFolderErrorText")
            }
            Button("Unlock") { Task { await vm.submitPIN() } }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isBusy || vm.pinEntry.count != 6 || vm.failedAttempts >= 5)
                .accessibilityIdentifier("lockedFolderUnlockButton")
            if vm.biometricsAvailable && vm.failedAttempts < 5 {
                Button("Unlock with Face ID") { Task { await vm.unlockWithBiometrics() } }
                    .buttonStyle(.bordered).disabled(vm.isBusy)
                    .accessibilityIdentifier("lockedFolderBiometricButton")
            }
        }
        .padding(PVSpacing.s24).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary).onAppear { focused = true }
    }
}
```

```swift
/// Bandeau de la grille ouverte — le seul écart visuel avec la timeline.
private var unlockedBanner: some View {
    HStack(spacing: PVSpacing.s8) {
        PVStatusBadge("Unlocked", color: .immichSuccess)   // aucun équivalent côté App Lock
        Text("Locked Folder").font(.pvCaption).foregroundStyle(Color.textSecondaryPV)
        Spacer()
        Text(vm.itemCountText).font(.pvNumeric).contentTransition(.numericText())
            .accessibilityIdentifier("lockedFolderCountValue")   // mise en forme faite par le VM
    }
    .padding(.horizontal, PVSpacing.s16).background(Color.bgSecondary)
}
```

## Interactions

| Geste | Effet |
|---|---|
| Tap `lockedFolderRow` (hub) | Pousse `LockedFolderView` ; `refreshGate()` lit `GET /api/auth/status` et choisit la porte |
| « Create a PIN » | `vm.setupPIN()` : PIN de 5 chiffres ou confirmation divergente refusés **sans** appel serveur, puis `POST /api/auth/pin-code` + `POST /api/auth/session/unlock` |
| Tap « Unlock » / « Unlock with Face ID » | `vm.submitPIN()` → `POST /api/auth/session/unlock` puis grille + `loadFirstPage()` ; `vm.unlockWithBiometrics()` évalue `.deviceOwnerAuthentication` puis **rejoue le PIN mémorisé** — jamais un accès direct |
| PIN refusé par le serveur | `InlineErrorBadge` « Wrong PIN », champ vidé et refocalisé, `failedAttempts += 1` ; bouton désactivé pendant l'aller-retour (`isBusy`), ce qui **impose l'attente entre deux tentatives** et interdit le tir en rafale |
| 5 échecs | « Unlock » et « Unlock with Face ID » désactivés, message « Too many attempts », seul le retour arrière sort de l'écran |
| Sélection multiple (timeline) | `moveToLockedFolderButton` → `vm.moveSelectedToLockedFolder()` : `PUT /api/assets` avec `visibility: locked`, sortie du mode sélection ; le menu contextuel d'une cellule appelle `vm.moveToLockedFolder(id:)`, même chemin |
| Tap `restoreFromLockedFolderButton` | `vm.restoreSelectionToTimeline()` : `PUT /api/assets` avec `visibility: .timeline`, retrait local des cellules |
| Tap `lockNowButton` | `vm.relock()` : `POST /api/auth/session/lock`, purge `items`/`buckets`/`selectedIds`, retour à la porte |
| App en arrière-plan (`scenePhase != .active`) | `vm.relock()` — le dossier se referme toujours, sans action de l'utilisateur ; grille vide : `ContentUnavailableView` |

**Ce que la timeline montre d'un asset enfermé** : rien. L'asset quitte la grille immédiatement (même mécanique
locale qu'« Archive » : `items.removeAll` + `loadedIds.subtract`), aucun compteur ni cellule fantôme ne subsiste ;
**aucun filtre « locked »** n'est ajouté au menu de la timeline : le dossier est le seul endroit d'où l'asset
redevient visible — absent aussi des widgets, Memories et App Intents.

## Liquid Glass / matériaux

Pas de `glassEffect` : le verre est réservé aux surfaces **flottantes** (barres de recherche, bandeaux, Live
Activity), pas aux écrans poussés depuis le hub « Me ». Cartes en `Color.bgSecondary`, séparateurs
`Color.separatorPV`, saisie via `PVFieldSurface` ; seuls accents colorés : pastille d'état et erreur — jamais
un fond `immichError` sur toute la porte.

## Accessibilité

- **Identifiants** (sur les éléments interactifs, jamais sur un conteneur qui les contient) :
  `lockedFolderRow`, `lockedFolderCreatePINButton`, `lockedFolderPINField`, `lockedFolderConfirmPINField`,
  `lockedFolderRememberToggle`, `lockedFolderUnlockButton`, `lockedFolderBiometricButton`,
  `lockedFolderErrorText`, `lockedFolderCountValue`, `lockedFolderStatusBadge`, `lockedFolderCell_<assetId>`,
  `restoreFromLockedFolderButton`, `lockNowButton`, `moveToLockedFolderButton` (toolbar de sélection et item de
  menu contextuel de `AssetThumbnailCell`, même identifiant).
- **VoiceOver** : la porte est un seul élément annonçant son état (`"Locked Folder, locked"`) ; le champ est un
  code à 6 chiffres, pas un mot de passe texte ; le statut du hub est **combiné** avec sa ligne
  (`accessibilityElement(children: .combine)`).
- **≥ 44 pt et Dynamic Type** : boutons de la porte en pleine largeur ; aucun `frame(height:)` figé sur la porte
  ni sur le bandeau ; le champ en `.pvNumeric` grossit sans troncature et le `HStack` passe à la ligne en taille
  accessibilité.
- **Reduce Motion** : porte → grille est un remplacement de contenu, pas un morphing ; libellés = **clés
  anglaises** du catalogue : `Locked Folder`, `Move to Locked Folder`, `Move back to timeline`, `Lock now`,
  `Unlock`, `Create a PIN`, `Confirm PIN`, `Unlock with Face ID`, `6 digits`, `Wrong PIN`, `Too many attempts`,
  `Nothing in your locked folder`.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Erreur après un échec | `.transition(.opacity)` sur `InlineErrorBadge` | fondu conservé |
| Porte → grille | `.animation(PVMotion.standard, value: vm.gate)` sur le `switch` | remplacement instantané |
| Compteur / `relock` | `.contentTransition(.numericText())` sur la valeur ; reverrouillage sans animation | neutralisé par le système |

## Fichiers touchés

- NEW `Sources/Features/LockedFolder/LockedFolderView.swift` — les trois portes, la grille, le bandeau, le
  `scenePhase` (spec §7-8) ; aucun `NavigationStack`.
- NEW `Sources/Features/LockedFolder/LockedFolderViewModel.swift` — porte, échecs, chargement, restaurations.
- EDIT `Sources/Features/Profile/ProfileView.swift` — `lockedFolderRow` dans `Security`, avant le toggle d'App Lock.
- EDIT `Sources/Features/Timeline/TimelineView.swift` — `moveToLockedFolderButton` après « Archive » ; closure
  `onMoveToLockedFolder` + item de menu dans `AssetThumbnailCell.swift`.
- EDIT `Sources/RootView.swift` — ViewModel du dossier passé à `ProfileView` (sheet « Me »).

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Déclarer un `NavigationStack` dans `LockedFolderView`** : `ProfileView` en porte déjà un ; un second stack
   produit deux barres de navigation (relevé sur `LanguageSettingsView`).
2. **Poser un `accessibilityIdentifier` sur un conteneur** (le `VStack` de la porte, le `LazyVGrid`) : il écrase
   ceux des descendants et le bouton devient introuvable en XCUITest (`languageRelaunchToast`).
3. **Réutiliser `AppLockService` / `LockView` comme porte du dossier** : état process-wide et overlay qui garde
   toute l'app — déverrouiller le dossier déverrouillerait l'app entière (l'App Lock est déjà le `Toggle` de
   `ProfileView`, déplacé depuis Backup le 2026-09-10).
4. **Donner à Face ID un accès direct au dossier** : `LAContext` ne remplace pas le PIN, il autorise son
   **rejeu** vers `POST /api/auth/session/unlock` ; un gate local laisserait le serveur refuser la lecture.
5. **Afficher « Wrong PIN » dans une `alert`** : la porte reste saisissable, le message est un `InlineErrorBadge`.
6. **Laisser le dossier ouvert en arrière-plan** (sans `onChange(of: scenePhase)` → `relock()`) : l'élévation de
   session survit et la grille reste lisible au retour.
7. **Appeler `relock()` sur `onDisappear`** : pousser le viewer redemanderait le PIN après chaque photo ; le
   reverrouillage explicite est porté par `lockNowButton`.
8. **Écrire un littéral français** (chaîne ou identifiant) : la clé du catalogue est la chaîne anglaise.
