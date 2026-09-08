# Task: memories-complete — UI Brief (Liquid Glass Primary)

## Design Philosophy

Les memories sont des **fragments de temps vitrés** — des cartes en glass qui laissent voir les photos en arrière-plan. Le tab bar est glass, chaque memory card est une fenêtre vitrée sur des souvenirs. C'est comme le widget Memories de Apple mais en plus immersif.

## Layout

```
NavigationStack (scrollEdgeEffectStyle: glass)
├── ImmichAppBar (glass morphing bar, scrollEdge)
└── ZStack {
    ├── Background: subtle blurred photo
    └── GlassEffectContainer {
        ├── ScrollView {
        │   └── LazyVStack {
        │       ├── FavoritesHeader (glass pill)
        │       ├── FavoriteMemoryCard (glass card)
        │       ├── FavoriteMemoryCard
        │       ├── Divider (glass line)
        │       ├── OnThisDayHeader (glass pill)
        │       ├── MemoryCard (glass card)
        │       ├── MemoryCard
        │       ├── Divider (glass line)
        │       ├── FirstDayHeader (glass pill)
        │       ├── MemoryCard (glass card)
        │       └── YearlyRecapHeader (glass pill)
        │   }
        │   └── MemoryCard (glass card)
        │   }
        │   }
        └── FAB "+" — glass capsule, morphs into create sheet
    }
```

## Components

### MemoriesView — Glass memory cards

```swift
struct MemoriesView: View {
    @State var vm: MemoriesViewModel
    @Namespace private var glassNamespace
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.immichBackground.ignoresSafeArea()
                
                GlassEffectContainer {
                    ScrollView {
                        LazyVStack(spacing: PVSpacing.s16) {
                            // Favorites section
                            sectionHeader("Favorites", symbol: "bookmark.fill")
                            ForEach(vm.savedMemories) { memory in
                                MemoryCardView(memory: memory)
                                    .glassEffect(.regular)
                                    .glassEffectID("memory_\(memory.id)", in: glassNamespace)
                            }
                            
                            Divider()
                            
                            // On This Day section
                            sectionHeader("On This Day", symbol: "calendar.badge.clock")
                            ForEach(vm.onThisDayMemories) { memory in
                                MemoryCardView(memory: memory)
                                    .glassEffect(.regular)
                                    .glassEffectID("memory_\(memory.id)", in: glassNamespace)
                            }
                            
                            // First Day section
                            sectionHeader("First Day", symbol: "calendar.badge.plus")
                            ForEach(vm.firstDayMemories) { memory in
                                MemoryCardView(memory: memory)
                                    .glassEffect(.regular)
                                    .glassEffectID("memory_\(memory.id)", in: glassNamespace)
                            }
                            
                            // Yearly Recap section
                            sectionHeader("Year in Review", symbol: "sparkles")
                            ForEach(vm.yearlyRecapMemories) { memory in
                                MemoryCardView(memory: memory)
                                    .glassEffect(.regular)
                                    .glassEffectID("memory_\(memory.id)", in: glassNamespace)
                            }
                        }
                        .padding(PVSpacing.s16)
                    }
                }
                .padding(.horizontal, PVSpacing.s16)
            }
            .toolbar { ImmichAppBar() }
        }
    }
}
```

### MemoryCardView — Glass window on memories

```swift
struct MemoryCardView: View {
    let memory: MemoryResponseDto
    @State var vm: MemoriesViewModel
    @Namespace private var cardNamespace
    
    var body: some View {
        VStack(alignment: .leading, spacing: PVSpacing.s12) {
            // Header: type badge + title + save button
            HStack {
                // Type badge — glass pill
                HStack(spacing: PVSpacing.s4) {
                    Image(systemName: memory.type.symbol)
                        .font(.caption)
                    Text(memory.type.displayName)
                        .font(.caption2)
                        .fontWeight(.heavy)
                }
                .foregroundStyle(memory.type.badgeColor)
                .padding(.horizontal, PVSpacing.s8)
                .padding(.vertical, PVSpacing.s4)
                .background(.ultraThinMaterial, in: Capsule())
                .glassEffect(.regular)
                
                Spacer()
                
                // Save button — glass interactive
                Button { vm.toggleSave(memory.id) } label: {
                    Image(systemName: memory.isSaved ? "bookmark.fill" : "bookmark")
                        .font(.pvBody)
                        .foregroundStyle(memory.isSaved ? Color.immichPrimary : .secondary)
                        .glassEffect(.interactive())
                        .frame(width: 32, height: 32)
                }
            }
            
            // Asset grid
            if !memory.assets.isEmpty {
                LazyVGrid(columns: photoColumns, spacing: PVSpacing.s4) {
                    ForEach(memory.assets.prefix(6)) { asset in
                        AsyncImage(url: asset.thumbnailPath.map(URL.init)) { phase in
                            phase.image?
                                .resizable()
                                .scaledToFill()
                            phase.errorView
                        }
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 0))
                    }
                }
            }
            
            // Asset count
            HStack {
                Image(systemName: "photo.badge.camera")
                    .foregroundStyle(.secondary)
                Text("\(memory.assets.count) photos")
                    .font(.pvCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(PVSpacing.s16)
        .glassEffect(.regular)
        .contextMenu {
            memoryContextMenu
        }
    }
}
```

### Section Header — Glass pill

```swift
private func sectionHeader(_ title: String, symbol: String) -> some View {
    HStack(spacing: PVSpacing.s8) {
        Image(systemName: symbol)
            .font(.pvBody)
            .foregroundStyle(Color.immichPrimary)
        Text(title)
            .font(.pvHeadline.weight(.semibold))
    }
    .padding(.horizontal, PVSpacing.s12)
    .padding(.vertical, PVSpacing.s8)
    .background(.ultraThinMaterial, in: Capsule())
    .glassEffect(.regular)
}
```

### Context Menu — Glass menu

```swift
private var memoryContextMenu: some ToolbarContent {
    Menu {
        Button { vm.toggleSave(memory.id) } label: {
            Label(memory.isSaved ? "Unsave" : "Save", systemImage: memory.isSaved ? "bookmark.slash" : "bookmark")
        }
        
        Button("Edit Memory") { openEditSheet() }
        
        if memory.type != .on_this_day {
            Button("Delete Memory", role: .destructive) { vm.deleteMemory(memory.id) }
        }
    } label: {
        Image(systemName: "ellipsis.circle")
            .foregroundStyle(.secondary)
            .glassEffect(.interactive())
            .frame(width: 32, height: 32)
    }
}
```

### CreateMemorySheet — Glass morph from FAB

```swift
struct CreateMemorySheet: View {
    @Bindable var vm: MemoriesViewModel
    @Environment(\.dismiss) private var dismiss
    @Namespace private var glassNamespace
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.immichBackground.ignoresSafeArea()
                
                GlassEffectContainer {
                    Form {
                        Section("Type") {
                            ForEach(MemoryType.allCases, id: \.self) { type in
                                TypeSelectionRow(type: type, selected: vm.selectedType == type)
                                    .glassEffect(.regular)
                                    .glassEffectID("type_\(type.rawValue)", in: glassNamespace)
                            }
                        }
                        
                        Section("Title") {
                            TextField("Memory name", text: $vm.memoryTitle)
                                .pvFieldSurface(focused: $vm.inputFocused)
                        }
                        
                        Section("Date") {
                            DatePicker("Memory date", selection: $vm.memoryDate, displayedComponents: .date)
                        }
                        
                        Section("Photos") {
                            Button("Choose Photos") { presentPhotoPicker() }
                                .foregroundStyle(Color.immichPrimary)
                                .glassEffect(.interactive())
                            
                            if !vm.selectedPhotos.isEmpty {
                                Text("\(vm.selectedPhotos.count) photos selected")
                                    .font(.pvCaption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
                .padding(PVSpacing.s16)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { vm.createMemory() }
                        .disabled(vm.isCreating || vm.selectedPhotos.isEmpty)
                }
            }
        }
    }
}
```

## Interactions

### Save/Unsave Memory
- Context menu button: `.glassEffect(.interactive())` with shimmer
- Star fill animation: `.contentTransition(.symbolEffect(.replace))`
- Haptic: `.impact(.medium)` save, `.impact(.light)` unsave

### Create Memory
- FAB "+" glass capsule → morph into create sheet via `glassEffectID`
- Type selection: glass pill rows, shimmer on tap
- Submit: glass shimmer button press → loading → success toast
- Success: glass toast "Memory created" + vibration.success

### Delete Memory
- Context menu "Delete" → confirmation dialog (glass-tinted)
- DELETE → card removal with glass morph
- Toast: glass toast "Memory deleted"

## Liquid Glass (iOS 26 — PRIMARY)

### Philosophy
- **Toutes** les memory cards sont des fenêtres vitrées sur des photos
- **Groupes** de controls dans `GlassEffectContainer`
- **Morphing** du FAB en sheet via `glassEffectID`
- **Badges** de type comme capsules vitrées colorées
- **Shimmer tactile** sur tous les éléments interactifs

### Specific applications
1. **Memory cards** : Glass cards with photos visible through — "window into memories"
2. **Type badges** : Small glass pills with color tints (purple, green, blue)
3. **Save button** : `.glassEffect(.interactive())` — tactile shimmer
4. **Context menu** : glass-tinted button for ellipsis
5. **Section headers** : Glass pills with SF Symbols
6. **Create FAB** : Glass capsule → morph into create sheet
7. **Type selection** : Glass pill rows in create sheet
8. **Create buttons** : Glass shimmer on press

### Background
- Subtle blurred photo visible through glass — creates context for each memory
- Different blur intensity per section (favorites more opaque, memories more transparent)

## Accessibility

- Glass cards maintain contrast via `.regular` glass (auto adjusts for Reduce Transparency)
- Memory card: `.accessibilityLabel("Memory: [type], [count] photos from year \(year)")`
- Save button: `.accessibilityLabel("Save memory" / "Unsave memory")`
- FAB: `.accessibilityLabel("Create new memory")`
- All elements ≥ 44×44pt
- Reduce Motion: glass morphs → opacity crossfade, no shape change

## Animations

- FAB → create sheet: `.glassEffectTransition(.matchedGeometry)` — shape morph
- Star fill: `.contentTransition(.symbolEffect(.replace))`
- Card removal: `.glassEffectTransition(.materialize)` — glass fades
- Type selection: `PVMotion.snappy` (0.25s, damping 0.75)
- Create success: glass toast slide-up + opacity
- Reduce Motion: all glass morphs → `.identity` (crossfade), no shape change

## Key Files Modified

- `Sources/Features/Memories/MemoriesView.swift` — Glass memory cards + context menu + FAB
- `Sources/Features/Memories/MemoriesViewModel.swift` — toggleSave, createMemory, deleteMemory
- `Sources/Features/Memories/MemoryCardView.swift` — NEW: glass card component
- `Sources/Features/Memories/CreateMemorySheet.swift` — NEW: glass create sheet
- `Sources/Core/Types/DTOs+Social.swift` — MemoryType extensions (displayName, symbol, badgeColor)
