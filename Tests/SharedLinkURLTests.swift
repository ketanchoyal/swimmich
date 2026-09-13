import XCTest
@testable import ImmichSwiftUI

/// The public URL of a shared link — the bug this suite guards.
///
/// The app used to hardcode `/share/<key>` and ignore both the link's slug and
/// the server's `externalDomain`, which produced a dead link for every sluzzed
/// link and for every server behind a reverse proxy (the onboarding screen
/// already displayed `externalDomain`, so the field was known but unused).
/// Reference: Flutter `mobile/lib/utils/url_helper.dart` `buildSharedLinkUrl`,
/// and the web routes `(user)/s/[slug]` / `/share/[key]`.
final class SharedLinkURLTests: XCTestCase {

    private let server = URL(string: "https://immich.local:2283")!

    func test_slugWinsOverKey() {
        let base = SharedLinkURL(serverURL: server)
        XCTAssertEqual(
            base.urlString(slug: "trip-2026", key: "a2V5"),
            "https://immich.local:2283/s/trip-2026"
        )
    }

    func test_noSlugFallsBackToTheSharePath() {
        let base = SharedLinkURL(serverURL: server)
        XCTAssertEqual(base.urlString(slug: nil, key: "a2V5"), "https://immich.local:2283/share/a2V5")
        // A blank slug is not a slug — the server stores `dto.slug || null`.
        XCTAssertEqual(base.urlString(slug: "   ", key: "a2V5"), "https://immich.local:2283/share/a2V5")
    }

    func test_externalDomainTakesPrecedenceOverTheServerURL() {
        let base = SharedLinkURL(serverURL: server, externalDomain: "https://photos.example.com")
        XCTAssertEqual(base.baseURL.absoluteString, "https://photos.example.com")
        XCTAssertEqual(
            base.urlString(slug: "trip-2026", key: "a2V5"),
            "https://photos.example.com/s/trip-2026"
        )
        XCTAssertEqual(
            base.urlString(slug: nil, key: "a2V5"),
            "https://photos.example.com/share/a2V5"
        )
    }

    func test_emptyExternalDomainUsesTheServerURL() {
        let base = SharedLinkURL(serverURL: server, externalDomain: "")
        XCTAssertEqual(base.baseURL, server)
        // Whitespace is not a domain either — the server sends "" when the
        // admin left the field empty.
        let blank = SharedLinkURL(serverURL: server, externalDomain: "   ")
        XCTAssertEqual(blank.baseURL, server)
    }

    func test_externalDomainIsNormalised() {
        // A trailing slash must not double the separator…
        let slashed = SharedLinkURL(serverURL: server, externalDomain: "https://photos.example.com/")
        XCTAssertEqual(
            slashed.urlString(slug: nil, key: "a2V5"),
            "https://photos.example.com/share/a2V5"
        )
        // …and a bare host (what the admin UI accepts) becomes HTTPS.
        let bare = SharedLinkURL(serverURL: server, externalDomain: "photos.example.com")
        XCTAssertEqual(
            bare.urlString(slug: nil, key: "a2V5"),
            "https://photos.example.com/share/a2V5"
        )
    }
}
