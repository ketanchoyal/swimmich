import Foundation
import Observation

/// Persisted map settings (gap G14b): the marker filter and the map theme.
///
/// Same precedent as `AppLanguageStore` / `BackupSettingsStore` — one
/// UserDefaults key per setting, decoded on creation and written on change — so
/// the choice survives a relaunch. One instance per process (owned by
/// `DependencyContainer`): the settings sheet, the badge, the banner and the
/// map all project the same state instead of each holding a copy.
@MainActor
@Observable
final class MapSettingsStore {
    static let defaultsKeyFilter = "mapMarkerFilter"
    static let defaultsKeyTheme = "mapTheme"

    private let defaults: UserDefaults

    private(set) var filter: MapMarkerFilter
    private(set) var theme: MapTheme

    /// `defaults` is injectable so tests exercise a dedicated suite instead of
    /// the real app's storage.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKeyFilter),
           let decoded = try? JSONDecoder.immich.decode(MapMarkerFilter.self, from: data) {
            filter = decoded
        } else {
            filter = .all
        }
        theme = defaults.string(forKey: Self.defaultsKeyTheme)
            .flatMap(MapTheme.init(rawValue:)) ?? .system
    }

    func setFilter(_ new: MapMarkerFilter) {
        guard new != filter else { return }
        filter = new
        if let data = try? JSONEncoder.immich.encode(new) {
            defaults.set(data, forKey: Self.defaultsKeyFilter)
        }
    }

    func setTheme(_ new: MapTheme) {
        guard new != theme else { return }
        theme = new
        defaults.set(new.rawValue, forKey: Self.defaultsKeyTheme)
    }

    /// Upstream's "Remove custom date range": drops both bounds **and** the
    /// relative preset, i.e. back to "All".
    func resetTimeRange() {
        var cleared = filter
        cleared.relativeDays = 0
        cleared.from = nil
        cleared.to = nil
        setFilter(cleared)
    }
}

/// Map appearance. The three cases exist because "follow the system" cannot be
/// expressed by a two-state switch; the mapping to `MKMapView` lives in the map
/// itself (`ClusteredMapView.interfaceStyle`), the only lever that repaints
/// MapKit's tiles.
enum MapTheme: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}
