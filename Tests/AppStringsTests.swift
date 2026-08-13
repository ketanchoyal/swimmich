import XCTest
@testable import ImmichSwiftUI

/// Guard tests for the string catalog (P5 i18n-catalog): the catalog must stay
/// a valid, growing JSON document and carry the FR translations for the
/// top-level navigation labels.
final class AppStringsTests: XCTestCase {

    private static var repoRoot: URL {
        // Tests run from the DerivedData build dir; walk up to the repo root
        // via the project file that always lives at the root.
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("project.yml").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return url
    }

    private static func loadCatalog() throws -> [String: Any] {
        let path = repoRoot.appendingPathComponent("Resources/Localizable.xcstrings").path
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try XCTUnwrap(object)
    }

    func test_catalog_isValidJSONWithExpectedSize() throws {
        let catalog = try Self.loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        XCTAssertGreaterThanOrEqual(strings.count, 196, "Catalog must keep growing")
    }

    func test_catalog_tabBarKeysHaveFrenchTranslations() throws {
        let catalog = try Self.loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        for key in ["Photos", "Memories", "Albums", "People", "Shared", "Me", "Search"] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], "Missing tab key \(key)")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], "No localizations for \(key)")
            XCTAssertNotNil(localizations["fr"], "Missing French translation for \(key)")
        }
    }

    func test_catalog_englishSourceKeysCarryFrench() throws {
        let catalog = try Self.loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let enOnly = strings.filter { key, value in
            guard let entry = value as? [String: Any],
                  let locs = entry["localizations"] as? [String: Any] else { return false }
            return locs["en"] != nil && locs["fr"] == nil
        }
        // Remaining en-only keys are format placeholders or French-source copy.
        XCTAssertLessThanOrEqual(enOnly.count, 24)
    }

    func test_catalog_memoryCardKeysHaveFrenchTranslations() throws {
        let catalog = try Self.loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let keys = [
            "Couldn't load memories", "Last year", "%lld years ago",
            "1 photo", "%lld photos", "1 video", "%lld videos", "+%lld more",
            "Memory photo from %lld"
        ]
        for key in keys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], "Missing memory key \(key)")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], "No localizations for \(key)")
            XCTAssertNotNil(localizations["fr"], "Missing French translation for \(key)")
        }
    }
}
