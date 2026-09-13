import Foundation

/// Deep link a Home / Lock Screen widget hands to the app (issue #19).
///
/// The URL shape lives in the shared framework on purpose: the widget
/// extension *builds* these links and the app *parses* them, and the two
/// binaries share no other module — `ImmichSharedKit` is the one both link, so
/// the scheme and the destination hosts are defined once here and cannot drift
/// apart. The widget process can hand a URL over but cannot navigate the app;
/// routing a parsed link to a tab is the app's job (`AuthenticatedRoot`).
public enum WidgetDeepLink: Equatable, Sendable {

    /// One timeline asset. `day` is the Immich timeline bucket key the asset
    /// sits in (`2024-07-01T00:00:00.000Z`), not a calendar date: it travels
    /// with the id so the timeline can scroll to an asset that is not loaded
    /// yet — a widget tap may be the first thing that happens on launch.
    case asset(id: String, day: String?)
    case memories
    case backup

    /// Every widget link uses the app's registered URL scheme — the same one
    /// `ASWebAuthenticationSession` answers on, which is why a foreign link on
    /// this scheme must be rejected rather than routed (see `parse`).
    private static let scheme = "app.immich"

    /// Parses an incoming `app.immich://…` URL. Returns nil for anything the
    /// widgets do not own.
    ///
    /// The destination is the URL **host**: `app.immich://asset/xyz` carries
    /// `asset` as host and `/xyz` as path. `pathComponents` cannot stand in for
    /// it — it starts with the separating slash, not with the host.
    public static func parse(_ url: URL) -> WidgetDeepLink? {
        guard url.scheme?.lowercased() == scheme,
              let host = url.host?.lowercased(), !host.isEmpty,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        else { return nil }

        switch host {
        case "asset":
            let id = components.path.split(separator: "/").first.map(String.init) ?? ""
            guard !id.isEmpty else { return nil }
            return .asset(id: id, day: day(from: components))
        case "memories":
            return .memories
        case "backup":
            return .backup
        default:
            // `app.immich:///oauth-callback` lands here: it has an empty host
            // and is consumed by `ASWebAuthenticationSession`, never routed.
            return nil
        }
    }

    /// The URL a widget hands to `widgetURL` for this destination.
    public var url: URL {
        switch self {
        case let .asset(id, day):
            var components = Self.components(host: "asset", path: "/\(id)")
            // A bucket key is a query value, so `URLComponents` percent-encodes
            // whatever the query cannot hold verbatim (`%`, `+`, `*`, …) and
            // `parse` decodes it back — the key survives the trip unchanged.
            if let day {
                components.queryItems = [URLQueryItem(name: "day", value: day)]
            }
            return Self.url(from: components)
        case .memories:
            return Self.url(from: Self.components(host: "memories"))
        case .backup:
            return Self.url(from: Self.components(host: "backup"))
        }
    }

    // MARK: - URL plumbing

    /// The optional `day` query value. An absent or empty one reads as "no
    /// bucket" — the timeline then simply shows the asset where it lands.
    private static func day(from components: URLComponents) -> String? {
        guard let value = components.queryItems?.first(where: { $0.name == "day" })?.value,
              !value.isEmpty
        else { return nil }
        return value
    }

    private static func components(host: String, path: String = "") -> URLComponents {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        return components
    }

    /// `URLComponents.url` is the only real constructor used here and it cannot
    /// fail for these fixed shapes (one scheme, one host, one path segment).
    /// The chain stays optional all the way down instead of force-unwrapping:
    /// a hypothetical failure degrades to a URL `parse` rejects rather than
    /// crashing the widget process that built it.
    private static func url(from components: URLComponents) -> URL {
        components.url
            ?? URL(string: components.string ?? "")
            ?? URL(fileURLWithPath: "/")
    }
}
