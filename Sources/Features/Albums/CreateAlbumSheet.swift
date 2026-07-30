import SwiftUI

/// Form sheet for creating a new album (AC-507).
/// Optionally receives preselected assetIds when launched from the Timeline
/// "Add to Album" picker (allows "New Album with these photos").
struct CreateAlbumSheet: View {
    @Bindable var vm: AlbumsViewModel
    let preselectedAssetIds: [String]?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var createTick = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Album") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let ids = preselectedAssetIds, !ids.isEmpty {
                    Section {
                        Label("\(ids.count) photo\(ids.count == 1 ? "" : "s") selected", systemImage: "photo.on.rectangle")
                    }
                }
            }
            .navigationTitle("New Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await vm.createAlbum(
                                name: name,
                                description: description.isEmpty ? nil : description,
                                assetIds: preselectedAssetIds
                            )
                            if vm.errorMessage == nil {
                                createTick &+= 1
                                dismiss()
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isCreating)
                }
            }
        }
        .sensoryFeedback(.success, trigger: createTick)
    }
}
