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
        options.predicate = NSPredicate(format: "creationDate != nil AND duration != nil AND isFavorite != nil")
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    func fetchAssets(inAlbumID albumID: String) -> [PHAsset] {
        guard let collection = Self.collection(forAlbumID: albumID) else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Property hint, same as `fetchAssets()`: the predicate filters nothing,
        // it only forces Photos to pre-fetch what the caller will read.
        options.predicate = NSPredicate(format: "creationDate != nil AND duration != nil AND isFavorite != nil")
        let result = PHAsset.fetchAssets(in: collection, options: options)
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
        let gate = ContinuationGate<Data>()
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


    /// Max wait for one asset's original data (iCloud download). A
    /// candidate that misses the window counts as failed and is retried on
    /// the next run — bounds "Checking library…" to at worst library ×
    /// interval instead of potentially infinite.
    private static let loadTimeoutSeconds: TimeInterval = 90

    /// iCloud-optimized originals can transiently report
    /// `CloudPhotoLibraryErrorDomain` 1005 ("asset not local and not
    /// preparing") when the download hasn't been scheduled yet — distinct from
    /// a genuinely missing/corrupt asset. Re-issuing the resource request nudges
    /// iCloud to start the download; deferring quickly after a single retry lets
    /// the run reach already-local assets fast, while iCloud-only ones are
    /// picked up on the next run once their download has landed.
    private static let cloudRetryAttempts = 2
    private static let cloudRetryDelayNanos: UInt64 = 2 * 1_000_000_000

    /// True when `error` is the retryable iCloud "not local and not preparing"
    /// condition (code 1005), directly or wrapped as an underlying error.
    static func isCloudNotReady(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == "CloudPhotoLibraryErrorDomain" && ns.code == 1005 { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == "CloudPhotoLibraryErrorDomain" && underlying.code == 1005 {
            return true
        }
        return false
    }

    private func makeLoadOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.version = .current
        return options
    }

    func loadThumbnail(for asset: PHAsset, targetSize: CGSize, scale: CGFloat) async -> UIImage? {
        // The process-wide image manager, reused rather than rebuilt per tile:
        // Photos coalesces identical in-flight requests and keeps its own
        // decoded-image cache behind this one instance.
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        // The screen inventories the *device*: an iCloud-evicted original stays a
        // placeholder instead of starting a download behind the grid.
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .opportunistic
        options.isSynchronous = false
        options.resizeMode = .fast
        let pixelSize = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)

        // A cancelled or resource-less tile answers `nil` through the same gate
        // as a delivered one — the caller never has to catch anything.
        let gate = ContinuationGate<UIImage?>()
        let handle = ImageRequestHandle()
        return await withTaskCancellationHandler {
            handle.store(manager.requestImage(for: asset, targetSize: pixelSize, contentMode: .aspectFill, options: options) { image, info in
                if (info?[PHImageCancelledKey] as? Bool) == true {
                    gate.finish(with: .success(nil))
                } else if let image, (info?[PHImageResultIsDegradedKey] as? Bool) != true {
                    // `.opportunistic` hands over a fast low-quality frame first;
                    // only the final one settles the tile.
                    gate.finish(with: .success(image))
                } else if image == nil, info?[PHImageErrorKey] != nil {
                    gate.finish(with: .success(nil))
                }
            })
            if Task.isCancelled {
                handle.cancel(manager)
                gate.finish(with: .success(nil))
            }
            return (try? await gate.value) ?? nil
        } onCancel: {
            handle.cancel(manager)
            gate.finish(with: .success(nil))
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
    /// User albums (name + count, sorted by localized title) followed by the
    /// smart albums the exclusion UI can offer. Smart albums carry a stable
    /// `BackupAlbum.SmartID` rather than a Photos `localIdentifier`, so a
    /// persisted exclusion keeps its meaning across reinstalls.
    func fetchAlbums() -> [BackupAlbum] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "localizedTitle", ascending: true)]
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
        var albums: [BackupAlbum] = []
        albums.reserveCapacity(collections.count + Self.smartAlbumIDs.count)
        collections.enumerateObjects { collection, _, _ in
            guard let name = collection.localizedTitle, !name.isEmpty else { return }
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            albums.append(BackupAlbum(id: collection.localIdentifier, name: name, count: assets.count))
        }
        albums.append(contentsOf: Self.smartAlbums())
        return albums
    }

    /// Smart albums offered for exclusion, in a fixed order.
    private static let smartAlbumIDs = [
        BackupAlbum.SmartID.screenshots,
        BackupAlbum.SmartID.selfPortraits,
        BackupAlbum.SmartID.bursts,
        BackupAlbum.SmartID.videos,
    ]

    /// Only the non-empty ones — an exclusion toggle for an album the library
    /// doesn't have is noise.
    private static func smartAlbums() -> [BackupAlbum] {
        smartAlbumIDs.compactMap { id in
            guard let collection = collection(forAlbumID: id) else { return nil }
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            guard count > 0 else { return nil }
            return BackupAlbum(id: id, name: collection.localizedTitle ?? id, count: count, isSmart: true)
        }
    }

    /// Resolves a scoping id: a `BackupAlbum.SmartID` maps to its smart album,
    /// anything else is a user-album `localIdentifier`.
    private static func collection(forAlbumID albumID: String) -> PHAssetCollection? {
        if let subtype = smartAlbumSubtype(for: albumID) {
            return PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: subtype, options: nil
            ).firstObject
        }
        return PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumID], options: nil
        ).firstObject
    }

    private static func smartAlbumSubtype(for albumID: String) -> PHAssetCollectionSubtype? {
        switch albumID {
        case BackupAlbum.SmartID.screenshots: return .smartAlbumScreenshots
        case BackupAlbum.SmartID.selfPortraits: return .smartAlbumSelfPortraits
        case BackupAlbum.SmartID.bursts: return .smartAlbumBursts
        case BackupAlbum.SmartID.videos: return .smartAlbumVideos
        default: return nil
        }
    }

    /// All library assets (creation date DESC), or the union of the selected
    /// albums, minus every asset that lives in an excluded album. Assets in
    /// several albums dedupe by localIdentifier. The exclusion is resolved by
    /// subtracting identifier sets up front — one `PHAsset.fetchAssets` per
    /// excluded album (none by default) instead of an album lookup per asset,
    /// which is what made a whole-library scan stall.
    func fetchCandidates(in albumIDs: Set<String>, excluding excludedAlbumIDs: Set<String>) -> [BackupCandidate] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Force Photos to pre-fetch creationDate, duration, isFavorite
        // so that makeCandidate() and exportOriginal() do not trigger the per-asset
        // "Missing prefetched properties for PHAssetOriginalMetadataProperties" warning.
        // The predicate does not filter anything — it only acts as a property hint.
        options.predicate = NSPredicate(format: "creationDate != nil AND duration != nil AND isFavorite != nil")

        let excludedIDs = Self.excludedAssetIDs(excludedAlbumIDs)

        var samplers: [PHAsset] = []
        if albumIDs.isEmpty {
            let result = PHAsset.fetchAssets(with: options)
            result.enumerateObjects { asset, _, _ in samplers.append(asset) }
        } else {
            var seen = Set<ObjectIdentifier>()
            for albumID in albumIDs {
                guard let collection = Self.collection(forAlbumID: albumID) else { continue }
                let result = PHAsset.fetchAssets(in: collection, options: options)
                result.enumerateObjects { asset, _, _ in
                    if seen.insert(ObjectIdentifier(asset)).inserted { samplers.append(asset) }
                }
            }
        }
        // Build candidates in a per-asset autorelease pool: makeCandidate calls
        // PHAssetResource.assetResources, which autoreleases Photos objects that
        // would otherwise pile up across a whole-library scan.
        var candidates: [BackupCandidate] = []
        candidates.reserveCapacity(samplers.count)
        for asset in samplers {
            autoreleasepool {
                if excludedIDs.contains(asset.localIdentifier) { return }
                prefetchProperties(of: asset)
                if let candidate = makeCandidate(asset) {
                    candidates.append(candidate)
                }
            }
        }
        return candidates
    }

    /// Identifier set of every asset living in an excluded album. Reads only
    /// `localIdentifier` — no property prefetch, so this costs no metadata.
    private static func excludedAssetIDs(_ albumIDs: Set<String>) -> Set<String> {
        guard !albumIDs.isEmpty else { return [] }
        var ids = Set<String>()
        for albumID in albumIDs {
            guard let collection = collection(forAlbumID: albumID) else { continue }
            PHAsset.fetchAssets(in: collection, options: nil)
                .enumerateObjects { asset, _, _ in ids.insert(asset.localIdentifier) }
        }
        return ids
    }

    /// Streams the asset's original resource to a temp file on disk (never a
    /// full `Data` in memory). `isNetworkAccessAllowed` lets iCloud-only
    /// originals download; a stall watchdog guards a hung download.
    func exportOriginal(
        for candidate: BackupCandidate,
        onState: @escaping @Sendable (BackupExportState) -> Void
    ) async throws -> URL {
        let asset = try asset(for: candidate)
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .photo || $0.type == .video })
            ?? resources.first(where: { $0.type == .fullSizePhoto || $0.type == .fullSizeVideo })
            ?? resources.first else {
            throw APIError.decoding("No original resource for \(candidate.id)")
        }
        return try await writeResource(resource, filenameHint: candidate.fileName, onState: onState)
    }

    /// The video paired with a Live Photo's still, or nil when the asset has no
    /// paired resource. Same export path as the still — a Live Photo on an
    /// optimized library has *two* iCloud-only resources, and both need the
    /// 1005 retry and the stall watchdog.
    func exportPairedVideo(
        for candidate: BackupCandidate,
        onState: @escaping @Sendable (BackupExportState) -> Void
    ) async throws -> BackupPairedVideo? {
        let asset = try asset(for: candidate)
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: {
            $0.type == .pairedVideo || $0.type == .fullSizePairedVideo
        }) else { return nil }
        let url = try await writeResource(
            resource, filenameHint: resource.originalFilename, onState: onState
        )
        return BackupPairedVideo(
            url: url,
            fileName: resource.originalFilename,
            duration: Int(max(0, asset.duration))
        )
    }

    /// Fetches the PHAsset behind a candidate, properties prefetched so the
    /// "missing prefetched properties" fetch never lands on the main queue.
    private func asset(for candidate: BackupCandidate) throws -> PHAsset {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "creationDate != nil AND duration != nil AND isFavorite != nil")
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [candidate.id], options: options).firstObject else {
            throw APIError.decoding("PHAsset not found for \(candidate.id)")
        }
        prefetchProperties(of: asset)
        return asset
    }

    /// Writes one Photos resource to a temp file and returns its URL. Shared by
    /// the still and the paired video on purpose: the 1005 retry, the stall
    /// watchdog and the partial-file cleanup are the whole reason an
    /// iCloud-optimized library survives a backup, and a second copy of them
    /// would drift.
    private func writeResource(
        _ resource: PHAssetResource,
        filenameHint: String,
        onState: @escaping @Sendable (BackupExportState) -> Void
    ) async throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("immich-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("\(UUID().uuidString)-\(filenameHint)")

        let resourceOptions = PHAssetResourceRequestOptions()
        resourceOptions.isNetworkAccessAllowed = true

        // iCloud-optimized originals may report a transient 1005 ("not local and
        // not preparing") before the download is scheduled. Retry a few times
        // with a short backoff — re-issuing the write nudges iCloud to start —
        // and only then surface the failure (retried again on the next run).
        var attempt = 0
        while true {
            let gate = ContinuationGate<Void>()
            // A wall-clock deadline would abort a slow-but-healthy iCloud download
            // (which can legitimately take minutes) and delete its half-written temp
            // file. Instead, a stall watchdog trips only after `loadTimeoutSeconds`
            // with neither a progress tick nor completion — so a download that keeps
            // making progress is never dropped, only a truly hung request is.
            let watchdog = StallWatchdog(interval: Self.loadTimeoutSeconds) {
                gate.finish(with: .failure(BackupExportError.cloudDownloadPending))
            }
            resourceOptions.progressHandler = { fraction in
                watchdog.pet()
                onState(.downloadingFromICloud(fraction: fraction))
            }
            watchdog.pet()
            PHAssetResourceManager.default().writeData(for: resource, toFile: dest, options: resourceOptions) { error in
                watchdog.cancel()
                gate.finish(with: error.map { .failure($0) } ?? .success(()))
            }
            do {
                try await gate.value
                return dest
            } catch {
                try? FileManager.default.removeItem(at: dest)
                attempt += 1
                if Self.isCloudNotReady(error) {
                    if attempt < Self.cloudRetryAttempts {
                        onState(.retryingICloud(attempt: attempt))
                        try? await Task.sleep(nanoseconds: Self.cloudRetryDelayNanos)
                        continue
                    }
                    throw BackupExportError.cloudDownloadPending
                }
                throw error
            }
        }
    }

    /// Deletes every leftover file in the shared export temp directory. Safe
    /// to call only at the start of a run — no export of the current run has
    /// written there yet, so this only reclaims orphans from a killed run.
    func purgeStaleExports() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("immich-backup", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    /// Maps a PHAsset to its value-typed candidate.
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
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive)
        )
    }

    private func prefetchProperties(of asset: PHAsset) {
        // Read all properties that makeCandidate/exportOriginal access. This forces
        // PhotosKit to cache them so the "Missing prefetched properties" warning
        // disappears. Access must happen on the main thread before any async switch.
        _ = asset.localIdentifier
        _ = asset.mediaType
        _ = asset.mediaSubtypes
        _ = asset.duration
        _ = asset.isFavorite
    }
}

/// Single-delivery async gate bridging a completion-handler API to
/// async/await. Robust to the completion firing *before* the awaiter installs
/// its continuation — common with fast, fully-local PhotosKit resources whose
/// `writeData`/`requestImageData` completion lands in the window between the
/// request call and `await gate.value`. The first result is stashed and
/// delivered as soon as `value` is awaited; later `finish` calls (e.g. the
/// timeout that lost the race) are ignored. Without this, a dropped resume
/// left the awaiter hung until the deadline, surfacing every local asset as a
/// bogus "export timed out".
final class ContinuationGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var pending: Result<Value, Error>?
    private var settled = false

    var value: Value {
        get async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
                lock.lock()
                if let pending {
                    lock.unlock()
                    continuation.resume(with: pending)
                } else {
                    self.continuation = continuation
                    lock.unlock()
                }
            }
        }
    }

    func finish(with result: Result<Value, Error>) {
        lock.lock()
        if settled { lock.unlock(); return }
        settled = true
        let cont = continuation
        continuation = nil
        if cont == nil { pending = result }
        lock.unlock()
        cont?.resume(with: result)
    }
}

/// Trips `onStall` only after `interval` seconds elapse with no `pet()` and no
/// `cancel()`. Each `pet()` (a progress tick) postpones the deadline, so a
/// slow-but-progressing transfer is never aborted; a request that produces no
/// bytes for `interval` is. Thread-safe via a private serial queue.
private final class StallWatchdog: @unchecked Sendable {
    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "immich.export.watchdog")
    private var item: DispatchWorkItem?
    private var stopped = false
    private let onStall: () -> Void

    init(interval: TimeInterval, onStall: @escaping () -> Void) {
        self.interval = interval
        self.onStall = onStall
    }

    /// Restart the countdown from now — call on start and on every progress tick.
    func pet() {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.item?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.stopped else { return }
                self.onStall()
            }
            self.item = work
            self.queue.asyncAfter(deadline: .now() + self.interval, execute: work)
        }
    }

    /// Stop for good — the transfer finished (success or failure).
    func cancel() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = true
            self.item?.cancel()
            self.item = nil
        }
    }
}

/// Carries an in-flight `PHImageRequestID` across the cancellation boundary.
/// The id only exists once `requestImage` returns, while the `onCancel` handler
/// can fire at any moment — so the hand-off is lock-guarded instead of captured
/// by value. An id that never landed cancels nothing (Photos never started).
private final class ImageRequestHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var id: PHImageRequestID = PHInvalidImageRequestID

    func store(_ requestID: PHImageRequestID) {
        lock.lock()
        id = requestID
        lock.unlock()
    }

    func cancel(_ manager: PHImageManager) {
        lock.lock()
        let requestID = id
        lock.unlock()
        guard requestID != PHInvalidImageRequestID else { return }
        manager.cancelImageRequest(requestID)
    }
}
