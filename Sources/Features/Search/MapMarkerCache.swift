import Foundation

/// File-backed cache of map markers so repeat map opens render instantly (no
/// network round-trip) while a silent, TTL-throttled background refresh in
/// `MapViewModel` keeps coordinates fresh.
///
/// Stored as a single JSON file in Caches/ (regenerable from the server, so
/// Caches is the correct domain — the OS may evict it under pressure). The
/// whole-catalogue payload can be large (10k+ markers); callers therefore run
/// `load`/`save` off the MainActor (`MapMarkerCache` is `Sendable`).
///
/// The persisted entry carries a `savedAt` timestamp so the ViewModel can
/// decide whether the cached set is fresh enough to skip the background
/// refresh entirely (see `age()`).
struct MapMarkerCache: Sendable {
    /// Persisted envelope: the markers plus when they were written.
    private struct Entry: Codable {
        let savedAt: Date
        let markers: [MapMarkerResponseDto]
    }

    private let fileURL: URL

    /// Default location: Caches/MapMarkers/markers.json.
    init(directory: URL? = nil) {
        let base = directory
            ?? (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("MapMarkers", isDirectory: true)
        self.fileURL = base.appendingPathComponent("markers.json")
    }

    /// Cached markers, or nil if the cache is empty/unreadable.
    func load() -> [MapMarkerResponseDto]? {
        loadEntry()?.markers
    }

    /// Seconds since the cache was written, or nil if there is no cache.
    /// Drives the ViewModel's refresh throttle (skip refetch while fresh).
    func age() -> TimeInterval? {
        guard let savedAt = loadEntry()?.savedAt else { return nil }
        return Date().timeIntervalSince(savedAt)
    }

    private func loadEntry() -> Entry? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder.immich.decode(Entry.self, from: data)
    }

    /// Writes the markers atomically, stamping the current time.
    func save(_ markers: [MapMarkerResponseDto]) {
        let entry = Entry(savedAt: Date(), markers: markers)
        guard let data = try? JSONEncoder.immich.encode(entry) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
