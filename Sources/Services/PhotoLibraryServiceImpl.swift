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
        try await timeoutLoadData(for: asset)
    }

    /// Hard deadline for the original-data request. The PHImageManager
    /// callback can never arrive for an iCloud-only asset whose download
    /// hangs — an unresumed continuation leaves the backup engine parked in
    /// "Checking library…" forever (infinite UI, unresponsive Cancel).
    /// Whichever wins the race resumes: the data handler, task
    /// cancellation, or this deadline (which also cancels the PH request).
    private func timeoutLoadData(for asset: PHAsset) async throws -> Data {
        let loader = PHImageManager.default()
        let gate = LoadGate()
        let request = loader.requestImageDataAndOrientation(for: asset, options: makeLoadOptions()) { data, _, _, info in
            if let data {
                gate.finish(with: .success(data))
            } else {
                let underlying = info?[PHImageErrorKey] as? Error
                gate.finish(with: .failure(underlying ?? APIError.decoding("Unable to load PHAsset data")))
            }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.loadTimeoutSeconds) {
            loader.cancelImageRequest(request)
            gate.finish(with: .failure(APIError.decoding("Asset download timed out — it will be retried on the next run")))
        }
        return try await withTaskCancellationHandler {
            try await gate.value
        } onCancel: {
            loader.cancelImageRequest(request)
            gate.finish(with: .failure(APIError.decoding("Asset download cancelled — it will be retried on the next run")))
        }
    }

    /// Single-delivery resume token — the data handler, the deadline timer
    /// and task cancellation race to finish the load; the first wins, the
    /// rest no-op.
    private final class LoadGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data, Error>?

        var value: Data {
            get async throws {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    lock.lock()
                    self.continuation = continuation
                    lock.unlock()
                }
            }
        }

        func finish(with result: Result<Data, Error>) {
            lock.lock()
            let cont = continuation
            continuation = nil
            lock.unlock()
            if let cont { cont.resume(with: result) }
        }
    }

    /// Max wait for one asset's original data (iCloud download). A
    /// candidate that misses the window counts as failed and is retried on
    /// the next run — bounds "Checking library…" to at worst library ×
    /// interval instead of potentially infinite.
    private static let loadTimeoutSeconds: TimeInterval = 90

    private func makeLoadOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.version = .current
        return options
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

    /// Streams the asset's original resource to a temp file on disk (never a
    /// full `Data` in memory). `isNetworkAccessAllowed` lets iCloud-only
    /// originals download; a deadline guards against a hung download, matching
    /// `loadData`'s timeout policy.
    func exportOriginal(for candidate: BackupCandidate) async throws -> URL {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [candidate.id], options: nil).firstObject else {
            throw APIError.decoding("PHAsset not found for \(candidate.id)")
        }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .photo || $0.type == .video })
            ?? resources.first(where: { $0.type == .fullSizePhoto || $0.type == .fullSizeVideo })
            ?? resources.first else {
            throw APIError.decoding("No original resource for \(candidate.id)")
        }

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("immich-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("\(UUID().uuidString)-\(candidate.fileName)")

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        let gate = WriteGate()
        PHAssetResourceManager.default().writeData(for: resource, toFile: dest, options: options) { error in
            gate.finish(error)
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.loadTimeoutSeconds) {
            gate.finish(APIError.decoding("Asset export timed out — it will be retried on the next run"))
        }
        do {
            try await gate.value
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw error
        }
        return dest
    }

    /// Single-delivery Void resume token — the write completion and the
    /// deadline race; the first wins, the rest no-op.
    private final class WriteGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?

        var value: Void {
            get async throws {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    lock.lock()
                    self.continuation = continuation
                    lock.unlock()
                }
            }
        }

        func finish(_ error: Error?) {
            lock.lock()
            let cont = continuation
            continuation = nil
            lock.unlock()
            guard let cont else { return }
            if let error { cont.resume(throwing: error) } else { cont.resume() }
        }
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
