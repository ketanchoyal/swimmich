import XCTest
@testable import ImmichSwiftUI

/// The store's contract is "what the user picked is still there next launch":
/// every case writes through one instance and reads it back with a second one,
/// so a value that only lives in memory fails.
@MainActor
final class MapSettingsStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MapSettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_defaults_areUnfilteredAndFollowTheSystem() {
        let store = MapSettingsStore(defaults: defaults)

        XCTAssertEqual(store.filter, .all)
        XCTAssertTrue(store.filter.isEmpty)
        XCTAssertEqual(store.theme, .system)
    }

    func test_setFilter_survivesARelaunch() {
        let store = MapSettingsStore(defaults: defaults)
        let filter = MapMarkerFilter(onlyFavorites: true, relativeDays: 30)

        store.setFilter(filter)

        XCTAssertEqual(store.filter, filter)
        XCTAssertEqual(MapSettingsStore(defaults: defaults).filter, filter)
    }

    func test_setTheme_survivesARelaunch() {
        let store = MapSettingsStore(defaults: defaults)

        store.setTheme(.dark)

        XCTAssertEqual(store.theme, .dark)
        XCTAssertEqual(MapSettingsStore(defaults: defaults).theme, .dark)
    }

    func test_resetTimeRange_dropsTheBoundsAndThePresetButKeepsTheToggles() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let store = MapSettingsStore(defaults: defaults)
        store.setFilter(MapMarkerFilter(onlyFavorites: true, relativeDays: 30, from: day, to: day))

        store.resetTimeRange()

        XCTAssertEqual(store.filter, MapMarkerFilter(onlyFavorites: true), "back to \"All\", markers still filtered")
        XCTAssertEqual(store.filter.relativeDays, 0)
        XCTAssertNil(store.filter.from)
        XCTAssertNil(store.filter.to)
        XCTAssertEqual(MapSettingsStore(defaults: defaults).filter, MapMarkerFilter(onlyFavorites: true))
    }

    func test_unreadablePayload_fallsBackToTheUnfilteredState() {
        defaults.set(Data("not a filter".utf8), forKey: MapSettingsStore.defaultsKeyFilter)

        // A payload written by another version must never wedge the map into a
        // filter the user cannot see the origin of.
        XCTAssertEqual(MapSettingsStore(defaults: defaults).filter, .all)
    }
}
