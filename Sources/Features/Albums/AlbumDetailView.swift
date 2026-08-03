import SwiftUI

/// Album detail screen (AC-508..AC-513). Asset grid + toolbar actions:
/// share-link management + delete album. Per-asset context menu offers
/// "Remove from album" (AC-510).
struct AlbumDetailView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var vm: AlbumDetailViewModel

    @State private var presentingShare = false
    @State private var presentingDeleteConfirm = false
    @State private var pendingRemoveAssetId: String?
    @State private var lastRemoveTick = 0
    @State private var lastDeleteTick = 0
    @State private var viewerItem: PhotoViewerItem? // Full-screen photo viewer

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 3)

    init(albumId: String, client: any ImmichClient = DependencyContainer.shared.client) {
        _vm = State(initialValue: AlbumDetailViewModel(client: client, albumId: albumId))
    }

    var body: some View {
        Group {
            if vm.isDeleted {
                ContentUnavailableView("Album Deleted", systemImage: "trash")
            } else if let album = vm.album {
                content(for: album)
            } else if vm.isLoading {
                ProgressView()
            } else {
                ContentUnavailableView("Album Unavailable", systemImage: "rectangle.stack")
            }
        }
        .navigationTitle(vm.album?.albumName ?? "Album")
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
                        Button(role: .destructive) {
                            presentingDeleteConfirm = true
                        } label: {
                            Label("Delete Album", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
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
        .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .sensoryFeedback(.warning, trigger: lastDeleteTick)
        .sensoryFeedback(.success, trigger: lastRemoveTick)
        // Full-screen photo viewer (tap any photo → browse/zoom).
        // Favorite/delete run self-sufficient on the shared client; refresh
        // the album grid after a mutation so badges/rows stay in sync.
        .photoViewer(
            item: $viewerItem,
            baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
            token: auth.accessToken,
            onDataChanged: {
                Task { await vm.load() }
            }
        )
    }

    /// Opens the Photos-style viewer at `item`, paging through album order.
    private func openViewer(for item: AssetReactItem) {
        guard let idx = vm.assets.firstIndex(where: { $0.id == item.id }) else { return }
        viewerItem = PhotoViewerItem(assets: vm.assets, index: idx)
    }

    @ViewBuilder
    private func content(for album: AlbumResponseDto) -> some View {
        if vm.assets.isEmpty && !vm.isLoading {
            ContentUnavailableView(
                "No Photos",
                systemImage: "photo",
                description: Text("Add photos from the Timeline using “Add to Album”.")
            )
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 0) {
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
}
