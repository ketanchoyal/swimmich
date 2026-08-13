import SwiftUI

/// Tag management screen (gap #2): list server tags, create new ones, delete
/// with swipe. Pushed from the Me section (ProfileView) — TrashView pattern
/// (no own NavigationStack).
struct TagsView: View {
    @Bindable var vm: TagsViewModel

    @State private var newTagName = ""
    @State private var showCreate = false

    var body: some View {
        Group {
            if vm.isLoading && vm.tags.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.tags.isEmpty {
                ContentUnavailableView(
                    "No tags yet",
                    systemImage: "tag",
                    description: Text("Create tags to organize your photos.")
                )
            } else {
                List {
                    ForEach(vm.tags, id: \.id) { tag in
                        HStack(spacing: PVSpacing.s12) {
                            Image(systemName: "tag.fill")
                                .font(.pvBody)
                                .foregroundStyle((tag.color.flatMap { Color(hex: $0) }) ?? Color.immichPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tag.name)
                                    .font(.pvBody)
                                    .foregroundStyle(Color.textPrimaryPV)
                                if let value = tag.value, value != tag.name {
                                    Text(value)
                                        .font(.pvCaption)
                                        .foregroundStyle(Color.textSecondaryPV)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            Task { await vm.delete(vm.tags[index]) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newTagName = ""
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create tag")
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load(force: true) }
        .alert("New Tag", isPresented: $showCreate) {
            TextField("Tag name", text: $newTagName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                Task { await vm.create(name: newTagName) }
            }
        } message: {
            Text("Tags help you group and search photos.")
        }
    }
}
