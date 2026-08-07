import SwiftUI

/// Picker sheet launched from Timeline selection toolbar (AC-515, AC-520).
/// Lists existing albums (shared AlbumsViewModel via @Environment) + a
/// "New Album" action that creates one with the selected assets pre-populated.
struct AddToAlbumPickerSheet: View {
    let selectedAssetIds: Set<String>
    var onCompleted: () -> Void = {}

    @Environment(AlbumsViewModel.self) private var albumsVM
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var presentingCreate = false
    @State private var addedAlbumId: String?
    @State private var lastAddTick = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Selected") {
                    Label("\(selectedAssetIds.count) photo\(selectedAssetIds.count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.textSecondaryPV)
                }
                Section("Albums") {
                    if albumsVM.albums.isEmpty {
                        Text("No albums yet")
                            .foregroundStyle(Color.textSecondaryPV)
                    }
                    ForEach(albumsVM.albums, id: \.id) { album in
                        Button {
                            Task { await add(to: album.id) }
                        } label: {
                            HStack {
                                if addedAlbumId == album.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.immichSuccess)
                                }
                                VStack(alignment: .leading) {
                                    Text(album.albumName).foregroundStyle(Color.textPrimaryPV)
                                    Text("\(album.assetCount) item\(album.assetCount == 1 ? "" : "s")")
                                        .font(.pvCaption)
                                        .foregroundStyle(Color.textSecondaryPV)
                                }
                                Spacer()
                            }
                        }
                        .disabled(albumsVM.isLoading)
                    }
                }
            }
            .navigationTitle("Add to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("New Album") { presentingCreate = true }
                }
            }
            .task { await albumsVM.load() }
            .refreshable { await albumsVM.refresh() }
            .sheet(isPresented: $presentingCreate) {
                CreateAlbumSheet(vm: albumsVM, preselectedAssetIds: Array(selectedAssetIds))
            }
            .sensoryFeedback(.success, trigger: lastAddTick)
        }
    }

    private func add(to albumId: String) async {
        await albumsVM.addAssets(ids: Array(selectedAssetIds), toAlbumId: albumId)
        if albumsVM.errorMessage == nil {
            addedAlbumId = albumId
            lastAddTick &+= 1
            // Refresh the shared list so the count badge updates.
            await albumsVM.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                dismiss()
                onCompleted()
            }
        }
    }
}
