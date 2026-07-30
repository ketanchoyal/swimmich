import SwiftUI

@main
struct ImmichSwiftUIApp: App {
    @State private var container = DependencyContainer.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                // AC-105: lock on background, attempt unlock on active.
                // FM-1 mitigated by AppLockViewModel.isAuthenticating guard.
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        container.appLock.lock()
                    case .active:
                        if container.appLock.isEnabled && container.appLock.isLocked {
                            Task { _ = await container.appLock.authenticate() }
                        }
                    default:
                        break
                    }
                }
        }
    }
}
