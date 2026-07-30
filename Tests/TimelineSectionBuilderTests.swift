import XCTest
@testable import ImmichSwiftUI

final class TimelineSectionBuilderTests: XCTestCase {

    /// Builds an `AssetReactItem` with sane defaults; only `id` + `fileCreatedAt`
    /// matter for the section builder (everything else is irrelevant to month
    /// interleaving).
    private func item(id: String) -> AssetReactItem {
        AssetReactItem(
            id: id, ownerId: "owner", ratio: 1.0, isFavorite: false,
            visibility: "timeline", isTrashed: false, isImage: true,
            thumbhash: nil, createdAt: "2024-07-01T00:00:00.000Z",
            fileCreatedAt: "2024-07-01T00:00:00.000Z", localOffsetHours: 0,
            duration: nil, livePhotoVideoId: nil, projectionType: nil,
            city: nil, country: nil, latitude: nil, longitude: nil
        )
    }

    // AC-N02 case (a): empty input → empty output.
    func test_build_emptyInput_returnsEmpty() {
        let sections = TimelineSectionBuilder.build(from: [])
        XCTAssertTrue(sections.isEmpty, "Empty groupedByDay must produce no sections")
    }

    // AC-N02 case (b): single day → exactly one monthHeader + one dayGroup, in order.
    func test_build_singleDay_emitsHeaderThenGroup() {
        let groups = [(day: "2024-07-15", items: [item(id: "a1"), item(id: "a2")])]
        let sections = TimelineSectionBuilder.build(from: groups)

        XCTAssertEqual(sections.count, 2)
        guard case .monthHeader(let month, _) = sections[0] else {
            return XCTFail("First section must be a monthHeader")
        }
        XCTAssertEqual(month, "2024-07")
        guard case .dayGroup(let day, let items) = sections[1] else {
            return XCTFail("Second section must be a dayGroup")
        }
        XCTAssertEqual(day, "2024-07-15")
        XCTAssertEqual(items.count, 2)
    }

    // AC-N02 case (c): multiple days in same month → ONE monthHeader, then each dayGroup.
    func test_build_sameMonth_singleHeaderMultipleDayGroups() {
        let groups = [
            (day: "2024-07-29", items: [item(id: "a1")]),
            (day: "2024-07-15", items: [item(id: "a2")]),
            (day: "2024-07-01", items: [item(id: "a3")])
        ]
        let sections = TimelineSectionBuilder.build(from: groups)

        // 1 monthHeader + 3 dayGroups = 4 sections
        XCTAssertEqual(sections.count, 4)
        guard case .monthHeader(let month, _) = sections[0] else {
            return XCTFail("First section must be a monthHeader")
        }
        XCTAssertEqual(month, "2024-07")

        // No other monthHeader should appear.
        let monthHeaderCount = sections.filter {
            if case .monthHeader = $0 { return true }
            return false
        }.count
        XCTAssertEqual(monthHeaderCount, 1, "Exactly one monthHeader per contiguous month run")
    }

    // AC-N02 case (d): days across months → monthHeader interleaved at each month change.
    func test_build_multipleMonths_interleavesHeaders() {
        let groups = [
            (day: "2024-07-29", items: [item(id: "a1")]),
            (day: "2024-07-01", items: [item(id: "a2")]),
            (day: "2024-06-15", items: [item(id: "a3")]),
            (day: "2024-05-01", items: [item(id: "a4")])
        ]
        let sections = TimelineSectionBuilder.build(from: groups)

        // Expected order (day-descending input → 3 monthHeaders + 4 dayGroups = 7):
        // [.month(2024-07), .day(2024-07-29), .day(2024-07-01),
        //  .month(2024-06), .day(2024-06-15),
        //  .month(2024-05), .day(2024-05-01)]
        XCTAssertEqual(sections.count, 7)

        let months = sections.compactMap { section -> String? in
            if case .monthHeader(let month, _) = section { return month }
            return nil
        }
        XCTAssertEqual(months, ["2024-07", "2024-06", "2024-05"])
    }

    // AC-N02 case (e): month display string is non-empty and contains the year.
    func test_build_monthHeaderDisplayContainsYear() {
        let groups = [(day: "2024-07-15", items: [item(id: "a1")])]
        let sections = TimelineSectionBuilder.build(from: groups)

        guard case .monthHeader(_, let display) = sections[0] else {
            return XCTFail("Expected a monthHeader")
        }
        XCTAssertFalse(display.isEmpty, "Display string must not be empty")
        XCTAssertTrue(display.contains("2024"), "Display must contain the year, got: \(display)")
    }

    // AC-N02 case (f): ids are unique and stable (ForEach identity).
    func test_build_sectionIds_uniqueAndStable() {
        let groups = [
            (day: "2024-07-29", items: [item(id: "a1")]),
            (day: "2024-06-15", items: [item(id: "a2")])
        ]
        let sections = TimelineSectionBuilder.build(from: groups)
        let ids = sections.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Section ids must be unique")
    }
}
