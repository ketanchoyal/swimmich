---
name: swiftui-animations
description: >
  State-of-the-art SwiftUI animation practices for iOS 26+, aligned with Apple's
  Human Interface Guidelines, App Store review expectations, and current SwiftUI
  documentation (Liquid Glass, the @Animatable macro, PhaseAnimator/KeyframeAnimator,
  matchedTransitionSource/zoom transitions, symbol effects). Use this skill whenever
  an agent is writing, reviewing, or refactoring ANY animation, transition, gesture-driven
  motion, loading state, custom Shape/ViewModifier, or Liquid Glass effect in a SwiftUI
  codebase — even if the user just says "animate this", "make it feel smoother", "add a
  transition", or "polish the UI". Also trigger for performance reviews of animated views
  (dropped frames, ProMotion/120Hz jank, ScrollView stutter) and for accessibility passes
  that touch motion (Reduce Motion). This is the source of truth for how agents building
  native iOS apps should implement motion — consult it before writing animation code, not
  just when something looks wrong.
---

# SwiftUI Animations — SOTA Guide (iOS 26 / Liquid Glass)

This skill exists so agents stop reaching for `withAnimation { }` wrapped around
everything and instead pick the *right* primitive, respect Apple's motion and
accessibility rules, and write animation code that survives App Store review and
performs at 120Hz. Apple's own docs are the ground truth — this skill distills
them into decisions an agent can apply directly.

## 0. Decision tree — pick the right tool first

| Situation | Use |
|---|---|
| One property flips between two states (bool, enum, number) | Implicit animation: `.animation(.spring, value: someValue)` scoped to the smallest view that needs it |
| A sequence of discrete visual states triggered by one event (bounce, shake, success pop) | `PhaseAnimator` |
| A continuous, choreographed multi-property animation (icon micro-interaction, complex entrance) | `KeyframeAnimator` |
| A custom `Shape`, `ViewModifier`, or `TextRenderer` needs a property to animate smoothly | `@Animatable` macro (iOS 26+); mark non-animatable properties `@AnimatableIgnored` |
| A view morphs into another view across a state/navigation change (card → detail) | `matchedTransitionSource` + `.navigationTransition(.zoom(...))`, or `matchedGeometryEffect` only if pre-iOS 18 support is required |
| An SF Symbol needs to react to a state change | `.symbolEffect(_:options:value:)`, not a manual scale/opacity hack |
| Content (text, numbers, icons) swaps in place | `.contentTransition(.numericText())` / `.contentTransition(.symbolEffect(...))` |
| Glass surfaces need to merge, split, or resize together | `GlassEffectContainer` + `.glassEffect(...).glassEffectID(...)`, animated as a unit — never animate glass materials by hand |
| User is dragging/scrolling and motion must track their finger 1:1 | Gesture-driven state, **not** wrapped in `withAnimation` (interactive motion should be immediate; only the settle/release phase gets a spring) |

If none of these clearly fit, default to the simplest implicit animation and
question whether the motion is earning its place at all (see §4).

## 1. Core animation model — get the fundamentals right

- **Implicit animation is a *response*, not a *trigger*.** `.animation(.spring, value: x)`
  animates changes to `x` for everything below it in the view tree. Scope it to the
  smallest subview possible — putting `.animation()` high in the tree silently animates
  unrelated state changes and is one of the most common sources of janky, hard-to-debug
  motion.
- **Prefer `withAnimation(_:) { }` for explicit, event-driven state changes** (button
  taps, completing a step) over sprinkling `.animation(value:)` everywhere. It makes the
  causal relationship between "this happened" and "this animates" explicit in the code.
- **Springs are the default, not linear/easeInOut.** Use `.spring(duration:bounce:)`
  (iOS 17+) rather than the old mass/stiffness/damping initializer — it's readable and
  matches system motion. Typical UI transitions: `duration: 0.3–0.5`, `bounce: 0–0.3`.
  Reach for `.interpolatingSpring` specifically when an explicit animation needs to blend
  smoothly with an interactive (gesture-driven) one in the same transaction.
- **Transactions, not just animations.** When you need to suppress animation for one
  specific state change inside an otherwise-animated tree, use
  `withTransaction(Transaction(animation: nil)) { }` rather than restructuring state.

## 2. The `@Animatable` macro (iOS 26+) — use it, don't hand-roll `animatableData`

Before iOS 26, custom `Shape`/`ViewModifier` animation required manually implementing
`animatableData` with a getter/setter — verbose and easy to get wrong for >1 property
(needed `AnimatablePair` nesting). On iOS 26+ targets, agents should default to the macro:

```swift
@Animatable
struct Wave: Shape {
    var amplitude: Double
    var frequency: Double
    var phase: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in stride(from: 0, through: rect.width, by: 1) {
            let angle = frequency * (x / rect.width) * 2 * .pi + phase
            let y = sin(angle) * amplitude + rect.midY
            let point = CGPoint(x: x, y: y)
            x == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}
```

- `@Animatable` synthesizes `Animatable` conformance and interpolates **every** stored
  numeric/vector property by default.
- Exclude properties that shouldn't interpolate (booleans, config flags, colors you
  don't want tweened) with `@AnimatableIgnored` — they still affect rendering, they just
  snap instead of interpolate.
- This applies to `View`, `ViewModifier`, `Shape`, and `TextRenderer` — not just shapes.
- **Only use this on an iOS 26+ deployment target.** If the project's minimum deployment
  target is lower, fall back to manual `animatableData` (or `AnimatablePair` for multiple
  properties) and note the version gate in a comment.

## 3. Liquid Glass — motion-specific rules

Liquid Glass (iOS 26+) is a *material*, and it has its own built-in motion language —
agents should not try to reimplement it with opacity/blur hacks.

- Group glass elements that should morph, merge, or split together inside a single
  `GlassEffectContainer` and give each a stable `.glassEffectID(_:in:)` — the container
  animates the merge/split transition automatically when membership or layout changes.
  Don't hand-animate blur radius or corner radius to fake a glass morph.
- Respect `appearsActive` (environment value) for custom glass elements that need to dim
  when a window/scene is inactive — this is expected system behavior, not optional
  polish.
- Don't stack custom animations on top of a `.glassEffect()` view's own transition
  timing — let the system-driven glass transition own its own frame, and only animate
  the *content* inside it explicitly.
- New toolbar APIs (`ToolbarSpacer`, `toolbarMinimizeBehavior`, `visibilityPriority`)
  already have their own Apple-tuned transitions on scroll/resize — don't wrap them in
  additional `withAnimation` unless testing shows a genuine visual gap.

## 4. Performance — this is what "SOTA" means in practice

App Store users judge animation quality by frame consistency, not cleverness. On
ProMotion displays the budget is ~8.3ms/frame (120Hz); on standard displays ~16.6ms
(60Hz). Dropped frames during a transition are the single most common "this app feels
cheap" signal in review feedback.

- **Scope `.animation(value:)` tightly.** An animation modifier high in a large view
  tree re-evaluates and re-diffs more than necessary on every change to `value`. Attach
  it to the smallest view that actually needs to animate.
- **Never wrap the whole screen's state in one `withAnimation` for unrelated changes.**
  If two properties change together but should animate differently (or one shouldn't
  animate at all), split them into separate transactions.
- **Avoid `AnyView` inside animated hierarchies.** Type erasure defeats SwiftUI's
  identity-based diffing, which turns what should be a smooth animated update into a
  full remove/insert (visible as a flicker or a snap instead of a transition). Use
  `@ViewBuilder` / `some View` and, if branching is unavoidable, keep branches as
  distinct concrete view types SwiftUI can diff.
- **Don't put expensive work inside `body` or inside animatable computed properties.**
  Every frame of an animation re-evaluates `body` for affected views; heavy geometry
  math, image processing, or filtering belongs outside the animated path (precomputed,
  cached, or moved to `Shape.path(in:)` which SwiftUI already calls efficiently per
  frame).
- **Use `.drawingGroup()` for vector-heavy or `Canvas`-based animations** with many
  layered shapes/gradients — it composites the subtree with Metal instead of CPU-driven
  compositing, which matters a lot once you have more than a handful of animated layers.
- **Watch `GeometryReader` nesting.** Nested `GeometryReader`s inside an animated view
  are a common cause of layout thrash — prefer `.containerRelativeFrame`,
  alignment guides, or reading geometry once at a stable ancestor.
- **Profile before shipping, don't guess.** Use Instruments' SwiftUI template (view body
  evaluation counts, "Long View Body Updates") and the Animation Hitches instrument on a
  real device — the simulator does not reflect real ProMotion frame timing.

## 5. Accessibility and App Store expectations (non-negotiable, not polish)

Apple's HIG motion guidance ("make motion optional", "don't add motion for the sake of
motion") is enforced in review, not just advisory. Agents should treat every item below
as a requirement, not a nice-to-have:

- **Always read `@Environment(\.accessibilityReduceMotion)`** in any view with non-trivial
  custom motion. When `true`: replace slides/parallax/zoom transitions with crossfades or
  instant state changes, and stop any looping/autoplay animation. System transitions (e.g.
  the zoom navigation transition) already do this automatically — custom ones do not, the
  agent must implement the fallback explicitly.
- **Never use motion as the only channel for important information** (e.g., a shake
  meaning "error" must be paired with color/icon/text, not rely on the shake alone —
  someone with Reduce Motion on will miss it entirely).
- **Avoid oscillating motion in the ~0.2Hz range and large-amplitude parallax** — Apple
  calls these out specifically as triggers for motion discomfort.
- **Never flash content more than ~3 times per second** — seizure risk, and a hard
  rejection risk under App Store Review Guideline 2 (performance/safety), not just a
  design nitpick.
- **Respect `accessibilityReduceTransparency`** alongside reduce motion when animating
  Liquid Glass or blurred materials — swap to solid backgrounds rather than animating
  opacity of a translucent material for those users.
- **Keep animation durations in the system's ballpark (~250–400ms for standard UI
  transitions).** Longer animations read as sluggish and are a common source of "the app
  feels laggy" App Store reviews; much shorter/instant changes can feel abrupt and
  unpolished — match the system, don't invent a house style out of nowhere.

## 6. Quick reference — common patterns

**Scoped implicit animation (correct scoping):**
```swift
VStack {
    Text(title)
    StatusBadge(isActive: isActive)
        .animation(.spring(duration: 0.3), value: isActive) // scoped to this subview only
}
```

**Phase-based micro-interaction:**
```swift
Image(systemName: "heart.fill")
    .phaseAnimator([false, true], trigger: didTapLike) { content, phase in
        content.scaleEffect(phase ? 1.3 : 1.0)
    } animation: { phase in
        phase ? .spring(duration: 0.2, bounce: 0.5) : .spring(duration: 0.15)
    }
```

**Respecting Reduce Motion:**
```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

var body: some View {
    content
        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
}
```

**Glass elements morphing together:**
```swift
GlassEffectContainer(spacing: 16) {
    HStack(spacing: 16) {
        ForEach(items) { item in
            ItemChip(item: item)
                .glassEffect()
                .glassEffectID(item.id, in: namespace)
        }
    }
}
```

## 7. Pre-ship checklist for any new animation

- [ ] Chose the narrowest tool from §0 rather than defaulting to `withAnimation` everywhere
- [ ] `.animation(value:)` scoped to the smallest subview, not the whole screen
- [ ] No `AnyView` inside the animated hierarchy
- [ ] Custom `Shape`/`ViewModifier` uses `@Animatable`/`@AnimatableIgnored` (iOS 26+ target) instead of hand-rolled `animatableData`
- [ ] `accessibilityReduceMotion` checked and given a real (non-decorative) fallback
- [ ] No information conveyed by motion alone
- [ ] No flashing/strobing above ~3Hz, no sustained ~0.2Hz oscillation
- [ ] Duration in the ~250–400ms system range unless there's a specific reason to deviate
- [ ] Glass elements animate via `GlassEffectContainer`/`glassEffectID`, not hand-tuned blur/opacity
- [ ] Verified on-device (not just simulator) at native refresh rate, ideally with Instruments' Animation Hitches
