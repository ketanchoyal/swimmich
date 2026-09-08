# Task: shared-links-enriched — UI Brief (Liquid Glass Primary)

## Design Philosophy

Les shared links sont des **fenêtres vitrées** sur du contenu partagé. Chaque lien est une carte glass avec un aperçu visuel. Le prévisualisation est dans un WKWebView avec barre d'outils glass. C'est comme l'app Partage de Apple mais avec des cartes vitrées au lieu de listes plates.

## Layout

```
SharedLinksView (dans Shared tab)
└── NavigationStack (scrollEdgeEffectStyle: glass)
    ├── ImmichAppBar (glass bar)
    └── ZStack {
        ├── Background: subtle blurred photo
        └── GlassEffectContainer {
            ├── LinkList — each row is a glass card
            │   ├── LinkRow (glass card with type icon, info, glass actions)
            │   └── LinkRow
            └── FAB "+" — glass capsule, morphs into create sheet
        }
        .padding(PVSpacing.s16)
```

### Extended screens
- ExternalLinkPreviewSheet — WKWebView with glass toolbar
- EditSharedLinkSheet — glass form
- UploadFromLinkSheet — glass form

## Components

### SharedLinksView — Glass link cards

```swift
struct SharedLinksView: View {
    @State var vm: SharedLinksViewModel
    @Namespace private var glassNamespace
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.immichBackground.ignoresSafeArea()
                
                GlassEffectContainer {
                    List {
                        if vm.links.isEmpty {
                            ContentUnavailableView(
                                "No shared links",
                                systemImage: "link.badge.plus",
                                description: Text("Create a link to share an album or individual photo.")
                            )
                        } else {
                            ForEach(vm.links) { link in
                                SharedLinkRow(link: link)
                                    .glassEffect(.regular)
                                    .glassEffectID("link_\(link.id)", in: glassNamespace)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .padding(.horizontal, PVSpacing.s4) // Remove list inset
                    .padding(PVSpacing.s16)
                }
                .padding(.horizontal, PVSpacing.s16)
            }
            .toolbar {
                ToolbarItem(placement: .principal) { ImmichAppBar(title: "Shared") }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { vm.showCreate = true } label: {
                        Image(systemName: "plus")
                            .glassEffect(.interactive())
                            .frame(width: 32, height: 32)
                    }
                }
            }
            .sheet(isPresented: $vm.showCreate) {
                CreateSharedLinkSheet(vm: vm)
            }
        }
    }
}
```

### SharedLinkRow — Glass card with actions

```swift
struct SharedLinkRow: View {
    let link: SharedLinkResponseDto
    @State var vm: SharedLinksViewModel
    @Namespace private var rowNamespace
    
    var body: some View {
        HStack(spacing: PVSpacing.s12) {
            // Type icon — glass pill
            Image(systemName: linkTypeIcon)
                .font(.pvBody)
                .foregroundStyle(Color.immichPrimary)
                .glassEffect(.regular)
                .frame(width: 32, height: 32)
            
            // Info
            VStack(alignment: .leading, spacing: PVSpacing.s2) {
                Text(link.description ?? "Shared link")
                    .font(.pvBody.weight(.semibold))
                    .lineLimit(1)
                
                HStack {
                    if let expiry = link.expiresAt {
                        Text("Expires \(expiry.formatted(date: .abbreviated, time: .omitted))")
                            .font(.pvCaption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Permission dots — glass pills
                    if link.allowUpload {
                        statusDot("Upload")
                    }
                    if link.allowDownload {
                        statusDot("Download")
                    }
                    if link.showMetadata {
                        statusDot("Info")
                    }
                }
            }
            
            Spacer()
            
            // More actions — glass interactive
            MoreActionsButton(link: link, vm: vm)
                .glassEffect(.interactive())
                .frame(width: 32, height: 32)
        }
        .padding(PVSpacing.s12)
        .glassEffect(.regular)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { vm.revokeLink(link.id) }
                .label { Label("Revoke", systemImage: "xmark.octagon") }
        }
    }
}
```

### MoreActionsButton — Glass menu

```swift
struct MoreActionsButton: View {
    let link: SharedLinkResponseDto
    @Bindable var vm: SharedLinksViewModel
    
    var body: some View {
        Menu {
            Button { openPreview() } label: {
                Label("Preview in Browser", systemImage: "safari")
            }
            Button { copyLink() } label: {
                Label("Copy Link", systemImage: "link")
            }
            Divider()
            if link.type != .album {
                Button { startUploadFromLink() } label: {
                    Label("Upload to Link", systemImage: "arrow.up.circle")
                }
            }
            Button { editLink() } label: {
                Label("Edit Link", systemImage: "pencil")
            }
            Button(role: .destructive) { vm.revokeLink(link.id) } label: {
                Label("Revoke", systemImage: "xmark.octagon")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
    }
}
```

### ExternalLinkPreviewSheet — Glass toolbar over WKWebView

```swift
struct ExternalLinkPreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            WKWebView(url: url)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .glassEffect(.regular)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Copy URL") { UIPasteboard.general.string = url.absoluteString }
                            .glassEffect(.interactive())
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Share") { /* share sheet */ }
                            .glassEffect(.interactive())
                    }
                }
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }
}
```

### EditSharedLinkSheet — Glass form with expiry picker

```swift
struct EditSharedLinkSheet: View {
    @Bindable var vm: SharedLinksViewModel
    @Environment(\.dismiss) private var dismiss
    @Namespace private var glassNamespace
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.immichBackground.ignoresSafeArea()
                
                GlassEffectContainer {
                    Form {
                        Section("Description") {
                            TextField("Link description", text: $vm.linkDescription)
                                .pvFieldSurface(focused: $vm.inputFocused)
                        }
                        
                        // Password — glass field
                        Section("Password") {
                            HStack {
                                if vm.linkPassword != nil && !vm.linkPassword!.isEmpty {
                                    Text("••••••")
                                        .font(.pvBody.monospacedDigit())
                                } else {
                                    Text("No password")
                                        .font(.pvBody)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(vm.linkPassword != nil ? "Change" : "Add") {
                                    vm.showPasswordPrompt = true
                                }
                                .foregroundStyle(Color.immichPrimary)
                                .glassEffect(.interactive())
                            }
                        }
                        
                        // Expiry — glass date picker
                        Section("Expiry") {
                            expirySection
                        }
                        
                        // Quick toggles — glass pills
                        Section {
                            ForEach(EditingToggleOption.allCases) { option in
                                ToggleOptionPill(option: option, enabled: vm.toggles[option] ?? false)
                                    .glassEffect(.interactive())
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
                    Button("Save") { vm.saveLink() }
                        .disabled(vm.isSaving)
                        .glassEffect(.interactive())
                }
            }
        }
    }
}
```

### Expiry Section — Glass date picker with quick presets

```swift
private var expirySection: some View {
    VStack(spacing: PVSpacing.s12) {
        if vm.linkExpiresAt != nil {
            Text("Expires \(vm.linkExpiresAt!.formatted(date: .standard, time: .standard))")
                .font(.pvBody)
            
            // Change date button — glass pill
            Button("Change date") { vm.showDatePicker = true }
                .font(.pvSubhead.weight(.semibold))
                .foregroundStyle(Color.immichPrimary)
                .glassEffect(.interactive())
                .frame(maxWidth: .infinity)
                .padding(PVSpacing.s12)
        } else {
            Text("Never expires")
                .font(.pvBody)
                .foregroundStyle(.secondary)
        }
        
        // Quick presets — glass pills row
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PVSpacing.s8) {
                ForEach(ExpiryPreset.allCases) { preset in
                    Button { vm.linkExpiresAt = preset.date } label: {
                        Text(preset.label)
                            .font(.pvCaption.weight(.semibold))
                            .foregroundStyle(Color.immichPrimary)
                            .padding(.horizontal, PVSpacing.s12)
                            .padding(.vertical, PVSpacing.s6)
                            .glassEffect(.regular)
                    }
                }
            }
        }
    }
    .padding(PVSpacing.s12)
    .glassEffect(.regular)
}
```

## Interactions

### Preview in Browser
- Tap → ExternalLinkPreviewSheet with glass toolbar
- In-app WKWebView (saves app switching)
- Close → glass morph back to link list

### Copy Link
- Tap → copies URL to UIPasteboard
- Toast: glass toast "Link copied" + haptic `.selection`
- Visual feedback: button text → "Copied!" → reverts after 2s

### Upload to Link
- Tap → UploadFromLinkSheet with glass form
- Asset picker via UIActivityViewController
- Submit → POST to link → toast "Uploaded to shared link"

### Edit Link
- Sheet opens with glass form
- Expiry date picker in glass card
- Quick presets as glass pills (1 day, 7 days, 30 days, Never)
- Save → glass shimmer → toast "Link updated"

### Revoke
- Swipe actions trailing (destructive glass row)
- Confirmation dialog (glass-tinted background)
- DELETE → row removal with glass morph
- Toast: glass toast "Link revoked"

## Liquid Glass (iOS 26 — PRIMARY)

### Philosophy
- **Toutes** les link rows sont des cartes vitrées
- **Groupes** de actions dans `GlassEffectContainer`
- **Morphing** du FAB en sheet via `glassEffectID`
- **Badges** de permission comme capsules vitrées colorées
- **Shimmer tactile** sur tous les éléments interactifs
- **Quick presets** comme pills vitrées colorées

### Specific applications
1. **Link rows** : Glass cards — each link is a glass window
2. **Type icon** : Glass pill with SF Symbol
3. **Permission dots** : Small glass pills (green/blue/gray)
4. **More actions** : `.glassEffect(.interactive())` on ellipsis
5. **Preview toolbar** : Glass navigation bar over WKWebView
6. **Edit form** : All inputs in glass field surfaces
7. **Expiry presets** : Glass pills in horizontal scroll row
8. **Toggle pills** : Glass interactive pills for upload/download/metadata
9. **Copy toast** : Glass floating bar

### Background
- Subtle blurred photo behind glass cards — context and depth

## Accessibility

- Glass cards maintain contrast via `.regular` glass (auto adjusts for Reduce Transparency)
- Link row: `.accessibilityLabel("Shared link: \(description), expires \(date or "never"), \(permissions)")`
- Copy button: `.accessibilityLabel("Copy link URL to clipboard")`
- Upload to link: `.accessibilityLabel("Upload photos to this shared link")`
- Revoke: `.accessibilityLabel("Revoke this link")`
- All elements ≥ 44×44pt
- Reduce Motion: glass morphs → opacity crossfade, no shape change

## Animations

- FAB → create sheet: `.glassEffectTransition(.matchedGeometry)` — shape morph
- Copy toast: slide-up + opacity, auto-dismiss after 2s
- Expiry date picker: sheet `.presentationDetents([.medium])`
- Upload from link: sheet `.presentationDetents([.large])`
- Revoke row removal: `.move(edge: .trailing)`
- Reduce Motion: all glass morphs → `.identity` (crossfade), no shape change

## Key Files Modified

- `Sources/Features/SharedLinks/SharedLinksView.swift` — Glass link cards + more actions
- `Sources/Features/SharedLinks/SharedLinksViewModel.swift` — copyLink, buildPublicURL, openPreview, startUploadFromLink, checkPassword
- `Sources/Features/SharedLinks/ExternalLinkPreviewSheet.swift` — NEW: glass WKWebView preview
- `Sources/Features/SharedLinks/UploadFromLinkSheet.swift` — NEW: glass upload form
- `Sources/Features/SharedLinks/EditSharedLinkSheet.swift` — Glass expiry picker + quick presets
- `Sources/Core/Protocols/ImmichClient.swift` — Add public/shared-link endpoints
- `Sources/Services/ImmichAPIClient.swift` — Implement new methods
