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
            city: city, country: country, latitude: latitude, longitude: longitude, stack: []
        )
    }
}

/// One annotation handed to MapKit. At world zoom the grid subsampling keeps
/// the ingested set bounded — each sampled marker then **represents** every
/// photo of its grid cell (`representedCount`), so cluster/marker badges sum
/// exactly to the photo-sheet total. Markers of the cull margin carry 0.
struct MapAnnotationMarker: Identifiable, Equatable {
    let photo: MapPhoto
    let representedCount: Int

    var id: String { photo.id }
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
    private(set) var visibleAnnotations: [MapAnnotationMarker] = []
    private(set) var visiblePhotos: [MapPhoto] = []
    private(set) var isLoading: Bool = false
    var errorMessage: String? = nil

    /// Presentation state of the native map photo sheet. Owned here (the
    /// ViewModel lives in RootView, outliving every navigation change) so
    /// RootView — the only stable presenter — can drive the `.sheet`.
    var isPhotoSheetPresented = false

    /// Marker selected by a map tap: while set, the photo sheet shows only
    /// that marker's cell photos instead of the whole region's.
    private(set) var selectedMarkerID: String?
    private(set) var selectedMarkerPhotos: [MapPhoto] = []

    /// Current region's photos grouped by grid cell — powers the marker
    /// selection filter (the marker's badge count == its cell's photos).
    private var photoCells: [CellKey: [MapPhoto]] = [:]
    private var cellOfPhotoID: [String: CellKey] = [:]

    /// Filters the photo sheet to the tapped marker's cell photos.
    func selectMarker(_ id: String) {
        guard let cell = cellOfPhotoID[id] else {
            selectedMarkerID = nil
            selectedMarkerPhotos = []
            return
        }
        selectedMarkerID = id
        selectedMarkerPhotos = photoCells[cell] ?? []
    }

    /// Clears the marker filter — the sheet returns to the region's photos.
    func deselectMarker() {
        selectedMarkerID = nil
        selectedMarkerPhotos = []
    }

    /// Bounding map rect of the tapped marker's grid cell photos — the drill-in
    /// zoom target. At coarse zoom an isolated area (e.g. an island) collapses
    /// into a single high-count marker that MapKit never turns into a real
    /// cluster, so tapping it must zoom to reveal the spread. `nil` when the id
    /// isn't a live cell. A degenerate rect (all photos share the server's
    /// rounded coordinate) is expanded to a minimum span so we drill to a
    /// sensible level instead of slamming to max zoom.
    func zoomRect(forMarker id: String) -> MKMapRect? {
        guard let cell = cellOfPhotoID[id], let photos = photoCells[cell], !photos.isEmpty else {
            return nil
        }
        var rect = MKMapRect.null
        for photo in photos {
            let pt = MKMapPoint(photo.coordinate)
            rect = rect.union(MKMapRect(x: pt.x - 1, y: pt.y - 1, width: 2, height: 2))
        }
        guard !rect.isNull else { return nil }

        // Minimum span (~2km at the equator in MKMapPoint units) so a
        // single-spot cell still drills in cleanly rather than to max zoom.
        let minSpan: Double = 8_000
        if rect.width < minSpan || rect.height < minSpan {
            let cx = rect.midX, cy = rect.midY
            let w = max(rect.width, minSpan), h = max(rect.height, minSpan)
            rect = MKMapRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        }
        return rect
    }

    /// Debounce for visible-region filtering (camera-change flood). Tests
    /// override with `.zero`.
    var debounceInterval: Duration = .milliseconds(250)

    /// How long a cached marker set is considered fresh. Within this window a
    /// map open serves the cache **without** a background refetch (the whole
    /// catalogue is a heavy request). Tests override with `.zero` to force a
    /// refresh on every open.
    var refreshTTL: Duration = .seconds(600)

    /// Guards against overlapping refreshes (repeated opens / rapid viewer
    /// mutations) all refetching the full catalogue at once.
    private var isRefreshing = false

    private var ttlSeconds: TimeInterval {
        let c = refreshTTL.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }

    /// Annotation-grid density: at world zoom MapKit would ingest every marker
    /// (10k+ → seconds of main-thread stall). One marker per grid cell keeps
    /// the rendered set bounded (~44×44) while zooming refines the grid and
    /// brings every marker of the region back.
    private let annotationGridSize = 44

    /// Grid cell identity for the annotation subsampling.
    private struct CellKey: Hashable {
        let x: Int
        let y: Int
    }

    private var regionTask: Task<Void, Never>?
    private var loaded = false

    /// Last visible region, re-applied after marker reloads so `visiblePhotos`
    /// never churns to empty mid-refresh (keeps the map photo sheet stable).
    private var lastRect: MKMapRect?

    init(client: any ImmichClient, cache: MapMarkerCache = MapMarkerCache()) {
        self.client = client
        self.cache = cache
    }

    /// Loads markers once per VM lifetime. Serves the disk cache instantly if
    /// present (map renders without a network wait) and refreshes silently in
    /// the background **only when the cache is older than `refreshTTL`**.
    /// Callers drive this via `.task {}` (project convention).
    ///
    /// Cache decode runs off the MainActor (the whole-catalogue JSON can be
    /// large); only the resulting model assignment hops back to the main actor.
    func loadMarkers() async {
        guard !isLoading, !loaded else { return }
        isLoading = true
        defer { isLoading = false }

        // Decode the disk cache off the MainActor so a large payload never
        // stalls the UI.
        let cache = self.cache
        let cached = await Task.detached(priority: .utility) {
            (markers: cache.load(), age: cache.age())
        }.value

        if let dtos = cached.markers, !dtos.isEmpty {
            print("[MapVM] cache hit: \(dtos.count) markers (age \(cached.age.map { Int($0) } ?? -1)s)")
            applyMarkers(dtos)
            loaded = true
            // Refresh only when the cache has gone stale — a fresh cache skips
            // the (heavy) refetch entirely.
            if cached.age == nil || (cached.age ?? .infinity) > ttlSeconds {
                Task { await refreshMarkers() }
            }
            return
        }

        print("[MapVM] cache miss — fetching from server…")
        do {
            let dtos = try await client.getMapMarkers(isFavorite: nil, isArchived: nil)
            print("[MapVM] fetched \(dtos.count) markers")
            applyMarkers(dtos)
            loaded = true
            await persist(dtos)
        } catch {
            print("[MapVM] fetch failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Re-fetches markers from the server, swapping in fresh data and
    /// refreshing the disk cache — without clearing anything. The map and the
    /// photo sheet keep showing the previous set while the fetch runs.
    /// Silent on failure (a stale set is fine until the next refresh).
    /// Overlapping calls no-op (`isRefreshing`) so repeated opens / rapid
    /// viewer mutations don't fire concurrent full-catalogue refetches.
    func refreshMarkers() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let dtos = try await client.getMapMarkers(isFavorite: nil, isArchived: nil)
            print("[MapVM] refresh fetched \(dtos.count) markers")
            applyMarkers(dtos)
            // Never overwrite a good cache with an empty response (an empty
            // cache would make loadMarkers skip the cache path forever).
            await persist(dtos)
        } catch {
            print("[MapVM] refresh failed: \(error.localizedDescription)")
            // Silent: a stale cache is fine until the next open.
        }
    }

    /// Single funnel for a freshly fetched/loaded marker set: maps the DTOs,
    /// clears any error, and re-applies the last visible-region filter. Keeps
    /// `loadMarkers` / `refreshMarkers` DRY. Persistence is a separate
    /// `persist` step so callers control it (cache hits never re-write).
    private func applyMarkers(_ dtos: [MapMarkerResponseDto]) {
        markers = dtos.map(MapPhoto.init(from:))
        errorMessage = nil
        refilterIfNeeded()
    }

    /// Writes the marker set to the disk cache off the MainActor (large JSON
    /// encode). Awaited by callers so the write is observable on return without
    /// ever blocking the main thread. Empty sets are never persisted (an empty
    /// cache would make `loadMarkers` skip the cache path forever).
    private func persist(_ dtos: [MapMarkerResponseDto]) async {
        guard !dtos.isEmpty else { return }
        let cache = self.cache
        await Task.detached(priority: .utility) { cache.save(dtos) }.value
    }

    /// Single funnel for a freshly fetched/loaded marker set: maps the DTOs,
    /// clears any error, (optionally) persists the cache off the MainActor, and
    /// re-applies the last visible-region filter. Keeps `loadMarkers` /
    /// `refreshMarkers` DRY.
    private func applyMarkers(_ dtos: [MapMarkerResponseDto], persist: Bool) {
        markers = dtos.map(MapPhoto.init(from:))
        errorMessage = nil
        if persist, !dtos.isEmpty {
            let cache = self.cache
            Task.detached(priority: .utility) { cache.save(dtos) }
        }
        refilterIfNeeded()
    }

    /// Full reload (retry path). Clears cache + markers so `.task` re-dispatches.
    /// `visiblePhotos`/`visibleAnnotations` survive the reload — the sheet
    /// stays populated while the refetch runs, then `loadMarkers` re-filters
    /// against `lastRect`.
    func reload() async {
        regionTask?.cancel()
        loaded = false
        markers = []
        errorMessage = nil
        cache.clear()
        await loadMarkers()
    }

    /// Debounced region change from the MKMapView wrapper. Filters markers in
    /// one pass into the culled annotation set + the exact-region photo set.
    func setVisibleRect(_ rect: MKMapRect) {
        lastRect = rect
        regionTask?.cancel()
        regionTask = Task {
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            filterVisible(rect)
        }
    }

    private func filterVisible(_ rect: MKMapRect) {
        // One grid cell across the region's long axis; at world zoom this caps
        // the annotation set at ~gridSize² while finer zooms tighten the grid
        // until every marker of the region is shown. Annotations are exactly
        // the region's markers (no cull margin): every badge therefore sums
        // to `visiblePhotos.count` at any zoom, with no zero badges.
        let cellWidth = max(max(rect.width, rect.height) / CGFloat(annotationGridSize), 1)
        var photos: [MapPhoto] = []
        var cellPhotos: [CellKey: [MapPhoto]] = [:]
        var cellOfPhoto: [String: CellKey] = [:]
        for (i, marker) in markers.enumerated() {
            // Cooperative cancellation: a newer region change supersedes this
            // pass (the scan is O(all markers) — abandon a stale one promptly).
            if i & 0x3FF == 0, Task.isCancelled { return }
            let point = MKMapPoint(marker.coordinate)
            guard rect.contains(point) else { continue }
            photos.append(marker)
            let cell = CellKey(x: Int(point.x / cellWidth), y: Int(point.y / cellWidth))
            cellPhotos[cell, default: []].append(marker)
            cellOfPhoto[marker.id] = cell
        }

        // One annotation per occupied cell, carrying the real photo count of
        // its cell (so badges sum to `visiblePhotos.count`).
        var annotations: [MapAnnotationMarker] = []
        var seenCells = Set<CellKey>()
        for marker in photos {
            guard let cell = cellOfPhoto[marker.id] else { continue }
            if seenCells.insert(cell).inserted {
                annotations.append(MapAnnotationMarker(photo: marker, representedCount: cellPhotos[cell]?.count ?? 0))
            }
        }
        photoCells = cellPhotos
        cellOfPhotoID = cellOfPhoto
        visiblePhotos = photos
        visibleAnnotations = annotations

        // The selected marker may have left the region or the library —
        // drop the filter instead of showing a stale selection.
        if let selected = selectedMarkerID, cellOfPhoto[selected] == nil {
            selectedMarkerID = nil
            selectedMarkerPhotos = []
        }
    }

    /// Re-applies the last region filter after markers are (re)loaded so the
    /// visible sets stay consistent without waiting for a new region callback.
    private func refilterIfNeeded() {
        if let lastRect {
            filterVisible(lastRect)
        }
    }
}
