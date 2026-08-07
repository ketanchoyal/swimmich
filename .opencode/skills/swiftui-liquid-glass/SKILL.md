---
name: swiftui-liquid-glass
description: iOS 26 Liquid Glass API reference for SwiftUI. Use when implementing, reviewing, or improving translucent glass surfaces, floating controls, toolbars, tab bars, buttons, or morphing transitions with glassEffect, GlassEffectContainer, glassEffectID, glassEffectUnion, glassEffectTransition, Glass.regular/.clear/.identity, tint, interactive, scrollEdgeEffectStyle, backgroundExtensionEffect, or ToolbarSpacer. Load whenever a screen needs the iOS 26 visual language, not just generic HIG rules.
license: MIT
compatibility: opencode
metadata:
  domain: ios-swiftui
  role: visual-language
  min-os: "iOS 26"
---

# iOS 26 Liquid Glass — SwiftUI API Reference

Liquid Glass is the dynamic translucent material introduced in iOS 26 (also iPadOS 26, macOS 26 "Tahoe", tvOS 26, watchOS 26, visionOS 26). It blurs content behind it, reflects surrounding light/color, and morphs shape on interaction. Availability: iOS 26+/iPadOS 26+/macOS 26+ — always gate with `if #available(iOS 26, *)` and fall back to `.background(.regularMaterial)` on older targets, or set a real deployment target if the project only ships iOS 26+.

## Core API

```swift
func glassEffect<S: Shape>(
    _ glass: Glass = .regular,
    in shape: S = Capsule(),
    isEnabled: Bool = true
) -> some View
```

- `Glass.regular` — default adaptive variant, standard glass for most controls.
- `Glass.clear` — high-transparency variant; needs a dimming layer over media-rich backgrounds to keep content legible.
- `Glass.identity` — no visual effect, useful for conditional application.
- `.tint(_:)` — dye the glass; keep alpha low, reserve for semantic meaning (success/warning/destructive) or brand accents, not decoration.
- `.interactive()` — iOS-only; adds scale/bounce/shimmer response to touch. Add only to tappable/focusable elements.

Chain modifiers: `.glassEffect(.regular.tint(.blue).interactive())`.

**Rule: apply `.glassEffect()` last in the modifier chain**, after typography, color, padding, and frame — glass renders based on the fully-composed view.

## Migration from pre-26 materials

| iOS 18 API | iOS 26 equivalent |
|---|---|
| `.background(.ultraThinMaterial)` | `.glassEffect()` |
| `.background(.thinMaterial)` | `.glassEffect()` |
| `.background(.regularMaterial)` | `.glassEffect()` |
| `.background(.thickMaterial)` | `.glassEffect()` or solid background |
| `.matchedGeometryEffect()` (for glass) | `.glassEffectID()` |
| custom `UIBlurEffect` views | `GlassEffectContainer` |

## Grouping & Morphing

```swift
GlassEffectContainer {
    HStack {
        Button("A") { }.glassEffect()
        Button("B") { }.glassEffect()
    }
}
```

- `GlassEffectContainer` groups sibling glass views for shared blending, consistent lighting/blur, and better rendering performance. Wrap any set of related floating controls (e.g. a cluster of FABs, a custom toolbar) in one container rather than applying `.glassEffect()` to isolated views.
- `.glassEffectID(_:in:)` — tag related glass views across state changes so they animate/morph between each other instead of cross-fading. Requires a shared `@Namespace`.
- `.glassEffectUnion(id:namespace:)` — merges multiple overlapping glass shapes into a single rendered glass shape.
- `.glassEffectTransition(_:)` — controls appear/disappear transition: `.matchedGeometry` (default when views are within spacing of each other), `.materialize` (fade content, animate glass in/out), `.identity` (no transition).

```swift
@Namespace private var glassNamespace

if expanded {
    ExpandedControl()
        .glassEffect()
        .glassEffectID("control", in: glassNamespace)
} else {
    CollapsedControl()
        .glassEffect()
        .glassEffectID("control", in: glassNamespace)
}
```

## System Surfaces

- `scrollEdgeEffectStyle` — controls how bars blend with content at scroll edges (e.g. shrinking tab bars).
- `backgroundExtensionEffect` — extends background content visually behind glass toolbars/bars for continuity.
- `ToolbarSpacer` — inserts a Liquid-Glass-aware spacer between toolbar item groups so they render as separate glass capsules instead of one continuous bar.

## Workflow for Applying Liquid Glass

1. Identify target surfaces: cards, floating action buttons, custom toolbars/tab bars, chips — not every view needs glass.
2. Replace any custom blur/material background with `.glassEffect()`.
3. Wrap grouped/sibling glass elements in a single `GlassEffectContainer`.
4. Apply `.glassEffect()` after all layout and appearance modifiers.
5. Add `.interactive()` only to elements the user actually taps/focuses.
6. Add `glassEffectID(_:in:)` morphing only where the view hierarchy changes with animation (e.g. expanding a button into a panel).
7. Check both Light and Dark mode, plus Increase Contrast and Reduce Transparency accessibility settings — Liquid Glass must degrade gracefully when those are enabled (the system does this automatically if you use the standard API instead of custom `.opacity()`/blur hacks).

## Anti-Patterns

- Applying `.glassEffect()` before frame/padding modifiers (produces incorrect shape sizing).
- Stacking many independent `.glassEffect()` calls instead of one `GlassEffectContainer` (hurts rendering performance and visual coherence).
- Using `.clear` variant over busy/bright backgrounds without a dimming layer (destroys legibility/contrast).
- Using Liquid Glass on every view indiscriminately — reserve it for the functional/control layer (toolbars, floating controls), not the content layer (text, photos), matching the HIG layering model.
- Hardcoding a blur/opacity value to fake glass instead of using the real `Glass` API — breaks automatically adapting to Reduce Transparency and Dark Mode.
