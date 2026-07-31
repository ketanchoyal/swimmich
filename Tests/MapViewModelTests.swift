import XCTest
import MapKit
@testable import ImmichSwiftUI

@MainActor
final class MapViewModelTests: XCTestCase {

    private func makeMarker(id: String, lat: Double, lon: Double, city: String? = nil) -> MapMarkerResponseDto {
        MapMarkerResponseDto(id: id, lat: lat, lon: lon, city: city, state: nil, country: nil)
    }

    /// Isolated cache per test — prevents UserDefaults.standard pollution
    /// across tests (MapMarkerCache reads/writes the same key).
    private func makeIsolatedCache() -> (MapMarkerCache, String) {
        let suite = "MapViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (MapMarkerCache(defaults: defaults), suite)
    }

    // MARK: - Load (AC-710)

    func test_loadMarkers_success() async {
        let mock = MockImmichClient()
        mock.mapMarkersResponse = [
            makeMarker(id: "paris", lat: 48.8566, lon: 2.3522),
            makeMarker(id: "nyc", lat: 40.7128, lon: -74.0060)
        ]
        let (cache, suite) = makeIsolatedCache()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let vm = MapViewModel(client: mock, cache: cache)

        await vm.loadMarkers()

        XCTAssertEqual(mock.requestCount, 1)
        XCTAssertEqual(vm.markers.count, 2)
        XCTAssertEqual(vm.markers.map(\.id), ["paris", "nyc"])
        XCTAssertEqual(vm.markers.first?.placeName, "")
        XCTAssertNil(vm.errorMessage)
    }

    func test_loadMarkers_idempotent() async {
        let mock = MockImmichClient()
        mock.mapMarkersResponse = [makeMarker(id: "a1", lat: 48.85, lon: 2.35)]
        let (cache, suite) = makeIsolatedCache()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let vm = MapViewModel(client: mock, cache: cache)

        await vm.loadMarkers()
        await vm.loadMarkers()

        XCTAssertEqual(mock.requestCount, 1, "second call must no-op (loaded)")
    }

    func test_loadMarkers_error() async {
        let mock = MockImmichClient()
        struct Boom: Error {}
        mock.mapMarkersError = Boom()
        let (cache, suite) = makeIsolatedCache()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let vm = MapViewModel(client: mock, cache: cache)

        await vm.loadMarkers()

        XCTAssertTrue(vm.markers.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Cache (AC-710 perf)

    func test_loadMarkers_servesCache_thenRefreshes() async {
        let (cache, suite) = makeIsolatedCache()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        cache.save([makeMarker(id: "c1", lat: 48.85, lon: 2.35)])

        let mock = MockImmichClient()
        mock.mapMarkersResponse = [makeMarker(id: "c1", lat: 48.85, lon: 2.35)]
        let vm = MapViewModel(client: mock, cache: cache)

        await vm.loadMarkers()

        XCTAssertEqual(vm.markers.map(\.id), ["c1"], "cached markers rendered")
        XCTAssertEqual(mock.requestCount, 1, "background refresh still fetches once")
        XCTAssertNil(vm.errorMessage)
    }

    func test_loadMarkers_cacheRefreshFailure_keepsCache() async {
        let (cache, suite) = makeIsolatedCache()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        cache.save([makeMarker(id: "c1", lat: 48.85, lon: 2.35)])

        let mock = MockImmichClient()
        struct Boom: Error {}
        mock.mapMarkersError = Boom()
        let vm = MapViewModel(client: mock, cache: cache)

        await vm.loadMarkers()

        XCTAssertEqual(vm.markers.map(\.id), ["c1"], "refresh failure keeps cached markers")
        XCTAssertNil(vm.errorMessage, "background refresh failure is silent")
    }

    func test_cache_roundTrip() {
        let (cache, suite) = makeIsolatedCache()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        XCTAssertNil(cache.load(), "empty cache")

        cache.save([
            makeMarker(id: "a", lat: 1, lon: 2),
            makeMarker(id: "b", lat: 3, lon: 4, city: "Paris")
        ])
        let loaded = cache.load()
        XCTAssertEqual(loaded?.count, 2)
        XCTAssertEqual(loaded?.first?.id, "a")
        XCTAssertEqual(loaded?.last?.city, "Paris")

        cache.clear()
        XCTAssertNil(cache.load())
    }

    func test_reload_after_error_retries() async {
        let mock = MockImmichClient()
        struct Boom: Error {}
        mock.mapMarkersError = Boom()
        let (cache, suite) = makeIsolatedCache()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let vm = MapViewModel(client: mock, cache: cache)
        await vm.loadMarkers()
        XCTAssertNotNil(vm.errorMessage)

        mock.mapMarkersError = nil
        mock.mapMarkersResponse = [makeMarker(id: "a1", lat: 48.85, lon: 2.35)]
        await vm.reload()

        XCTAssertEqual(mock.requestCount, 2)
        XCTAssertEqual(vm.markers.count, 1)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Visible region filtering

    func test_setVisibleRect_filters_markers_in_rect() async {
        let mock = MockImmichClient()
        mock.mapMarkersResponse = [
            makeMarker(id: "paris", lat: 48.8566, lon: 2.3522),
            makeMarker(id: "nyc", lat: 40.7128, lon: -74.0060)
        ]
        let (cache, suite) = makeIsolatedCache()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let vm = MapViewModel(client: mock, cache: cache)
        vm.debounceInterval = .zero
        await vm.loadMarkers()

        let center = MKMapPoint(CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522))
        let rect = MKMapRect(x: center.x - 1_000_000, y: center.y - 1_000_000, width: 2_000_000, height: 2_000_000)

        vm.setVisibleRect(rect)
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(vm.visiblePhotos.map(\.id), ["paris"])
        XCTAssertEqual(vm.visibleAnnotations.map(\.id), ["paris"])
    }

    func test_setVisibleRect_expanded_annotations_include_margin() async {
        let mock = MockImmichClient()
        let center = MKMapPoint(CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522))
        // MKMapPoint.x ≈ 745,654 units per degree of longitude. Exact rect
        // half-width = 150,000 (~22km), expanded half = 300,000 (~45km).
        mock.mapMarkersResponse = [
            makeMarker(id: "center", lat: 48.8566, lon: 2.3522),
            makeMarker(id: "margin", lat: 48.8566, lon: 2.7), // ≈38km east: outside exact, inside expanded
            makeMarker(id: "far", lat: 48.8566, lon: 4.0)     // ≈183km east: outside both
        ]
        let (cache, suite) = makeIsolatedCache()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let vm = MapViewModel(client: mock, cache: cache)
        vm.debounceInterval = .zero
        await vm.loadMarkers()

        let rect = MKMapRect(x: center.x - 150_000, y: center.y - 150_000, width: 300_000, height: 300_000)

        vm.setVisibleRect(rect)
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(vm.visiblePhotos.map(\.id), ["center"], "exact rect keeps only in-region photos")
        XCTAssertEqual(Set(vm.visibleAnnotations.map(\.id)), Set(["center", "margin"]), "expanded rect adds margin markers for culling")
    }

    func test_setVisibleRect_empty_region() async {
        let mock = MockImmichClient()
        mock.mapMarkersResponse = [makeMarker(id: "paris", lat: 48.8566, lon: 2.3522)]
        let (cache, suite) = makeIsolatedCache()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let vm = MapViewModel(client: mock, cache: cache)
        vm.debounceInterval = .zero
        await vm.loadMarkers()

        let far = MKMapPoint(CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093))
        let rect = MKMapRect(x: far.x - 1_000, y: far.y - 1_000, width: 2_000, height: 2_000)

        vm.setVisibleRect(rect)
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertTrue(vm.visiblePhotos.isEmpty)
        XCTAssertTrue(vm.visibleAnnotations.isEmpty)
    }

    // MARK: - MapPhoto adapter

    func test_mapPhoto_asAssetItem_keeps_identity_and_coords() {
        let dto = MapMarkerResponseDto(id: "a1", lat: 48.8566, lon: 2.3522, city: "Paris", state: "Île-de-France", country: "France")
        let photo = MapPhoto(from: dto)
        XCTAssertEqual(photo.placeName, "Paris, Île-de-France, France")

        let item = photo.asAssetItem
        XCTAssertEqual(item.id, "a1")
        XCTAssertEqual(item.latitude, 48.8566)
        XCTAssertEqual(item.longitude, 2.3522)
        XCTAssertEqual(item.city, "Paris")
    }
}
