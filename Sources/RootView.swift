import SwiftUI

/// Auth-gated root router. Shows login flow until authenticated, then timeline.
/// When app lock is enabled + locked, overlays a LockView (AC-104/AC-105).
struct RootView: View {
    @State private var auth: AuthViewModel
    @State private var timeline: TimelineViewModel
    @State private var trash: TrashViewModel
    @State private var search: SearchViewModel
    @State private var albums: AlbumsViewModel
    @State private var appLock: AppLockViewModel

    init(container: DependencyContainer = .shared) {
        let authVM = container.makeAuthViewModel()
        _auth = State(initialValue: authVM)
        _timeline = State(initialValue: container.makeTimelineViewModel())
        _trash = State(initialValue: container.makeTrashViewModel())
        _search = State(initialValue: container.makeSearchViewModel())
        _albums = State(initialValue: container.makeAlbumsViewModel())
        _appLock = State(initialValue: container.appLock)
    }

    private var isGated: Bool { appLock.isEnabled && appLock.isLocked }

    var body: some View {
        ZStack {
            Group {
                if auth.isAuthenticated {
                    TabView {
                        TimelineView(vm: timeline)
                            .tabItem { Label("Timeline", systemImage: "photo.on.rectangle") }
                        AlbumsView(vm: albums)
                            .tabItem { Label("Albums", systemImage: "rectangle.stack") }
                        SearchView(vm: search)
                            .tabItem { Label("Search", systemImage: "magnifyingglass") }
                        TrashView(vm: trash)
                            .tabItem { Label("Trash", systemImage: "trash") }
                        BackupSettingsView()
                            .tabItem { Label("Backup", systemImage: "icloud.and.arrow.up") }
                    }
                } else {
                    ServerConnectView()
                }
            }
            .environment(auth)
            .environment(appLock)
            .environment(albums)
            .blur(radius: isGated ? 30 : 0)

            if isGated {
                LockView(appLock: appLock)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isGated)
    }
}

private struct LockView: View {
    let appLock: AppLockViewModel

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text("PhotoVault Locked")
                    .font(.title2.bold())
                Button {
                    Task { _ = await appLock.authenticate() }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .accessibilityIdentifier("AppLockOverlay")
    }
}
