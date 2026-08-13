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
    @State private var upload: UploadViewModel
    @State private var people: PeopleViewModel
    @State private var memories: MemoriesViewModel
    @State private var duplicates: DuplicatesViewModel
    @State private var appLock: AppLockViewModel
    @State private var selection: RootTab = .photos
    @State private var lastContentTab: RootTab = .photos
    @State private var showCreateAlbum = false
    @State private var showCreateSharedLink = false
    @State private var showProfile = false
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
        _upload = State(initialValue: container.makeUploadViewModel())
        _people = State(initialValue: container.makePeopleViewModel())
        _memories = State(initialValue: container.makeMemoriesViewModel())
        _duplicates = State(initialValue: container.makeDuplicatesViewModel())
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
            Tab("Memories", systemImage: "sparkles.rectangle.stack", value: RootTab.memories) {
                MemoriesView(vm: memories)
            }
            Tab("Albums", systemImage: "square.stack", value: RootTab.albums) {
                AlbumsView(vm: albums)
            }
            Tab("Shared", systemImage: "person.2.fill", value: RootTab.shared) {
                SharedLinksView(vm: sharedLinks)
            }
            Tab("Search", systemImage: bubbleIcon, value: RootTab.search, role: .search) {
                SearchView(vm: search, mapVM: map)
            }
        }
        .immichBottomBar()
        .environment(\.openProfile) { showProfile = true }
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
        // Me section: presented as a sheet from the stable root presenter, from
        // the avatar button that every tab's navigation bar exposes.
        .sheet(isPresented: $showProfile) {
            ProfileView(trash: trash, storage: storage, upload: upload, duplicates: duplicates, people: people)
        }
        .sheet(isPresented: Binding(
            get: { map.isPhotoSheetPresented },
            set: { map.isPhotoSheetPresented = $0 }
        )) {
            MapPhotosSheet(vm: map)
                .presentationDetents([.fraction(1.0 / 3.0), .medium])
                .presentationBackgroundInteraction(.enabled)
                .presentationBackground(.regularMaterial)
        }
    }

    private var bubbleIcon: String {
        switch selection {
        case .photos, .memories, .search: "magnifyingglass"
        case .albums, .shared: "plus"
        }
    }

    private func handleBubbleTap() {
        switch lastContentTab {
        case .photos, .memories: break // Landing on the Search tab is handled by the TabView itself.
        case .albums: showCreateAlbum = true
        case .shared: showCreateSharedLink = true
        case .search: break
        }
    }
}

/// Root-level tabs. Order defines tab order; raw value used only for matching.
private enum RootTab: Int, Hashable {
    case photos
    case memories
    case albums
    case shared
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

// MARK: - Me (profile) entry from every tab

/// Presentation action injected by RootView so every tab's avatar button can
/// raise the Me sheet from the stable TabView presenter (iOS 26 serializes
/// presentations; RootView is the only safe presenter above the tabs).
private struct OpenProfileKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openProfile: () -> Void {
        get { self[OpenProfileKey.self] }
        set { self[OpenProfileKey.self] = newValue }
    }
}

/// Circular initials avatar pinned to the trailing corner of every tab's
/// navigation bar. Tapping presents the Me section (`ProfileView`) as a sheet
/// from RootView.
struct ProfileAvatarButton: View {
    let action: () -> Void
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.immichPrimary)
                Text(UserAvatarCircle.initials(from: auth.userName ?? "?"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 30, height: 30)
            .padding(7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
    }
}
