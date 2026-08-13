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

    /// Faces detected on this asset (gap #5) — `GET /api/faces?id=`.
    var faces: [AssetFaceResponseDto] = []
    /// All people on the instance, for the face-assignment picker (gap #5).
    var allPeople: [PersonResponseDto] = []
    /// True while faces/people are loading (drives the faces card spinner).
    var facesLoading = false

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
        await loadFaces()
    }

    /// Loads the faces on this asset + the people list for the assignment
    /// picker (gap #5). Failures are non-fatal — the rest of the panel still
    /// renders; the faces card just shows nothing.
    @MainActor
    func loadFaces() async {
        facesLoading = true
        defer { facesLoading = false }
        do {
            async let fetchedFaces = client.getFaces(assetId: asset.id)
            async let page = client.getPeople(page: nil, withHidden: true)
            let (f, p) = try await (fetchedFaces, page)
            faces = f
            allPeople = p.people
        } catch {
            // Non-fatal: keep any previously loaded faces.
        }
    }

    /// Reassigns one face to an existing person (gap #5), then reloads faces.
    @MainActor
    func reassignFace(faceId: String, toPersonId: String) async {
        do {
            _ = try await client.reassignFace(faceId: faceId, toPersonId: toPersonId)
            errorMessage = nil
            await loadFaces()
        } catch let e {
            errorMessage = e.localizedDescription
        }
    }

    /// Creates a new person by name and assigns the face to it (gap #5).
    @MainActor
    func createPersonAndAssign(faceId: String, name: String) async {
        do {
            let person = try await client.createPerson(name: name)
            _ = try await client.reassignFace(faceId: faceId, toPersonId: person.id)
            errorMessage = nil
            await loadFaces()
        } catch let e {
            errorMessage = e.localizedDescription
        }
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

    /// Adjust date/time (gap #3): PATCH /api/assets/:id {dateTimeOriginal}.
    /// The date is encoded as Immich's UTC ISO-8601 (`yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`).
    @MainActor
    func setDateTime(_ date: Date) async {
        let body = UpdateAssetDto(dateTimeOriginal: ISO8601.immichFormatter.string(from: date))
        lastUpdateBody = body
        lastUpdateAssetId = asset.id
        do {
            let updated = try await client.updateAsset(id: asset.id, dto: body)
            detail = updated
        } catch let e {
            errorMessage = e.localizedDescription
        }
    }

    /// Adjust-location (map-extras): PATCH /api/assets/:id {latitude, longitude},
    /// then re-run reverse geocoding so the panel label reflects the new spot.
    /// Out-of-bounds coordinates are rejected without touching the network.
    @MainActor
    func setLocation(latitude: Double, longitude: Double) async {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            errorMessage = "Invalid coordinates."
            return
        }
        let body = UpdateAssetDto(latitude: latitude, longitude: longitude)
        lastUpdateBody = body
        lastUpdateAssetId = asset.id
        do {
            let updated = try await client.updateAsset(id: asset.id, dto: body)
            detail = updated
            geocoded = false // FM-3 guard reset: the spot changed, re-geocode allowed.
            await reverseGeocodeIfNeeded()
        } catch let e {
            errorMessage = e.localizedDescription
        }
    }
}
