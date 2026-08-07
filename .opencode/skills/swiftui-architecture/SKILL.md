---
name: swiftui-architecture
description: Modern SwiftUI app architecture, state management, and Swift Testing conventions for native iOS apps. Use when scaffolding a new SwiftUI project, choosing between MV/MVVM/MVVM-C, wiring navigation with NavigationStack/NavigationPath, structuring dependency injection, or writing/reviewing unit and UI tests with Swift Testing and XCUITest.
license: MIT
compatibility: opencode
metadata:
  domain: ios-swiftui
  role: architecture-testing
---

# SwiftUI Architecture & Testing

## Default Architecture (2026 baseline)

For a new production SwiftUI app on iOS 17+, default to **MVVM + Coordinators + Dependency Injection** written in Swift 6 with strict concurrency:

- **Model** — plain structs/`Codable` types, no framework dependency.
- **ViewModel** — `@Observable` class holding UI state and business logic orchestration; one per screen/feature, injected with its dependencies (services, repositories) via initializer, not singletons.
- **View** — SwiftUI struct, owns its ViewModel via `@State private var viewModel = ...` (or receives it injected), stays declarative: no business logic in `body`.
- **Coordinator/Router** — owns `NavigationPath`/navigation state so views don't need to know about each other; enables push/present decisions to live outside the view layer and keeps views reusable and testable.

For simple, single-screen or leaf views with no meaningful logic, a lighter **MV** pattern (View talks directly to a shared `@Observable` model, no dedicated ViewModel) is acceptable — don't force a ViewModel onto a view that only displays static or trivially-derived data.

```swift
@Observable
final class ProfileViewModel {
    private let userService: UserService
    var user: User?
    var isLoading = false

    init(userService: UserService) {
        self.userService = userService
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        user = try? await userService.fetchCurrentUser()
    }
}

struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    init(userService: UserService) {
        _viewModel = State(initialValue: ProfileViewModel(userService: userService))
    }
    var body: some View {
        content
            .task { await viewModel.load() }
    }
}
```

## Navigation

- Own a single `NavigationPath` (or typed path enum) per navigation stack, held by a coordinator/root view, injected into child views as a binding — never let a leaf view push directly onto an ambient global stack.
- Model destinations as an enum conforming to `Hashable`, matched with `.navigationDestination(for:)`.
- Keep the coordinator dumb: it maps intents ("show detail for X") to path mutations; it does not contain business logic.

## Dependency Injection

- Inject dependencies (network clients, persistence, services) through initializers or `@Environment` for cross-cutting concerns (theme, analytics) — avoid ambient singletons for anything that needs to be mocked in tests.
- Define dependencies as protocols; production types conform for real behavior, test doubles conform for fakes/mocks.

## Swift Testing Conventions

Use the **Swift Testing** framework (`@Test`, `#expect`) for new code, not legacy `XCTest` assertions.

- **Always test:** business logic, validation rules, state transitions in ViewModels, error handling paths, edge cases (empty collections, nil, boundaries), async success and failure, task cancellation.
- **Skip testing directly:** SwiftUI view body layout (use snapshot tests instead), simple property forwarding, Apple framework internals, private methods (test through the public API).
- Name tests by behavior, not method: `fetchUserReturnsNilOnNetworkError`, not `testFetchUser`.
- Use `confirmation()` for async expectations — never `Task.sleep` as a synchronization hack.
- Use parameterized `@Test(arguments:)` for repetitive input variations instead of copy-pasted test functions.
- Mock dependencies via protocol conformance, not subclassing concrete types.
- No shared mutable state between tests — each test builds its own fixtures.

```swift
@Test("fetchUser returns nil on network error")
func fetchUserReturnsNilOnNetworkError() async {
    let service = MockUserService(shouldFail: true)
    let viewModel = ProfileViewModel(userService: service)
    await viewModel.load()
    #expect(viewModel.user == nil)
}
```

## Test Pyramid

1. **ViewModel/state tests** (most numerous) — fast, no UI, cover logic and edge cases.
2. **Snapshot tests** — visual regression for view output across Dynamic Type sizes and Light/Dark mode.
3. **UI tests (XCUITest)** — critical end-to-end flows only; locate elements by `.accessibilityIdentifier`, never by index or visible text; use `waitForExistence(timeout:)` instead of assuming immediate availability; reset app state in `setUpWithError()`.

## Anti-Patterns

- Fat views containing network calls, parsing, or business rules directly in `body` or button actions.
- Global mutable singletons standing in for dependency injection (untestable, hidden coupling).
- Massive single `ObservableObject`/`@Observable` "god objects" shared across unrelated screens.
- UI tests asserting on visible text/index instead of accessibility identifiers (brittle to copy/localization changes).
- Using `Task.sleep` to "wait" for async work in tests instead of proper `confirmation()`/expectation APIs.
