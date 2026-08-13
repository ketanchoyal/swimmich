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
    @State private var sharedLinks: SharedLinksViewModel
    @State private var storage: StorageStatsViewModel
    @State private var appLock: AppLockViewModel
    @State private var selection: RootTab = .photos
    @State private var lastContentTab: RootTab = .photos
    @State private var showCreateAlbum = false
    @State private var showCreateSharedLink = false
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
        _sharedLinks = State(initialValue: container.makeSharedLinksViewModel())
        _storage = State(initialValue: container.makeStorageStatsViewModel())
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
    /// From Photos the bubble lands on the real Search tab (a plain tab, so a
    /// `.sheet` can be presented safely on top of it — the search full-screen
    /// cover was removed because SwiftUI serializes presentations from the
    /// same presenter, which made a sheet above it impossible, and a sheet
    /// inside the cover crashed on teardown). From Albums/Shared/Me the bubble
    /// keeps its contextual action (create / placeholder / logout) and the
    /// selection snaps back. The bubble icon mirrors the active tab.
    private var authenticatedTabView: some View {
        TabView(selection: $selection) {
            Tab("Photos", systemImage: "photo.on.rectangle.angled", value: RootTab.photos) {
                TimelineView(vm: timeline)
            }
            Tab("Albums", systemImage: "square.stack", value: RootTab.albums) {
                AlbumsView(vm: albums)
            }
            Tab("Shared", systemImage: "person.2.fill", value: RootTab.shared) {
                SharedLinksView(vm: sharedLinks)
            }
            Tab("Me", systemImage: "person.crop.circle", value: RootTab.me) {
                ProfileView(trash: trash, storage: storage)
            }
            Tab("Search", systemImage: bubbleIcon, value: RootTab.search, role: .search) {
                SearchView(vm: search, mapVM: map)
            }
        }
        .immichBottomBar()
        .onChange(of: selection) { _, newValue in
            if newValue == .search {
                if lastContentTab == .photos {
                    // Bubble from Photos: land on the Search tab itself.
                    lastContentTab = newValue
                } else {
                    handleBubbleTap()
                    selection = lastContentTab
                }
            } else {
                lastContentTab = newValue
                // Leaving the search tab takes the map photo sheet down with
                // it (stable presenter — RootView — so no teardown trap).
                map.isPhotoSheetPresented = false
            }
        }
        .sheet(isPresented: $showCreateAlbum) {
            CreateAlbumSheet(vm: albums, preselectedAssetIds: nil)
        }
        .sheet(isPresented: $showCreateSharedLink) {
            CreateSharedLinkSheet(vm: sharedLinks, baseURL: auth.baseURL ?? URL(string: "https://example.com")!)
        }
        // Native map photo sheet, owned by RootView (never deallocated): the
        // only presentation active while browsing the map tab, so SwiftUI
        // presents it directly above the tab — detents, swipe-down and the
        // system corner radius for free.
        .sheet(isPresented: Binding(
            get: { map.isPhotoSheetPresented },
            set: { map.isPhotoSheetPresented = $0 }
        )) {
            MapPhotosSheet(vm: map)
                .presentationDetents([.fraction(1.0 / 3.0), .medium])
                .presentationBackgroundInteraction(.enabled)
                .presentationBackground(.regularMaterial)
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
        case .photos: break // Landing on the Search tab is handled by the TabView itself.
        case .albums: showCreateAlbum = true
        case .shared: showCreateSharedLink = true
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
