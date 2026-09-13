# Task: partners-ui — UI Brief

> **Révision du 2026-09-13.** Le brief d'origine décrivait un `TabView` segmenté dans l'onglet Shared, une `UserSearchView` imbriquée et un `SearchField(query:)` — **ce composant n'existe pas dans le dépôt** (`Sources/DesignSystem/` n'a pas de `SearchField` ; la recherche native passe par `.searchable`). Il pinçait aussi des combinaisons non utilisées ailleurs (`Toggle(...).glassEffect(.interactive())` dans une ligne de `Form`). Réécrit sur la structure réelle : écran poussé depuis le hub « Me », **deux sections dans une `Form`** (le `TabView` segmenté masquait la moitié de l'information et dupliquait une machinerie de liste dans un `Form`), et les primitives du design system qui existent.

## Design Philosophy

Deux listes, deux responsabilités, jamais mélangées :

- **Shared with me** — des personnes qui me donnent accès à leur photothèque. La seule action est *la mienne* : est-ce que leurs photos apparaissent dans mon planning (`inTimeline`).
- **Sharing** — des personnes à qui **je** donne accès. La seule action est de retirer cet accès.

Ce n'est pas une préférence esthétique : le serveur refuse l'inverse (voir le contrat dans `.omp/partners-ui/partners-ui.specs.md`). L'écran doit rendre cette asymétrie évidente — un interrupteur là, un bouton destructif ici, jamais les deux sur la même ligne.

L'écran suit le langage du dépôt : `Form` groupée, en-têtes de section, tokens `PVSpacing` / `PVMotion`, `Color.immichPrimary` pour l'accent et `Color.immichError` pour le destructif, verre natif sur les surfaces flottantes (feuille d'invitation, CTA).

## Structure

```
ProfileView (hub « Me », section Management)
└── NavigationLink → PartnersView            ← poussée, donc PAS de NavigationStack propre
    Form
    ├── Section "Shared with me"
    │   ├── PartnerRow(mode: .incoming)      avatar · nom · « Shown in timeline » + Switch
    │   └── (vide) texte explicatif : personne ne partage sa photothèque avec vous
    ├── Section "Sharing"
    │   ├── PartnerRow(mode: .outgoing)      avatar · nom · e-mail + bouton poubelle
    │   └── (vide) texte explicatif + CTA d'invitation
    └── toolbar: bouton « + » (personne +) → InvitePartnerSheet
```

Pas de `TabView` : les deux directions tiennent dans un écran qui défile, et chacune garde son propre état vide.

## Composants

### PartnersView — `Sources/Features/Partners/PartnersView.swift`

```swift
struct PartnersView: View {
    @State var vm: PartnersViewModel
    @State private var partnerPendingRemoval: PartnerResponseDto?
    @State private var showPartnerRemoveConfirm = false
    @State private var presentingInvite = false

    var body: some View {
        Form {
            Section("Shared with me") {
                if vm.sharedWithMe.isEmpty { emptyIncoming } else {
                    ForEach(vm.sharedWithMe, id: \.id) { partner in
                        PartnerRow(partner: partner, mode: .incoming) { enabled in
                            Task { await vm.setInTimeline(partnerId: partner.id, enabled: enabled) }
                        }
                    }
                }
            }
            Section("Sharing") {
                if vm.sharing.isEmpty { emptyOutgoing } else {
                    ForEach(vm.sharing, id: \.id) { partner in
                        PartnerRow(partner: partner, mode: .outgoing) {
                            partnerPendingRemoval = partner
                            showPartnerRemoveConfirm = true
                        }
                    }
                }
            }
            if let error = vm.errorMessage { Section { InlineErrorBadge(message: error) } }
        }
        .navigationTitle("Partners")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { inviteButton } }
        .task { await vm.load(); await vm.loadCandidates() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $presentingInvite) { InvitePartnerSheet(vm: vm) }
        .confirmationDialog("Remove this partner?", isPresented: $showPartnerRemoveConfirm, titleVisibility: .visible) { … }
    }
}
```

La forme `isPresented:` + id en `@State` est celle du dépôt (`SharedLinksView.swift:112`, `StackDetailView.swift:63`) — le motif est repris tel quel, pas réinventé.

### PartnerRow — `Sources/Features/Partners/PartnerRow.swift` (déplacé depuis `SharedLinksView.swift:346`)

La ligne actuelle porte **les deux** actions ; elle est scindée par un `mode` :

| mode | actions rendues | identifiants |
|---|---|---|
| `.incoming` (lignes `shared-with`) | `Switch` « Show in timeline » + sous-titre « Shown in timeline » / « Hidden from timeline » | conserve `partnerTimelineToggle-<id>` (`SharedLinksView.swift:368`) |
| `.outgoing` (lignes `shared-by`) | bouton poubelle (`Image(systemName: "trash")`, `Color.immichError`, `.buttonStyle(.plain)`) | ajoute `partnerRemove-<id>` |

`PartnerAvatarCircle` est déplacé intact (initiales + `Color(hex: avatarColor) ?? .immichPrimary`).

### InvitePartnerSheet — `Sources/Features/Partners/InvitePartnerSheet.swift`

La feuille **est** le sélecteur : pas de `NavigationLink` imbriquée vers une seconde vue (la liste des candidats est l'unique contenu).

⚠ **Piège vérifié en exécution (2026-09-13)** : `.buttonStyle(.plain)` sur un `Button` placé dans une `List` **avale le tap** sur iOS 26 — la ligne s'affiche, paraît cliquable, et l'action n'est jamais appelée (le CTA « Invite » restait grisé, aucune coche après le tap). La ligne garde donc le style de bouton par défaut de la `List`, avec `contentShape(Rectangle())` et des couleurs de texte explicites pour ne pas hériter du teintage d'accent. Même classe de défaut que le `Button` autour d'`AssetThumbnailCell` dans le picker de piles, corrigé le même jour — dans ce dépôt, un tap de ligne sans effet est presque toujours un `Button`/`buttonStyle` qui intercepte le geste, et seul un test d'exécution le voit.

```swift
struct InvitePartnerSheet: View {
    @Bindable var vm: PartnersViewModel
    let currentUserId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(vm.filteredCandidates, id: \.id) { user in
                // Pas de .buttonStyle(.plain) : il avale le tap (cf. l'encadré ci-dessus).
                Button { vm.selectCandidate(user) } label: { row(user) }
                    .accessibilityIdentifier("inviteCandidate-\(user.id)")
            }
            .searchable(text: $vm.searchQuery, prompt: "Name or email")
            .overlay { if vm.inviteCandidates.isEmpty { directoryUnavailable } }
            .navigationTitle("Invite partner")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invite") { Task { if await vm.invite(userId: selected) { dismiss() } } }
                        .disabled(!vm.canInvite)
                        .accessibilityIdentifier("confirmInvitePartner")
                }
            }
            .task { await vm.loadCandidates(excludingUserId: currentUserId) }
        }
    }
}
```

**État vide obligatoire** — `GET /api/users` ne renvoie que l'utilisateur courant aux non-admins d'un serveur privé (`server.publicUsers` désactivé) : la feuille explique qu'aucun autre utilisateur n'est exposé plutôt que d'afficher une liste vide sans raison.

## Interactions

- **Toggle timeline** : écriture optimiste interdite — la ligne reflète la réponse serveur. Échec ⇒ l'interrupteur **revient** à sa valeur et un message apparaît (`PartnersViewModel.setInTimeline`, testé par `test_setInTimeline_failure_keepsRow`).
- **Remove** : `confirmationDialog` destructif, puis retrait de la ligne après succès serveur ; annulation ne change rien. La mutation est bornée aux lignes **sortantes** — `PartnersViewModel.remove` refuse un id qui n'est pas dans `sharing` (testé par `test_remove_ignoresIncomingPartner`).
- **Toggle timeline** borné symétriquement aux lignes **entrantes** (`test_setInTimeline_ignoresOutgoingPartner`).
- **Invite** : CTA désactivé tant qu'aucun candidat n'est sélectionné ; en succès la feuille se ferme et la personne apparaît dans « Sharing ». L'annuaire exclut soi-même et les partenaires **sortants** — pas les entrants : le partage est unidirectionnel, donc un partenaire entrant reste une cible d'invitation légitime.
- **Animations** : `PVMotion.snappy` pour l'insertion/retrait de ligne (convention du dépôt, `SharedLinksView.swift:118`).

## Accessibilité

- `Switch` : `.accessibilityLabel("Show in timeline")` (déjà posé) + identifiant `partnerTimelineToggle-<id>`.
- Bouton de retrait : identifiant `partnerRemove-<id>`, label parlant incluant le nom.
- Bouton d'invitation : label « Invite a partner », identifiant `invitePartner`.
- Cibles ≥ 44×44 pt ; aucun texte porteur d'information sous `.pvCaption`.
- Aucun test UI ne vise un libellé affiché : les CTA sont localisés (leçon stacks-ui).

## Key Files

- `Sources/Features/Partners/PartnersView.swift` — NEW
- `Sources/Features/Partners/PartnersViewModel.swift` — NEW
- `Sources/Features/Partners/InvitePartnerSheet.swift` — NEW
- `Sources/Features/Partners/PartnerRow.swift` — MOVE depuis `SharedLinksView.swift:341-407`
- `Sources/Features/Profile/ProfileView.swift` — lien « Partners » dans Management
- `Sources/Features/SharedLinks/SharedLinksView.swift` + `SharedLinksViewModel.swift` — retrait du bloc partenaires
