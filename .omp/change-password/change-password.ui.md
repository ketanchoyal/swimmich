# Task: change-password — UI Brief

> Compagnon de `.omp/change-password/change-password.specs.md` (écrit le 2026-09-15). Ce document ne décrit
> que la **surface** — placement, hiérarchie de vues, gestes, états, tokens.

## Design Philosophy

L'écran fait **une** chose : remplacer un secret. Une seule action, un seul bouton de validation, tout le
reste est du **contexte** — pourquoi le changement est demandé, ce que le serveur exige, ce qui a échoué :

1. **Le bouton ne ment jamais** : désactivé tant que les trois règles mesurables de la spec ne sont pas
   satisfaites, et ces règles sont **affichées en clair** à côté des champs — pas devinées après échec.
2. **Rien ne se perd** : une erreur serveur laisse les trois champs intacts ; et `invalidateSessions` ne
   déconnecte que les **autres** appareils, la session courante survit (spec, `auth.service.ts:143-147`).
3. **Pas de promesse que le serveur ne tient pas** : le contrat n'impose qu'une borne (`minLength: 8`) — on
   affiche une **liste d'exigences** exacte, jamais une jauge de « force ».

## Placement dans la navigation

- Poussée depuis **`ProfileView`** (hub « Me »), **dans la section `Security` existante**
  (`Sources/Features/Profile/ProfileView.swift:130-141`), au-dessus du `Toggle("Require Face ID")` : la clé
  `Security` existe **déjà** dans `Resources/Localizable.xcstrings`, et `LanguageSettingsView` a acté qu'une
  préférence liée à l'identité/appareil a sa propre section, pas `Management`.
- Ligne d'entrée : un `NavigationLink` vers `ChangePasswordView` avec
  `Label("Change Password", systemImage: "key")` et `.accessibilityIdentifier("changePasswordRow")`.
- Sous cette ligne, **conditionné à `auth.shouldChangePassword`**, l'avertissement serveur
  (`shouldChangePasswordNotice`) : le signal qu'un administrateur a réinitialisé le mot de passe. Il vit dans
  le hub, pas dans une alerte modale ; le drapeau est relu par `refreshShouldChangePassword()` dans le `.task`
  de `ProfileView` (spec, étape 10), donc il survit à un reset en cours de session.
- `ChangePasswordView` **ne déclare aucun `NavigationStack`** : `ProfileView` en porte déjà un
  (`ProfileView.swift:25`) ; un second stack donnerait deux barres de navigation (piège de
  `LanguageSettingsView`). Écran de détail, retour natif, barre :
  `ToolbarItem(placement: .principal) { ImmichAppBar(title: "Change Password") }` + `.navigationBarTitleDisplayMode(.inline)`.

## Layout

```
ChangePasswordView                                 (poussée par ProfileView)
└── Form
    ├── Section « Current »     → PasswordField(currentPasswordField)
    ├── Section « New »         → PasswordField(newPasswordField)
    │                             PasswordField(confirmPasswordField)
    │                             RequirementsChecklist  (3 lignes, un état par règle)
    ├── Section « Sessions »    → Toggle(invalidateSessionsToggle) + footer explicatif
    ├── Section « Action »      → Button(changePasswordSubmit) pleine largeur, .borderedProminent
    │                             ProgressView inline si vm.isSubmitting
    │                             Label succès (changePasswordSuccess) si vm.didSucceed
    │                             InlineErrorBadge (changePasswordError) si vm.errorMessage != nil
    └── Section « footer »      → reset administrateur uniquement (voir les chaînes plus bas)
```

- `Form` et non `ScrollView` : trois champs à libellés fixes — cellules inset groupées, clavier qui suit le
  focus, fond `Color.bgPrimary`. `.scrollDismissesKeyboard(.interactively)` (la moitié basse est faite d'aides).
- Focus : `@FocusState` local — `.submitLabel(.next)` sur *Current* → *New*, `.next` sur *New* → *Confirm*,
  `.done` sur *Confirm*. Le `onSubmit` du dernier déclenche `submit()` **seulement si `vm.canSubmit`** :
  jamais de validation silencieuse d'un formulaire invalide. Le bouton est le **seul** chemin d'écriture.
- `.task { vm.clearError() }` : l'écran s'ouvre sans erreur héritée d'une visite précédente.

## Composants

Le **seul** composant local est le champ à révélation : aucun équivalent n'existe dans le dépôt (`SecureField`
est utilisé brut dans `LoginScreen`, `AdminView`, `SharedLinkSheet`, `SharedLinkViewerView`).

| Besoin | Composant existant |
|---|---|
| Barre de titre | `ImmichAppBar` dans `ToolbarItem(placement: .principal)` |
| Groupe de champs encadré (hors `Form`) | `PVInputGroup` + `.pvFieldSurface()` |
| Erreur non bloquante | `InlineErrorBadge(message:)` |
| Règle satisfaite / non satisfaite | `PVStatusBadge(text:color:symbol:)` compact, ou icône + `Color.immichSuccess`/`Color.textTertiaryPV` |
| Bouton principal | `PVButtonStyle` / `.borderedProminent` pleine largeur |

```swift
/// Contrat local à ChangePasswordView.swift, privé à cet écran.
private struct PasswordField: View {
    let title: LocalizedStringKey            // clé EN, jamais un littéral français
    @Binding var text: String
    let identifier: String                   // posé sur le champ, pas sur le HStack
    let revealIdentifier: String             // posé sur le bouton, pas sur le HStack
    let contentType: UITextContentType
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: PVSpacing.s8) {
            Group {
                if isRevealed { TextField(title, text: $text) } else { SecureField(title, text: $text) }
            }
            .textContentType(contentType)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .accessibilityIdentifier(identifier)
            Button { isRevealed.toggle() } label: { Image(systemName: isRevealed ? "eye.slash" : "eye") }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)      // cible tactile, pas une icône de 17 pt
                .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
                .accessibilityIdentifier(revealIdentifier)
        }
    }
}
```

`RequirementsChecklist` : `VStack(alignment: .leading, spacing: PVSpacing.s4)` de trois lignes
`rule(_ title: LocalizedStringKey, met: Bool, id: String)` — `checkmark.circle.fill` en `Color.immichSuccess`
ou `circle` en `Color.textTertiaryPV`, texte en `.font(.pvCaption)`. Elle lit `vm.newPasswordTooShort`,
`vm.confirmationMismatch`, `vm.newPasswordUnchanged` : la vue ne recalcule **jamais** une règle.

## Interactions

| Geste | Effet |
|---|---|
| Frappe dans un champ | Met à jour le binding, rafraîchit la liste d'exigences et l'état `disabled` du bouton, efface l'erreur serveur affichée (`vm.clearError()`) |
| Tap sur l'œil d'un champ | Bascule **ce** champ entre `SecureField` et `TextField` ; identifiant et valeur inchangés |
| Tap « Change Password » | `Task { if let response = await vm.submit() { auth.notePasswordChanged(); _ = response } }` |
| Retour clavier sur *Confirm* | Identique au bouton, seulement si `vm.canSubmit` |
| Tap `invalidateSessionsToggle` | Change `vm.invalidateSessions` (défaut UI `true`, cf. spec étape 4) ; le footer explique la conséquence |
| Tap `changePasswordRow` | Pousse l'écran ; si `auth.shouldChangePassword`, la ligne `shouldChangePasswordNotice` reste visible au-dessus |
| Succès | `vm.didSucceed` → `Label("Your password has been changed.", systemImage: "checkmark.circle.fill")` en `Color.immichSuccess`, champs vidés par le VM ; **l'écran ne se ferme pas tout seul** — l'utilisateur lit la confirmation et revient par le retour natif, où l'avertissement a disparu du hub |
| Échec (mot de passe actuel faux, nouveau identique à l'actuel) | `vm.errorMessage` non nul → `InlineErrorBadge` sous le bouton ; **les trois champs gardent leur contenu**, le focus revient sur *Current* |
| Double tap pendant l'in-flight | Impossible : `.disabled(!vm.canSubmit)` devient vrai dès `isSubmitting`, et `submit()` n'est pas réentrant |

Le `400` de cette route **n'est pas** une perte de session : le serveur jette `BadRequestException('Wrong
password')` — HTTP 400, pas 401 — le handler global 401 (qui appelle `resetSession()`) n'est jamais atteint, et
l'écran ne propose pas « se reconnecter ».

## Liquid Glass / matériaux

Pas de `glassEffect` ici : le verre est réservé aux surfaces **flottantes** (barres de recherche, bandeaux,
îlot Live Activity) — `StackView`, `OfflineAssetsView`, `SyncStatusView` n'en utilisent pas, et un formulaire
poussé n'en est pas une. Séparateurs `Color.separatorPV`, fonds `bgPrimary`/`bgSecondary` et cellules du
`Form` suffisent. Aucun `GlassEffectContainer`, aucun `glassEffectID`.

## Accessibilité

- **Identifiants** (sur les éléments **interactifs**, jamais sur un conteneur qui en contient — un identifiant
  de conteneur écrase celui de tous ses descendants dans l'arbre XCUITest, mesuré sur `languageRelaunchToast`) :
  `changePasswordRow`, `shouldChangePasswordNotice`, `currentPasswordField`, `newPasswordField`,
  `confirmPasswordField`, `currentPasswordReveal`, `newPasswordReveal`, `confirmPasswordReveal`,
  `invalidateSessionsToggle`, `changePasswordSubmit`, `changePasswordError`, `changePasswordSuccess`,
  `passwordRuleLength`, `passwordRuleMatch`, `passwordRuleDifferent`. Chaque identifiant est porté par le
  `SecureField`/`Button` **à l'intérieur** du `HStack` — jamais par le `HStack` ni la `Section`.
- **VoiceOver** : un champ de mot de passe est annoncé « secure text field » ; les libellés sont donc
  explicites (`Current Password`, `New Password`, `Confirm New Password`) et le bouton de révélation un
  **élément séparé** avec son label `Show password` / `Hide password` — sinon la bascule est inatteignable.
- **Liste d'exigences** : chaque ligne est un seul élément portant l'état dans son label
  (`.accessibilityLabel("At least 8 characters, not met")` puis `"At least 8 characters, met"`). **Dynamic
  Type** : aucun `frame(height:)` figé ; cibles ≥ 44 pt.
- **Remplissage automatique iOS** : `.textContentType(.password)` sur *Current* (le trousseau propose, ne
  génère jamais) et `.textContentType(.newPassword)` sur *New* **et** *Confirm* — cette paire reconnue par iOS
  déclenche la proposition de mot de passe fort et l'enregistrement au trousseau. Si la règle inférée doit être
  resserrée, la voie est `UITextInputPasswordRules(descriptor: "minlength: 8;")` ; `.textContentType(.newPassword)`
  reste la source du comportement.
- Libellés : clés **anglaises** — `Change Password`, `Current Password`, `New Password`,
  `Confirm New Password`, `At least 8 characters.`, `The two passwords do not match.`,
  `The new password is the same as the current one.`, `Sign out on other devices`,
  `Other devices will need to sign in again with the new password. This device stays signed in.`,
  `Your password has been changed.`, `Show password`, `Hide password`, `This server asks you to change your
  password.`, `If you forget this password, an administrator has to reset it from the Immich web interface.` —
  aucune écriture manuelle dans `Resources/Localizable.xcstrings`.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Exigence non satisfaite → satisfaite | `.contentTransition(.symbolEffect(.replace))` sur l'icône, `PVMotion.snappy` | remplacement instantané (système) |
| Apparition du message de succès | `.transition(.opacity.combined(with: .move(edge: .top)))`, `PVMotion.standard` | fondu conservé |
| Apparition de l'`InlineErrorBadge` | `.transition(.opacity)`, `PVMotion.standard` | fondu conservé |
| Bascule œil ⇄ œil barré | `.contentTransition(.symbolEffect(.replace))` sur l'icône | remplacement instantané |
| État `disabled` du bouton | `.animation(PVMotion.snappy, value: vm.canSubmit)` sur l'opacité seule | système |

Pas de morphing, pas de `matchedGeometryEffect`, aucune animation sur le contenu des champs ni de secousse sur
l'erreur (aucun précédent de `shake` dans le dépôt) : l'erreur est un texte stable.

## Fichiers touchés

- NEW `Sources/Features/Security/ChangePasswordView.swift` — l'écran + `PasswordField` et `RequirementsChecklist`.
- NEW `Sources/Features/Security/ChangePasswordViewModel.swift` — trois champs, règles, `submit()` (spec 4-5).
- NEW `Tests/ChangePasswordViewModelTests.swift` — 8 cas nommés dans la spec.
- EDIT `Sources/Features/Profile/ProfileView.swift` — `@State var changePassword`, `changePasswordRow`, `shouldChangePasswordNotice`.
- EDIT `Sources/Features/Auth/AuthViewModel.swift` — `shouldChangePassword`, `notePasswordChanged()`,
  `refreshShouldChangePassword()`.
- EDIT `Sources/RootView.swift`, `Sources/DependencyContainer.swift` — fabrication et passage du VM.
- EDIT `Sources/Core/Protocols/ImmichClient.swift`, `Sources/Services/ImmichAPIClient.swift`,
  `Sources/Core/Types/DTOs.swift`, `Tests/Mocks/MockImmichClient.swift` — couture et doublure.

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Déclarer un `NavigationStack` dans `ChangePasswordView`** : elle est poussée par `ProfileView`, qui en a
   un — deux barres de navigation (décision déjà actée pour `LanguageSettingsView`).
2. **Poser un identifiant sur le `HStack` d'un champ, une `Section` ou un conteneur** : il écrase ceux de tous
   ses descendants ; mesuré sur `languageRelaunchToast`, où le bouton devenait introuvable par son identifiant.
3. **Traiter le 400 « Wrong password » comme une session expirée** : le serveur répond 400, pas 401 ; le
   handler global 401 ne doit pas être atteint, l'écran ne déconnecte pas.
4. **Vider les champs après une erreur** : le VM ne vide qu'au **succès**.
5. **Construire une jauge de « force »** : le serveur n'impose que `minLength: 8` ; on affiche les trois règles.
6. **Retirer le champ de confirmation de `canSubmit`** : décision d'ergonomie retenue par la spec.
7. **Persister `shouldChangePassword` en `UserDefaults`** : contrairement à `isAdmin`
   (`AuthViewModel.swift:105`), c'est un état serveur — il se relit, il ne se mémorise pas.
8. **Journaliser le corps de la requête** (`ChangePasswordDto`) : deux mots de passe en clair dans les logs.
9. **Fermer l'écran automatiquement après le succès** : la session courante survit à `invalidateSessions`
   (spec, `auth.service.ts:143-147`) et l'utilisateur doit lire la confirmation.
10. **Écrire un littéral français dans la vue** : la clé du catalogue est la chaîne anglaise.
