---
name: swiftui-swiftdata-persistence
description: SwiftData and local/cloud persistence patterns for SwiftUI apps. Use when a screen needs to save, query, or sync structured data — @Model definitions, @Query, ModelContainer/ModelContext setup, relationships, migrations, CloudKit sync, or choosing between SwiftData, Core Data, and simple file/UserDefaults storage. Load when a feature involves data that must survive app restarts or sync across devices.
license: MIT
compatibility: opencode
metadata:
  domain: ios-swiftui
  role: persistence
  min-os: "iOS 17"
---

# SwiftData & Persistence

## Choosing a Storage Layer

| Need | Use |
|---|---|
| Small, simple key-value settings (theme, flags, last-viewed tab) | `@AppStorage` / `UserDefaults` |
| Structured, relational, queryable data (notes, tasks, catalog items) | **SwiftData** (default choice for new iOS 17+ apps) |
| Complex existing Core Data stack, or need features SwiftData lacks (e.g. some advanced migrations) | Core Data |
| Large binary blobs (images, files) | File system (`FileManager`, Documents directory) — store only a reference/path in SwiftData, never the blob itself |
| Sensitive data (tokens, credentials) | Keychain — never `UserDefaults` or plain SwiftData for secrets |
| Cross-device sync of user data | SwiftData + CloudKit integration |

## SwiftData Basics

```swift
import SwiftData

@Model
final class Task {
    var title: String
    var isCompleted: Bool
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var subtasks: [Subtask]

    init(title: String, isCompleted: Bool = false) {
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = .now
        self.subtasks = []
    }
}
```

- Register the container once at app root:
  ```swift
  @main
  struct MyApp: App {
      var body: some Scene {
          WindowGroup { ContentView() }
              .modelContainer(for: Task.self)
      }
  }
  ```
- Query in views with `@Query` (auto-updates when data changes):
  ```swift
  struct TaskListView: View {
      @Query(sort: \Task.createdAt, order: .reverse) private var tasks: [Task]
      @Environment(\.modelContext) private var context

      var body: some View {
          List(tasks) { task in Text(task.title) }
      }
  }
  ```
- Mutate via `modelContext.insert(_:)` / `modelContext.delete(_:)`; SwiftData autosaves by default, but call `try? context.save()` explicitly after critical writes if immediate persistence matters.
- Filter with `#Predicate` macro for type-safe queries:
  ```swift
  @Query(filter: #Predicate<Task> { !$0.isCompleted })
  private var pendingTasks: [Task]
  ```

## Relationships & Deletion Rules

- `.cascade` — deleting the parent deletes children (e.g. a list deleting its items).
- `.nullify` — deleting the parent nulls the reference on children (default).
- `.deny` — prevents deleting a parent that still has children (use for protecting referenced data).
- Model inverse relationships explicitly with `@Relationship(inverse: \OtherModel.property)` to avoid duplicate/orphaned records.

## Migrations

- Any change to a `@Model`'s stored properties is a schema change. For **additive** changes (new optional property, new model), SwiftData often migrates automatically (lightweight migration).
- For renames, type changes, or non-optional new properties without defaults, define an explicit `VersionedSchema` + `SchemaMigrationPlan` — never assume silent compatibility across schema versions in a shipped app.
- Test migrations against a real "old" database file before shipping — don't trust it works from reading the diff alone.

## CloudKit Sync

- Add CloudKit capability, then configure `ModelConfiguration(cloudKitDatabase: .automatic)`.
- All `@Model` properties needed for sync must have defaults or be optional — CloudKit requires this to merge schema versions across devices.
- Design for eventual consistency: don't assume immediate cross-device sync; show sync status if the feature is sync-critical.
- Test with two simulators/devices signed into the same iCloud sandbox account before shipping.

## Performance

- Don't fetch entire large tables into memory — use `@Query` with predicates/limits, not manual `fetchAll()` + in-memory `filter()`.
- Keep `@Model` classes focused; avoid one giant model with dozens of unrelated properties (each mutation triggers observers watching that model).
- Perform bulk imports/writes in a background `ModelContext` (via `ModelActor` or a separate context), not the main-thread view context, to avoid blocking UI.
- Avoid storing large images/blobs directly as `Data` properties in a `@Model` — store a file reference instead, or query performance and app size will degrade.

## Anti-Patterns

- Using `UserDefaults` for structured or relational data instead of SwiftData.
- Storing secrets/tokens in SwiftData or `UserDefaults` instead of Keychain.
- Making non-optional property changes to a shipped `@Model` without an explicit migration plan.
- Fetching all records then filtering in Swift instead of using `#Predicate` at the query level.
- Performing large batch writes on the main `ModelContext` synchronously, causing UI hitches.
- Assuming CloudKit sync is instantaneous or guaranteed — always design for conflict/delay.
