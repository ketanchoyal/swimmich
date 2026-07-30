import CoreLocation

/// Reverse-geocoding abstraction (CLGeocoder wrapped for testability).
/// @MainActor because CLGeocoder must be used from the main thread and its
/// completion-driven API is wrapped with `@MainActor` isolation.
@MainActor
protocol LocationGeocoding: AnyObject {
    func placeName(latitude: Double, longitude: Double) async throws -> String
}

enum GeocodingError: Error {
    case noPlacemarks
}

/// Production impl wrapping `CLGeocoder.reverseGeocodeLocation`.
/// Returns subLocality, locality, administrativeArea, country joined by ", ".
@MainActor
final class AppleGeocoder: LocationGeocoding {
    // nonisolated so it can be used as a stored-property default value from
    // non-@MainActor ViewModels (the @MainActor protocol methods still serialize).
    nonisolated init() {}

    func placeName(latitude: Double, longitude: Double) async throws -> String {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: latitude, longitude: longitude)
        )
        guard let pm = placemarks.first else { throw GeocodingError.noPlacemarks }
        return [pm.subLocality, pm.locality, pm.administrativeArea, pm.country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
