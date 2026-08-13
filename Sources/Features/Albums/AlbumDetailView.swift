import SwiftUI

/// Identifiable wrapper for the "Shared With" sheet — `.sheet(item:)` requires
/// a non-optional item at render time, guaranteeing the sheet never presents
/// an empty body (the VM is built when the menu item is tapped).
private struct AlbumShareSheetItem: Identifiable {
    let id = UUID()
    let vm: AlbumShareViewModel
}

/// Identifiable wrapper for the Activity sheet — same pattern as the share
/// sheet so the VM is built on tap, never while the row renders.
private struct ActivityFeedSheetItem: Identifiable {
    let id = UUID()
    let vm: ActivityFeedViewModel
}

/// Album detail screen (AC-508..AC-513). A Photos-style stretchy parallax hero
/// (album cover + overlaid title/count) sits above a 3-column photo grid with a
/// "Photos" section header. Toolbar menu offers share-link management + delete;
/// per-asset context menu offers "Remove from album" (AC-510).
struct AlbumDetailView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var vm: AlbumDetailViewModel

    @State private var presentingShare = false
    @State private var shareSheetItem: AlbumShareSheetItem?
    @State private var presentingDeleteConfirm = false
    @State private var pendingRemoveAssetId: String?
    @State private var pendingRemoveSelected = false
    @State private var pendingDeleteSelected = false
    @State private var presentAlbumPicker = false // Add selected assets to another album
    @State private var activityFeedItem: ActivityFeedSheetItem?
    @State private var lastRemoveTick = 0
    @State private var lastDeleteTick = 0
    @State private var lastFavoriteTick = 0
    @State private var lastSelectionTick = 0
    @State private var viewerItem: PhotoViewerItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s2), count: 3)

    /// The album as known by the grid. Rendered immediately on the first frame
    /// (hero cover + title) so the zoom-open transition lands on real content,
    /// not a spinner; the freshly-fetched `vm.album` replaces it once loaded.
    private let initialAlbum: AlbumResponseDto

    /// True when the signed-in user owns the album. The server always lists the
    /// owner first in `albumUsers`; only owners may manage collaborators.
    private var isAlbumOwner: Bool {
        (vm.album ?? initialAlbum).albumUsers.first?.user.id == auth.userId
    }

    init(
        album: AlbumResponseDto,
        client: any ImmichClient = DependencyContainer.shared.client
    ) {
        self.initialAlbum = album
        _vm = State(initialValue: AlbumDetailViewModel(client: client, albumId: album.id))
    }

    var body: some View {
        Group {
            if vm.isDeleted {
                ContentUnavailableView("Album Deleted", systemImage: "trash")
            } else if let album = vm.album {
                content(for: album)
            } else if vm.isLoading {
                // First frame: hero renders from the grid-known DTO so the zoom
                // transition lands on real content; skeleton below while loading.
                loadingContent
            } else if vm.errorMessage != nil {
                errorState
            } else {
                ContentUnavailableView("Album Unavailable", systemImage: "rectangle.stack")
            }
        }
        .navigationTitle(vm.selectionMode ? "\(vm.selectedIds.count) selected" : (vm.album?.albumName ?? initialAlbum.albumName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vm.selectionMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        vm.exitSelectionMode()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task {
                            let target = !vm.selectedIds.allSatisfy { id in
                                vm.assets.first { $0.id == id }?.isFavorite ?? false
                            }
                            // Exit only on success (retry keeps selection) —
                            // parity with Timeline's favorite button (audit fix).
                            if await vm.batchSetFavorite(vm.selectedIds, favorite: target) {
                                vm.exitSelectionMode()
                            }
                            lastFavoriteTick &+= 1
                        }
                    } label: {
                        Label("Favorite", systemImage: "heart")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(vm.selectedIds.isEmpty)

                    Button {
                        presentAlbumPicker = true
                    } label: {
                        Label("Add to Album", systemImage: "rectangle.stack.badge.plus")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(vm.selectedIds.isEmpty)

                    Button {
                        guard vm.selectedIds.count == 1, let first = vm.selectedIds.first else { return }
                        Task {
                            // Exit only on success (retry keeps selection).
                            if await vm.setCover(assetId: first) {
                                vm.exitSelectionMode()
                            }
                        }
                    } label: {
                        Label("Set as Cover", systemImage: "photo.badge.checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(vm.selectedIds.count != 1)
                }
                // Native trailing ellipsis menu — Photos-parity bulk actions.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            pendingRemoveSelected = true
                        } label: {
                            Label {
                                Text("Remove from Album")
                                    .foregroundStyle(Color.red)
                            } icon: {
                                Image(systemName: "rectangle.stack.badge.minus")
                                    .foregroundStyle(Color.red)
                            }
                        }
                        .tint(.red)
                        .disabled(vm.selectedIds.isEmpty)

                        Button(role: .destructive) {
                            pendingDeleteSelected = true
                        } label: {
                            Label {
                                Text("Delete")
                                    .foregroundStyle(Color.red)
                            } icon: {
                                Image(systemName: "trash")
                                    .foregroundStyle(Color.red)
                            }
                        }
                        .tint(.red)
                        .disabled(vm.selectedIds.isEmpty)
                    } label: {
                        Label("Album actions", systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                    }
                    .tint(.primary)
                }
            } else if !vm.isDeleted {
                // Native trailing ellipsis menu — Apple Files parity. Bare
                // `ellipsis` glyph (3 horizontal dots, no circle), the system
                // dropdown chrome. The zoom-transition toolbar lag is avoided
                // upstream by gating `.navigationTransition(.zoom)` to iOS 27+
                // (see AlbumsView); on iOS 26 this screen uses a standard push,
                // so the bar (back chevron + title + this menu) renders as one.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            vm.enterSelectionMode()
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                                .foregroundStyle(Color.primary)
                        }
                        .tint(Color.primary)
                        Divider()
                        Button {
                            presentingShare = true
                        } label: {
                            Label("Shared Links", systemImage: "square.and.arrow.up")
                                .foregroundStyle(Color.primary)
                        }
                        .tint(Color.primary)
                        Button {
                            activityFeedItem = ActivityFeedSheetItem(
                                vm: ActivityFeedViewModel(
                                    client: DependencyContainer.shared.client,
                                    albumId: vm.albumId,
                                    currentUserId: auth.userId ?? ""
                                )
                            )
                        } label: {
                            Label("Activity", systemImage: "bubble.left.and.bubble.right")
                                .foregroundStyle(Color.primary)
                        }
                        .tint(Color.primary)
                        Divider()
                        // "Shared With" is owner-only: the server puts the
                        // album owner first in `albumUsers`, and only owners
                        // may manage collaborators (403 otherwise).
                        if isAlbumOwner {
                            Button {
                                shareSheetItem = AlbumShareSheetItem(
                                    vm: vm.makeShareViewModel(
                                        currentUserId: auth.userId ?? "",
                                        isAdmin: auth.isAdmin
                                    )
                                )
                            } label: {
                                Label("Shared With", systemImage: "person.2")
                                    .foregroundStyle(Color.primary)
                            }
                            .tint(Color.primary)
                        }
                        Divider()
                        // Forced red: the menu-level `.tint(.primary)` below can
                        // override the destructive role on iOS 26, so the icon
                        // AND the title carry their own explicit red style.
                        Button(role: .destructive) {
                            presentingDeleteConfirm = true
                        } label: {
                            Label {
                                Text("Delete Album")
                                    .foregroundStyle(Color.red)
                            } icon: {
                                Image(systemName: "trash")
                                    .foregroundStyle(Color.red)
                            }
                        }
                        .tint(Color.red)
                    } label: {
                        Label("Album actions", systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                    }
                    .tint(.primary)
                }
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $presentingShare) {
            SharedLinkSheet(vm: vm, baseURL: auth.baseURL ?? URL(string: "https://example.com")!)
        }
        .sheet(item: $shareSheetItem, onDismiss: {
            Task { await vm.refreshAlbum() }
        }) { item in
            AlbumShareSheet(vm: item.vm)
        }
        .sheet(item: $activityFeedItem) { item in
            ActivityFeedSheet(vm: item.vm)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete this album? The photos themselves are not deleted.",
            isPresented: $presentingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Album", role: .destructive) {
                Task {
                    await vm.deleteAlbum()
                    if vm.isDeleted { lastDeleteTick &+= 1 }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil && vm.album != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .alert("Delete \(vm.selectedIds.count) asset(s)?", isPresented: $pendingDeleteSelected) {
            Button("Delete", role: .destructive) {
                Task {
                    await vm.deleteSelected()
                    lastDeleteTick &+= 1
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes them from your library. Action cannot be undone.")
        }
        .alert(
            "Remove \(vm.selectedIds.count) photo\(vm.selectedIds.count == 1 ? "" : "s") from this album?",
            isPresented: $pendingRemoveSelected
        ) {
            Button("Remove", role: .destructive) {
                Task {
                    await vm.removeSelected()
                    lastRemoveTick &+= 1
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes them from the album. The photos stay in your library.")
        }
        .sheet(isPresented: $presentAlbumPicker) {
            AddToAlbumPickerSheet(selectedAssetIds: vm.selectedIds) {
                vm.exitSelectionMode()
            }
        }
        .sensoryFeedback(.warning, trigger: lastDeleteTick)
        .sensoryFeedback(.success, trigger: lastRemoveTick)
        .sensoryFeedback(.success, trigger: vm.album?.albumThumbnailAssetId)
        .sensoryFeedback(.selection, trigger: vm.selectionMode)
        .sensoryFeedback(.selection, trigger: lastSelectionTick)
        .photoViewer(
            item: $viewerItem,
            baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
            token: auth.accessToken,
            onDataChanged: {
                Task { await vm.load() }
            }
        )
    }

    private var errorState: some View {
        ContentUnavailableView {
            Label("Couldn't load album", systemImage: "wifi.exclamationmark")
        } description: {
            Text(vm.errorMessage ?? "")
        } actions: {
            Button("Try Again") { Task { await vm.load() } }
                .buttonStyle(PVPrimaryButtonStyle())
        }
    }

    /// Opens the Photos-style viewer at `item`, paging through album order.
    private func openViewer(for item: AssetReactItem) {
        guard let idx = vm.assets.firstIndex(where: { $0.id == item.id }) else { return }
        viewerItem = PhotoViewerItem(assets: vm.assets, index: idx)
    }

    // MARK: - Cell container — navigation vs selection-aware tap

    @ViewBuilder
    private func cellView(for item: AssetReactItem) -> some View {
        let cell = AssetThumbnailCell(
            asset: item,
            baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
            token: auth.accessToken,
            selectionMode: vm.selectionMode,
            isSelected: vm.selectedIds.contains(item.id),
            onTap: {
                if vm.selectionMode {
                    vm.toggleSelection(id: item.id)
                    lastSelectionTick &+= 1
                } else {
                    openViewer(for: item)
                }
            }
        )
        .buttonStyle(.plain)

        if vm.selectionMode {
            // Context menu suppressed in selection mode: long-press must toggle,
            // and "Remove" mid-selection would corrupt the selection set
            // (audit fix — stale selectedIds after removeAssets).
            cell
                .onLongPressGesture(minimumDuration: 0.4) {
                    vm.toggleSelection(id: item.id)
                    lastSelectionTick &+= 1
                }
        } else {
            cell
                .contextMenu {
                    Button {
                        Task { await vm.setCover(assetId: item.id) }
                    } label: {
                        Label("Set as Cover", systemImage: "photo.badge.checkmark")
                    }
                    Button(role: .destructive) {
                        pendingRemoveAssetId = item.id
                    } label: {
                        Label("Remove from Album", systemImage: "rectangle.stack.badge.minus")
                    }
                }
                .onLongPressGesture(minimumDuration: 0.4) {
                    vm.enterSelectionMode()
                    vm.toggleSelection(id: item.id)
                    lastSelectionTick &+= 1
                }
        }
    }

    private var coverAssetId: String? {
        (vm.album ?? initialAlbum).albumThumbnailAssetId ?? vm.assets.first?.id
    }

    /// First-frame layout: hero from the grid-known album + skeleton grid, so
    /// the zoom-open lands on the real hero and the layout does not jump when
    /// the network resolves.
    @ViewBuilder
    private var loadingContent: some View {
        ScrollView {
            heroHeader(for: initialAlbum)

            HStack {
                Text("Photos")
                    .font(.pvCaption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.textSecondaryPV)
                Spacer()
            }
            .padding(.horizontal, PVSpacing.s4)
            .padding(.top, PVSpacing.s8)
            .padding(.bottom, PVSpacing.s2)

            PVSkeletonGrid(rows: 4, columnCount: 3)
                .padding(.horizontal, PVSpacing.s4)
        }
    }

    @ViewBuilder
    private func content(for album: AlbumResponseDto) -> some View {
        if vm.assets.isEmpty && !vm.isLoading {
            ScrollView {
                heroHeader(for: album)
                ContentUnavailableView(
                    "No Photos",
                    systemImage: "photo",
                    description: Text("Add photos from the Timeline using “Add to Album”.")
                )
                .padding(.top, PVSpacing.s24)
            }
        } else {
            ScrollView {
                heroHeader(for: album)

                // "Photos" section header — Apple Photos style.
                HStack {
                    Text("Photos")
                        .font(.pvCaption)
                        .fontWeight(.semibold)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.textSecondaryPV)
                    Spacer()
                }
                .padding(.horizontal, PVSpacing.s4)
                .padding(.top, PVSpacing.s8)
                .padding(.bottom, PVSpacing.s2)

                LazyVStack(alignment: .leading, spacing: PVSpacing.s2) {
                    LazyVGrid(columns: columns, spacing: PVSpacing.s2) {
                        ForEach(vm.assets, id: \.id) { item in
                            cellView(for: item)
                        }
                    }
                    .padding(.horizontal, PVSpacing.s4)
                }
            }
            // D6: tap on empty grid area exits selection mode. Cell taps win
            // via their own onTapGesture (hit-tested first).
            .onTapGesture {
                if vm.selectionMode { vm.exitSelectionMode() }
            }
            .animation(PVMotion.standard, value: vm.selectionMode)
            .alert(
                "Remove this photo from the album?",
                isPresented: Binding(
                    get: { pendingRemoveAssetId != nil },
                    set: { if !$0 { pendingRemoveAssetId = nil } }
                )
            ) {
                Button("Remove", role: .destructive) {
                    if let id = pendingRemoveAssetId {
                        Task {
                            await vm.removeAssets(ids: [id])
                            pendingRemoveAssetId = nil
                            lastRemoveTick &+= 1
                        }
                    }
                }
                Button("Cancel", role: .cancel) { pendingRemoveAssetId = nil }
            } message: {
                Text("The photo stays in your library.")
            }
        }
    }

    /// Stretchy parallax hero: the album cover scales up when over-scrolled at
    /// the top, with the title + count overlaid on a legibility gradient. Pairs
    /// with `AlbumsView`'s matched source for the zoom-morph open/close.
    @ViewBuilder
    private func heroHeader(for album: AlbumResponseDto) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    if let coverId = coverAssetId {
                        AuthenticatedAsyncImage(
                            url: ImmichAssetURL.thumbnail(assetId: coverId, thumbhash: "", baseURL: auth.baseURL ?? URL(string: "https://example.com")!),
                            token: auth.accessToken
                        )
                    } else {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.textSecondaryPV)
                    }
                }
                .scrollTransition { content, phase in
                    // Stretchy-header: scale up beyond bounds when pulled down.
                    content
                        .scaleEffect(phase.isIdentity ? 1 : 1.35, anchor: .top)
                        .opacity(phase.isIdentity ? 1 : 0.92)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .allowsHitTesting(false)
                }
                .clipped()

            VStack(alignment: .leading, spacing: PVSpacing.s2) {
                Text(album.albumName)
                    .font(.pvTitle)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.4), radius: 4)
                // While loading, the grid-known count is authoritative; once
                // loaded the fetched asset list wins (matches grid contents).
                Text("\(vm.album == nil ? album.assetCount : vm.assets.count) Photos")
                    .font(.pvSubhead)
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.4), radius: 3)
                collaboratorAvatars(for: album)
            }
            .padding(PVSpacing.s16)
        }
    }

    /// Photos-style overlapping avatar stack of the album's collaborators
    /// (self excluded), with a "+N" overflow badge. Nothing when not shared.
    @ViewBuilder
    private func collaboratorAvatars(for album: AlbumResponseDto) -> some View {
        let others = album.albumUsers.filter { $0.user.id != auth.userId }
        if !others.isEmpty {
            HStack(spacing: -PVSpacing.s8) {
                ForEach(others.prefix(4), id: \.user.id) { entry in
                    UserAvatarCircle(user: entry.user, size: 24)
                        .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                }
                if others.count > 4 {
                    Text("+\(others.count - 4)")
                        .font(.pvCaption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.black.opacity(0.45), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 3)
        }
    }
}
