import Foundation
import Photos

/// Abstraction over PHPhotoLibrary for backup / upload workflows.
protocol PhotoLibraryService: AnyObject, Sendable {
    func authorizationStatus() -> PHAuthorizationStatus
    func requestAuthorization(_ handler: @escaping (PHAuthorizationStatus) -> Void)

    /// Enumerates assets in the user's library (ordered by creation date desc).
    func fetchAssets() -> [PHAsset]

    /// Loads full-resolution data for a PHAsset.
    func loadData(for asset: PHAsset) async throws -> Data

    /// SHA1 of file bytes, base64-encoded (for `x-immich-checksum`).
    func checksum(for asset: PHAsset) async throws -> String

    /// Creation + modification timestamps formatted as ISO8601 `yyyy-MM-dd'T'HH:mm:ss.SSSZ`.
    func isoTimestamps(for asset: PHAsset) -> (createdAt: String, modifiedAt: String)
}
