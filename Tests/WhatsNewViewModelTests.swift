import XCTest
@testable import ImmichSwiftUI

/// "What's New" (gap G23): the once-per-batch rule and the numeric release
/// comparison it rests on, plus the shape of the embedded catalog.
///
/// Every case runs on a throwaway `UserDefaults` suite — the real key is the
/// user's, and a test that wrote to `.standard` would leak a seen-release into
/// the app under test.
@MainActor
final class WhatsNewViewModelTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: WhatsNewStore!

    override func setUp() {
        super.setUp()
        suiteName = "whats-new-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = WhatsNewStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Seen once per batch

    /// A user who has seen nothing carries "0.0.0", so the very first launch
    /// with a catalog presents the batch.
    func test_shouldShow_whenNothingSeenYet() {
        XCTAssertEqual(store.seenRelease, "0.0.0")
        XCTAssertTrue(store.shouldShow)
        XCTAssertTrue(WhatsNewViewModel(store: store).shouldPresentAutomatically())
    }

    /// The rule has to survive the process: a *new* store and a *new* view model
    /// over the same defaults — what the next launch builds — must answer false.
    /// Asserting on the view model alone would pass on in-memory state.
    func test_shouldShow_isFalse_onceMarked() {
        let vm = WhatsNewViewModel(store: store)
        vm.markSeen()

        let nextLaunchStore = WhatsNewStore(defaults: defaults)
        XCTAssertEqual(nextLaunchStore.seenRelease, FeatureHighlightCatalog.release)
        XCTAssertFalse(nextLaunchStore.shouldShow)
        XCTAssertFalse(WhatsNewViewModel(store: nextLaunchStore).shouldPresentAutomatically())
    }

    /// What is persisted is the catalog's release, not the app version: the
    /// sheet must not come back on every patch build.
    func test_markSeen_writesTheCatalogRelease() {
        store.markSeen()
        XCTAssertEqual(
            defaults.string(forKey: WhatsNewStore.seenReleaseKey),
            FeatureHighlightCatalog.release
        )
    }

    // MARK: - Release comparison

    /// The tenth minor release sorts *below* the ninth as strings. A
    /// lexicographic comparison would silently drop its batch.
    func test_isNewer_isNumericNotLexicographic() {
        XCTAssertTrue("3.10.0" < "3.9.0", "the trap this case exists for")
        XCTAssertTrue(FeatureHighlightCatalog.isNewer("3.10.0", than: "3.9.0"))
        XCTAssertFalse(FeatureHighlightCatalog.isNewer("3.9.0", than: "3.10.0"))
    }

    func test_isNewer_isFalse_forAnOlderOrEqualRelease() {
        XCTAssertFalse(FeatureHighlightCatalog.isNewer("3.0.0", than: "3.0.0"))
        XCTAssertFalse(FeatureHighlightCatalog.isNewer("2.9.9", than: "3.0.0"))
        // Missing components read as zero, not as a failure: "3.0" is "3.0.0".
        XCTAssertFalse(FeatureHighlightCatalog.isNewer("3.0", than: "3.0.0"))
        XCTAssertFalse(FeatureHighlightCatalog.isNewer("3", than: "3.0.0"))
        XCTAssertTrue(FeatureHighlightCatalog.isNewer("3.0.1", than: "3.0.0"))
    }

    // MARK: - The catalog

    func test_catalog_excludesTheAndroidOnlyHighlight() {
        XCTAssertFalse(
            FeatureHighlightCatalog.all.contains { $0.id == "openInImmich" },
            "a card must never advertise a screen this app cannot show"
        )
    }

    func test_catalog_hasNoDuplicateIdentifiers() {
        let ids = FeatureHighlightCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func test_highlights_haveNonEmptyTitleAndBody() {
        XCTAssertFalse(FeatureHighlightCatalog.all.isEmpty)
        for highlight in FeatureHighlightCatalog.all {
            XCTAssertFalse(highlight.id.isEmpty)
            XCTAssertFalse(highlight.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(highlight.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(highlight.systemImage.isEmpty)
        }
    }
}
