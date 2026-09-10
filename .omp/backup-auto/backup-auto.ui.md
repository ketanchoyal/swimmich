# Task: backup-auto — UI Brief (Liquid Glass Primary)

> **Révision du 2026-09-10** — la `BackfillReorganizeButton` / `BackfillSheet` décrites plus bas ont été RETIRÉES (doublon du scoping d'albums + « Run now »). La section « Security / Require Face ID » a quitté l'écran Backup pour `ProfileView` (« Me » → Security). Le scoping d'albums est désormais un mode tri-état (All / Only selected / All but selected) : un `Picker` + un seul `NavigationLink` contextuel.

## Design Philosophy

Tout l'écran est pensé **à partir du matériau vitreux** — pas une couche ajoutée après, mais la fondation de chaque surface, contrôle et interaction. Le user voit des photos en arrière-plan à travers les surfaces vitrées. C'est Apple qui a fait ça.

## Layout

`BackupSettingsView` existe déjà (~240 lignes). On **étend** l'écran existant.

### Structure cible
```
NavigationStack (scrollEdgeEffectStyle: glass)
└── ZStack (photos en background, glass overlay)
    ├── ImmichAppBar (glass morphing bar, scrollEdge)
    ├── ScrollView {
    │   └── GlassEffectContainer {  ← TODOUS les contrôles dans un container
    │       ├── BackfillReorganizeButton (glass morphing into sheet)
    │       ├── BackupToggleRow (glass card)
    │       ├── BackupToggleRow
    │       ├── BackupToggleRow
    │       ├── BackupToggleRow
    │       ├── BackupToggleRow
    │       ├── BackupToggleRow
    │       ├── AlbumSelectorButton (glass pill)
    │       ├── AlbumSelectorButton
    │       ├── ResumeToggleRow
    │       ├── UploadHistoryButton (glass pill)
    │       └── ProgressCard (morphs from idle→checking→uploading→done)
    │   }
    └── UploadProgressBanner (floating glass bar at top, morphs into progress card when running)
```

## Components

### GlassEffectContainer — Le fondement de la page

Tous les contrôles de backup sont encapsulés dans un seul `GlassEffectContainer`. Le système de rendu unifie le flou, les reflets et les ombres pour un groupe cohérent de surfaces vitrées — exactement ce qu'on voit dans les paramètres iOS de Apple.

```swift
struct BackupSettingsView: View {
    @State var vm: UploadViewModel
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Photos en background (subtle, only when no photo visible)
                ZStack {
                    Color.immichBackground.ignoresSafeArea()
                    photoBackgroundThumbnail
                        .opacity(0.15)
                        .blur(radius: 30)
                        .blur(radius: 15)
                }
                .blur(radius: 30)
                .opacity(0.08)
                
                // Content area — everything glass
                GlassEffectContainer {
                    contentArea
                }
                .padding(.horizontal, PVSpacing.s16)
                .padding(.top, PVSpacing.s24)
                .padding(.bottom, PVSpacing.s48)
            }
            .toolbar { ImmichAppBar() }
        }
    }
}
```

### BackfillReorganizeButton — Glass morphing into sheet

Le bouton principal CTA est une capsule vitrée qui se transforme (glass morph) en sheet quand tapée. L'animation de morphing est gérée par `glassEffectID` + namespace.

```swift
Button { vm.showBackfillSheet = true } label: {
    HStack(spacing: PVSpacing.s12) {
        Image(systemName: "rectangle.on.rectangle.angled")
            .font(.pvBody)
            .foregroundStyle(Color.immichPrimary)
        Text("Reorganize & Upload")
            .font(.pvHeadline.weight(.semibold))
        Spacer()
        Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding(PVSpacing.s16)
    .glassEffect(.regular.tint(Color.immichPrimary.opacity(0.1)))
}
```

**Morphing** : Quand la sheet s'ouvre, le bouton `backup_reorganize` morph en le header de la sheet via `.glassEffectID("backup_reorganize", in: glassNamespace)`. Le bouton "disparaît" tandis que la sheet "apparaît" — c'est une continuité spatiale Apple.

### BackupToggleRow — Glass card row

Chaque toggle n'est pas dans un Form natif mais dans une cellule vitrée individuellement :

```swift
struct BackupToggleRow: View {
    let title: String
    let description: String?
    @Binding var isOn: Bool
    @Namespace private var glassNamespace
    
    var body: some View {
        HStack(spacing: PVSpacing.s12) {
            VStack(alignment: .leading, spacing: PVSpacing.s2) {
                Text(title)
                    .font(.pvBody.weight(.semibold))
                if let description {
                    Text(description)
                        .font(.pvCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(Color.immichPrimary)
                .glassEffect(.interactive())
                .frame(width: 40, height: 24)
        }
        .padding(PVSpacing.s12)
        .glassEffect(.regular)
        .glassEffectID("row", in: glassNamespace)
    }
}
```

**Désign rationale** : Un Form natif est plat — un matériau uniforme. Des cellules vitrées individuelles créent de la profondeur et du rythme visuel, comme les cellules de réglages iOS. Le `.glassEffect(.interactive())` sur le switch ajoute le shimmer tactile au tap.

### UploadProgressBanner — Floating glass bar

Le banner est une barre flottante en haut de la timeline qui utilise la `scrollEdgeEffectStyle` pour se fondre dans le contenu au scroll.

```swift
struct UploadProgressBanner: View {
    var activity: BackupActivity
    
    var body: some View {
        HStack(spacing: PVSpacing.s12) {
            // Circular progress
            ProgressView(value: activity.uploaded, total: activity.total)
                .progressViewStyle(.circular)
                .tint(Color.immichPrimary)
                .frame(width: 24, height: 24)
                .glassEffect(.interactive())
            
            // Labels
            VStack(alignment: .leading, spacing: 2) {
                Text("Uploading")
                    .font(.pvSubhead.weight(.semibold))
                Text("\(activity.uploaded) / \(activity.total)")
                    .font(.pvCaption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            
            Spacer()
            
            // Retry button (if error)
            if let error = activity.error {
                Button("Retry") { retryAction() }
                    .font(.pvSubhead.weight(.semibold))
                    .foregroundStyle(Color.immichError)
                    .glassEffect(.interactive())
            }
        }
        .padding(PVSpacing.s12)
        .glassEffect(.regular)
        .scrollEdgeEffectStyle(.floating) // Floats on scroll edge
    }
}
```

**Design rationale** : `.scrollEdgeEffectStyle(.floating)` — le banner se fond avec le contenu scrollé en arrière-plan, exactement comme la tab bar de Safari. Quand l'upload est terminé, il morph en un petit toast vitré en bas de l'écran.

### UploadHistoryRow — Glass list row

```swift
struct UploadHistoryRow: View {
    let entry: UploadHistoryEntry
    
    var body: some View {
        HStack(spacing: PVSpacing.s12) {
            // Status icon — glass pill
            statusIcon
                .glassEffect(.regular)
                .frame(width: 32, height: 32)
            
            // Info
            VStack(alignment: .leading, spacing: PVSpacing.s2) {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.pvBody)
                Text("\(entry.uploaded)/\(entry.total) uploaded")
                    .font(.pvCaption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Status badge — glass pill
            statusBadge
                .glassEffect(.regular)
        }
        .padding(PVSpacing.s12)
        .glassEffect(.regular)
        .contentShape(Rectangle())
        .glassEffectID("history_row", in: historyNamespace)
    }
}
```

## Interactions

### Toggle Auto-Detect New Photos
- Toggle dans cellule vitrée avec `.glassEffect(.interactive())`
- Quand activé, un subtile shimmer apparait autour du switch
- Quand désactivé, les toggles restants deviennent légèrement désaturés (disabled glass)

### Backfill Reorganize CTA
- Tap → `glassEffectID` morph du bouton vers le sheet header
- Sheet:玻璃 EffectContainer avec sections vitrées
- Completion : toast vitré "Photos reorganized" en bas

### Upload Progress Banner
- `scrollEdgeEffectStyle(.floating)` — se fond avec le contenu
- Tap → ouvre UploadHistory dans un NavigationStack (la timeline scroll derrière)
- Swipe-down pour dismiss
- Disparaît après 3s → morph en petit badge "Upload done" en bas

### Retry Button
- `.glassEffect(.interactive())` — shimmer au tap
- Impact haptique `medium` au tap

## Liquid Glass (iOS 26 — PRIMARY)

### Philosophy
- **TODOUS** les surfaces interactives ont `.glassEffect(.regular)`
- **Groupes** de contrôles reliés dans `GlassEffectContainer` pour un rendu unifié
- **Morphing** de boutons en sheets via `.glassEffectID(_:in:)` + `@Namespace`
- **Floating** elements utilisent `scrollEdgeEffectStyle` pour se fondre
- **Shimmer tactile** sur tous les éléments interactifs via `.interactive()`

### Specific applications
1. **BackupSettingsView** : Every toggle row is a glass card. The GlassEffectContainer unifies them into one blended surface.
2. **Backfill button** : Glass morph into sheet — the button shape becomes the sheet header. Seamless spatial continuity.
3. **Album selector buttons** : Glass pills that ripple/shimmer on selection.
4. **Progress card** : Glass morphs from idle state → checking → uploading → done. The shape evolves with phase.
5. **UploadProgressBanner** : Glass bar that floats on scroll edge using `scrollEdgeEffectStyle`.
6. **UploadHistoryRow** : Glass list rows, status icons in glass pills.
7. **Retry button** : `.glassEffect(.interactive())` for tactile shimmer.

### Background
- Subtle blurred photo in background (opacity 0.08, blur 30) visible through glass
- This creates the "window into photos" effect — exactly what Apple does in Settings

## Accessibility

- Glass cards maintain contrast via `.regular` glass (auto adjusts for Reduce Transparency)
- Every toggle: `.accessibilityLabel("Toggle \(title), \(isOn ? "enabled" : "disabled")"`)
- Progress: `.accessibilityLabel("\(uploaded) of \(total) uploaded")`
- Retry: `.accessibilityLabel("Retry upload")`
- Sheet: `.navigationTitle("Reorganize Photos")`
- All elements ≥ 44×44pt
- Reduce Motion: glass morphs to opacity crossfade, floating → fixed position

## Animations

- Backfill button → sheet: `.glassEffectTransition(.matchedGeometry)` — shape morph, not crossfade
- Banner slide-in: `.move(edge: .top).combined(with: .opacity)` — `PVMotion.snappy`
- Sheet presentation: `detent(.medium)` → drag to `.large` with spring
- Progress: `.contentTransition(.numericText())` for counts
- Toggle changes: `PVMotion.snappy` (0.25s, damping 0.75)
- Retry button press: `.interactive()` shimmer + `PVMotion.snappy`
- Reduce Motion: all glass morphs become `.identity` (crossfade), no shape change

## Key Files Modified

- `Sources/Features/Upload/UploadViewModel.swift` — BackupSettingsStore + UploadViewModel + BackupSettingsView extensions
- `Sources/Features/Upload/UploadViewModel.swift` — BackfillSheet (NEW struct) + UploadHistoryRow
- `Sources/Features/Timeline/TimelineView.swift` — UploadProgressBanner + scrollEdgeEffectStyle
- `Sources/Features/Upload/UploadViewModel.swift` — UploadHistoryEntry model
- `Sources/Features/Upload/UploadViewModel.swift` — glassNamespace in BackupSettingsView
