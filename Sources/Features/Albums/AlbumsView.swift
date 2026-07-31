import SwiftUI

/// Albums tab (AC-514). Grid of album cards; tap → AlbumDetailView.
/// Toolbar + button presents CreateAlbumSheet.
///
/// `AlbumsViewModel` is injected via `@Environment` from RootView so the
/// Timeline "Add to Album" picker shares the same instance (FM-3 mitigation).
struct AlbumsView: View {
    @Bindable var vm: AlbumsViewModel
    @Environment(AuthViewModel.self) private var auth
    @State private var presentingCreate = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s4), count: 2)

    var body: some View {
        NavigationStack {
            Group {
                if vm.albums.isEmpty && !vm.isLoading {
                    ContentUnavailableView(
                        "No Albums Yet",
                        systemImage: "rectangle.stack",
                        description: Text("Create an album to organize your photos.")
                    )
                } else {
                    albumGrid
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ImmichAppBar()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(vm.isCreating)
                }
            }
            .overlay {
                if vm.isLoading && vm.albums.isEmpty {
                    ProgressView()
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .sheet(isPresented: $presentingCreate) {
                CreateAlbumSheet(vm: vm, preselectedAssetIds: nil)
            }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    private var albumGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: PVSpacing.s4) {
                ForEach(vm.albums, id: \.id) { album in
                    NavigationLink {
                        AlbumDetailView(albumId: album.id)
                    } label: {
                        AlbumCard(album: album, baseURL: auth.baseURL ?? URL(string: "https://example.com")!, token: auth.accessToken)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, PVSpacing.s4)
        }
    }
}

/// Square cover card for an album (corner radius 0 — project convention).
private struct AlbumCard: View {
    let album: AlbumResponseDto
    let baseURL: URL
    let token: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PVSpacing.s8) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let thumbId = album.albumThumbnailAssetId {
                        let url = ImmichAssetURL.thumbnail(assetId: thumbId, thumbhash: "", baseURL: baseURL)
                        AuthenticatedAsyncImage(url: url, token: token)
                    } else {
                        Image(systemName: "rectangle.stack")
                            .font(.pvTitleXL)
                            .foregroundStyle(Color.textSecondaryPV)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: PVRadius.none, style: .continuous))

            Text(album.albumName)
                .font(.pvSubhead)
                .lineLimit(1)
            Text("\(album.assetCount) item\(album.assetCount == 1 ? "" : "s")")
                .font(.pvCaption)
                .foregroundStyle(Color.textSecondaryPV)
        }
    }
}
