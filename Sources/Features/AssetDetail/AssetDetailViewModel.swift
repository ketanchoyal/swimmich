import Foundation
import SwiftUI

/// Asset detail state. AC-010: PATCH /api/assets/:id on toggleFavorite.
@Observable
final class AssetDetailViewModel {
    let asset: AssetReactItem
    let client: any ImmichClient

    var isFavorite: Bool
    var detail: AssetResponseDto?
    var isLoading = false
    var errorMessage: String?

    /// Test-visible: last PATCH body sent + asset id targeted (AC-010).
    private(set) var lastUpdateBody: UpdateAssetDto?
    private(set) var lastUpdateAssetId: String?

    init(asset: AssetReactItem, client: any ImmichClient) {
        self.asset = asset
        self.client = client
        self.isFavorite = asset.isFavorite
    }

    @MainActor
    func loadDetail() async {
        isLoading = true
        do { detail = try await client.getAsset(id: asset.id) } catch let e { errorMessage = e.localizedDescription }
        isLoading = false
    }

    @MainActor
    func toggleFavorite() async {
        let newValue = !isFavorite
        let body = UpdateAssetDto(isFavorite: newValue)
        lastUpdateBody = body
        lastUpdateAssetId = asset.id
        do {
            let updated = try await client.updateAsset(id: asset.id, dto: body)
            isFavorite = updated.isFavorite
            detail = updated
        } catch let e {
            errorMessage = e.localizedDescription
        }
    }
}
