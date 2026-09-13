import XCTest
@testable import ImmichSwiftUI

/// The widget deep links (issue #19): the URL shape the Home Screen widgets
/// hand over and the app routes.
///
/// Two things can break here silently. The round trip through `URLComponents`
/// — a timeline bucket key is a query value and must come back byte-for-byte,
/// or the timeline is primed with a day no asset belongs to. And the links the
/// app must NOT swallow: the OAuth callback shares this scheme but belongs to
/// `ASWebAuthenticationSession`, so routing it would be a regression on a flow
/// that has nothing to do with widgets.
final class WidgetDeepLinkTests: XCTestCase {

    // MARK: - Round trip (what a widget builds is what the app parses)

    func test_url_assetWithDayRoundTrips() {
        let link = WidgetDeepLink.asset(id: "abc", day: "2024-07-01T00:00:00.000Z")

        XCTAssertEqual(WidgetDeepLink.parse(link.url), link)
    }

    func test_url_assetWithoutDayRoundTrips() {
        let link = WidgetDeepLink.asset(id: "abc", day: nil)

        XCTAssertEqual(WidgetDeepLink.parse(link.url), link)
    }

    /// The bucket key is percent-encoded by the builder: characters a raw query
    /// string would mangle (`+`, `%`, `*`) have to survive the trip.
    func test_url_assetKeepsReservedCharactersInTheBucketKey() {
        let day = "2024-07-01T00:00:00.000+02:00%*"

        XCTAssertEqual(
            WidgetDeepLink.parse(WidgetDeepLink.asset(id: "abc", day: day).url),
            .asset(id: "abc", day: day)
        )
    }

    func test_url_memoriesRoundTrips() {
        XCTAssertEqual(WidgetDeepLink.parse(WidgetDeepLink.memories.url), .memories)
    }

    func test_url_backupRoundTrips() {
        XCTAssertEqual(WidgetDeepLink.parse(WidgetDeepLink.backup.url), .backup)
    }

    /// `ImmichHomeWidget` hands over its own literal string — the app has to
    /// read exactly that, not only whatever this enum would build.
    func test_parse_readsTheLiteralShapesTheWidgetsSend() {
        XCTAssertEqual(WidgetDeepLink.parse(URL(string: "app.immich://backup")!), .backup)
        XCTAssertEqual(
            WidgetDeepLink.parse(URL(string: "app.immich://asset/1f2e3d?day=2024-07-01T00:00:00.000Z")!),
            .asset(id: "1f2e3d", day: "2024-07-01T00:00:00.000Z")
        )
    }

    // MARK: - Links the widgets do not own

    func test_parse_oauthCallbackIsNotAWidgetLink() {
        XCTAssertNil(WidgetDeepLink.parse(URL(string: "app.immich:///oauth-callback")!))
    }

    func test_parse_unknownHostIsNotAWidgetLink() {
        XCTAssertNil(WidgetDeepLink.parse(URL(string: "app.immich://unknown/xyz")!))
    }

    func test_parse_foreignSchemeIsNotAWidgetLink() {
        XCTAssertNil(WidgetDeepLink.parse(URL(string: "https://example.com/asset/xyz")!))
    }

    func test_parse_assetWithoutAnIDIsNotAWidgetLink() {
        XCTAssertNil(WidgetDeepLink.parse(URL(string: "app.immich://asset")!))
        XCTAssertNil(WidgetDeepLink.parse(URL(string: "app.immich://asset/")!))
        XCTAssertNil(WidgetDeepLink.parse(URL(string: "app.immich://asset?day=2024-07-01T00:00:00.000Z")!))
    }

    // MARK: - Shapes the widgets do not spell out

    /// An empty `day` is not a bucket key — reading it as one would prime the
    /// timeline with an empty day instead of leaving it alone.
    func test_parse_emptyDayReadsAsNoDay() {
        XCTAssertEqual(
            WidgetDeepLink.parse(URL(string: "app.immich://asset/xyz?day=")!),
            .asset(id: "xyz", day: nil)
        )
    }

    /// Hosts and schemes are matched case-insensitively (a URL's scheme may
    /// keep the case it was written with).
    func test_parse_isCaseInsensitiveOnTheSchemeAndHost() {
        XCTAssertEqual(WidgetDeepLink.parse(URL(string: "APP.IMMICH://memories")!), .memories)
    }

    /// A trailing slash is not part of a destination.
    func test_parse_trailingSlashIsIgnored() {
        XCTAssertEqual(WidgetDeepLink.parse(URL(string: "app.immich://memories/")!), .memories)
        XCTAssertEqual(
            WidgetDeepLink.parse(URL(string: "app.immich://asset/xyz/")!),
            .asset(id: "xyz", day: nil)
        )
    }
}
