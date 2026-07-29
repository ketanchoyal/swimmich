import SwiftUI

@main
struct ImmichSwiftUIApp: App {
    @State private var container = DependencyContainer.shared

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }
}
