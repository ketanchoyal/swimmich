# Task: widgets-homescreen — UI Brief (Liquid Glass Primary)

> **Corrections du 2026-09-13 (avant implémentation)** — trois demandes de ce brief ne tiennent pas côté WidgetKit, et ce qui a été livré les remplace :
> - **`glassEffect(.regular)` sur les cellules est impossible** : la Liquid Glass API est réservée à l'UI de l'app, un widget rend sa propre platter et le système ne lui accorde pas d'effet de verre. Le « vitré » est obtenu autrement : pastilles `.ultraThinMaterial`, scrim dégradé sur la photo, `containerBackground` opaque et `contentMarginsDisabled()` pour que la mosaïque saigne jusqu'au bord (comme le widget Photos d'Apple). Vérifié au rendu.
> - **Un `widgetURL` par widget, pas par cellule** : les deep links par photo sont des `Link(destination:)` (et un seul `widgetURL` racine, qui ouvre l'app / l'onglet Souvenirs).
> - **Pas de « configuration » ni de « pull-to-refresh »** : aucun des deux n'existe dans WidgetKit (l'édition d'un widget se fait par `AppIntentConfiguration`, jamais construite ici).
>
> Ce qui a été gardé du brief : le watermark cœur (mais **par-dessus** la mosaïque : dessous, il est invisible — constat de rendu), la capsule vitrée par photo, le contour, les pastilles de type en dégradé de marque, l'état vide centré, zéro parallaxe (Reduce Motion). Les widgets Favoris/Photos/Souvenirs existent en small/medium (grand en plus pour Photos et Favoris) + familles Lock Screen circulaire/rectangulaire/inline.

## Design Philosophy

Les widgets sont des **fenêtres vitrées** sur le contenu Immich. Ils flottent sur le Home Screen avec du glass, des photos visibles à travers, et des contours vitrés. Le tout est cohérent avec le widget Photos de Apple mais en mieux vitré.

## Layout

```
ImmichWidgets (WidgetKit extension)
├── ImmichGridWidget — small (2x2) + medium (4x2)
│   └── Glass card grid of photos
├── ImmichMemoriesWidget — small (2x2) + medium (4x2)
│   └── Glass memory card(s) with photos
└── ImmichFavoritesWidget — small (2x2) + medium (4x2)
    └── Glass card grid of favorites
```

## Components (Widget extension)

### ImmichGridWidget — Glass photo grid

```swift
import WidgetKit
import SwiftUI

struct ImmichGridWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ImmichGridWidget", provider: WidgetProvider()) { entry in
            GridWidgetView(entry: entry)
        }
        .configurationDisplayName("Photos")
        .description("Your most recent photos.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct GridWidgetView: View {
    let entry: TimelineEntry
    
    var body: some View {
        ZStack {
            // Background — subtle gradient
            LinearGradient(
                colors: [Color.immichPrimary.opacity(0.15), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Photos in glass-tinted grid
            if let assets = entry.assets, !assets.isEmpty {
                LazyVGrid(columns: gridColumns, spacing: 4) {
                    ForEach(assets.prefix(gridCount)) { asset in
                        widgetAssetImage(asset)
                            .clipShape(RoundedRectangle(cornerRadius: PVRadius.sm, style: .continuous))
                            .glassEffect(.regular)
                    }
                }
            } else {
                widgetEmptyState("No recent photos")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PVRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PVRadius.lg, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
                .glassEffect(.regular)
        )
    }
}
```

### ImmichMemoriesWidget — Glass memory cards

```swift
struct MemoryCardWidgetView: View {
    let memory: MemoryItem
    
    var body: some View {
        VStack(spacing: PVSpacing.s8) {
            // Type badge — glass pill
            HStack(spacing: PVSpacing.s8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(Color.immichPrimary)
                    .glassEffect(.regular)
                    .frame(width: 20, height: 20)
                
                Text("On This Day")
                    .font(.caption)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(memory.year)")
                    .font(.caption2)
                    .fontWeight(.heavy)
                    .foregroundStyle(Color.immichPrimary)
                    .padding(.horizontal, PVSpacing.s6)
                    .padding(.vertical, PVSpacing.s4)
                    .background(.thinMaterial, in: Capsule())
                    .glassEffect(.regular)
            }
            .padding(.horizontal, PVSpacing.s8)
            
            // Photo grid — glass cards
            if !memory.assets.isEmpty {
                LazyVGrid(columns: memoryGridColumns, spacing: 4) {
                    ForEach(memory.assets.prefix(memoryGridCount)) { asset in
                        widgetAssetImage(asset)
                            .clipShape(RoundedRectangle(cornerRadius: PVRadius.sm, style: .continuous))
                            .glassEffect(.regular)
                    }
                }
            }
        }
        .padding(PVSpacing.s12)
        .glassEffect(.regular)
    }
}
```

### ImmichFavoritesWidget — Glass favorites grid

```swift
struct FavoritesWidgetView: View {
    let entry: TimelineEntry
    
    var body: some View {
        ZStack {
            // Heart watermark — subtle glass overlay
            Image(systemName: "heart.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.immichPrimary.opacity(0.06))
                .position(x: widgetSize.width / 2, y: widgetSize.height / 2)
            
            // Photos in glass grid
            if let assets = entry.favorites, !assets.isEmpty {
                LazyVGrid(columns: gridColumns, spacing: 4) {
                    ForEach(assets.prefix(gridCount)) { asset in
                        widgetAssetImage(asset)
                            .clipShape(RoundedRectangle(cornerRadius: PVRadius.sm, style: .continuous))
                            .glassEffect(.regular)
                    }
                }
            } else {
                widgetEmptyState("No favorites")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PVRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PVRadius.lg, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
                .glassEffect(.regular)
        )
    }
}
```

### widgetAssetImage — Glass-tinted photo

```swift
private func widgetAssetImage(_ asset: AssetItem) -> some View {
    AsyncImage(url: asset.thumbnailURL) { phase in
        phase.image?
            .resizable()
            .scaledToFill()
            .clipped()
        phase.placeholder {
            Color(.systemGray5)
        }
        phase.error {
            Color(.systemGray5)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .widgetURL(asset.deepLinkURL)
    .glassEffect(.regular)
}
```

## Interactions

### Widget tap → deep link
- `widgetURL` on each photo cell → opens app to that asset (PhotoViewer)
- URL scheme: `app.immich://asset/{id}`
- Handle in ImmichSwiftUIApp `.onOpenURL` → parse and navigate

### Widget configuration (long-press → "Edit Widget")
- Tap long-press → opens configuration UI
- Show album selector (if album-specific)
- Toggle options: "Show Favorites" / "Show Recent" / "Show Memories"

### Widget refresh
- Pull-to-refresh on the widget (iOS 26)
- Auto-refresh every hour (TimelineProvider policy)
- Manual refresh button in widget (iOS 26+)

## Liquid Glass (iOS 26 — PRIMARY)

### Philosophy
- **Toutes** les cellules de photos sont des glass cards
- **Contour** de widget en glass
- **Badges** de type comme capsules vitrées colorées
- **Watermarks** en glass subtil (heart, calendar)

### Specific applications
1. **Photo cells** : Each photo is a glass card — photos visible through glass
2. **Widget border** : Glass outline — subtle glass capsule edge
3. **Memory badges** : Glass pills with color tints (purple, green, blue)
4. **Empty state** : Glass overlay with centered content
5. **Heart watermark** : Subtle glass overlay for favorites widget
6. **Configuration** : System native (auto glass on iOS 26)

### Background
- Subtle gradient behind glass widgets — Immich brand tint at low opacity
- Creates depth without competing with photos

## Accessibility

- Each photo cell: `.accessibilityLabel("Photo from [date]")`
- Memory cards: `.accessibilityLabel("On this day memory from year [year]")`
- Empty states: `.accessibilityLabel("No [type] photos available")`
- Widget configuration: labels are clear and descriptive
- VoiceOver reads widget content in reading order
- Reduce Motion: no parallax or scale in widgets

## Animations

- Widget refresh: system transition (subtle fade)
- Photo load: skeleton placeholder → fade-in when loaded
- Empty state: `.contentTransition(.opacity)` — smooth fade
- Deep link transition: matchedGeometryEffect from widget cell to viewer
- Reduce Motion: all transitions use `.linear(duration: 0.3)`

## Key Files Modified

- `ImmichWidgets/ImmichGridWidget.swift` — NEW: glass photo grid widget
- `ImmichWidgets/ImmichMemoriesWidget.swift` — NEW: glass memories widget
- `ImmichWidgets/ImmichFavoritesWidget.swift` — NEW: glass favorites widget
- `ImmichWidgets/WidgetDataProvider.swift` — NEW: shared data provider
- `ImmichWidgets/ImmichWidgetsBundle.swift` — Register all 3 widgets
- `Sources/ImmichSwiftUIApp.swift` — Handle widget deep links
- `Sources/DependencyContainer.swift` — Add widget data factory
