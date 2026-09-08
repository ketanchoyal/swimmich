# Task: partners-ui — UI Brief (Liquid Glass Primary)

## Design Philosophy

L'interface est un **espace vitré continu** où chaque partenaire vit dans une cellule de verre distincte. Le tab bar segmenté utilise le glass natif iOS 26. Les actions de partage sont des capsules flottantes. C'est exactement ce qu'on voit dans les réglages de contacts iOS.

## Layout

```
NavigationStack (scrollEdgeEffectStyle: glass)
├── ImmichAppBar (glass morphing bar, scrollEdge)
└── ZStack {
    ├── Background: subtle blurred photo
    └── Content — GlassEffectContainer {
        ├── TabView (segmented) — system glass
        │   ├── Tab "Shared with me"
        │   │   └── List — each row is a glass card
        │   └── Tab "Sharing"
        │       └── List — each row is a glass card
        └── FAB "+" — glass capsule, morphs into invite sheet
    }
```

## Components

### PartnerShellView — Glass card list

Chaque partenaire est une carte vitrée individuelle — pas un row de Form plat. C'est comme la liste de contacts iOS avec des cellules en glass.

```swift
struct PartnerShellView: View {
    @State var vm: PartnerShellViewModel
    @Namespace private var glassNamespace
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.immichBackground.ignoresSafeArea()
                
                GlassEffectContainer {
                    TabView {
                        PartnerListTab(partners: vm.sharedByPartners, direction: .sharedBy, glassNamespace: glassNamespace)
                        PartnerListTab(partners: vm.sharedWithPartners, direction: .sharedWith, glassNamespace: glassNamespace)
                    }
                    .tabViewStyle(.segmented)
                    .padding(.horizontal, PVSpacing.s16)
                    .padding(.top, PVSpacing.s8)
                    .padding(.bottom, PVSpacing.s8)
                }
                .padding(.horizontal, PVSpacing.s16)
            }
            .toolbar { ImmichAppBar() }
        }
    }
}
```

### PartnerRowView — Glass card row

```swift
struct PartnerRowView: View {
    let partner: PartnerResponseDto
    @Namespace private var rowNamespace
    
    var body: some View {
        HStack(spacing: PVSpacing.s12) {
            // Avatar — glass circle
            PartnerAvatarCircle(partner: partner)
                .frame(width: 44, height: 44)
                .glassEffect(.regular)
            
            // Info
            VStack(alignment: .leading, spacing: PVSpacing.s2) {
                Text(partner.name)
                    .font(.pvBody.weight(.semibold))
                Text(partner.email)
                    .font(.pvCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Toggle — glass interactive
            Toggle("", isOn: $isInTimeline)
                .toggleStyle(.switch)
                .tint(Color.immichPrimary)
                .glassEffect(.interactive())
                .frame(width: 40, height: 24)
        }
        .padding(PVSpacing.s12)
        .glassEffect(.regular)
        .glassEffectID("partner_\(partner.id)", in: rowNamespace)
    }
}
```

### InvitePartnerSheet — Glass morph from FAB

Le FAB "+" est une capsule vitrée qui morph en header de la sheet.

```swift
struct InvitePartnerSheet: View {
    @Bindable var vm: PartnerShellViewModel
    @Environment(\.dismiss) private var dismiss
    @Namespace private var glassNamespace
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.immichBackground.ignoresSafeArea()
                
                GlassEffectContainer {
                    Form {
                        // Email input — glass field
                        Section {
                            TextField("Email or username", text: $vm.inviteInput)
                                .pvFieldSurface(focused: $vm.inputFocused)
                                .glassEffect(.regular)
                        }
                        
                        // Server users — glass search
                        Section {
                            NavigationLink {
                                UserSearchView(users: vm.availableUsers, vm: vm, glassNamespace: glassNamespace)
                            } label: {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(Color.immichPrimary)
                                    Text("Search users on this server")
                                        .font(.pvBody)
                                }
                                .padding(PVSpacing.s12)
                                .glassEffect(.regular)
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
                .padding(PVSpacing.s16)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .glassEffect(.regular)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invite") { vm.createPartner() }
                        .disabled(vm.inviteInput.isEmpty || vm.isCreating)
                        .glassEffect(.interactive())
                }
            }
        }
    }
}
```

### UserSearchView — Glass list with search

```swift
struct UserSearchView: View {
    let users: [UserResponseDto]
    @Bindable var vm: PartnerShellViewModel
    @Environment(\.dismiss) private var dismiss
    @Namespace private var glassNamespace
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.immichBackground.ignoresSafeArea()
                
                GlassEffectContainer {
                    List {
                        // Search field — glass pill
                        SearchField(query: $vm.searchQuery)
                            .glassEffect(.regular)
                        
                        // Results — glass rows
                        ForEach(vm.filteredUsers) { user in
                            UserSearchRow(user: user, selected: vm.selectedUserId == user.id)
                                .glassEffect(.regular)
                                .glassEffectID("user_\(user.id)", in: glassNamespace)
                        }
                    }
                    .listStyle(.plain)
                }
                .padding(PVSpacing.s16)
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Cancel") { dismiss() }
                        .glassEffect(.regular)
                }
            }
        }
    }
}
```

## Interactions

### Toggle "Show in Timeline"
- `.glassEffect(.interactive())` — tactile shimmer au tap
- Success: spring animation + haptic `.selection`
- Failure: toggle reverts with spring (damping 0.75) + error haptic

### Remove Partner
- Swipe-actions trailing (destructive red glass row)
- Confirmation dialog: glass-tinted background
- On confirm: DELETE + row removal with glass morph

### Invite New Partner
- FAB "+" glass capsule → morph into sheet via `glassEffectID`
- Email input in glass field surface
- Submit: glass shimmer on button press → loading state
- Success: glass toast "Partner invited" + vibration.success

### Empty States
- `ContentUnavailableView` avec SF Symbol
- Background: subtle glass overlay

## Liquid Glass (iOS 26 — PRIMARY)

### Philosophy
- **Toutes** les surfaces interactives sont des glass cards
- **Groupes** de rangées dans `GlassEffectContainer`
- **Morphing** du FAB en sheet via `glassEffectID`
- **Shimmer tactile** sur tous les toggles et boutons

### Specific applications
1. **Partner rows** : Each row is a glass card — like iOS contacts
2. **Toggle switches** : `.glassEffect(.interactive())` with tactile shimmer
3. **Segmented tab bar** : system glass (native iOS 26)
4. **Invite FAB** : glass capsule → morph into sheet
5. **User search** : glass search pill + glass result rows
6. **Confirmation dialogs** : glass-tinted background
7. **Empty state** : glass overlay with centered content

### Background
- Subtle blurred photo visible through glass — "window into the world"
- Creates depth and context for the glass surfaces

## Accessibility

- Glass cards maintain contrast via `.regular` glass (auto adjusts for Reduce Transparency)
- Partner row: `.accessibilityLabel("Partner: \(name), email: \(email), timeline: \(isOn ? "on" : "off")"`)
- Toggle: `.accessibilityLabel("Show in timeline: \(isOn ? "on" : "off")")`
- Remove: `.accessibilityLabel("Remove \(name)")`
- FAB: `.accessibilityLabel("Invite new partner")`
- All elements ≥ 44×44pt
- Reduce Motion: glass morphs → opacity crossfade, no shape change

## Animations

- FAB → sheet: `.glassEffectTransition(.matchedGeometry)` — shape morph
- Toggle change: `PVMotion.snappy` (0.25s, damping 0.75)
- Row swipe: system native
- Row removal: `.glassEffectTransition(.materialize)` — glass fades out
- Invite success: glass toast slide-up + opacity
- Reduce Motion: opacity-only fades, no morph

## Key Files Modified

- `Sources/Features/SharedLinks/PartnerShellView.swift` — NEW: main partner view with glass
- `Sources/Features/SharedLinks/PartnerShellViewModel.swift` — NEW: partner VM
- `Sources/Features/SharedLinks/InvitePartnerSheet.swift` — NEW: glass invite sheet
- `Sources/Features/SharedLinks/UserSearchView.swift` — NEW: glass user search
- `Sources/Features/SharedLinks/SharedLinksView.swift` — Add glass-tinted section
