import Photos
import SwiftUI

/// The device library laid out 3-up, with the same columns and the same spacing
/// as `AssetMultiSelectGrid` so the app's two selection grids read alike.
///
/// A grid of its own rather than a reuse of `AssetMultiSelectGrid`, which is
/// typed on `[AssetReactItem]` (server assets paged through
/// `POST /api/search/metadata`) and carries paging and exclusion — neither of
/// which means anything for a complete, cursor-less PhotoKit enumeration.
///
/// Owns no state: it renders the library it is handed and reports taps back. The
/// tiles arrive through the `loadThumbnail` closure, so the service stays in the
/// ViewModel.
struct LocalAssetGrid: View {
    let assets: [PHAsset]
    let selectedIDs: Set<String>
    /// The assets the server reported as missing. Read only when a verdict
    /// exists — see `verdictAvailable`.
    let localOnlyIDs: Set<String>
    /// False until `checkSelection()` ran. Without it, "no answer yet" would be
    /// rendered as "on the server", which is the one confusion this screen
    /// exists to avoid.
    let verdictAvailable: Bool
    let onToggle: (String) -> Void
    let loadThumbnail: (PHAsset) async -> UIImage?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s2), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: PVSpacing.s2) {
            ForEach(assets, id: \.localIdentifier) { asset in
                LocalAssetCell(
                    asset: asset,
                    isSelected: selectedIDs.contains(asset.localIdentifier),
                    isLocalOnly: verdictAvailable ? localOnlyIDs.contains(asset.localIdentifier) : nil,
                    onTap: { onToggle(asset.localIdentifier) },
                    loadThumbnail: loadThumbnail
                )
            }
        }
    }
}
