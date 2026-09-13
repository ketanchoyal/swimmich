import SwiftUI

/// Extends an existing stack with more photos.
///
/// There is no "add asset to stack" route on the server, so this sheet feeds
/// `StacksViewModel.addPhotos`, which re-posts `POST /api/stacks` with the
/// stack's current cover first — the server's documented merge path. The stack
/// therefore comes back with a **new id**, which the host view adopts through
/// `onExtended`.
struct AddToStackSheet: View {
    /// Stack being extended.
    let stackId: String
    /// Its current cover — leads the payload so the stack keeps it.
    let primaryAssetId: String
    /// Members to leave out of the grid.
    let existingAssetIds: Set<String>

    @Bindable var vm: StacksViewModel
    /// Called with the stack's new id once the server answers.
    var onExtended: (String) -> Void

    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            StackPhotoPicker(
                vm: vm,
                baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
                token: auth.accessToken,
                excluding: existingAssetIds
            )
            .navigationTitle("Add to Stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await add() }
                    }
                    .disabled(vm.selectedIds.isEmpty)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("confirmAddToStack")
                }
            }
        }
        .task { await vm.beginPicking() }
    }

    /// Only dismisses on success: a failure has to stay on screen, with its
    /// message and the user's selection intact.
    private func add() async {
        let newID = await vm.addPhotos(
            toStackId: stackId,
            primaryAssetId: primaryAssetId,
            assetIds: vm.orderedSelection
        )
        guard let newID else { return }
        onExtended(newID)
        dismiss()
    }
}
