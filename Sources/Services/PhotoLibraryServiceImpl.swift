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

    func saveImage(data: Data) async throws -> String {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("immich-save-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("image.\(Self.imageExtension(for: data))")
        try data.write(to: fileURL, options: .atomic)

        var identifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            identifier = request?.placeholderForCreatedAsset?.localIdentifier
        }
        guard let identifier else {
            throw APIError.decoding("Photos save returned no local identifier")
        }
        return identifier
    }

    /// Sniffs the leading bytes for a HEIC/HEIF brand; anything else gets the
    /// safe `jpg` extension (Photos re-detects the actual content type).
    private static func imageExtension(for data: Data) -> String {
        let head = String(data: data.prefix(16), encoding: .ascii) ?? ""
        if head.contains("ftypheic") || head.contains("ftypheix") || head.contains("ftypmif1") {
            return "heic"
        }
        return "jpg"
    }

    func saveVideo(at fileURL: URL) async throws -> String {
        var identifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            identifier = request?.placeholderForCreatedAsset?.localIdentifier
        }
        guard let identifier else {
            throw APIError.decoding("Photos save returned no local identifier")
        }
        return identifier
    }
}

// MARK: - BackupAssetSource

extension PhotoLibraryServiceImpl: BackupAssetSource {
    /// User albums (name + count), sorted by localized title. Smart albums
    /// ("Recents") are excluded — backups target user albums only.
    func fetchAlbums() -> [BackupAlbum] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "localizedTitle", ascending: true)]
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
        var albums: [BackupAlbum] = []
        albums.reserveCapacity(collections.count)
        collections.enumerateObjects { collection, _, _ in
            guard let name = collection.localizedTitle, !name.isEmpty else { return }
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            albums.append(BackupAlbum(id: collection.localIdentifier, name: name, count: assets.count))
        }
        return albums
    }

    /// All library assets (creation date DESC), or the union of the selected
    /// albums. Assets in multiple albums dedupe by localIdentifier. The
    /// "Screenshots" album is dropped when the engine requests it.
    func fetchCandidates(in albumIDs: Set<String>) -> [BackupCandidate] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        var samplers: [PHAsset] = []
        if albumIDs.isEmpty {
            let result = PHAsset.fetchAssets(with: options)
            result.enumerateObjects { asset, _, _ in samplers.append(asset) }
        } else {
            var seen = Set<ObjectIdentifier>()
            for albumID in albumIDs {
                guard let collection = PHAssetCollection.fetchAssetCollections(
                    withLocalIdentifiers: [albumID], options: nil
                ).firstObject else { continue }
                let result = PHAsset.fetchAssets(in: collection, options: options)
                result.enumerateObjects { asset, _, _ in
                    if seen.insert(ObjectIdentifier(asset)).inserted { samplers.append(asset) }
                }
            }
        }
        return samplers.compactMap(makeCandidate)
    }

    func loadData(for candidate: BackupCandidate) async throws -> Data {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [candidate.id], options: nil).firstObject else {
            throw APIError.decoding("PHAsset not found for \(candidate.id)")
        }
        return try await loadData(for: asset)
    }

    /// Maps a PHAsset to its value-typed candidate. Local albums are resolved
    /// per-asset (first album match carries the album name; "Screenshots" is
    /// the convention the engine filters on).
    private func makeCandidate(_ asset: PHAsset) -> BackupCandidate? {
        let kind: BackupAssetKind = asset.mediaType == .video ? .video : .image
        let timestamps = isoTimestamps(for: asset)
        let resources = PHAssetResource.assetResources(for: asset)
        let originalName = resources.first(where: { $0.type == .photo || $0.type == .video })?.originalFilename
        return BackupCandidate(
            id: asset.localIdentifier,
            kind: kind,
            fileName: originalName ?? (kind == .video ? "Video" : "Photo"),
            fileCreatedAt: timestamps.createdAt,
            fileModifiedAt: timestamps.modifiedAt,
            duration: kind == .video ? Int(max(0, asset.duration)) : nil,
            isFavorite: asset.isFavorite,
            albumName: assetAlbumName(asset)
        )
    }

    /// First enclosing user album name (used to filter "Screenshots").
    private func assetAlbumName(_ asset: PHAsset) -> String? {
        let result = PHAssetCollection.fetchAssetCollectionsContaining(
            asset, with: .album, options: nil
        )
        for i in 0..<result.count {
            let collection = result.object(at: i)
            guard let name = collection.localizedTitle, !name.isEmpty else { continue }
            return name
        }
        return nil
    }
}
