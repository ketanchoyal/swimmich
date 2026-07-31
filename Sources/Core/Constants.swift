import Foundation

/// API path constants and helpers shared across the app.
enum ImmichAPI {
    static let apiPath = "/api"

    static let auth = SubPath(root: "/auth")
    static let server = SubPath(root: "/server")
    static let assets = SubPath(root: "/assets")
    static let timeline = SubPath(root: "/timeline")
    static let trash = SubPath(root: "/trash") // AC-311
    static let search = SubPath(root: "/search") // AC-400
    static let map = SubPath(root: "/map") // AC-710 (MapKit markers)
    static let people = SubPath(root: "/people") // AC-400 (deferred People feature)
    static let albums = SubPath(root: "/albums") // AC-500
    static let sharedLinks = SubPath(root: "/shared-links") // AC-500

    struct SubPath {
        let root: String
        func path(_ suffix: String) -> String { apiPath + root + suffix }
    }

    /// Header used for SHA1 checksum dedup on uploads + bulk-upload-check.
    static let checksumHeader = "x-immich-checksum"
}

enum ImmichHeader {
    static let authorization = "Authorization"
    static let contentType = "Content-Type"
    static let accept = "Accept"
    static let checksum = "x-immich-checksum"
}

enum AssetMediaSize: String {
    case thumbnail
    case preview
    case fullsize
}

enum AssetVisibility: String, Codable, CaseIterable, Sendable {
    case archive
    case timeline
    case hidden
    case locked
}

enum AssetType: String, Codable, Sendable {
    case image = "IMAGE"
    case video = "VIDEO"
    case audio = "AUDIO"
    case other = "OTHER"
}

enum AssetOrder: String, Codable, Sendable {
    case asc
    case desc
}

enum AssetOrderBy: String, Codable, Sendable {
    case takenAt
    case createdAt
}
