# Task: timeline-no-gap-no-radius

## Plan
**Objectif**: Timeline grid — no spacing between photo/video cells + no border radius anywhere (cells + skeleton). User explicit constraint overriding pending redesign values (spacing 4, radius 8).

**Hypothèses**:
- Only inter-cell spacing → 0. Screen-edge padding (`.padding(.horizontal, 4)`) preserved (not "between elements").
- All corner radii → 0: cell `clipShape`, skeleton `RoundedRectangle`.
- Selection scale, badges, tints unchanged.
- VM invariant. Tests unchanged.

**Étapes**:
1. `TimelineView.swift`: `columns` spacing 4→0; inner `LazyVGrid(columns:, spacing: 4)` → 0; `SkeletonShimmerGrid.columns` spacing 4→0; `SkeletonCell` cornerRadius 8→0 (×2: fill + mask).
2. `AssetThumbnailCell.swift`: `clipShape(RoundedRectangle(cornerRadius: 8))` → cornerRadius 0 (use `Rectangle()` to keep idiom clean, or `cornerRadius: 0`).
3. Build + tests.

## Acceptance Contract

### Approches candidates
**A — Value edits only (retenu)**: change spacing/radius literals. Zero behavioral change, minimal diff, no API touched.
**B — Rectangle() swap**: replace RoundedRectangle by Rectangle structurally. Cleaner intent but bigger diff, mask rewrite for skeleton gradient.
**C — Conditional radius via env**: over-engineering, scope creep.

### Approche retenue + rationale
**A**. Smallest diff, exact user intent, no risk.

### Critères

```
### AC-T1 [type: new]
Assertion: Timeline grid inter-cell spacing == 0 (both main grid + skeleton grid).
Check post-impl: sh -c 'n=$(grep -cE "spacing: 0" Sources/Features/Timeline/TimelineView.swift); test "$n" -ge 3 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (current values are spacing: 4 in 3 spots)
Post-state attendu: PASS (≥3 lines with spacing: 0)
```

```
### AC-T2 [type: new]
Assertion: All corner radii in TimelineView + AssetThumbnailCell == 0 (no border radius on cells, skeleton, gradient mask).
Check post-impl: sh -c 'r=$(grep -rhE "cornerRadius: 8|RoundedRectangle\(cornerRadius: 8" Sources/Features/Timeline/); test -z "$r" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (cornerRadius 8 present in TimelineView + AssetThumbnailCell)
Post-state attendu: PASS (no cornerRadius 8 left)
```

```
### AC-T3 [type: regression]
Assertion: Project compiles + timeline tests stay green.
Check post-impl: xcodebuild test -scheme ImmichSwiftUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ImmichSwiftUITests/TimelineViewModelTests -only-testing:ImmichSwiftUITests/TimelineSectionBuilderTests 2>&1 | grep -E '(\*\* TEST SUCCEEDED \*\*|TEST FAILED|error:)'
Pre-state attendu: ** TEST SUCCEEDED **
Post-state attendu: ** TEST SUCCEEDED **
```

### Failure modes (top 3 + quel AC les détecte)
**FM1 — Missed a radius**: e.g. skeleton mask still 8 → visible rounded shimmer on square cells. AC-T2 catches via grep.
**FM2 — Broke grid by changing wrong spacing (e.g. LazyVStack spacing 0 already exists, accidental edit elsewhere)**: AC-T3 build/test catches.
**FM3 — Edge padding removed by over-reading "no spacing"**: kept horizontal 4 (not between elements). Manual vérif.

## Vérifications manuelles (hors auto-feedback loop)
1. Photos butt against each other horizontally + vertically (no gap).
2. Videos + photos share the same no-gap layout.
3. Cells are sharp rectangles (no rounded corners) — both filled + loading skeleton.
4. Screen outer edge still has the 4pt inset (not flush to display edge).
5. Selection scale 0.96 + tint unchanged.
