import Foundation

/// The server's `Permission` enum (`components.schemas.Permission` in the
/// published OpenAPI document), regenerated rather than transcribed:
///
///     jq -r '.components.schemas.Permission.enum[]' /tmp/immich-openapi-main.json
///
/// A value missing here is a scope the server accepts and the picker cannot
/// grant, so this list is data from the document, never a curated subset.
///
/// Pure data plus two projections — the screen never walks `key.permissions`
/// itself, so the grouping and the summary live in one place.
enum APIKeyPermission {

    /// `"all"` — the wildcard: granting it makes every other value redundant.
    static let allPermission = "all"

    /// The server enum, in the order the document lists it (`all` first, then
    /// one block per resource).
    static let allValues: [String] = [
        "all",
        "activity.create",
        "activity.read",
        "activity.update",
        "activity.delete",
        "activity.statistics",
        "apiKey.create",
        "apiKey.read",
        "apiKey.update",
        "apiKey.delete",
        "apiKey.rotate",
        "asset.read",
        "asset.update",
        "asset.delete",
        "asset.statistics",
        "asset.share",
        "asset.view",
        "asset.download",
        "asset.upload",
        "asset.copy",
        "asset.derive",
        "assetFile.read",
        "assetFile.delete",
        "assetFile.download",
        "asset.edit.get",
        "asset.edit.create",
        "asset.edit.delete",
        "album.create",
        "album.read",
        "album.update",
        "album.delete",
        "album.statistics",
        "album.share",
        "album.download",
        "albumAsset.create",
        "albumAsset.delete",
        "albumUser.create",
        "albumUser.update",
        "albumUser.delete",
        "auth.changePassword",
        "authDevice.delete",
        "archive.read",
        "backup.list",
        "backup.download",
        "backup.upload",
        "backup.delete",
        "clusterGroup.read",
        "clusterGroup.leave",
        "clusterGroupRequest.create",
        "clusterGroupRequest.read",
        "clusterGroupRequest.delete",
        "adminConfig.read",
        "adminConfig.update",
        "userConfig.read",
        "duplicate.read",
        "duplicate.delete",
        "face.create",
        "face.read",
        "face.update",
        "face.delete",
        "folder.read",
        "job.create",
        "job.read",
        "library.create",
        "library.read",
        "library.update",
        "library.delete",
        "library.statistics",
        "timeline.read",
        "timeline.download",
        "maintenance",
        "map.read",
        "map.search",
        "memory.create",
        "memory.read",
        "memory.update",
        "memory.delete",
        "memory.statistics",
        "memoryAsset.create",
        "memoryAsset.delete",
        "notification.create",
        "notification.read",
        "notification.update",
        "notification.delete",
        "partner.create",
        "partner.read",
        "partner.update",
        "partner.delete",
        "person.create",
        "person.read",
        "person.update",
        "person.delete",
        "person.statistics",
        "person.merge",
        "person.reassign",
        "pinCode.create",
        "pinCode.update",
        "pinCode.delete",
        "plugin.create",
        "plugin.read",
        "plugin.update",
        "plugin.delete",
        "server.about",
        "server.apkLinks",
        "server.storage",
        "server.statistics",
        "server.versionCheck",
        "serverLicense.read",
        "serverLicense.update",
        "serverLicense.delete",
        "session.create",
        "session.read",
        "session.update",
        "session.delete",
        "session.lock",
        "sharedLink.create",
        "sharedLink.read",
        "sharedLink.update",
        "sharedLink.delete",
        "stack.create",
        "stack.read",
        "stack.update",
        "stack.delete",
        "sync.stream",
        "syncCheckpoint.read",
        "syncCheckpoint.update",
        "syncCheckpoint.delete",
        "systemConfig.read",
        "systemConfig.update",
        "systemMetadata.read",
        "systemMetadata.update",
        "tag.create",
        "tag.read",
        "tag.update",
        "tag.delete",
        "tag.asset",
        "user.read",
        "user.update",
        "userLicense.create",
        "userLicense.read",
        "userLicense.update",
        "userLicense.delete",
        "userOnboarding.read",
        "userOnboarding.update",
        "userOnboarding.delete",
        "userPreference.read",
        "userPreference.update",
        "userProfileImage.create",
        "userProfileImage.read",
        "userProfileImage.update",
        "userProfileImage.delete",
        "queue.read",
        "queue.update",
        "queueJob.create",
        "queueJob.read",
        "queueJob.update",
        "queueJob.delete",
        "workflow.create",
        "workflow.read",
        "workflow.update",
        "workflow.delete",
        "workflow.logs",
        "adminUser.create",
        "adminUser.read",
        "adminUser.update",
        "adminUser.delete",
        "adminSession.read",
        "adminAuth.unlinkAll",
    ]

    /// The picker's sections: one per category — the segment before the first
    /// `.` — in the order the document first mentions it, so the list does not
    /// reshuffle between two launches. `all` and `maintenance` carry no dot and
    /// share the `general` group.
    static var grouped: [(category: String, items: [String])] {
        var order: [String] = []
        var items: [String: [String]] = [:]
        for value in allValues {
            let category = value.contains(".")
                ? String(value.prefix(while: { $0 != "." }))
                : "general"
            if items[category] == nil { order.append(category) }
            items[category, default: []].append(value)
        }
        return order.map { ($0, items[$0] ?? []) }
    }

    /// `"Full access"` under the wildcard, otherwise how many scopes the key
    /// carries. The key itself is the catalog key, with `%lld` for the count.
    static func summary(for permissions: [String]) -> String {
        if permissions.contains(allPermission) { return String(localized: "Full access") }
        return String(localized: "\(permissions.count) permissions")
    }
}
