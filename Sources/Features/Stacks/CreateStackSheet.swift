import SwiftUI

/// Creates a stack from a multi-selection of the newest photos. A stack is
/// just an ordered id list server-side (`StackCreateDto { assetIds }`, min 2,
/// first id becomes the cover) — there is no stack name to collect, so this
/// sheet is only a picker plus a CTA.
struct CreateStackSheet: View {
    @Bindable var vm: StacksViewModel
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s2), count: 3)

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoadingAssets && vm.recentAssets.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.recentAssets.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing to stack", systemImage: "photo.on.rectangle.angled")
                    } description: {
                        Text(vm.errorMessage ?? "Add photos to your library first.")
                    }
                } else {
                    picker
                }
            }
            .navigationTitle("New Stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        // Selection order follows the grid (newest first) so the
                        // cover is the newest photo the user picked.
                        Task { await vm.createStack(assetIds: orderedSelection) }
                    }
                    .disabled(vm.selectedIds.count < 2)
                    .fontWeight(.semibold)
                }
            }
        }
        .task { await vm.beginCreateFlow() }
    }

    private var picker: some View {
        ScrollView {
            selectionSummary

            LazyVGrid(columns: columns, spacing: PVSpacing.s2) {
                ForEach(vm.recentAssets) { asset in
                    Button {
                        vm.toggleSelection(id: asset.id)
                    } label: {
                        AssetThumbnailCell(
                            asset: asset,
                            baseURL: auth.baseURL ?? URL(string: "https://example.com")!,
                            token: auth.accessToken,
                            selectionMode: true,
                            isSelected: vm.selectedIds.contains(asset.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        // Prefetch the next page a screenful early so the grid
                        // never dead-ends on a spinner.
                        if asset.id == vm.recentAssets.last?.id, vm.canLoadMoreAssets {
                            Task { await vm.loadMoreAssets() }
                        }
                    }
                }
            }
            .padding(.horizontal, PVSpacing.s4)

            if vm.isLoadingAssets {
                ProgressView()
                    .padding(.vertical, PVSpacing.s16)
            }
        }
    }

    /// Live count + the rule the server enforces (min 2), so the disabled CTA
    /// is explained rather than mysterious.
    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: PVSpacing.s2) {
            Text(vm.selectedIds.count == 1
                 ? "1 selected"
                 : "\(vm.selectedIds.count) selected")
                .font(.pvSubhead.weight(.semibold))
                .foregroundStyle(Color.textPrimaryPV)
            Text("Pick at least 2 photos. The newest one becomes the cover.")
                .font(.pvCaption)
                .foregroundStyle(Color.textSecondaryPV)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PVSpacing.s16)
        .padding(.vertical, PVSpacing.s8)
    }

    /// Selected ids in the picker's display order (newest first).
    private var orderedSelection: [String] {
        vm.recentAssets.map(\.id).filter { vm.selectedIds.contains($0) }
    }
}
