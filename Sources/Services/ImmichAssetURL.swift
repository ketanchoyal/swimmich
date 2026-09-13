import Foundation

/// Canonical Immich asset-media URL builders.
enum ImmichAssetURL {

    /// Builds the thumbnail URL for a given asset (AC-007 canonical form).
    /// Format: `{base}/api/assets/{id}/thumbnail?size={size}&c={thumbhash}`
    ///
    /// `sharedLink` adds the visitor's `key`/`slug` query item: a public link is
    /// read without a bearer token, and that credential is what the server
    /// authenticates the request with (`AuthService.validate`). Asking for
    /// `size=fullsize` on a shared link is safe — `AssetMediaService.viewThumbnail`
    /// forces `edited = true` for shared-link auth, which skips the redirect to
    /// `original` (a route needing `AssetDownload`, which a link may not grant).
    static func thumbnail(
        assetId: String,
        thumbhash: String,
        baseURL: URL,
        size: AssetMediaSize = .thumbnail,
        sharedLink: SharedLinkCredential? = nil
    ) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(ImmichAPI.assets.path("/\(assetId)/thumbnail")),
            resolvingAgainstBaseURL: false
        )
        var items = [
            URLQueryItem(name: "size", value: size.rawValue),
            URLQueryItem(name: "c", value: thumbhash)
        ]
        if let sharedLink { items.append(sharedLink.queryItem) }
        components?.queryItems = items
        return components?.url ?? baseURL
    }

    /// Original-file URL for a given asset.
    static func original(assetId: String, baseURL: URL, sharedLink: SharedLinkCredential? = nil) -> URL {
        var url = baseURL.appendingPathComponent(ImmichAPI.assets.path("/\(assetId)/original"))
        if let sharedLink { url.append(queryItems: [sharedLink.queryItem]) }
        return url
    }

    /// Video playback URL (supports Range header on server side).
    static func videoPlayback(assetId: String, baseURL: URL, sharedLink: SharedLinkCredential? = nil) -> URL {
        var url = baseURL.appendingPathComponent(ImmichAPI.assets.path("/\(assetId)/video/playback"))
        if let sharedLink { url.append(queryItems: [sharedLink.queryItem]) }
        return url
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
