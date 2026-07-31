---
name: swiftui-apple-design
description: Use this skill whenever writing, reviewing, or improving SwiftUI code, UI, or app screens — especially when the user wants their app to look and feel native, polished, or "Apple-like." Trigger on requests to build SwiftUI views, screens, components (cards, lists, forms, buttons, sheets, onboarding, settings, tab bars, navigation), or to improve/critique existing SwiftUI UI for visual quality, spacing, typography, color, motion, or accessibility. Also trigger for questions about Apple's Human Interface Guidelines (HIG), SF Symbols usage, Dynamic Type, Dark Mode, materials/glass effects, haptics, or adaptive layout across iPhone/iPad/Mac/Vision Pro. Do not use for non-SwiftUI UI frameworks (UIKit-only, AppKit-only, Android/Jetpack Compose, web/React) unless the user is porting concepts to SwiftUI.
license: MIT
compatibility: opencode
metadata:
  domain: swiftui
  platform: apple
---

# SwiftUI Apple-Style Design

Build SwiftUI UI that looks and feels like it shipped from Cupertino: correct system typography and color, generous native spacing, real depth via materials, purposeful motion, and full accessibility support — never generic "AI app" UI (centered gradients, oversized rounded cards, mismatched shadows, non-system fonts).

## Workflow

1. **Identify the surface.** What is being built — a screen, a component, a full flow (onboarding, settings, detail view)? What platform(s): iPhone, iPad, Mac, Vision Pro, watchOS? Default to iOS unless stated.
2. **Reach for native components first.** `List`, `Form`, `NavigationStack`, `NavigationSplitView`, `TabView`, `.sheet`, `.confirmationDialog`, `ShareLink`, `Menu`. Custom-built equivalents of these are a strong signal something is wrong — Apple's built-ins already carry the correct spacing, materials, and accessibility for free.
3. **Apply the core principles below** (typography, color, spacing, depth, motion) as you write the view code — don't bolt them on after.
4. **Check the relevant reference file** for the component/topic in question before hand-rolling something (see Reference Files below) — it has concrete code patterns, exact spacing/sizing tokens, and platform variants.
5. **Before finishing, self-review against the Common Anti-Patterns checklist** at the bottom of this file.

## Core Principles

### Typography
Always use semantic text styles, never fixed point sizes — this is what makes text scale correctly with Dynamic Type and stay consistent with the system:
```swift
Text("Title").font(.title2).fontWeight(.semibold)
Text("Body copy").font(.body)
Text("Caption detail").font(.caption).foregroundStyle(.secondary)
```
Use `.rounded` design sparingly for playful/consumer apps (`Font.system(.title, design: .rounded)`); default to the standard SF Pro grade for anything professional or content-heavy. Never import a random Google Font for "an Apple look" — the system font *is* the Apple look.

### Color
Use semantic and system colors, not hardcoded hex/RGB:
```swift
.foregroundStyle(.primary)       // adapts to light/dark automatically
.foregroundStyle(.secondary)
.tint(.accentColor)              // respects user/app accent color
Color(.systemBackground)
Color(.secondarySystemBackground)
```
Pick ONE accent color for the whole app and let the system handle the rest via `.tint()`. Test every screen in both Light and Dark Mode — never ship a screen only checked in one appearance.

### Spacing & Layout
Apple's system spacing (the default in `.padding()`, `VStack(spacing:)` when omitted, list row insets) is already correct — resist replacing it with arbitrary pixel values. When you do need explicit values, stay on an 4/8-pt grid: `4, 8, 12, 16, 20, 24, 32`. Standard screen margin is `16pt` (`20pt` on larger phones/iPad is also common — let `.padding()` default handle it rather than hardcoding).

Build layout with `VStack` / `HStack` / `ZStack` / `Grid` / `LazyVGrid`, not manual `.position()` or `.offset()` math. Prefer `ViewThatFits` over `GeometryReader` when the goal is just "fit available space."

### Depth & Materials
Apple's visual depth comes from **materials and blur**, not drop shadows on flat colored rectangles:
```swift
.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
.background(.ultraThinMaterial)
```
Use materials for sheets, toolbars, floating controls, and cards that sit over content. Reserve shadows for genuinely elevated elements (floating action buttons, dragged items) and keep them subtle: `.shadow(color: .black.opacity(0.08), radius: 8, y: 2)` — never a heavy default black shadow.

Corner radii: match Apple's continuous ("squircle") curvature, not plain rounded rects, for card-like containers:
```swift
RoundedRectangle(cornerRadius: 16, style: .continuous)
```
Common radii: `10` (small controls/buttons), `16` (cards), `20-28` (sheets/large surfaces).

### Motion
Motion should communicate a state change, not decorate. Default to Apple's standard springs, not linear/ease curves:
```swift
withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { ... }
// or the shorthand
withAnimation(.snappy) { ... }
withAnimation(.bouncy) { ... }
```
Always respect Reduce Motion:
```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion
withAnimation(reduceMotion ? nil : .snappy) { ... }
```
Use `.matchedGeometryEffect` for hero/shared-element transitions between views, and `.contentTransition(.numericText())` for numbers that update in place.

### Components — reach for these before building custom
| Need | Use |
|---|---|
| List of items | `List` with `.listStyle(.insetGrouped)` or `.plain` |
| Settings-style screen | `Form` with `Section` |
| Root navigation | `NavigationStack` (single column), `NavigationSplitView` (iPad/Mac multi-column) |
| Tab-based app | `TabView`, `.tabViewStyle(.sidebarAdaptable)` on iPadOS 18+ |
| Modal task | `.sheet(isPresented:)`, `.fullScreenCover` only for immersive/onboarding flows |
| Contextual actions | `.contextMenu`, `.swipeActions` |
| Confirmation | `.confirmationDialog`, `.alert` |
| Search | `.searchable(text:)` attached to the containing List/NavigationStack |
| Pull to refresh | `.refreshable { }` |
| Icons | SF Symbols (`Image(systemName:)`) — never custom icon sets when a system symbol fits; use `.symbolRenderingMode(.hierarchical)` or `.palette` for multi-tone icons |

### Accessibility (non-negotiable, not a nice-to-have)
- Minimum tap target: 44×44pt — pad tappable icons/buttons to hit this even if the glyph is smaller.
- Every custom (non-Text, non-Button-with-label) interactive control needs `.accessibilityLabel()`; add `.accessibilityHint()` when the action isn't obvious from the label.
- Group decorative/compound elements with `.accessibilityElement(children: .combine)` so VoiceOver reads them as one unit, not fragments.
- Never convey information by color alone — pair with an icon or text.
- Test that every screen still works with the largest Dynamic Type size (`.dynamicTypeSize(.accessibility3)` in previews is a fast way to check).

## Reference Files

Load these when you need concrete, copy-paste-ready patterns rather than principles:

- **`references/components.md`** — full code patterns for cards, list rows, buttons, forms, sheets, tab bars, onboarding screens, empty states, and toolbars, written the Apple way.
- **`references/typography-color.md`** — the complete semantic type scale, semantic color list, SF Symbols rendering modes, and Dark Mode checklist.
- **`references/layout-motion.md`** — spacing tokens, adaptive layout patterns for iPad/Mac (NavigationSplitView, ViewThatFits), the standard animation curves, and haptic feedback patterns.

## Common Anti-Patterns to Avoid

Before handing back SwiftUI code, check it doesn't have any of these "generic AI app" tells:
- Hardcoded hex colors instead of semantic/system colors
- Fixed `.font(.system(size: 34))` instead of `.font(.largeTitle)`
- Heavy, dark drop shadows on every card
- Centered single-column layout with huge padding that ignores iPad/Mac entirely
- Custom-built tab bar / nav bar / back button reimplementing what `TabView`/`NavigationStack` already provide for free
- Non-continuous corner radii on card-like surfaces
- Animations using `.linear` or no spring at all
- Missing Dark Mode pass, missing Dynamic Type pass, missing `accessibilityLabel` on icon-only buttons
- Random gradient backgrounds as a substitute for actual visual hierarchy
