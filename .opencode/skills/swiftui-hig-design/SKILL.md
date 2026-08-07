---
name: swiftui-hig-design
description: Apple Human Interface Guidelines and iOS 26 visual language rules for building SwiftUI interfaces. Use when designing or reviewing any screen, choosing navigation patterns (TabView, NavigationStack, NavigationSplitView, sheets, alerts), typography, color, spacing, components (lists, buttons, forms, search), accessibility requirements, or when a UI needs to look and feel like a native, HIG-compliant, iOS 26 app. Load before writing SwiftUI view code that has any user-facing layout.
license: MIT
compatibility: opencode
metadata:
  domain: ios-swiftui
  role: design-guidelines
---

# SwiftUI HIG & iOS 26 Design Guidelines

Design rules based on Apple's Human Interface Guidelines for building native iOS interfaces with SwiftUI. Apply these rules to every screen you generate — do not treat them as optional polish.

## Design Philosophy

iOS design prioritizes **content over chrome**. The interface should feel invisible — users focus on their task, not the UI.

1. **Let content breathe** — full-screen layouts, minimal borders/boxes, let images and text lead.
2. **Leverage system conventions** — don't reinvent navigation, gestures, or controls users already know.
3. **Design for fingers** — touch is imprecise; generous tap targets beat pixel-perfect layouts.
4. **Respect user choices** — Dynamic Type, Dark Mode, Reduce Motion, and other accessibility settings are first-class requirements, not edge cases.

**iOS 26 baseline:** the system uses Liquid Glass — translucent material that reflects/refracts content behind it and morphs between states. Typography is bolder and left-aligned for easier scanning. For the full Liquid Glass API, load the `swiftui-liquid-glass` skill.

## 1. Layout & Safe Areas — CRITICAL

- **44×44pt minimum touch targets** on every interactive element (points, not pixels).
- Never place interactive/essential content under the status bar, Dynamic Island, or home indicator. `.ignoresSafeArea()` is only for backgrounds/decorative images — never for text or controls.
- Put primary actions in the **thumb zone** (bottom of screen); secondary actions/navigation at the top.
- Support every screen size from iPhone SE (375pt) to iPad Pro (1024pt+) using `@Environment(\.horizontalSizeClass)` and flexible layouts (`.frame(maxWidth: .infinity)`), never hardcoded widths.
- Align spacing/padding/sizes to an **8pt grid** (8, 16, 24, 32, 40, 48); use 4pt only for fine adjustments.
- Support landscape unless the app is task-specific (camera, etc.); use `ViewThatFits` for adaptive layouts.

```swift
Button(action: handleTap) {
    Image(systemName: "heart.fill")
}
.frame(minWidth: 44, minHeight: 44)
```

## 2. Navigation — CRITICAL

- **Tab bar** (bottom) for 3–5 top-level, equal-importance sections. Most important content leftmost. Never hide the tab bar when pushing deeper in a tab.
- **Hierarchical (NavigationStack)** for tree-structured content: push/pop, minimize depth to 3–4 levels, provide search as an escape hatch.
- **Modal (sheet/fullScreenCover)** for self-contained tasks: full-screen for critical flows, page sheet for dismissible ones, always a clear Done/Cancel.
- **Never use hamburger/drawer menus** — they measurably reduce feature discoverability.
- Use `NavigationStack` (never the deprecated `NavigationView`) with `NavigationPath`/`navigationDestination(for:)` for programmatic, type-safe navigation.
- Use large titles (`.navigationBarTitleDisplayMode(.large)`) on top-level views; they collapse to inline on scroll automatically.
- Never intercept the left-edge back-swipe gesture.
- Preserve scroll position and selected tab across navigation with `@SceneStorage`.
- On iPad, prefer `NavigationSplitView` (sidebar/content/detail) over a compressed iPhone layout.

```swift
NavigationSplitView {
    SidebarView()
} content: {
    ListContentView()
} detail: {
    DetailView()
}
.navigationSplitViewStyle(.balanced)
```

## 3. Typography & Dynamic Type — HIGH

Always use semantic text styles — they scale automatically with Dynamic Type.

| Style | Usage |
|---|---|
| `.largeTitle` | Screen titles |
| `.title` / `.title2` / `.title3` | Section headers |
| `.headline` | Emphasized body text |
| `.body` (17pt default) | Primary content |
| `.callout` | Secondary emphasized |
| `.subheadline` | Supporting labels |
| `.footnote` / `.caption` | Tertiary info |
| `.caption2` (11pt) | Absolute minimum size |

- Support Dynamic Type up to accessibility sizes (~200%); layouts must **reflow**, never truncate essential text. Check `@Environment(\.dynamicTypeSize).isAccessibilitySize` to switch HStack→VStack.
- Custom fonts must scale via `Font.custom(_:size:relativeTo:)`.
- Never go below 11pt text.
- Use SF Symbols instead of custom icon assets — they match text weight, scale with Dynamic Type, and align to baselines automatically. Don't force them into fixed-size containers.

## 4. Color & Dark Mode — HIGH

- Never hardcode RGB/hex/`.black`/`.white`. Use semantic labels: `.primary`, `.secondary`, `.tertiary`, `.quaternary`.
- Backgrounds: `Color(.systemBackground)` → `Color(.secondarySystemBackground)` → `Color(.tertiarySystemBackground)` for layered depth (card, then nested content).
- Custom colors need 4 asset-catalog variants: light, dark, light+high-contrast, dark+high-contrast.
- Never convey meaning by color alone — pair with icon or text (≈8% of men have color vision deficiency).
- Meet WCAG AA contrast: 4.5:1 normal text, 3:1 for large/bold text.
- Support Display P3 wide gamut for vibrant colors on modern displays.
- Pick **one** accent/tint color for all interactive elements app-wide via `.tint(_:)` on the root view.

## 5. Accessibility — CRITICAL

- Every icon-only button/control needs `.accessibilityLabel()`.
- Fix VoiceOver reading order with `.accessibilitySortPriority()` when visual order ≠ logical order.
- Respect `.accessibilityReduceMotion` — disable decorative animation/parallax when enabled.
- Respect `@Environment(\.colorSchemeContrast)` for Increase Contrast.
- Never convey info only via color/shape/position — add text or accessibility descriptions.
- Every gesture-only action needs a button/menu alternative.
- Test with Switch Control and Full Keyboard Access (focus order, activation).

```swift
Button(action: toggleFavorite) {
    Image(systemName: isFavorite ? "heart.fill" : "heart")
}
.accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
```

## 6. Gestures & Input — HIGH

- Use standard gestures only: tap, long-press (context menu / edit mode), horizontal swipe (row actions, back nav), vertical swipe (scroll, dismiss sheet), pinch (scale), rotate.
- Never intercept reserved edge gestures: left-edge (back), top-left pull (Notification Center), top-right pull (Control Center), bottom edge (home/app switcher).
- Any custom gesture needs a discoverable visual hint **and** a button/menu fallback.
- Support hardware keyboard, pointer, and assistive input alongside touch.

## 7. Components — HIGH

- **Buttons:** `.borderedProminent` for primary, `.bordered` for secondary, `role: .destructive` for destructive actions.
- **Alerts:** critical decisions only, max 2–3 buttons.
- **Sheets:** self-contained tasks, always a Cancel/Done and `.presentationDetents([.medium, .large])` + drag indicator.
- **Lists** are the foundation of most iOS screens. Use `.insetGrouped` (modern default), `.plain` (edge-to-edge), or `.sidebar` (iPad). Swipe actions: leading = positive (max 3–4), trailing = destructive at far right.
- **Tab bars:** SF Symbol filled variant when selected, outline when not; use `.badge()` for counts; never hide on push.
- **Search:** `.searchable()` with `.searchSuggestions` and recent searches.
- **Context menus** (long-press) for secondary actions only — never the sole path to an action.
- **Forms:** 44pt min field height, match keyboard type to input type (`.emailAddress`, `.numberPad`), clear button, `.quaternary` placeholder color.
- **Progress:** determinate `ProgressView(value:total:)` when duration is known, indeterminate otherwise. Never a full-screen blocking spinner — prefer skeleton/redacted placeholders.

## 8. Patterns — MEDIUM

- **Onboarding:** max 3 pages, always skippable, defer sign-in until actually needed.
- **Loading:** skeleton views with `.redacted(reason: .placeholder)`, never a blocking full-screen spinner.
- **Launch screen:** must visually match the app's first screen — no logo splash.
- **Modality:** use sparingly, always a clear dismiss, never stack modals on modals.
- **Notifications:** high-value only, actionable, user-controllable categories.
- **Settings:** frequent settings in-app; privacy/permission settings deep-link to system Settings; never duplicate system controls.
- **Action sheets** (`confirmationDialog`): destructive action on top (red), Cancel at bottom.
- **Pull-to-refresh:** `.refreshable { await ... }`.
- **Haptics:** `UIImpactFeedbackGenerator` for physical impact, `UINotificationFeedbackGenerator` for success/warning/error, `UISelectionFeedbackGenerator` for selection changes.

## 9. Privacy & Permissions — HIGH

- Request permissions **in context**, at the moment the action needs them — never at launch.
- Show a custom explanation screen before the one-shot system prompt; if denied, direct users to Settings.
- If offering any third-party sign-in, also offer **Sign in with Apple**, presented first.
- Don't require an account until a feature genuinely needs it (purchases, sync, social).
- Show the ATT prompt if tracking across apps/sites; respect denial fully.
- Use `LocationButton` for one-time location access without a standing permission.

## 10. System Integration — MEDIUM

- Provide WidgetKit widgets for glanceable, frequently-checked data.
- Define App Shortcuts (Siri/Spotlight/Shortcuts app) for key actions.
- Index content with `CSSearchableItem` for Spotlight.
- Support `ShareLink` for shareable content.
- Use Live Activities/Dynamic Island for real-time, time-bound events.
- Handle `@Environment(\.scenePhase)` transitions (active/inactive/background) to save state and pause work gracefully.

## Anti-Patterns to Reject in Review

| Pattern | Problem | Fix |
|---|---|---|
| Hamburger/drawer menu | Hides navigation | `TabView` with 3–5 tabs |
| Custom gesture blocking back-swipe | Breaks system nav | Keep default `NavigationStack` behavior |
| Full-screen spinner | Feels frozen | Skeleton views with `.redacted()` |
| Logo splash screen | Artificial delay | Launch screen matches first view |
| Permission request at launch | Denied without context | Request at point of use |
| Fixed font sizes | Breaks Dynamic Type | Semantic `.font()` styles |
| Color-only status | Colorblind users miss it | Add icon/text |
| Hidden tab bar on push | Loses nav context | Keep tab bar visible |
| Content under notch/Dynamic Island | Hidden/clipped | Only `.ignoresSafeArea()` for backgrounds |
| Nested modals | Confusing | One `NavigationStack` per sheet |
| Small tap targets | Mis-taps | 44×44pt minimum |
| Hardcoded colors | Breaks Dark Mode | Semantic colors / asset catalog variants |

## Pre-Ship Review Checklist

- [ ] All interactive elements ≥44×44pt; essential content inside safe area
- [ ] Primary actions reachable one-handed (bottom); spacing on 8pt grid
- [ ] Works from iPhone SE to iPad Pro; no hardcoded widths
- [ ] Bottom `TabView` (3–5 tabs) or `NavigationSplitView` on iPad; no hamburger menu
- [ ] Large titles on root views; back-swipe untouched; tab/scroll state persists
- [ ] Semantic text styles everywhere; reflows correctly at max accessibility Dynamic Type size; nothing below 11pt
- [ ] Semantic colors only; custom colors have all 4 asset variants; 4.5:1 contrast; status never color-only
- [ ] Every icon button has `.accessibilityLabel()`; VoiceOver order correct; Reduce Motion respected; every gesture has a non-gesture alternative
- [ ] Alerts reserved for critical decisions; sheets always dismissible; no stacked modals
- [ ] Permissions requested at point of use with a pre-explanation screen; core features usable without sign-in
- [ ] SF Symbols instead of custom icon PNGs; destructive actions require confirmation

*SwiftUI, SF Symbols, Dynamic Island, Liquid Glass, and Apple are trademarks of Apple Inc.*
