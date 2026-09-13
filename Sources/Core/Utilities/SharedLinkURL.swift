import Foundation

/// Public URL of a shared link — ONE builder, used by every surface that shows
/// or copies a link.
///
/// The rule is the server's, mirrored from the Flutter client
/// (`mobile/lib/utils/url_helper.dart`, `buildSharedLinkUrl`) and the web
/// routes `(user)/s/[slug]` and `/share/[key]`:
///
/// * the base is `externalDomain` when the server advertises one, otherwise
///   the server URL the app is connected to — a server behind a reverse proxy
///   is reached through its public domain, not its internal address;
/// * the path is `s/<slug>` when the link carries a custom slug, otherwise
///   `share/<key>`.
///
/// The app used to hardcode `share/<key>` in two places, which produced a dead
/// link for any link carrying a slug, and for any proxied server (the
/// onboarding screen already displayed `externalDomain`, so the field was known
/// but unused).
struct SharedLinkURL: Equatable, Sendable {
    /// Server URL the app is connected to. Used when `externalDomain` is empty.
    let serverURL: URL
    /// `ServerConfigDto.externalDomain` — empty when the admin did not set one.
    let externalDomain: String

    init(serverURL: URL, externalDomain: String = "") {
        self.serverURL = serverURL
        self.externalDomain = externalDomain
    }

    /// Base actually used for links: the external domain when the server
    /// advertises one, the server URL otherwise. Trailing slashes are dropped
    /// so joining a path never doubles a separator; a domain without a scheme
    /// is taken as HTTPS (the admin UI accepts a bare host).
    var baseURL: URL {
        let domain = externalDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty else { return serverURL }

        var trimmed = domain
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return url
        }
        return URL(string: "https://\(trimmed)") ?? serverURL
    }

    /// The link's public URL. A slug always wins over the key — that is the
    /// point of a custom slug — and `key` is the `SharedLinkResponseDto.key`.
    func url(slug: String?, key: String) -> URL {
        let slugged = slug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let path = slugged.isEmpty ? "share/\(key)" : "s/\(slugged)"
        return baseURL.appendingPathComponent(path)
    }

    /// Same URL as a string, for the pasteboard and the share sheet.
    func urlString(slug: String?, key: String) -> String {
        url(slug: slug, key: key).absoluteString
    }
}
