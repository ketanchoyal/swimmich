import SwiftUI

/// Auth-gated root router. Shows login flow until authenticated, then timeline.
struct RootView: View {
    @State private var auth: AuthViewModel
    @State private var timeline: TimelineViewModel

    init(container: DependencyContainer = .shared) {
        let authVM = container.makeAuthViewModel()
        _auth = State(initialValue: authVM)
        _timeline = State(initialValue: container.makeTimelineViewModel())
    }

    var body: some View {
        Group {
            if auth.isAuthenticated {
                TabView {
                    TimelineView(vm: timeline)
                        .tabItem { Label("Timeline", systemImage: "photo.on.rectangle") }
                    BackupSettingsView()
                        .tabItem { Label("Backup", systemImage: "icloud.and.arrow.up") }
                }
            } else {
                ServerConnectView()
            }
        }
        .environment(auth)
    }
}
