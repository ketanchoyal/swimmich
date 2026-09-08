# Task: offline-download — UI Brief (Liquid Glass Primary)

## Design Philosophy

Le téléchargement offline est une **expérience vitrée** : le stockage est une jauge circulaire en glass, les assets sont des vignettes dans un grid glass, et chaque action de gestion est un bouton interactif. C'est comme l'app Stockage de iPhone mais avec des cartes vitrées et une jauge circulaire en glass.

## Layout

```
ProfileView (Me hub)
└── Form
    └── Section "Management"
        └── NavigationLink: Offline Storage → OfflineAssetsView (glass screen)

PhotoViewer (Viewer)
└── Share Sheet / Context Menu
    └── Button: "Download for Offline" — glass pill

TimelineView
└── AssetThumbnailCell
    └── Overlay: cached indicator (small glass circle with checkmark)
```

### OfflineAssetsView — Glass storage management
```
NavigationStack (scrollEdgeEffectStyle: glass)
├── ImmichAppBar (glass bar)
└── ZStack {
    ├── Background: subtle blurred photo
    └── GlassEffectContainer {
        ├── StorageUsageCard (glass card with circular progress ring)
        ├── SearchField (glass pill)
        ├── Section Header (glass pill)
        ├── AssetGrid — each cell is a glass card
        │   └── OfflineAssetCell (glass card with cached indicator)
        └── ClearAllButton (glass pill)
    }
    .padding(PVSpacing.s16)
```

## Components

### OfflineAssetsView — Glass storage management

```swift
struct OfflineAssetsView: View {
    @State var vm: OfflineDownloadViewModel
    @Namespace private var glassNamespace
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.immichBackground.ignoresSafeArea()
                
                GlassEffectContainer {
                    ScrollView {
                        VStack(spacing: PVSpacing.s16) {
                            // Storage usage card
                            storageUsageCard
                            
                            // Search
                            SearchField(query: $vm.searchQuery)
                                .glassEffect(.regular)
                                .padding(PVSpacing.s16)
                            
                            // Asset grid
                            if !vm.searchedAssets.isEmpty {
                                sectionHeader("Results")
                                assetGrid(vm.searchedAssets)
                            } else if vm.cachedAssets.isEmpty {
                                ContentUnavailableView(
                                    "No offline photos",
                                    systemImage: "externaldrive.badge.exclamationmark",
                                    description: Text("Download photos to view them without an internet connection.")
                                )
                            } else {
                                sectionHeader("Offline photos")
                                assetGrid(vm.cachedAssets)
                            }
                            
                            // Clear all
                            Button(role: .destructive) {
                                vm.showClearAllConfirm = true
                            } label: {
                                Label("Clear All Offline Photos", systemImage: "trash")
                                    .foregroundStyle(Color.immichError)
                                    .frame(maxWidth: .infinity)
                                    .padding(PVSpacing.s16)
                                    .glassEffect(.interactive())
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

### StorageUsageCard — Glass card with circular progress ring

```swift
private var storageUsageCard: some View {
    HStack(spacing: PVSpacing.s16) {
        // Info
        VStack(alignment: .leading, spacing: PVSpacing.s4) {
            Text("Offline Storage")
                .font(.pvHeadline.weight(.semibold))
            Text("\(formatSize(vm.cacheUsage)) used")
                .font(.pvCaption)
                .foregroundStyle(.secondary)
        }
        
        Spacer()
        
        // Circular progress ring — glass
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.immichGray.opacity(0.2), lineWidth: 8)
            
            // Progress ring — glass tinted
            Circle()
                .trim(from: 0, to: progressFraction)
                .stroke(
                    Color.immichPrimary.gradient.opacity(
                        usageColor == .error ? 0.6 : 1.0
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progressFraction)
            
            // Usage text in center
            Text(formatSize(vm.cacheUsage))
                .font(.caption)
                .fontWeight(.heavy)
                .foregroundStyle(usageColor)
        }
        .frame(width: 72, height: 72)
        .glassEffect(.regular)
    }
    .padding(PVSpacing.s16)
    .glassEffect(.regular)
}
```

### OfflineAssetCell — Glass card with cached indicator

```swift
struct OfflineAssetCell: View {
    let item: CachedAssetItem
    @State var vm: OfflineDownloadViewModel
    
    var body: some View {
        Button {
            showInViewer(item.asset)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                // Photo
                AsyncImage(url: item.asset.thumbnailURL) { phase in
                    phase.image?
                        .resizable()
                        .scaledToFill()
                    phase.errorView
                }
                .aspectRatio(1, contentMode: .fill)
                
                // Cached indicator — small glass circle
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.immichSuccess)
                    .glassEffect(.regular)
                    .frame(width: 20, height: 20)
                    .position(x: 60, y: 4)
                
                // Video badge
                if item.asset.isVideo {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .glassEffect(.regular)
                        .frame(width: 28, height: 16)
                        .position(x: 16, y: 4)
                }
            }
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: PVRadius.sm, style: .continuous))
        }
        .glassEffect(.regular)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { vm.removeCached(item.asset.id) }
                .label { Label("Remove", systemImage: "xmark.circle.fill") }
        }
        .contextMenu {
            Button("Open in Maps") { /* existing */ }
            Button("Remove from Offline") { vm.removeCached(item.asset.id) }
        }
    }
}
```

### PhotoViewer "Download for offline" — Glass action

Dans le context menu du viewer, ajouté au share sheet :

```swift
// Dans PhotoViewer context menu:
Button { vm.downloadForOffline() } label: {
    Label("Download for Offline", systemImage: "arrow.down.circle")
        .foregroundStyle(Color.immichPrimary)
        .glassEffect(.interactive())
}
```

### Download Progress Toast — Glass overlay

Pendant le téléchargement, un toast vitré apparaît au-dessus de la barre de navigation :

```swift
struct DownloadProgressToast: View {
    let progress: Double
    let status: DownloadStatus
    
    var body: some View {
        HStack(spacing: PVSpacing.s8) {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .tint(Color.immichPrimary)
                .frame(width: 16, height: 16)
                .glassEffect(.interactive())
            
            Text(status.label)
                .font(.pvCaption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button("Dismiss") { dismiss() }
                .font(.pvCaption.weight(.semibold))
                .foregroundStyle(Color.immichPrimary)
                .glassEffect(.interactive())
        }
        .padding(PVSpacing.s8)
        .glassEffect(.regular)
    }
}
```

## Interactions

### Download for Offline (from viewer)
- Tap "Download for offline" in context menu → glass shimmer
- Toast "Downloading..." with progress ring
- Complete: toast "Saved for offline" + haptic success + checkmark appears
- Failure: glass toast "Download failed — try again" + retry button

### View Offline Asset
- Tap any cached asset in grid → opens PhotoViewer
- Viewer banner: "Available offline" in glass card
- Download progress: thin progress ring in viewer toolbar

### Remove from Offline
- Swipe right → "Remove" button (destructive glass row)
- Context menu → "Remove from Offline"
- Confirmation: "Remove this photo? \(formatSize(assetSize)) will be freed."
- On confirm: DELETE cache + row removal with glass morph

### Clear All
- Bottom of list → "Clear All Offline Photos" (glass pill)
- Confirmation dialog (glass-tinted)
- On confirm: remove all + toast "Storage cleared"

### Storage Usage Ring
- Circular progress ring in glass card
- Color changes: primary → warning (80%) → error (90%)
- When over 80%: subtle pulse animation on the ring

## Liquid Glass (iOS 26 — PRIMARY)

### Philosophy
- **Toutes** les surfaces interactives sont des glass cards
- **Groupes** de controls dans `GlassEffectContainer`
- **Morphing** du bouton en sheet via `glassEffectID`
- **Shimmer tactile** sur tous les éléments interactifs
- **Jauge circulaire** vitrée pour le stockage

### Specific applications
1. **Storage card** : Glass card with circular progress ring — storage usage visualized
2. **Asset cells** : Glass cards in grid — photos visible through glass
3. **Cached indicator** : Small glass circle with checkmark — glass pill
4. **Download button** : `.glassEffect(.interactive())` — shimmer on press
5. **Download progress** : Glass floating toast with progress ring
6. **Search field** : Glass pill
7. **Clear all button** : Glass pill
8. **Asset selection** : Glass card with tactile shimmer on tap
9. **Video badge** : Small glass capsule

### Background
- Subtle blurred photo behind glass cards — context and depth

## Accessibility

- Glass cards maintain contrast via `.regular` glass (auto adjusts for Reduce Transparency)
- Asset cell: `.accessibilityLabel("Photo from [date], available offline")`
- Download button: `.accessibilityLabel("Download photo for offline viewing")`
- Remove button: `.accessibilityLabel("Remove photo from offline storage")`
- Clear all: `.accessibilityLabel("Clear all offline photos")`
- Storage ring: `.accessibilityLabel("Offline storage used: \(formatSize(vm.cacheUsage)) of \(formatSize(vm.maxCacheSize))")`
- All elements ≥ 44×44pt
- Reduce Motion: glass morphs → opacity crossfade, no shape change

## Animations

- Download progress: thin linear ProgressView — `.contentTransition(.numericText())`
- Checkmark appearance: `.contentTransition(.symbolEffect(.replace))`
- Asset removal: `.glassEffectTransition(.materialize)` — glass fades out
- Storage ring: `.contentTransition(.opacity)` — smooth changes
- Toast appearance: `.move(edge: .top).combined(with: .opacity)` — spring 0.35s
- Reduce Motion: all glass morphs → `.identity` (crossfade), no shape change

## Key Files Modified

- `Sources/Features/Offline/OfflineDownloadViewModel.swift` — NEW: download logic
- `Sources/Features/Offline/OfflineAssetsView.swift` — NEW: glass storage management
- `Sources/Services/OfflineAssetStore.swift` — NEW: file-based cache
- `Sources/Features/PhotoViewer/PhotoViewer.swift` — Add "Download for offline" glass action
- `Sources/Features/PhotoViewer/PhotoViewer.swift` — Download progress toast
- `Sources/Features/Timeline/AssetThumbnailCell.swift` — Cached indicator overlay (glass circle)
- `Sources/Features/Profile/ProfileView.swift` — Add "Offline Storage" glass navigation link
