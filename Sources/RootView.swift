import SwiftUI

/// Auth-gated root router. Shows login flow until authenticated, then timeline.
/// When app lock is enabled + locked, overlays a LockView (AC-104/AC-105).
///
/// The authenticated tab tree is owned by `AuthenticatedRoot`, keyed on
/// `auth.activeAccountID` — switching accounts tears the whole subtree down and
/// recreates every view model, so no stale data/cache survives a switch.
struct RootView: View {
    @State private var auth: AuthViewModel
    @State private var appLock: AppLockViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let container: DependencyContainer

    init(container: DependencyContainer = .shared) {
        self.container = container
        let authVM = container.makeAuthViewModel()
        _auth = State(initialValue: authVM)
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
                    AuthenticatedRoot(container: container)
                        .id(auth.activeAccountID)
                } else {
                    OnboardingFlowView()
                }
            }
            .environment(auth)
            .environment(appLock)
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

/// 5-tab authenticated root (Photos/Memories/Albums/Shared) + a native iOS 26
/// search tab (`role: .search`) rendered as a floating Liquid Glass bubble
/// pinned to the tab bar's trailing edge, perfectly aligned by the system.
///
/// Owns every tab view model so the parent can recreate the whole subtree on
/// account switch (`.id(activeAccountID)`) — fresh VMs = fresh loads.
///
/// From Photos the bubble lands on the real Search tab (a plain tab, so a
/// `.sheet` can be presented safely on top of it — the search full-screen
/// cover was removed because SwiftUI serializes presentations from the same
/// presenter, which made a sheet above it impossible, and a sheet inside the
/// cover crashed on teardown). From Albums/Shared/Me the bubble keeps its
/// contextual action (create / placeholder / logout) and the selection snaps
/// back. The bubble icon mirrors the active tab.
private struct AuthenticatedRoot: View {
    @Environment(AuthViewModel.self) private var auth

    /// Kept (not only consumed in `init`) so a screen can build a view model at
    /// presentation time — the shared-link viewer needs the connected server,
    /// which the eager `make*` calls in `init` do not yet know.
    private let container: DependencyContainer

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
    @State private var tags: TagsViewModel
    @State private var stacks: StacksViewModel
    @State private var partners: PartnersViewModel
    @State private var admin: AdminViewModel
    @State private var selection: RootTab = .photos
    @State private var lastContentTab: RootTab = .photos
    @State private var pendingTimelineScrollID: String?
    @State private var pendingTimelineScrollDay: String?
    @State private var showCreateAlbum = false
    @State private var showCreateSharedLink = false
    @State private var showProfile = false

    init(container: DependencyContainer) {
        self.container = container
        _timeline = State(initialValue: container.makeTimelineViewModel())
        _trash = State(initialValue: container.makeTrashViewModel())
        _search = State(initialValue: container.makeSearchViewModel())
        _map = State(initialValue: container.makeMapViewModel())
        _albums = State(initialValue: container.makeAlbumsViewModel())
        _sharedLinks = State(initialValue: container.makeSharedLinksViewModel())
        _storage = State(initialValue: container.makeStorageStatsViewModel())
        _upload = State(initialValue: container.upload)
        _people = State(initialValue: container.makePeopleViewModel())
        _memories = State(initialValue: container.makeMemoriesViewModel())
        _duplicates = State(initialValue: container.makeDuplicatesViewModel())
        _tags = State(initialValue: container.makeTagsViewModel())
        _stacks = State(initialValue: container.makeStacksViewModel())
        _partners = State(initialValue: container.makePartnersViewModel())
        _admin = State(initialValue: container.makeAdminViewModel())
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Photos", systemImage: "photo.on.rectangle.angled", value: RootTab.photos) {
                TimelineView(vm: timeline, stacks: stacks, scrollTargetID: $pendingTimelineScrollID, scrollTargetDay: $pendingTimelineScrollDay)
            }
            Tab("Memories", systemImage: "sparkles.rectangle.stack", value: RootTab.memories) {
                MemoriesView(vm: memories)
            }
            Tab("Albums", systemImage: "square.stack", value: RootTab.albums) {
                AlbumsView(vm: albums)
            }
            Tab("Shared", systemImage: "person.2.fill", value: RootTab.shared) {
                SharedLinksView(vm: sharedLinks) { baseURL, externalDomain in
                    container.makeSharedLinkViewerViewModel(
                        baseURL: baseURL,
                        externalDomain: externalDomain
                    )
                }
            }
            Tab("Search", systemImage: bubbleIcon, value: RootTab.search, role: .search) {
                SearchView(vm: search, mapVM: map)
            }
        }
        .immichBottomBar()
        .environment(upload)
        .environment(\.openProfile) { showProfile = true }
        .environment(\.openInTimeline) { assetID, day in
            pendingTimelineScrollID = assetID
            pendingTimelineScrollDay = day
            selection = .photos
        }
        .environment(albums)
        .onReceive(NotificationCenter.default.publisher(for: .immichAssetsChanged)) { _ in
            Task {
                await timeline.refresh()
                await albums.refresh()
                await people.load(force: true)
                await memories.load()
            }
        }
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
                // it (stable presenter — AuthenticatedRoot — so no teardown trap).
                map.isPhotoSheetPresented = false
            }
        }
        .sheet(isPresented: $showCreateAlbum) {
            CreateAlbumSheet(vm: albums, preselectedAssetIds: nil)
        }
        .sheet(isPresented: $showCreateSharedLink) {
            CreateSharedLinkSheet(vm: sharedLinks)
        }
        // Native map photo sheet, owned by AuthenticatedRoot (never deallocated
        // while the tab tree lives): the only presentation active while browsing
        // the map tab, so SwiftUI presents it directly above the tab — detents,
        // swipe-down and the system corner radius for free.
        // Me section: presented as a sheet from the stable root presenter, from
        // the avatar button that every tab's navigation bar exposes.
        .sheet(isPresented: $showProfile) {
            ProfileView(trash: trash, storage: storage, upload: upload, duplicates: duplicates, people: people, tags: tags, stacks: stacks, partners: partners, admin: admin)
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

/// Presentation action injected by AuthenticatedRoot so every tab's avatar
/// button can raise the Me sheet from the stable TabView presenter (iOS 26
/// serializes presentations; the root presenter is the only safe one above
/// the tabs).
private struct OpenProfileKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openProfile: () -> Void {
        get { self[OpenProfileKey.self] }
        set { self[OpenProfileKey.self] = newValue }
    }
}

/// Presentation action injected by AuthenticatedRoot so any surface (e.g. a
/// memory's "view in timeline" button) can jump to the Photos tab and scroll
/// the timeline to a specific asset (id + day).
private struct OpenInTimelineKey: EnvironmentKey {
    static let defaultValue: (String, String) -> Void = { _, _ in }
}

extension EnvironmentValues {
    var openInTimeline: (String, String) -> Void {
        get { self[OpenInTimelineKey.self] }
        set { self[OpenInTimelineKey.self] = newValue }
    }
}

/// Circular initials avatar pinned to the trailing corner of every tab's
/// navigation bar. Tapping presents the Me section (`ProfileView`) as a sheet
/// from AuthenticatedRoot.
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
