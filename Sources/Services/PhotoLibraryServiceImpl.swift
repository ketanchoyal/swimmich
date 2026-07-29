import Foundation
import Photos
import CryptoKit
import UIKit
import os

/// PHPhotoLibrary-backed implementation of PhotoLibraryService.
final class PhotoLibraryServiceImpl: PhotoLibraryService, @unchecked Sendable {
    func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization(_ handler: @escaping (PHAuthorizationStatus) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { handler($0) }
    }

    func fetchAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    func loadData(for asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.version = .current

            // PHImageManager may invoke the handler more than once (progressive
            // delivery). Guard against double-resume (which would crash).
            let resumeGate = OSAllocatedUnfairLock(initialState: false)
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                let alreadyResumed = resumeGate.withLock { locked -> Bool in
                    if locked { return true }
                    locked = true
                    return false
                }
                guard !alreadyResumed else { return }

                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: APIError.decoding("Unable to load PHAsset data"))
                }
            }
        }
    }

    func checksum(for asset: PHAsset) async throws -> String {
        let data = try await loadData(for: asset)
        let digest = Insecure.SHA1.hash(data: data)
        return Data(digest).base64EncodedString()
    }

    func isoTimestamps(for asset: PHAsset) -> (createdAt: String, modifiedAt: String) {
        let created = asset.creationDate ?? Date()
        let modified = asset.modificationDate ?? created
        let createdAt = ISO8601.immichFormatter.string(from: created)
        let modifiedAt = ISO8601.immichFormatter.string(from: modified)
        return (createdAt, modifiedAt)
    }
}
