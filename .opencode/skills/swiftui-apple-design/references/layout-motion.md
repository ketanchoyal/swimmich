# Layout, Adaptive Design & Motion Reference

## Spacing Tokens
Stay on a 4pt grid. In order of frequency of use:

| Value | Use |
|---|---|
| 4pt | Tight internal spacing (icon-to-label) |
| 8pt | Between related elements (label + value) |
| 12pt | Inside a card/row, between stacked lines |
| 16pt | Standard screen margin, standard `HStack`/`VStack` spacing, card internal padding |
| 20-24pt | Section spacing, large card padding, onboarding screen padding |
| 32pt+ | Major section breaks, hero spacing |

Default `.padding()` (no argument) applies the system default, which is correct in most cases — only override with an explicit value when you have a specific reason.

Corner radii:
| Radius | Use |
|---|---|
| 8-10pt | Small controls, chips, small buttons |
| 12-14pt | Standard buttons, text fields |
| 16pt | Cards |
| 20-28pt | Sheets, large modal surfaces, hero images |
Always use `style: .continuous` for card/sheet-scale radii to match Apple's squircle curvature.

## Adaptive Layout (iPhone → iPad → Mac)

**Multi-column navigation** — use this instead of a custom split layout:
```swift
NavigationSplitView {
    List(items, selection: $selection) { item in
        Text(item.name)
    }
    .navigationTitle("Items")
} detail: {
    if let selection {
        DetailView(item: selection)
    } else {
        ContentUnavailableView("Select an Item", systemImage: "sidebar.left")
    }
}
```
On iPhone this collapses to a single-column stack automatically — no `#if os()` branching needed for the common case.

**Fit content instead of measuring manually:**
```swift
ViewThatFits(in: .horizontal) {
    HStack { /* wide layout */ }
    VStack { /* narrow fallback */ }
}
```

**Grids that reflow by available width:**
```swift
LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
    ForEach(items) { item in CardView(item: item) }
}
```

**Platform-specific tweaks** — only reach for `#if os(iOS)` / `#if os(macOS)` when a component genuinely doesn't exist cross-platform (e.g. haptics, certain sheet behaviors). Don't reach for it as a first resort.

## Motion

Standard springs (preferred over `.easeInOut`/`.linear` for almost everything):
```swift
withAnimation(.snappy) { }                                  // quick UI feedback, default choice
withAnimation(.bouncy) { }                                  // playful, has overshoot
withAnimation(.smooth) { }                                  // no overshoot, calm
withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { } // manual tuning
```

Shared-element ("hero") transitions:
```swift
@Namespace var animation

// source
Image("thumb").matchedGeometryEffect(id: "photo", in: animation)
// destination
Image("full").matchedGeometryEffect(id: "photo", in: animation)
```

Numeric value changes (counters, prices, scores):
```swift
Text(count, format: .number)
    .contentTransition(.numericText())
    .animation(.snappy, value: count)
```

Always gate non-essential motion behind Reduce Motion:
```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

withAnimation(reduceMotion ? nil : .snappy) {
    isExpanded.toggle()
}
```

## Haptics
Use sparingly, only for meaningful confirmations (success, error, selection change) — not on every tap.
```swift
// SwiftUI-native (iOS 17+)
.sensoryFeedback(.success, trigger: didComplete)
.sensoryFeedback(.impact(weight: .light), trigger: didTap)
.sensoryFeedback(.selection, trigger: selectedIndex)
```
Fallback (UIKit, when finer control is needed):
```swift
UIImpactFeedbackGenerator(style: .light).impactOccurred()
UINotificationFeedbackGenerator().notificationOccurred(.success)
```
