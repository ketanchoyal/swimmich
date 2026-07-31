# Component Patterns

Concrete, Apple-style SwiftUI code for common UI needs. Adapt names/content; keep the structural/styling choices.

## Card
```swift
struct InfoCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
```

## List row (settings-style)
```swift
List {
    Section {
        Label("Notifications", systemImage: "bell.fill")
            .labelStyle(.titleAndIcon)
    } header: {
        Text("Preferences")
    }
}
.listStyle(.insetGrouped)
```

## Primary / secondary buttons
```swift
Button("Continue") { }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)

Button("Cancel", role: .cancel) { }
    .buttonStyle(.bordered)
    .controlSize(.large)

// Icon-only — always add accessibilityLabel
Button {
    // action
} label: {
    Image(systemName: "square.and.arrow.up")
        .frame(width: 44, height: 44) // tap target
}
.accessibilityLabel("Share")
```

## Form (settings / data entry)
```swift
Form {
    Section("Profile") {
        TextField("Name", text: $name)
        TextField("Email", text: $email)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
    }
    Section {
        Toggle("Enable Notifications", isOn: $notificationsEnabled)
    }
}
```

## Sheet with proper detents
```swift
.sheet(isPresented: $showingDetail) {
    DetailView()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
}
```

## Tab bar (iOS) with sidebar adaptation (iPadOS/macOS)
```swift
TabView {
    Tab("Home", systemImage: "house.fill") { HomeView() }
    Tab("Search", systemImage: "magnifyingglass") { SearchView() }
    Tab("Profile", systemImage: "person.crop.circle") { ProfileView() }
}
.tabViewStyle(.sidebarAdaptable) // iPadOS 18+/macOS: becomes a sidebar automatically
```

## Empty state
```swift
ContentUnavailableView(
    "No Results",
    systemImage: "magnifyingglass",
    description: Text("Try a different search term.")
)
```
`ContentUnavailableView` is the system component for this — prefer it over a hand-rolled empty state VStack.

## Toolbar
```swift
.toolbar {
    ToolbarItem(placement: .principal) {
        Text("Inbox").font(.headline)
    }
    ToolbarItem(placement: .primaryAction) {
        Button {
            // compose
        } label: {
            Image(systemName: "square.and.pencil")
        }
        .accessibilityLabel("New Message")
    }
}
```

## Onboarding screen
```swift
VStack(spacing: 24) {
    Spacer()
    Image(systemName: "sparkles")
        .font(.system(size: 64))
        .foregroundStyle(.tint)
        .symbolRenderingMode(.hierarchical)

    VStack(spacing: 8) {
        Text("Welcome").font(.largeTitle.bold())
        Text("A short, benefit-focused subtitle goes here.")
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
    Spacer()
    Button("Get Started") { }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
}
.padding(24)
```

## Pull to refresh + search on a list
```swift
NavigationStack {
    List(items) { item in
        Text(item.name)
    }
    .searchable(text: $query)
    .refreshable { await reload() }
    .navigationTitle("Items")
}
```

## Swipe actions & context menu
```swift
.swipeActions(edge: .trailing) {
    Button(role: .destructive) { delete(item) } label: {
        Label("Delete", systemImage: "trash")
    }
    Button { archive(item) } label: {
        Label("Archive", systemImage: "archivebox")
    }
    .tint(.orange)
}
.contextMenu {
    Button { } label: { Label("Rename", systemImage: "pencil") }
    Button(role: .destructive) { } label: { Label("Delete", systemImage: "trash") }
}
```
