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

    /// Reverse-geocoded place label. Nil if no coords, geocoder failed with no fallback data,
    /// or loadDetail not yet run. (AC-204/205/206)
    var placeName: String?

    /// Injectable geocoder. `@ObservationIgnored` because identity swaps shouldn't trigger view updates.
    /// Default = `AppleGeocoder()` (production); tests inject a `MockLocationGeocoder`.
    @ObservationIgnored var geocoder: any LocationGeocoding = AppleGeocoder()

    /// FM-3 guard: prevent CLGeocoder double-invoke on reload (rate-limit / label-flip).
    /// Reset only when a NEW asset is loaded (not in MVP).
    @ObservationIgnored private var geocoded = false

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
        await reverseGeocodeIfNeeded()
    }

    /// AC-204/205/206: drive reverse-geocoding once per VM lifetime.
    /// No-op without coords (AC-206). On geocoder throw, fall back to EXIF city/state/country (AC-205).
    private func reverseGeocodeIfNeeded() async {
        guard !geocoded else { return } // FM-3: skip on reload
        geocoded = true
        guard let exif = detail?.exifInfo,
              let lat = exif.latitude,
              let lon = exif.longitude else { return } // AC-206: no coords → no geocode
        do {
            placeName = try await geocoder.placeName(latitude: lat, longitude: lon)
        } catch {
            let fallback = [exif.city, exif.state, exif.country]
                .compactMap { $0 }
                .joined(separator: ", ")
            placeName = fallback.isEmpty ? nil : fallback
        }
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
