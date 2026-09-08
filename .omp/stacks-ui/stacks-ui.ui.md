# Task: stacks-ui — UI Brief (Liquid Glass Primary)

## Design Philosophy

Les stacks sont des **pile de mémoire vitrées** — chaque stack est une carte vitrée qui contient des photos. La gestion des stacks se fait via des contrôles interactifs en glass. C'est comme l'app Photos de Apple avec des stacks de verre.

## Layout

```
ProfileView (Me hub)
└── Form
    └── Section "Management"
        └── NavigationLink: Stacks → StackView (glass screen)

StackView
└── NavigationStack (scrollEdgeEffectStyle: glass)
    ├── ImmichAppBar (glass bar)
    └── ZStack {
        ├── Background: subtle blurred photo
        └── GlassEffectContainer {
            ├── Section Header (glass pill)
            ├── StackList — each item is a glass card
            │   └── StackRow (glass card with thumbnail collage)
            └── FAB "+" — glass capsule, morphs into create sheet
        }
        .padding(PVSpacing.s16)
```

### StackDetailView — Glass stack management
```
NavigationStack
├── ImmichAppBar (glass bar)
└── ZStack {
    ├── Background
    └── GlassEffectContainer {
        ├── Primary asset — glass card (larger)
        ├── Other assets — glass cards (smaller)
        └── Actions — glass pills
    }
```

### StackSheet (enhanced viewer) — Glass stack viewer
```
PhotoViewer
└── Context menu / toolbar
    └── StackSheet (glass overlay)
        ├── All assets grid — glass cards
        └── Controls — glass pills
```

## Components

### StackView — Glass stack list

```swift
struct StackView: View {
    @State var vm: StacksViewModel
    @Namespace private var glassNamespace
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.immichBackground.ignoresSafeArea()
                
                GlassEffectContainer {
                    List {
                        if vm.stacks.isEmpty {
                            ContentUnavailableView(
                                "No stacks yet",
                                systemImage: "square.stack.3d.down.right",
                                description: Text("Group similar photos together to keep your timeline clean.")
                            )
                        } else {
                            ForEach(vm.stacks.prefix(20)) { stack in
                                NavigationLink {
                                    StackDetailView(stack: stack, vm: vm)
                                } label: {
                                    StackRowView(stack: stack)
                                        .glassEffect(.regular)
                                        .glassEffectID("stack_\(stack.id)", in: glassNamespace)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .padding(.horizontal, PVSpacing.s4)
                    .padding(PVSpacing.s16)
                }
                .padding(.horizontal, PVSpacing.s16)
            }
            .toolbar {
                ToolbarItem(placement: .principal) { ImmichAppBar(title: "Stacks") }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { vm.showCreate = true } label: {
                        Image(systemName: "plus")
                            .glassEffect(.interactive())
                            .frame(width: 32, height: 32)
                    }
                }
            }
            .sheet(isPresented: $vm.showCreate) {
                CreateStackSheet(vm: vm)
            }
        }
    }
}
```

### StackRowView — Glass card with thumbnail collage

```swift
struct StackRowView: View {
    let stack: StackResponseDto
    @Namespace private var rowNamespace
    
    var body: some View {
        HStack(spacing: PVSpacing.s12) {
            // Thumbnail collage — glass card
            ZStack(alignment: .topLeading) {
                // Primary asset (full)
                AsyncImage(url: primaryAsset.thumbnailURL) { phase in
                    phase.image?
                        .resizable()
                        .scaledToFill()
                    phase.errorView
                }
                .aspectRatio(1, contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: PVRadius.sm, style: .continuous))
                
                // Count badge — glass pill
                if stack.assets.count > 1 {
                    Text("+\(stack.assets.count - 1)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.immichPrimary.opacity(0.8), in: Circle())
                        .position(x: 48, y: 8)
                }
            }
            .glassEffect(.regular)
            
            // Info
            VStack(alignment: .leading, spacing: PVSpacing.s2) {
                Text("\(stack.assets.count) photos")
                    .font(.pvBody.weight(.semibold))
                Text(stack.lastModified.formatted(date: .abbreviated, time: .shortened))
                    .font(.pvCaption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Arrow — glass pill
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .glassEffect(.regular)
                .frame(width: 20, height: 20)
        }
        .padding(PVSpacing.s12)
        .glassEffect(.regular)
    }
}
```

### StackDetailView — Glass stack management

```swift
struct StackDetailView: View {
    let stack: StackResponseDto
    @Bindable var vm: StacksViewModel
    @Environment(\.dismiss) private var dismiss
    @Namespace private var glassNamespace
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.immichBackground.ignoresSafeArea()
                
                GlassEffectContainer {
                    VStack(spacing: PVSpacing.s16) {
                        // Primary asset — large glass card
                        assetCard(stack.assets.first { $0.id == stack.primaryAssetId } ?? stack.assets.first!, isPrimary: true)
                        
                        // Other assets
                        if stack.assets.count > 1 {
                            HStack {
                                Text("\(stack.assets.count - 1) other")
                                    .font(.pvHeadline.weight(.semibold))
                                Spacer()
                            }
                            .padding(.horizontal, PVSpacing.s12)
                            .padding(.vertical, PVSpacing.s8)
                            .background(.thinMaterial, in: Capsule())
                            .glassEffect(.regular)
                            
                            ForEach(stack.assets.filter { $0.id != stack.primaryAssetId }) { asset in
                                assetCard(asset, isPrimary: false)
                                    .glassEffect(.regular)
                                    .glassEffectID("stack_asset_\(asset.id)", in: glassNamespace)
                            }
                        }
                        
                        // Delete action
                        Button(role: .destructive) { vm.deleteStack(stack.id) } label: {
                            Label("Delete Stack", systemImage: "trash")
                                .foregroundStyle(Color.immichError)
                                .frame(maxWidth: .infinity)
                                .padding(PVSpacing.s16)
                                .glassEffect(.interactive())
                        }
                    }
                    .padding(PVSpacing.s16)
                }
                .padding(.horizontal, PVSpacing.s16)
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

### assetCard — Glass photo card

```swift
private func assetCard(_ asset: AssetResponseDto, isPrimary: Bool) -> some View {
    HStack(spacing: PVSpacing.s12) {
        AsyncImage(url: asset.thumbnailURL) { phase in
            phase.image?
                .resizable()
                .scaledToFill()
            phase.errorView
        }
        .aspectRatio(1, contentMode: .fill)
        .frame(width: isPrimary ? 80 : 40, height: isPrimary ? 80 : 40)
        .clipShape(RoundedRectangle(cornerRadius: PVRadius.sm, style: .continuous))
        
        VStack(alignment: .leading, spacing: PVSpacing.s2) {
            Text(asset.takeShotAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")
                .font(isPrimary ? .pvBody : .pvSubhead)
                .foregroundStyle(isPrimary ? .primary : .secondary)
            
            if asset.isFavorite {
                Text("Favorite")
                    .font(.pvCaption)
                    .foregroundStyle(Color.immichWarning)
                    .glassEffect(.regular)
                    .padding(.horizontal, PVSpacing.s6)
                    .padding(.vertical, PVSpacing.s2)
            }
        }
        
        Spacer()
        
        if isPrimary {
            Image(systemName: "star.fill")
                .font(.caption)
                .foregroundStyle(Color.immichWarning)
                .glassEffect(.interactive())
                .frame(width: 24, height: 24)
        }
        
        if !isPrimary {
            Button { vm.removeAssetFromStack(stack.id, asset.id) } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
                    .glassEffect(.interactive())
                    .frame(width: 32, height: 32)
            }
        }
    }
    .padding(isPrimary ? PVSpacing.s16 : PVSpacing.s12)
}
```

### CreateStackSheet — Glass create form

```swift
struct CreateStackSheet: View {
    @Bindable var vm: StacksViewModel
    @Environment(\.dismiss) private var dismiss
    @Namespace private var glassNamespace
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.immichBackground.ignoresSafeArea()
                
                GlassEffectContainer {
                    Form {
                        Section("Select Photos") {
                            Button("Choose Photos") { presentPhotoPicker() }
                                .foregroundStyle(Color.immichPrimary)
                                .glassEffect(.interactive())
                            
                            if !vm.selectedPhotos.isEmpty {
                                Text("\(vm.selectedPhotos.count) photos selected")
                                    .font(.pvCaption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Section("Stack Name") {
                            TextField("Optional name", text: $vm.stackName)
                                .pvFieldSurface(focused: $vm.inputFocused)
                        }
                    }
                    .formStyle(.grouped)
                }
                .padding(PVSpacing.s16)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { vm.createStack() }
                        .disabled(vm.selectedPhotos.isEmpty)
                        .glassEffect(.interactive())
                }
            }
        }
    }
}
```

## Interactions

### Create Stack
- FAB "+" glass capsule → morph into create sheet via `glassEffectID`
- Choose photos via UIActivityViewController
- Optional stack name
- Submit → glass shimmer button press → toast "Stack created"

### View Stack Detail
- Tap stack row → Glass morph into detail (matchedGeometryEffect)
- Shows all assets in the stack
- Primary asset highlighted (larger glass card + star badge)
- Non-primary assets can be removed (x button, glass interactive)

### StackSheet (enhanced in PhotoViewer)
- When viewing a stack: shows all assets in a grid (glass cards)
- Primary asset has a star badge (glass interactive)
- Swipe on non-primary → "Remove from stack" (glass row)
- Long press → "Set as primary" (glass menu)
- "Delete Stack" at bottom (destructive glass pill)

### Timeline Stacked Thumbnails
- When `withStacked: true`, timeline shows composite thumbnails
- Each composite = primary photo + "+N" badge (small glass pill)
- Tap composite → StackDetailView (glass morph)

### Remove from Stack
- Swipe right on non-primary → "Remove" (destructive glass row)
- Row removal with glass morph animation
- Stack count updates immediately

### Delete Stack
- Bottom of StackDetailView → "Delete Stack" (destructive glass pill)
- Confirmation dialog (glass-tinted background)
- DELETE → toast "Stack deleted"

## Liquid Glass (iOS 26 — PRIMARY)

### Philosophy
- **Toutes** les stacks sont des cartes vitrées
- **Groupes** de controls dans `GlassEffectContainer`
- **Morphing** du FAB en sheet via `glassEffectID`
- **Badges** de stack comme capsules vitrées colorées
- **Shimmer tactile** sur tous les éléments interactifs

### Specific applications
1. **Stack rows** : Glass cards — each stack is a glass window
2. **Thumbnail collage** : Glass card with "+N" badge (glass pill)
3. **Stack detail** : Large glass card for primary, smaller for others
4. **Star badge** : `.glassEffect(.interactive())` on primary indicator
5. **Remove button** : `.glassEffect(.interactive())` on x button
6. **Delete action** : Destructive glass pill
7. **Create form** : All inputs in glass field surfaces
8. **Empty state** : Glass overlay with centered content

### Background
- Subtle blurred photo behind glass stack cards — context and depth

## Accessibility

- Glass cards maintain contrast via `.regular` glass (auto adjusts for Reduce Transparency)
- Stack row: `.accessibilityLabel("\(count) photos in stack from \(date)")`
- Stack detail: `.accessibilityLabel("Stack: \(name), \(count) photos")`
- Remove button: `.accessibilityLabel("Remove from stack")`
- Set as primary: `.accessibilityLabel("Set as primary photo")`
- Delete stack: `.accessibilityLabel("Delete this stack")`
- All elements ≥ 44×44pt
- Reduce Motion: glass morphs → opacity crossfade, no shape change

## Animations

- FAB → create sheet: `.glassEffectTransition(.matchedGeometry)` — shape morph
- Row tap → detail: `.matchedGeometryEffect` (card grows from list to detail)
- Asset removal: `.glassEffectTransition(.materialize)` — glass fades
- Star swap: `.contentTransition(.symbolEffect(.replace))`
- Stack creation: list insert with `.move(edge: .top)` animation
- Reduce Motion: all glass morphs → `.identity` (crossfade), no shape change

## Key Files Modified

- `Sources/Features/Stacks/StackView.swift` — NEW: glass stack list
- `Sources/Features/Stacks/StacksViewModel.swift` — NEW: stack management VM
- `Sources/Features/Stacks/StackDetailView.swift` — NEW: glass stack detail
- `Sources/Features/Stacks/CreateStackSheet.swift` — NEW: glass create form
- `Sources/Features/PhotoViewer/StackSheet.swift` — Enhance: glass grid + remove + set primary
- `Sources/Features/Timeline/TimelineView.swift` — Composite thumbnails with glass "+N" badge
- `Sources/Features/Profile/ProfileView.swift` — Add "Stacks" glass navigation link
