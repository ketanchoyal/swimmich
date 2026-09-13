import SwiftUI

/// Creates a stack from a multi-selection of the newest photos. A stack is
/// just an ordered id list server-side (`StackCreateDto { assetIds }`, min 2,
/// first id becomes the cover) — there is no stack name to collect, so this
/// sheet is only the picker plus a CTA.
struct CreateStackSheet: View {
    @Bindable var vm: StacksViewModel
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            StackPhotoPicker(
                vm: vm,
                baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
                token: auth.accessToken
            )
            .navigationTitle("New Stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        // Grid order (newest first) decides the cover.
                        Task { await vm.createStack(assetIds: vm.orderedSelection) }
                    }
                    .disabled(vm.selectedIds.count < 2)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("confirmCreateStack")
                }
            }
        }
        .task { await vm.beginPicking() }
    }
}
