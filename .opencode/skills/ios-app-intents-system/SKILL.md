---
name: ios-app-intents-system
description: App Intents integration for iOS apps — Siri, Shortcuts, Spotlight, widgets, Live Activities, and Apple Intelligence system surfaces. Use when a feature needs to be exposed outside the app itself (voice commands, Shortcuts automation, widget actions, Spotlight search results, Control Center) or when defining AppIntent/AppEntity/EntityQuery types. Load when the user asks for Siri, Shortcuts, widget, or system-integration support.
license: MIT
compatibility: opencode
metadata:
  domain: ios-swiftui
  role: system-integration
  min-os: "iOS 16"
---

# App Intents & System Integration

Modern iOS apps are reached through more than a home-screen tap: Shortcuts, Siri, Spotlight, widgets, Live Activities, and Control Center. App Intents is the framework that exposes app actions/content to all of these surfaces from a single definition.

## Core Principle

**Map the real user action first, then define the AppIntent** — not the reverse. Every intent should be narrow, understandable in one sentence, and correspond to something a user genuinely wants to do quickly (e.g. "Start Timer", "Add Task", "Mark as Read") — not a vague catch-all wrapping the whole app.

## Basic AppIntent

```swift
import AppIntents

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription("Adds a new task to your list.")

    @Parameter(title: "Title")
    var taskTitle: String

    func perform() async throws -> some IntentResult {
        let context = try ModelContainerProvider.shared.mainContext
        let task = Task(title: taskTitle)
        context.insert(task)
        try context.save()
        return .result()
    }
}
```

- Register discoverability with `AppShortcutsProvider` so Siri/Spotlight surface the intent without manual user setup:
  ```swift
  struct MyAppShortcuts: AppShortcutsProvider {
      static var appShortcuts: [AppShortcut] {
          AppShortcut(
              intent: AddTaskIntent(),
              phrases: ["Add a task in \(.applicationName)"],
              shortTitle: "Add Task",
              systemImageName: "plus.circle"
          )
      }
  }
  ```
- Keep `perform()` fast and resilient — it can run in the background without the app's UI ever appearing; never assume `@Environment` or view-layer state is available inside it.

## AppEntity & EntityQuery (for content, not just actions)

Expose app data (not just actions) so Shortcuts/Siri can reference specific items ("Mark 'Buy milk' as done"):

```swift
struct TaskEntity: AppEntity {
    let id: UUID
    var title: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    static var defaultQuery = TaskEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct TaskEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [TaskEntity] {
        // fetch matching tasks by id
    }
    func suggestedEntities() async throws -> [TaskEntity] {
        // return recent/relevant tasks for Shortcuts autocomplete
    }
}
```

## Widgets

- Widgets should show **glanceable, frequently-checked** data — not a shrunken version of the full app.
- Use `AppIntentTimelineProvider` (not the legacy `TimelineProvider`) so widget configuration and interactive buttons can use App Intents directly.
- Interactive widget buttons (`Button(intent:)`) must trigger fast, self-contained App Intents — avoid long-running work inside a widget's intent handler.
- Keep widget refresh budgets in mind: request timeline reloads only as often as data actually changes.

## Live Activities

- Use for real-time, time-bound events only (delivery tracking, live scores, timers) — not for persistent/static state.
- Update via push notifications (`ActivityKit` push-token updates) for the most efficient background refresh, not local timers alone.
- Design the Dynamic Island's compact/minimal/expanded states explicitly — don't assume the expanded layout looks right shrunk down.

## Spotlight

- Index searchable content with `CSSearchableItem` / `CSSearchableIndex` so users can find in-app content without opening the app first.
- Update the index incrementally as content changes — don't do a full reindex on every launch, that wastes battery/CPU.

## Testing Intents

- Test `perform()` logic directly as a unit test — it's just async Swift code, no UI needed.
- Manually verify discoverability in the Shortcuts app and via Siri after adding/changing an `AppShortcut` — static analysis can't confirm real-world phrase matching.
- Check that intents behave correctly when the app is not running/backgrounded, since Shortcuts/Siri can invoke them without launching the full app UI.

## Anti-Patterns

- One giant "Do Anything" AppIntent with many optional parameters instead of several narrow, well-named intents.
- Assuming `@Environment`, `@State`, or any view-layer context is available inside `perform()`.
- Long-running or network-heavy work inside a widget's interactive intent handler.
- Live Activities used for content that isn't actually time-bound or real-time.
- Skipping `suggestedEntities()` on an `EntityQuery`, making Shortcuts autocomplete empty/useless.
- Reindexing all Spotlight content on every app launch instead of incrementally.
