import XCTest
@testable import ImmichSwiftUI

/// Pins the map route's wire contract: which query items a filter produces, and
/// which cache file each filter owns. Both are behaviour the server and the
/// disk see, not internals.
final class MapMarkerFilterTests: XCTestCase {

    // MARK: - Serialisation

    func test_all_isEmptyAndSendsNoQueryItems() {
        let filter = MapMarkerFilter.all
        XCTAssertTrue(filter.isEmpty)
        XCTAssertNil(filter.cacheVariant, "the unconstrained filter owns the legacy cache file")
        XCTAssertTrue(filter.queryItems().isEmpty)
    }

    func test_queryItems_onlyEncodesTheTogglesThatAreOn() {
        let filter = MapMarkerFilter(onlyFavorites: true, withPartners: true)
        XCTAssertEqual(filter.queryItems(), [
            URLQueryItem(name: "isFavorite", value: "true"),
            URLQueryItem(name: "withPartners", value: "true")
        ])
        XCTAssertFalse(filter.isEmpty)
    }

    func test_queryItems_relativePresetUsesFileCreatedAfter() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let filter = MapMarkerFilter(relativeDays: 30)
        XCTAssertEqual(filter.queryItems(now: now), [
            URLQueryItem(
                name: "fileCreatedAfter",
                value: ISO8601.immichFormatter.string(from: now.addingTimeInterval(-30 * 86_400))
            )
        ])
    }

    func test_queryItems_customRangeOverridesTheRelativePresetAndIncludesTheEndDay() {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let to = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_600_000))
        // Both carried at once (a decoded filter can): the custom range wins.
        let filter = MapMarkerFilter(relativeDays: 30, from: from, to: to)

        let items = filter.queryItems(now: Date(timeIntervalSince1970: 1_800_000_000))

        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to))?
            .addingTimeInterval(-1)
        XCTAssertEqual(items, [
            URLQueryItem(name: "fileCreatedAfter", value: ISO8601.immichFormatter.string(from: from)),
            URLQueryItem(name: "fileCreatedBefore", value: ISO8601.immichFormatter.string(from: endOfDay!))
        ], "a DatePicker day is midnight: the upper bound must be the end of that day, not its start")
    }

    func test_queryItems_singleBoundSendsOnlyThatBound() {
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(MapMarkerFilter(from: day).queryItems(), [
            URLQueryItem(name: "fileCreatedAfter", value: ISO8601.immichFormatter.string(from: day))
        ])
        let onlyBefore = MapMarkerFilter(to: day).queryItems()
        XCTAssertEqual(onlyBefore.count, 1)
        XCTAssertEqual(onlyBefore.first?.name, "fileCreatedBefore")
    }

    // MARK: - Validation

    func test_isValid_refusesAnInvertedRange() {
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_700_600_000)
        XCTAssertFalse(MapMarkerFilter(from: later, to: earlier).isValid)
        XCTAssertTrue(MapMarkerFilter(from: earlier, to: later).isValid)
        XCTAssertTrue(MapMarkerFilter(from: later).isValid, "a single bound is always a valid range")
        XCTAssertTrue(MapMarkerFilter.all.isValid)
    }

    // MARK: - Cache variant

    func test_cacheVariant_isAFixedKeyPerFilter() {
        XCTAssertEqual(MapMarkerFilter(onlyFavorites: true, relativeDays: 30).cacheVariant, "f1-a0-p0-r30")
        XCTAssertEqual(
            MapMarkerFilter(includeArchived: true, withPartners: true).cacheVariant,
            "f0-a1-p1-r0"
        )
        XCTAssertNotEqual(
            MapMarkerFilter(relativeDays: 30).cacheVariant,
            MapMarkerFilter(relativeDays: 7).cacheVariant
        )
    }

    func test_cacheVariant_customRangeUsesDayBoundaries() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: day)?.addingTimeInterval(-1)

        XCTAssertEqual(
            MapMarkerFilter(from: day, to: day).cacheVariant,
            "f0-a0-p0-c\(Int(day.timeIntervalSince1970))-\(Int(endOfDay!.timeIntervalSince1970))"
        )
    }

    // MARK: - Persistence

    func test_codableRoundTrip_keepsEveryField() throws {
        let filter = MapMarkerFilter(
            onlyFavorites: true,
            includeArchived: true,
            withPartners: true,
            relativeDays: 7,
            from: Date(timeIntervalSince1970: 1_700_000_000),
            to: Date(timeIntervalSince1970: 1_700_600_000)
        )
        let data = try JSONEncoder.immich.encode(filter)
        XCTAssertEqual(try JSONDecoder.immich.decode(MapMarkerFilter.self, from: data), filter)
    }
}
