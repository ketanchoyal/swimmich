import SwiftUI

/// Multi-select grid of the newest photos, paged from `POST /api/search/metadata`.
///
/// Shared by `CreateStackSheet` (start a stack) and `AddToStackSheet` (extend
/// one): the picking surface is identical, only the CTA and the call differ, so
/// there is one grid to keep right instead of two drifting copies.
///
/// Owns no state — it reads and writes the picker state on `StacksViewModel`
/// and expects the host sheet to have opened the flow (`beginPicking`).
struct StackPhotoPicker: View {
    @Bindable var vm: StacksViewModel
    let baseURL: URL
    let token: String?

    /// Members to leave out of the grid (the stack being extended). Kept out of
    /// the selection rather than merely unchecked: "adding" a photo the stack
    /// already holds would re-create the stack for nothing.
    var excluding: Set<String> = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s2), count: 3)

    /// What the grid actually renders — the picker's page minus the excluded
    /// members. Empty while pages keep turning up nothing new is handled by
    /// `emptyButMore`, not by a dead-end empty state.
    private var visibleAssets: [AssetReactItem] {
        vm.recentAssets.filter { !excluding.contains($0.id) }
    }

    var body: some View {
        Group {
            if vm.isLoadingAssets && vm.recentAssets.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleAssets.isEmpty {
                emptyState
            } else {
                grid
            }
        }
    }

    /// Nothing to show yet. Only a dead end once the library is exhausted —
    /// otherwise a page was entirely made of photos already in the stack, and
    /// the next page is on its way.
    @ViewBuilder
    private var emptyState: some View {
        if vm.canLoadMoreAssets {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: vm.recentAssets.count) { await vm.loadMoreAssets() }
        } else {
            ContentUnavailableView {
                Label("Nothing to add", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text(vm.errorMessage ?? "Every photo in your library is already in a stack you can see here.")
            }
        }
    }

    private var grid: some View {
        ScrollView {
            selectionSummary

            LazyVGrid(columns: columns, spacing: PVSpacing.s2) {
                ForEach(visibleAssets) { asset in
                    // The tap goes through the cell's own `onTap`: wrapping it in
                    // a `Button` does not work, because `AssetThumbnailCell`
                    // attaches a descendant `onTapGesture` that wins over the
                    // button's action and would swallow every tap.
                    AssetThumbnailCell(
                        asset: asset,
                        baseURL: baseURL,
                        token: token,
                        selectionMode: true,
                        isSelected: vm.selectedIds.contains(asset.id),
                        onTap: { vm.toggleSelection(id: asset.id) }
                    )
                    .accessibilityIdentifier("pickerAsset_\(asset.id)")
                    .onAppear {
                        // Prefetch the next page a screenful early so the grid
                        // never dead-ends on a spinner.
                        if asset.id == visibleAssets.last?.id, vm.canLoadMoreAssets {
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

    /// Live count + the rule the server enforces, so a disabled CTA is
    /// explained rather than mysterious.
    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: PVSpacing.s2) {
            Text(vm.selectedIds.count == 1
                 ? "1 selected"
                 : "\(vm.selectedIds.count) selected")
                .font(.pvSubhead.weight(.semibold))
                .foregroundStyle(Color.textPrimaryPV)
            Text(minimumSelectionHint)
                .font(.pvCaption)
                .foregroundStyle(Color.textSecondaryPV)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PVSpacing.s16)
        .padding(.vertical, PVSpacing.s8)
    }

    /// The hint differs because the minimum does: a new stack needs 2 ids
    /// (`.min(2)` on `StackCreateDto`), while extending one already has a member
    /// — its cover — to lead the payload.
    private var minimumSelectionHint: String {
        excluding.isEmpty
            ? "Pick at least 2 photos. The newest one becomes the cover."
            : "Pick at least 1 photo. The stack's current cover stays its cover."
    }
}
