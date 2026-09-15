import ImmichSharedKit
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
    /// Interface language (issue #21). The store is owned by the container, so
    /// the picker in the Me sheet writes exactly what this reads.
    @State private var language: AppLanguageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let container: DependencyContainer

    init(container: DependencyContainer = .shared) {
        self.container = container
        let authVM = container.makeAuthViewModel()
        _auth = State(initialValue: authVM)
        _appLock = State(initialValue: container.appLock)
        _language = State(initialValue: container.language)
    }

    private var isGated: Bool { appLock.isEnabled && appLock.isLocked }

    var body: some View {
        ZStack {
            Group {
                if auth.isRestoringSession {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if auth.isAuthenticated {
                    AuthenticatedRoot(container: container, session: auth)
                        .id(auth.activeAccountID)
                } else {
                    OnboardingFlowView()
                }
            }
            .environment(auth)
            .environment(appLock)
            .environment(language)
            // Every `Text("…")` literal below resolves its key through this
            // locale, so the language picker retranslates the view tree as soon
            // as it is touched. Strings built outside a render (view models,
            // notifications, widgets) go through `Bundle` instead and only
            // follow on the next launch — `AppLanguageStore` writes
            // `AppleLanguages` for exactly that.
            .environment(\.locale, language.effectiveLocale)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    @State private var uploadDetail: UploadDetailViewModel
    @State private var people: PeopleViewModel
    @State private var memories: MemoriesViewModel
    @State private var duplicates: DuplicatesViewModel
    @State private var tags: TagsViewModel
    @State private var stacks: StacksViewModel
    @State private var partners: PartnersViewModel
    @State private var admin: AdminViewModel
    @State private var offline: OfflineDownloadViewModel
    @State private var syncStatus: SyncStatusViewModel
    @State private var localLibrary: LocalLibraryViewModel
    @State private var notifications: NotificationsViewModel
    @State private var language: LanguageSettingsViewModel
    @State private var freeUpSpace: FreeUpSpaceViewModel
    /// Profile picture screen (gap G16). Owned here so the account row of the Me
    /// hub and the screen it pushes project the same photo.
    @State private var profilePicture: ProfilePictureViewModel
    /// Process-wide download queue (gap G10). Held here so the panel, the
    /// info screen and the viewer's "Download to Files" all project ONE queue
    /// — the container's instance, never a per-view one.
    @State private var downloads: DownloadQueueViewModel
    @State private var selection: RootTab = .photos
    @State private var lastContentTab: RootTab = .photos
    @State private var pendingTimelineScrollID: String?
    @State private var pendingTimelineScrollDay: String?
    @State private var showCreateAlbum = false
    @State private var showCreateSharedLink = false
    @State private var showProfile = false
    @State private var showDownloadInfo = false

    init(container: DependencyContainer, session: AuthViewModel) {
        self.container = container
        _timeline = State(initialValue: container.makeTimelineViewModel())
        _trash = State(initialValue: container.makeTrashViewModel())
        _search = State(initialValue: container.makeSearchViewModel())
        _map = State(initialValue: container.makeMapViewModel())
        _albums = State(initialValue: container.makeAlbumsViewModel())
        _sharedLinks = State(initialValue: container.makeSharedLinksViewModel())
        _storage = State(initialValue: container.makeStorageStatsViewModel())
        _upload = State(initialValue: container.upload)
        _uploadDetail = State(initialValue: container.makeUploadDetailViewModel(upload: container.upload))
        _people = State(initialValue: container.makePeopleViewModel())
        _memories = State(initialValue: container.makeMemoriesViewModel())
        _duplicates = State(initialValue: container.makeDuplicatesViewModel())
        _tags = State(initialValue: container.makeTagsViewModel())
        _stacks = State(initialValue: container.makeStacksViewModel())
        _partners = State(initialValue: container.makePartnersViewModel())
        _admin = State(initialValue: container.makeAdminViewModel())
        _offline = State(initialValue: container.makeOfflineDownloadViewModel())
        _syncStatus = State(initialValue: container.makeSyncStatusViewModel(
            upload: container.upload,
            offline: container.makeOfflineDownloadViewModel()
        ))
        _localLibrary = State(initialValue: container.makeLocalLibraryViewModel())
        _notifications = State(initialValue: container.makeNotificationsViewModel())
        _language = State(initialValue: container.makeLanguageSettingsViewModel())
        _freeUpSpace = State(initialValue: container.makeFreeUpSpaceViewModel())
        _profilePicture = State(initialValue: container.makeProfilePictureViewModel(
            baseURL: session.baseURL,
            token: session.accessToken
        ))
        _downloads = State(initialValue: container.makeDownloadQueueViewModel())
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Photos", systemImage: "photo.on.rectangle.angled", value: RootTab.photos) {
                TimelineView(vm: timeline, stacks: stacks, downloads: downloads, scrollTargetID: $pendingTimelineScrollID, scrollTargetDay: $pendingTimelineScrollDay)
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
        // Offline cache (issue #18): the mirror reaches every grid cell, the VM
        // reaches the viewer's share sheet. Injected here because the whole
        // authenticated tree must share one cache.
        .environment(container.offlineIndex)
        // Backup-state mirror (G6): same injection, same reason — every tile in
        // every grid reads the one index the ledger feeds.
        .environment(container.cloudStatus)
        .environment(offline)
        .onReceive(NotificationCenter.default.publisher(for: .immichAssetsChanged)) { _ in
            Task {
                await timeline.refresh()
                await albums.refresh()
                await people.load(force: true)
                await memories.load()
                await offline.load()
            }
        }
        // Widget deep links (issue #19), parsed by the shared framework so the
        // widget extension and this router cannot drift: an asset lands on the
        // Photos tab with the timeline primed to its bucket + day (a not-yet-
        // loaded asset still resolves), memories lands on the Memories tab, and
        // backup lands on Photos while kicking the gated engine. Anything else
        // (the OAuth callback included) is not ours — no state changes.
        .onOpenURL { url in
            switch WidgetDeepLink.parse(url) {
            case let .asset(id, day):
                pendingTimelineScrollID = id
                pendingTimelineScrollDay = day
                selection = .photos
            case .memories:
                selection = .memories
            case .backup:
                selection = .photos
                container.kickOffAutoBackup()
            case nil:
                break
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
        // Download queue (gap G10): the capsule rides above the tab bar from
        // every tab and stays up while a transfer runs — that is the point of
        // the feature. Declared before the sheets below so the detail screen
        // presents over it, on the same pattern as the neighboring `@State`
        // flows; the root view is already where this app overlays global state
        // (`LockView`).
        .overlay(alignment: .bottom) {
            Group {
                if downloads.isPanelVisible {
                    DownloadProgressPanel(vm: downloads) { showDownloadInfo = true }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(PVMotion.adaptive(PVMotion.standard, reduceMotion: reduceMotion), value: downloads.isPanelVisible)
        }
        // The stack is the sheet's, not the screen's: `DownloadInfoView`
        // declares none, so there is exactly one navigation bar.
        .sheet(isPresented: $showDownloadInfo) {
            NavigationStack { DownloadInfoView(vm: downloads) }
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
            ProfileView(trash: trash, storage: storage, upload: upload, uploadDetail: uploadDetail, duplicates: duplicates, people: people, tags: tags, stacks: stacks, partners: partners, admin: admin, offline: offline, syncStatus: syncStatus, notifications: notifications, language: language, localLibrary: localLibrary, freeUpSpace: freeUpSpace, profilePicture: profilePicture)
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
        // The label is translated, so the UI tests reach for the identifier
        // instead of a string that changes with the language.
        .accessibilityIdentifier("profileAvatar")
    }
}
