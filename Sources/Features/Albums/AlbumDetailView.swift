import SwiftUI

/// Album detail screen (AC-508..AC-513). A Photos-style stretchy parallax hero
/// (album cover + overlaid title/count) sits above a 3-column photo grid with a
/// "Photos" section header. Toolbar menu offers share-link management + delete;
/// per-asset context menu offers "Remove from album" (AC-510).
///
/// Opens with an iOS 26 zoom-morph transition paired with `AlbumsView`'s
/// `.matchedTransitionSource` via the shared `namespace` + `sourceID`.
struct AlbumDetailView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var vm: AlbumDetailViewModel

    @State private var presentingShare = false
    @State private var presentingDeleteConfirm = false
    @State private var pendingRemoveAssetId: String?
    @State private var lastRemoveTick = 0
    @State private var lastDeleteTick = 0
    @State private var viewerItem: PhotoViewerItem?

    private let namespace: Namespace.ID
    private let sourceID: String
    private let columns = Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s2), count: 3)

    init(
        albumId: String,
        albumName: String,
        client: any ImmichClient = DependencyContainer.shared.client,
        namespace: Namespace.ID,
        sourceID: String
    ) {
        _vm = State(initialValue: AlbumDetailViewModel(client: client, albumId: albumId))
        self.namespace = namespace
        self.sourceID = sourceID
        // Use the known name immediately so the title is correct on first frame,
        // before the network resolves — no "Album" flash.
        _initialTitle = State(initialValue: albumName)
    }

    @State private var initialTitle: String

    var body: some View {
        Group {
            if vm.isDeleted {
                ContentUnavailableView("Album Deleted", systemImage: "trash")
            } else if let album = vm.album {
                content(for: album)
            } else if vm.isLoading {
                ProgressView()
            } else if vm.errorMessage != nil {
                errorState
            } else {
                ContentUnavailableView("Album Unavailable", systemImage: "rectangle.stack")
            }
        }
        .navigationTitle(vm.album?.albumName ?? initialTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vm.album != nil && !vm.isDeleted {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            presentingShare = true
                        } label: {
                            Label("Shared Links", systemImage: "square.and.arrow.up")
                        }
                        .tint(.primary)
                        Button(role: .destructive) {
                            presentingDeleteConfirm = true
                        } label: {
                            Label("Delete Album", systemImage: "trash")
                        }
                        .tint(.red)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Color.primary)
                    }
                }
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $presentingShare) {
            SharedLinkSheet(vm: vm, baseURL: auth.baseURL ?? URL(string: "https://example.com")!)
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
        .sensoryFeedback(.warning, trigger: lastDeleteTick)
        .sensoryFeedback(.success, trigger: lastRemoveTick)
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

    private var coverAssetId: String? {
        vm.album?.albumThumbnailAssetId ?? vm.assets.first?.id
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
                            AssetThumbnailCell(
                                asset: item,
                                baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
                                token: auth.accessToken,
                                onTap: { openViewer(for: item) }
                            )
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    pendingRemoveAssetId = item.id
                                } label: {
                                    Label("Remove from Album", systemImage: "rectangle.stack.badge.minus")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, PVSpacing.s4)
                }
                .navigationTransition(.zoom(sourceID: sourceID, in: namespace))
            }
            .confirmationDialog(
                "Remove this photo from the album?",
                isPresented: Binding(
                    get: { pendingRemoveAssetId != nil },
                    set: { if !$0 { pendingRemoveAssetId = nil } }
                ),
                titleVisibility: .visible
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
                Text("\(vm.assets.count) Photos")
                    .font(.pvSubhead)
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.4), radius: 3)
            }
            .padding(PVSpacing.s16)
        }
    }
}
