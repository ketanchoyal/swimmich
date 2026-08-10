# Task: timeline-visual-redesign

Status: shipped — Timeline visual redesign (year + day-month + weekday headers).

## Plan
Elevate timeline from "trainee" to Apple-Photos-grade professional aesthetics. iOS 17 target. Purely visual — no new endpoints, no VM behavior changes, no breaking the 29 passing tests.

### Objective
- Fix #1 amateur tell: ragged grid → uniform 1:1 square cells.
- Human-relative date headers (Today/Yesterday/weekday/full) replacing raw ISO strings.
- Uniform material-pill badges (heart/play/360 same treatment).
- Pro selection: cell scale 0.96 + blue tint + symbol-morphing checkmark.
- Large title collapsing, SF Symbol toolbar, skeleton shimmer loading, empty/error states.

### Hypotheses (verified by reading source — scout not re-needed)
1. `TimelineView.swift:57` renders `Text(group.day)` raw — `group.day` is ISO prefix `"2024-07-01"`. Formatting belongs in View layer; VM `groupedByDay` stays raw (AC-100 test asserts `groups[0].day == "2024-07-03"`).
2. `AssetThumbnailCell.swift:27` has `.aspectRatio(CGFloat(asset.aspectRatio), contentMode: .fill)` → variable ragged heights. Replace with `.aspectRatio(1, contentMode: .fill)`.
3. iOS 17 safe APIs: `.headerProminence(.increased)`, `.symbolEffect(.bounce)`, `.contentTransition(.symbolEffect(.replace))` (iOS 17), `ContentUnavailableView` (iOS 17), `.animation(.spring(duration:), value:)`, `PhaseAnimator`, `LazyVStack(pinnedViews:)`.
4. AVOID iOS 18+: `.navigationTransition(.zoom)`, `.scrollPosition`, `.onScrollGeometryChange`.
5. 29 existing tests must stay green. VM untouched.

### Steps
1. NEW `Sources/Features/Timeline/DateHeaderFormatter.swift` — `static func displayString(for isoPrefix:relativeTo:calendar:)`. Parse ISO → UTC noon Date, relative label.
2. NEW `Tests/DateHeaderFormatterTests.swift` (AC-V01) — Today/Yesterday/weekday/full/timezone edge.
3. MODIFY `Sources/Features/Timeline/AssetThumbnailCell.swift` — square cells, uniform pill badges, pro selection (blue tint, scale 0.96, symbol morph).
4. MODIFY `Sources/Features/Timeline/TimelineView.swift` — large title, SF Symbol toolbar, skeleton shimmer loading, empty/error states, spring selection animation, `DateHeaderFormatter` integration, `.headerProminence(.increased)`.

## Acceptance Contract

### Approches candidates
- A "Apple Photos Parity" (square grid, safe pro): uniform 1:1 cells, human dates, material pills, blue-tint selection, large title, icons, skeleton shimmer.
- B "Editorial Masonry" (variable aspect, risky): packed/masonry layout — needs `Layout` protocol or UIKit interop, complex on iOS 17. Rejected.
- C "Day-Hero" (Instagram): first photo full-width 4:3, rest square — irregular pacing, scope creep. Rejected.

### Approche retenue + rationale
**A**. Single largest visual upgrade per LOC. Square cells alone fix #1 amateur tell. Every change has clear "does this look like Photos.app?" litmus. No novel layouts, no iOS 18 risk. Safe, fast, high-impact.

### Critères

```
### AC-R01 [type: regression]
Assertion: All 29 existing tests in TimelineViewModelTests pass after redesign (zero regressions).
Check post-impl: xcodebuild test -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' → Test Suite 'TimelineViewModelTests' passed, 0 failures.
Pre-state attendu: 29 PASS
Post-state attendu: 29 PASS

### AC-R02 [type: regression]
Assertion: TimelineViewModel.groupedByDay still returns raw ISO prefix strings — VM untouched by visual redesign.
Check post-impl: xcodebuild test -only-testing:.../test_AC_100_groupedByDay → PASS (asserts groups[0].day == "2024-07-03" etc.)
Pre-state attendu: PASS
Post-state attendu: PASS

### AC-V01 [type: new]
Assertion: DateHeaderFormatter produces human-readable day labels for ISO prefixes relative to a reference date — Today/Yesterday/weekday+monthDay within 7 days/full date older/timezone-safe. Test MUST force a non-default TimeZone (Pacific/Honolulu GMT-10) via the injected `calendar:` parameter to prove timezone determinism.
Check post-impl: xcodebuild test -only-testing:.../DateHeaderFormatterTests → PASS
  Cases (all w/ `calendar.timeZone = TimeZone(identifier:"Pacific/Honolulu")!`):
  - "2024-07-29"@2024-07-29T12:00:00-10:00 → "Today"
  - "2024-07-28" → "Yesterday"
  - "2024-07-27" → "Saturday, July 27"  (within 7 days → weekday + month day)
  - "2024-07-20" (9 days) → "Saturday, July 20, 2024"  (older → full date)
  - "2023-12-25" → "Monday, December 25, 2023"
  - Honolulu midnight edge: ISO "2024-07-29" vs ref 2024-07-29T23:30:00-10:00 → "Today" (NOT "Tomorrow") — proves UTC-noon parsing.
Pre-state attendu: build/test invocation fails — DateHeaderFormatterTests class does not exist (xcodebuild exits non-zero with "no tests found" / compile error). Red.
Post-state attendu: PASS

### AC-V02 [type: new]
Assertion: AssetThumbnailCell enforces 1:1 square aspect — no variable-ratio calls anywhere in file.
Check post-impl:
  - `rg "\.aspectRatio\(CGFloat" Sources/Features/Timeline/AssetThumbnailCell.swift` → 0 matches (no variable aspect at all)
  - `rg "\.aspectRatio\(1," Sources/Features/Timeline/AssetThumbnailCell.swift` → ≥1 match (square policy present)
Pre-state attendu: line 27 has `.aspectRatio(CGFloat(asset.aspectRatio), contentMode: .fill)` → first grep ≥1, second 0. RED.
Post-state attendu: first grep 0, second grep ≥1. GREEN.

### AC-V03 [type: new]
Assertion: TimelineView toolbar uses SF Symbol icons — no raw text "Logout"/"Cancel" toolbar buttons (alert-dismiss "Cancel" w/ `, role: .cancel` is fine and stays).
Check post-impl:
  - `rg 'Button\("Logout"\)' Sources/Features/Timeline/TimelineView.swift` → 0 (Logout only ever in toolbar)
  - `rg 'systemImage: "xmark"' Sources/Features/Timeline/TimelineView.swift` → ≥1 (Cancel→xmark icon landed)
  - `rg 'rectangle.portrait.and.arrow.right' Sources/Features/Timeline/TimelineView.swift` → ≥1 (Logout icon landed)
  Note: regex `Button\("Cancel"\)` (literal, no comma) excludes alert variants `Button("Cancel", role: .cancel)` by design, but the SF-Symbol positive greps above are the authoritative proof.
Pre-state attendu: line 219 `Button("Cancel") {`, line 247 `Button("Logout")` → Logout grep ≥1, xmark 0, arrow 0. RED.
Post-state attendu: Logout grep 0, xmark ≥1, arrow ≥1. GREEN.

### AC-V04 [type: new]
Assertion: Selection mode enter/exit uses spring animation.
Check post-impl: `rg "\.animation\(\.spring" Sources/Features/Timeline/TimelineView.swift` → ≥1 match.
Pre-state attendu: no spring on selection (RED)
Post-state attendu: spring drives selection (GREEN)

### AC-V05 [type: new]
Assertion: Empty library state shows meaningful placeholder (ContentUnavailableView), not spinner or blank.
Check post-impl: `rg "ContentUnavailableView" Sources/Features/Timeline/TimelineView.swift` → ≥1 match.
Pre-state attendu: only ProgressView when empty+loading; empty+!loading → blank (RED)
Post-state attendu: dedicated empty state (GREEN)

### AC-V06 [type: new]
Assertion: Navigation title is "Photos" w/ large display mode (collapsing on scroll); selection mode still overrides to "X selected".
Check post-impl:
  - `rg '"Photos"' Sources/Features/Timeline/TimelineView.swift` → ≥1 match (string literal present, regardless of ternary/conditional structure)
  - `rg '\.navigationBarTitleDisplayMode\(\.large\)' Sources/Features/Timeline/TimelineView.swift` → ≥1 match
  - `rg '\(vm\.selectedIds\.count\) selected' Sources/Features/Timeline/TimelineView.swift` → ≥1 (selection-mode title override present)
Pre-state attendu: line 97 `.navigationTitle(vm.selectionMode ? "\(vm.selectedIds.count) selected" : "Timeline")` (no "Photos" literal), line 98 `.navigationBarTitleDisplayMode(.inline)` → "Photos" grep 0, .large grep 0. RED.
Post-state attendu: "Photos" grep ≥1, .large grep ≥1, selected-override grep ≥1. GREEN.

### AC-V07 [type: new]
Assertion: Loading state uses a skeleton shimmer grid (animated gradient sweep over redacted/gray placeholders), NOT ProgressView. Both initial-load (4×3) and bottom load-more (1×3) use the shimmer.
Check post-impl:
  - `rg "ProgressView" Sources/Features/Timeline/TimelineView.swift` → 0 matches (no spinners anywhere in timeline)
  - `rg "SkeletonShimmer|shimmer|redacted" Sources/Features/Timeline/TimelineView.swift` → ≥1 match (skeleton view present)
  - `rg "PhaseAnimator|shimmer" Sources/Features/Timeline/TimelineView.swift` → ≥1 match (animation/skeleton present; "shimmer" matches SkeletonShimmerGrid name)
Pre-state attendu: lines 42, 67 have ProgressView → first grep ≥2. RED.
Post-state attendu: first grep 0, others ≥1. GREEN.
Definition (positive spec): SkeletonShimmerGrid renders N rows × 3 cols of `RoundedRectangle(cornerRadius: 4, style: .continuous)` filled `Color(.systemGray5)`, overlaid by an animated linear `Gradient` (clear → white.opacity(0.4) → clear) sweeping horizontally via `PhaseAnimator` or `.offset(x:)` w/ `.linear(1.5).repeatForever()`. NOT a static gray rectangle, NOT ProgressView.
```

### Failure modes (top 3 + quel AC/V les détecte)
1. **Square cropping removes image content** — design intent (Photos.app also crops). Caught by V1 visual. UX choice, not bug. Severity LOW.
2. **Date formatter wrong day near midnight in non-UTC timezones** — must parse ISO as UTC noon, compare via `Calendar.current.isDateInToday`. AC-V01 timezone-edge case (Honolulu GMT-10) catches it. Severity MEDIUM.
3. **scrollTransition scale + tight square spacing exposes background at row boundaries** — V2 visual. Mitigation: `.clipped()` outer container or slight spacing bump. Severity LOW.

## Vérifications manuelles (hors auto-feedback loop)
- V1 square grid uniformity (all cells perfect squares, 2pt gaps, 16pt section spacing, works 393pt + 375pt + iPad widths).
- V2 scrollTransition smoothness (0.92→1.0→0.92 no flicker/clip/background bleed; scroll-to-top button no overlap).
- V3 date header typography (`.subheadline.weight(.regular)`, `.foregroundStyle(.secondary)`, `.background(.bar)`, `.headerProminence(.increased)`, smooth collapse).
- V4 badge uniformity (all 3 = `.ultraThinMaterial` Capsule, `.caption2.weight(.medium)`, 6/3 padding, 6pt from cell edge).
- V5 selection polish (long-press haptic + spring scale 0.96; selected = blue 0.15 tint + checkmark morph circle→checkmark.circle.fill via `.contentTransition(.symbolEffect(.replace))` + `.symbolEffect(.bounce)` on tap; unselected = subtle 0.08 dim not 0.35 crush; exit spring back).
- V6 large title (`.navigationTitle("Photos")`, `.navigationBarTitleDisplayMode(.large)`, collapse on scroll; selection overrides to "X selected" inline).
- V7 skeleton shimmer loading — SkeletonShimmerGrid: N×3 `RoundedRectangle(cornerRadius:4,.continuous)` `Color(.systemGray5)` w/ animated linear Gradient (clear→white.opacity(0.4)→clear) sweeping horizontally 1.5s repeatForever. 4×3 on initial load, 1×3 at bottom load-more. NOT ProgressView, NOT static gray.
- V8 delete animation (`.transition(.scale(0.5).combined(with:.opacity))` on removed cells, remaining slide up).
- V9 empty/error state (ContentUnavailableView "No Photos" + description; error variant w/ Try Again).

## Files
- NEW `Sources/Features/Timeline/DateHeaderFormatter.swift`
- NEW `Tests/DateHeaderFormatterTests.swift`
- MODIFY `Sources/Features/Timeline/AssetThumbnailCell.swift` (square, pills, pro selection)
- MODIFY `Sources/Features/Timeline/TimelineView.swift` (large title, icons, skeleton, empty/error, spring, headerProminence)
- NOT TOUCHED: TimelineViewModel.swift, AssetReactItem.swift, AuthenticatedAsyncImage.swift, ImmichClient, AssetDetailView.
