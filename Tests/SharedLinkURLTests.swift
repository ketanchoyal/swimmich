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

    // MARK: - Reading a link someone sent you (issue #22)

    /// The server's own key format: 50 random bytes, base64url — the shape is
    /// what lets a pasted token be read as a key rather than a slug.
    private let key = "wJalrXUtnFEMI7K7MDENGbPxRfiCYEXAMPLEKEY_0123456789-abcdef"

    func test_reference_readsTheKeyFromASharePath() {
        XCTAssertEqual(
            SharedLinkURL.reference(from: "https://photos.example.com/share/\(key)"),
            .init(host: "photos.example.com", credential: .key(key))
        )
    }

    func test_reference_readsTheSlugFromAnSPath() {
        XCTAssertEqual(
            SharedLinkURL.reference(from: "https://photos.example.com/s/trip-2026"),
            .init(host: "photos.example.com", credential: .slug("trip-2026"))
        )
    }

    /// A slug always wins on the server side too (`Route.viewSharedLink`), so a
    /// path that carries both markers is read by its first one.
    func test_reference_takesTheFirstMarkerSegments() {
        XCTAssertEqual(
            SharedLinkURL.reference(from: "https://photos.example.com/s/trip-2026/photos")?.credential,
            .slug("trip-2026")
        )
    }

    /// What a chat app hands over when the scheme got lost on copy.
    func test_reference_acceptsASchemeLessLink() {
        XCTAssertEqual(
            SharedLinkURL.reference(from: "photos.example.com/s/trip-2026"),
            .init(host: "photos.example.com", credential: .slug("trip-2026"))
        )
    }

    /// A bare pasted token: long base64url is the key, a short word is a slug.
    func test_reference_disambiguatesABareToken() {
        XCTAssertEqual(SharedLinkURL.reference(from: key), .init(host: nil, credential: .key(key)))
        XCTAssertEqual(SharedLinkURL.reference(from: " trip-2026 "), .init(host: nil, credential: .slug("trip-2026")))
        // A slug that happens to be long but is not base64url is still a slug.
        XCTAssertEqual(
            SharedLinkURL.reference(from: String(repeating: "a", count: 48) + "!")?.credential,
            .slug(String(repeating: "a", count: 48) + "!")
        )
    }

    func test_reference_rejectsTextWithoutACredential() {
        XCTAssertNil(SharedLinkURL.reference(from: ""))
        XCTAssertNil(SharedLinkURL.reference(from: "   "))
        XCTAssertNil(SharedLinkURL.reference(from: "https://photos.example.com/"))
        XCTAssertNil(SharedLinkURL.reference(from: "https://photos.example.com/albums/123"))
        XCTAssertNil(SharedLinkURL.reference(from: "photos.example.com"))
    }
}
