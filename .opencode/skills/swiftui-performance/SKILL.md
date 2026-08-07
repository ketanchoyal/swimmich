---
name: swiftui-performance
description: SwiftUI performance optimization rules for smooth, native-feeling iOS apps. Use when writing, reviewing, or debugging view code that scrolls, animates, updates state frequently, renders lists/grids, or shows any jank, hitches, hangs, slow list scrolling, excessive redraws, or memory growth. Load before finalizing any SwiftUI view whose data changes over time or that contains a List, ScrollView, or animation.
license: MIT
compatibility: opencode
metadata:
  domain: ios-swiftui
  role: performance
---

# SwiftUI Performance Rules

Target: every view body renders in under 16ms (60fps) or under 8ms (120fps on ProMotion devices). SwiftUI is declarative — the biggest wins come from controlling *when* and *how often* bodies re-evaluate, not from micro-optimizing individual lines.

## Core Principle

**Ensure view bodies update quickly and only when needed.** Every extra or slow body evaluation risks hitches, hangs, paused animations, and delayed scrolling. Profile with the Instruments **SwiftUI** template (view body update counts) and **Time Profiler**, early and often — don't guess.

## 1. Data Flow & State

- Use `@Observable` (Observation framework, iOS 17+) instead of `ObservableObject`/`@Published` for models — it tracks only the properties actually read by a given view body, so unrelated property changes don't trigger re-renders.
- Owning view: `@State private var model = MyModel()`. Read-only access: plain `let`/`var`. Two-way binding: `@Bindable`. Shared down the tree: `@Environment(MyType.self)` instead of `@EnvironmentObject`.
- Mark properties that change often but aren't UI-relevant with `@ObservationIgnored` (cached data, internal services).
- Prefer `@State` over `@StateObject` when the type doesn't need reference semantics.
- Use **structs**, not classes, for plain data models — value types are cheaper for SwiftUI to diff.
- Design data flow so views update only when the specific data they render changes. Be extra careful with dependencies that change very frequently (timers, scroll offsets, geometry) — isolate them to the smallest possible subview.

## 2. View Hierarchy

- Break large views into small, focused subviews — each subview's body is diffed independently, so smaller bodies mean cheaper re-evaluation and better change isolation.
- Extract subviews instead of large inline closures; store the *result* of a view builder on a view/property rather than re-invoking a closure, so SwiftUI can compare the produced view instead of the closure identity.
- Avoid `AnyView` — it erases type information SwiftUI needs for efficient diffing. Use `@ViewBuilder`, generics, or `Group` instead.
- Avoid deeply nested, complex view hierarchies and complex inline expressions inside `body`; move computation out of `body` into stored properties or methods computed on state change.
- Use an `@Equatable`-style wrapper or manual `Equatable` conformance on subviews so SwiftUI skips re-rendering when the underlying value hasn't actually changed.

## 3. Lists, Grids & Scrolling

- Use `List` over manual `ForEach` + `ScrollView` when possible — `List` only renders visible cells (built-in cell reuse).
- Use `LazyVStack`/`LazyHStack`/`LazyVGrid`/`LazyHGrid` instead of eager `VStack`/`HStack` for large or offscreen content — lazy containers render only what's visible.
- Cache/prefetch images shown in lists; never decode large images synchronously on the main thread inside a row's body.
- Debounce search/filter input with `.task(id:)` cancellation instead of firing work on every keystroke.
- Keep row bodies trivial — push formatting/computation to the model layer, not into the row's `body`.

## 4. Animations

- Limit the number of concurrent animations and their complexity; specify explicit durations rather than relying on defaults everywhere.
- Use `drawingGroup()` for complex layered views with many overlapping effects/animations to flatten them into a single rendered layer (trades memory for GPU compositing speed) — but measure first, it's not free.
- Respect `@Environment(\.accessibilityReduceMotion)`: disable decorative/parallax animations when enabled.
- Avoid writing to `@State`/`@Environment` repeatedly inside hot paths (e.g. per-frame gesture or scroll callbacks) — isolate that state to the smallest possible subview to limit the blast radius of each update.

## 5. Concurrency & Main Thread

- Never block the main thread with heavy work; offload to `Task`/async-await or background `Dispatch` queues.
- Use `.task` (not `.onAppear` + manual cancellation) for async work tied to a view's lifetime — it auto-cancels when the view disappears, preventing leaks and stale updates.
- For streaming/incremental results (e.g. LLM responses, network data), use the streaming API to keep the UI responsive rather than waiting for a full payload.
- Avoid storing escaping closures directly on views if avoidable — store the view builder's *result*, not the closure, so SwiftUI can compare views structurally.

## 6. Measuring

Always validate with Instruments before and after a change:

| Tool | Use for |
|---|---|
| SwiftUI instrument | Body evaluation counts, update frequency, long updates |
| Time Profiler | Slow functions / CPU hotspots |
| Allocations | Memory leaks, retain cycles |
| Core Animation / Hitches | Frame drops, animation stutter |

Workflow: profile → find the view/update causing the problem → fix → profile again to confirm. Not every "unexpected" update causes a real perf problem — verify impact before spending time on it.

## Quick Diagnosis Table

| Symptom | Likely cause | Fix |
|---|---|---|
| Slow list scrolling | Eager rendering, uncached images | `LazyVStack`/`List` + image caching |
| Excessive redraws | Coarse `@Observable`/`ObservableObject` dependencies | Extract subviews, `@ObservationIgnored`, Equatable views |
| Memory leaks | `.onAppear` without cancellation | Use `.task` instead |
| Choppy animations | Too many concurrent/layered effects | `drawingGroup()`, reduce effect count |
| Search lag | Filtering on every keystroke | Debounce via `.task(id:)` |
| Hitches on state change | Frequent writes in hot path (scroll/gesture) | Isolate state to smallest subview |

## Anti-Patterns

- Deeply nested `ObservableObject` graphs where any change re-renders the whole tree.
- Reading the entire model object inside a subview when only one property is needed (defeats `@Observable` fine-grained tracking).
- `AnyView` used as a default escape hatch.
- Doing image decoding, JSON parsing, or date formatting inline inside a view's `body`.
- Firing network/filter requests on every character typed with no debounce.
- `GeometryReader` wrapping entire screens when only one dimension is needed (causes excess layout passes).
