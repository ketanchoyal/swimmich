import Foundation

/// UserDefaults-backed cache of map markers so repeat map opens render
/// instantly (no network round-trip) while a silent background refresh in
/// `MapViewModel` keeps coordinates fresh.
struct MapMarkerCache {
    private let defaults: UserDefaults
    private let key = "mapMarkers"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [MapMarkerResponseDto]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder.immich.decode([MapMarkerResponseDto].self, from: data)
    }

    func save(_ markers: [MapMarkerResponseDto]) {
        guard let data = try? JSONEncoder.immich.encode(markers) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
