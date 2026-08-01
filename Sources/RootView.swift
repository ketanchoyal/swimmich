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
    @State private var selection: RootTab = .photos
    @State private var lastContentTab: RootTab = .photos
    @State private var showSearch = false
    @State private var showCreateAlbum = false
    @State private var showSharedPlaceholder = false
    @State private var confirmLogout = false
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
                    authenticatedTabView
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

    // MARK: - Authenticated root

    /// 5-tab root (Photos/Albums/Shared/Me) + a native iOS 26 search tab
    /// (`role: .search`) rendered as a floating Liquid Glass bubble pinned to
    /// the tab bar's trailing edge, perfectly aligned by the system.
    ///
    /// The bubble is intercepted: instead of landing on the search tab, its tap
    /// opens the screen matching the active tab (search on Photos, create on
    /// Albums/Shared, logout on Me) and the selection snaps back to the
    /// originating tab. The bubble icon mirrors the active tab.
    private var authenticatedTabView: some View {
        TabView(selection: $selection) {
            Tab("Photos", systemImage: "photo.on.rectangle.angled", value: RootTab.photos) {
                TimelineView(vm: timeline)
            }
            Tab("Albums", systemImage: "square.stack", value: RootTab.albums) {
                AlbumsView(vm: albums)
            }
            Tab("Shared", systemImage: "person.2.fill", value: RootTab.shared) {
                SharedLinksView()
            }
            Tab("Me", systemImage: "person.crop.circle", value: RootTab.me) {
                ProfileView(trash: trash)
            }
            Tab("Search", systemImage: bubbleIcon, value: RootTab.search, role: .search) {
                SearchView(vm: search, mapVM: map)
            }
        }
        .immichBottomBar()
        .tabBarMinimizeBehavior(.never)
        .onChange(of: selection) { _, newValue in
            if newValue == .search {
                handleBubbleTap()
                selection = lastContentTab
            } else {
                lastContentTab = newValue
            }
        }
        .sheet(isPresented: $showCreateAlbum) {
            CreateAlbumSheet(vm: albums, preselectedAssetIds: nil)
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchView(vm: search, mapVM: map)
        }
        .alert("Shared links coming soon", isPresented: $showSharedPlaceholder) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Creating shared links from here isn't available yet.")
        }
        .confirmationDialog("Log out?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                Task { await auth.logout() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var bubbleIcon: String {
        switch selection {
        case .photos: "magnifyingglass"
        case .albums, .shared: "plus"
        case .me: "rectangle.portrait.and.arrow.right"
        case .search: "magnifyingglass"
        }
    }

    private func handleBubbleTap() {
        switch lastContentTab {
        case .photos: showSearch = true
        case .albums: showCreateAlbum = true
        case .shared: showSharedPlaceholder = true
        case .me: confirmLogout = true
        case .search: break
        }
    }
}

/// Root-level tabs. Order defines tab order; raw value used only for matching.
private enum RootTab: Int, Hashable {
    case photos
    case albums
    case shared
    case me
    case search
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
