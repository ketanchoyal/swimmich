# immich_swiftui — documentation index

Start here. This is an Apple-native (not ported) SwiftUI client for [Immich](https://github.com/immich-app/immich),
targeting iOS 26 / Liquid Glass, structured as a single-module MVVM app with `@Observable` view models.

## Project knowledge

| Doc | What it is |
| --- | --- |
| [`audit-2026-08.md`](audit-2026-08.md) | Consolidated read-only audit: research/docs, runtime performance, iOS 26 design/HIG. Every finding cites `file:line`. |
| [`../immich-swiftui-prd-design-system.md`](../immich-swiftui-prd-design-system.md) | Primary PRD + design-system spec (vision, scope, IA, colors, onboarding). v0.1 Draft. |
| [`../PhotoVault-DesignSystem.md`](../PhotoVault-DesignSystem.md) | Single source of truth for the PhotoVault visual language (color/font/spacing/radius/motion tokens). |
| [`../.opencode/memory.md`](../.opencode/memory.md) | The de-facto onboarding doc for new contributors: architecture decisions, Immich API gotchas, per-feature decision logs, acceptance-contract methodology. Read this first. |
| [`../.opencode/AGENTS.pipeline.md`](../.opencode/AGENTS.pipeline.md) | Multi-agent pipeline methodology (Phase 0a-0d, AC-NNN template, Phase 1-4). |
| [`../.opencode/scratch/*.acceptance.md`](../.opencode/scratch) | Executable acceptance contracts (one per feature). Each now carries a `Status:` line (shipped / wip / backlog). |
| [`../project.yml`](../project.yml) | xcodegen project spec (bundle id, team, targets, sources). |

## Code map

- `Sources/DesignSystem/` — tokens (`Tokens/`) + components (`Components/`). The canonical brand colors live in `Tokens/ImmichColors.swift` (`Color.immich*`).
- `Sources/Core/` — `Types/` (DTOs), `Protocols/` (`ImmichClient`, `KeychainStore`, …), `Utilities/`.
- `Sources/Services/` — `ImmichAPIClient`, `AuthenticatedAsyncImage` (3-tier image pipeline), `ImageCache` (actor-isolated `NSCache`).
- `Sources/Features/` — one folder per feature: `Timeline`, `Search` (Results/Explore/Map), `PhotoViewer`, `Albums`, `Editor`, `Auth` (onboarding), `Profile`, `Trash`, `SharedLinks`, `Upload`, `AssetDetail`.
- `Sources/ImmichSwiftUIApp.swift` + `RootView.swift` + `DependencyContainer.swift` — app entry, auth-gated 5-tab router, composition root.

## Quick start

```bash
xcodegen generate        # regenerates ImmichSwiftUI.xcodeproj from project.yml
open ImmichSwiftUI.xcodeproj
# pick a simulator, ⌘R
```
