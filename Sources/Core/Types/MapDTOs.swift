import Foundation

/// One element of `GET /api/map/markers` — one marker per asset that has
/// location data. The server aggregates by rounded lat/lon, so multiple
/// assets in the same spot collapse into the same marker (any asset id wins).
struct MapMarkerResponseDto: Codable, Equatable, Sendable {
    let id: String
    let lat: Double
    let lon: Double
    let city: String?
    let state: String?
    let country: String?
}
