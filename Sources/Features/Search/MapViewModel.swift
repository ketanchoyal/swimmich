import Foundation
import MapKit

/// A map-pin representation of a geolocated asset. Backed by the server's
/// `MapMarkerResponseDto` (one marker per asset with location data).
struct MapPhoto: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    let city: String?
    let state: String?
    let country: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var placeName: String {
        [city, state, country].compactMap { $0 }.joined(separator: ", ")
    }

    init(from dto: MapMarkerResponseDto) {
        self.id = dto.id
        self.latitude = dto.lat
        self.longitude = dto.lon
        self.city = dto.city
        self.state = dto.state
        self.country = dto.country
    }

    /// Placeholder `AssetReactItem` for pushing `AssetDetailView`. Thumbnail
    /// URL only needs the id; the detail VM refetches the full asset via
    /// `getAsset(id:)` — same contract as search's ratio-1.0 default (AC-410).
    var asAssetItem: AssetReactItem {
        AssetReactItem(
            id: id, ownerId: "", ratio: 1.0, isFavorite: false, visibility: "timeline",
            isTrashed: false, isImage: true, thumbhash: nil,
            createdAt: "", fileCreatedAt: "", localOffsetHours: 0.0,
            duration: nil, livePhotoVideoId: nil, projectionType: nil,
            city: city, country: country, latitude: latitude, longitude: longitude
        )
    }
}

/// Map feature ViewModel — covers cahier §3.2 "Carte (Map)".
///
/// Loads all geolocated markers (`GET /api/map/markers`), served from a disk
/// cache first so repeat opens render instantly, then silently refreshed in
/// the background. The visible map region (debounced) is filtered into two
/// sets in a single scan:
/// - `visibleAnnotations` — markers inside the region **expanded** by
///   `cullMargin`, what `ClusteredMapView` actually displays (culling: we
///   never hand MapKit the full library, which is the 10-15s startup killer).
/// - `visiblePhotos` — markers inside the exact region, feeding the bottom
///   photo sheet.
///
/// `@Observable @MainActor` mirrors SearchViewModel / TimelineViewModel.
@Observable
@MainActor
final class MapViewModel {
    let client: any ImmichClient
    private let cache: MapMarkerCache

    private(set) var markers: [MapPhoto] = []
    private(set) var visibleAnnotations: [MapPhoto] = []
    private(set) var visiblePhotos: [MapPhoto] = []
    private(set) var isLoading: Bool = false
    var errorMessage: String? = nil

    /// Debounce for visible-region filtering (camera-change flood). Tests
    /// override with `.zero`.
    var debounceInterval: Duration = .milliseconds(250)

    /// Extra margin (× rect half-size) around the visible rect for culling.
    private let cullMargin = 0.5

    private var regionTask: Task<Void, Never>?
    private var loaded = false

    init(client: any ImmichClient, cache: MapMarkerCache = MapMarkerCache()) {
        self.client = client
        self.cache = cache
    }

    /// Loads markers once per VM lifetime. Serves the disk cache instantly if
    /// present (map renders without a network wait) and refreshes silently in
    /// the background. Callers drive this via `.task {}` (project convention).
    func loadMarkers() async {
        guard !isLoading, !loaded else { return }
        isLoading = true
        defer { isLoading = false }

        if let cached = cache.load(), !cached.isEmpty {
            markers = cached.map(MapPhoto.init(from:))
            loaded = true
            errorMessage = nil
            await refreshInBackground()
            return
        }

        do {
            let dtos = try await client.getMapMarkers(isFavorite: nil, isArchived: nil)
            markers = dtos.map(MapPhoto.init(from:))
            loaded = true
            cache.save(dtos)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Full reload (retry path). Clears cache + markers so `.task` re-dispatches.
    func reload() async {
        regionTask?.cancel()
        loaded = false
        markers = []
        visibleAnnotations = []
        visiblePhotos = []
        errorMessage = nil
        cache.clear()
        await loadMarkers()
    }

    /// Debounced region change from the MKMapView wrapper. Filters markers in
    /// one pass into the culled annotation set + the exact-region photo set.
    func setVisibleRect(_ rect: MKMapRect) {
        regionTask?.cancel()
        regionTask = Task {
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            filterVisible(rect)
        }
    }

    private func filterVisible(_ rect: MKMapRect) {
        let expanded = rect.insetBy(dx: -rect.width * cullMargin, dy: -rect.height * cullMargin)
        var photos: [MapPhoto] = []
        var annotations: [MapPhoto] = []
        for marker in markers {
            let point = MKMapPoint(marker.coordinate)
            if rect.contains(point) {
                photos.append(marker)
                annotations.append(marker)
            } else if expanded.contains(point) {
                annotations.append(marker)
            }
        }
        visiblePhotos = photos
        visibleAnnotations = annotations
    }

    private func refreshInBackground() async {
        do {
            let dtos = try await client.getMapMarkers(isFavorite: nil, isArchived: nil)
            markers = dtos.map(MapPhoto.init(from:))
            cache.save(dtos)
        } catch {
            // Silent: a stale cache is fine until the next open.
        }
    }
}
