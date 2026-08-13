import Foundation

/// Canonical Immich asset-media URL builders.
enum ImmichAssetURL {

    /// Builds the thumbnail URL for a given asset (AC-007 canonical form).
    /// Format: `{base}/api/assets/{id}/thumbnail?size={size}&c={thumbhash}`
    static func thumbnail(assetId: String, thumbhash: String, baseURL: URL, size: AssetMediaSize = .thumbnail) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(ImmichAPI.assets.path("/\(assetId)/thumbnail")),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "size", value: size.rawValue),
            URLQueryItem(name: "c", value: thumbhash)
        ]
        return components?.url ?? baseURL
    }

    /// Original-file URL for a given asset.
    static func original(assetId: String, baseURL: URL) -> URL {
        baseURL.appendingPathComponent(ImmichAPI.assets.path("/\(assetId)/original"))
    }

    /// Video playback URL (supports Range header on server side).
    static func videoPlayback(assetId: String, baseURL: URL) -> URL {
        baseURL.appendingPathComponent(ImmichAPI.assets.path("/\(assetId)/video/playback"))
    }

    /// Face thumbnail for a person (`GET /api/people/{id}/thumbnail`).
    static func personThumbnail(personId: String, baseURL: URL, size: AssetMediaSize = .thumbnail) -> URL {
        var url = baseURL.appendingPathComponent(ImmichAPI.people.path("/\(personId)/thumbnail"))
        if size != .thumbnail {
            url = url.appending(queryItems: [URLQueryItem(name: "size", value: size.rawValue)])
        }
        return url
    }
}
