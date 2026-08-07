---
name: ios-build-debug
description: Xcode build, simulator, and runtime debugging workflow for iOS apps. Use when a build fails, a simulator won't launch, a run-time crash/hang occurs, dependency resolution breaks (SPM/CocoaPods), signing/provisioning errors appear, or before making code changes to diagnose whether a problem is environmental rather than a code bug. Load before rewriting Swift code in response to a build or runtime failure.
license: MIT
compatibility: opencode
metadata:
  domain: ios-swiftui
  role: build-debug
---

# iOS Build & Debug Workflow

Most iOS failures agents encounter are **environmental, not logical** — a stale derived data folder, a mismatched simulator runtime, a broken package graph, or a signing issue. Diagnose the environment before rewriting product code.

## Diagnostic Order — Always Follow This Sequence

1. **Confirm the target context**: scheme, active simulator/device, Xcode version, deployment target. A failure on iPhone 15 Simulator with iOS 17 SDK vs iOS 26 SDK can look identical in logs but have different root causes.
2. **Build before touching code.** Run the actual build command and read the *real* compiler/linker error — don't guess from the source file alone.
   ```
   xcodebuild -scheme <SchemeName> -destination 'platform=iOS Simulator,name=iPhone 16' build
   ```
3. **Read the first error, not the last.** Cascading errors in Swift often stem from one root cause (a missing import, a broken protocol conformance) — fix the first reported error and rebuild before addressing the rest.
4. **Reproduce in the simulator**, don't reason abstractly about UI/runtime bugs. Launch, navigate to the exact flow, and capture actual logs (`xcrun simctl spawn booted log stream --predicate '...'`) rather than assuming behavior.
5. **Make the smallest change** that addresses the diagnosed cause.
6. **Re-run the exact same build/launch command** to confirm the fix — don't declare success without re-verifying.

## Common Failure Classes

| Symptom | Likely cause | Fix |
|---|---|---|
| "No such module X" | Stale derived data, broken package cache | Clean build folder (`Cmd+Shift+K`), reset package caches (`File > Packages > Reset Package Caches`) |
| Build succeeds, simulator won't install | Simulator runtime mismatch with deployment target | Check `Deployment Target` vs installed simulator OS versions |
| Random Swift compiler errors on unrelated files | Corrupted derived data / incremental build state | `rm -rf ~/Library/Developer/Xcode/DerivedData/<project>` and rebuild clean |
| "Signing for X requires a development team" | Provisioning/signing config missing | Check target's Signing & Capabilities, automatic signing team |
| SPM dependency resolution fails | Version conflict or unreachable package source | Check `Package.resolved`, verify each dependency's version constraints |
| App crashes on launch, no visible SwiftUI error | Force-unwrap, missing `@main`, or Info.plist misconfiguration | Check crash log's exception type and top frame before touching views |
| UI looks correct in Preview but wrong in simulator | Preview uses different data/environment than runtime | Never trust Preview alone for final verification — run in simulator |
| Hang / frozen UI | Blocking main thread (sync I/O, heavy computation in body) | Capture a stack trace via Xcode's "Debug > Attach to Process" or Instruments Time Profiler |

## Simulator Verification Loop

Never claim a UI fix works without actually seeing it. When XcodeBuildMCP or simulator automation tools are available:

1. Build for a specific simulator.
2. Boot/launch the app.
3. Navigate to the exact screen/flow under test.
4. Capture a screenshot or inspect the accessibility tree — don't rely on code review alone for anything visual.
5. Check console logs for warnings (SwiftUI update-cycle warnings, constraint conflicts, Sendable warnings) even if the app doesn't crash.

## Crash Log Triage

When given a crash log or symbolicated stack trace:

1. Identify the **exception type** (`EXC_BAD_ACCESS`, `SIGABRT`, `EXC_BREAKPOINT` from a Swift `fatalError`/force-unwrap).
2. Find the **first frame belonging to app code** (not system frameworks) — that's usually the real culprit, not the top frame.
3. For `EXC_BAD_ACCESS`: check for use of a deallocated object, often a delegate/closure not held strongly enough or a dangling reference from a Combine/notification subscription.
4. For `SIGABRT` with "Fatal error": search for `!`, `try!`, or `as!` near the reported line.
5. For SwiftUI-specific runtime warnings ("Publishing changes from background threads", "Modifying state during view update"): trace to the exact `@State`/`@Observable` mutation happening off the main actor or inside `body`.

## Anti-Patterns

- Rewriting Swift code speculatively without first reproducing the actual build/runtime error.
- Ignoring build warnings that hint at the real bug (Sendable, deprecated API, unused result).
- Trusting SwiftUI Previews as proof a screen works — Previews can hide state-dependent or async bugs.
- Declaring a fix successful without re-running the exact reproduction steps.
- Deleting and recreating a whole project/target to "fix" what is actually a narrow caching issue.
