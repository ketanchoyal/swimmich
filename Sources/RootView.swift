import SwiftUI

/// Auth-gated root router. Shows login flow until authenticated, then timeline.
/// When app lock is enabled + locked, overlays a LockView (AC-104/AC-105).
struct RootView: View {
    @State private var auth: AuthViewModel
    @State private var timeline: TimelineViewModel
    @State private var trash: TrashViewModel
    @State private var search: SearchViewModel
    @State private var map: MapViewModel
    @State private var albums: AlbumsViewModel
    @State private var appLock: AppLockViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(container: DependencyContainer = .shared) {
        let authVM = container.makeAuthViewModel()
        _auth = State(initialValue: authVM)
        _timeline = State(initialValue: container.makeTimelineViewModel())
        _trash = State(initialValue: container.makeTrashViewModel())
        _search = State(initialValue: container.makeSearchViewModel())
        _map = State(initialValue: container.makeMapViewModel())
        _albums = State(initialValue: container.makeAlbumsViewModel())
        _appLock = State(initialValue: container.appLock)
    }

    private var isGated: Bool { appLock.isEnabled && appLock.isLocked }

    var body: some View {
        ZStack {
            Group {
                if auth.isRestoringSession {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if auth.isAuthenticated {
                    TabView {
                        TimelineView(vm: timeline)
                            .tabItem { Label("Photos", systemImage: "photo.on.rectangle.angled") }
                        AlbumsView(vm: albums)
                            .tabItem { Label("Albums", systemImage: "square.stack") }
                        SearchView(vm: search, mapVM: map)
                            .tabItem { Label("Recherche", systemImage: "magnifyingglass") }
                        SharedLinksView()
                            .tabItem { Label("Partagé", systemImage: "person.2.fill") }
                        ProfileView(trash: trash)
                            .tabItem { Label("Moi", systemImage: "person.crop.circle") }
                    }
                    .immichBottomBar()
                } else {
                    OnboardingFlowView()
                }
            }
            .environment(auth)
            .environment(appLock)
            .environment(albums)
            .blur(radius: isGated ? 30 : 0)
            .task {
                // Reconfigure the shared client from the stored session and
                // validate the token on launch (auth persistence across relaunch).
                await auth.restoreSession()
            }

            if isGated {
                LockView(appLock: appLock)
                    .transition(.opacity)
            }
        }
        .animation(PVMotion.adaptive(PVMotion.gentle, reduceMotion: reduceMotion), value: isGated)
    }
}

private struct LockView: View {
    let appLock: AppLockViewModel

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: PVSpacing.s24) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56)) // DS-exempt: hero illustration §8.6
                    .foregroundStyle(Color.textSecondaryPV)
                Text("PhotoVault Locked")
                    .font(.pvTitle)
                Button {
                    Task { _ = await appLock.authenticate() }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                }
                .buttonStyle(PVPrimaryButtonStyle())
            }
        }
        .accessibilityIdentifier("AppLockOverlay")
    }
}
